#!/bin/bash

# Production Image Build Script for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: Build optimized production Docker images with security scanning

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_LOG_FILE="${PROJECT_ROOT}/logs/build-$(date +%Y%m%d_%H%M%S).log"

# Default values
ENVIRONMENT="${1:-production}"
SERVICE_VERSION="${2:-$(date +%Y%m%d-%H%M%S)}"
BUILD_CACHE="${BUILD_CACHE:-true}"
SECURITY_SCAN="${SECURITY_SCAN:-false}"
PUSH_IMAGES="${PUSH_IMAGES:-false}"
REGISTRY_URL="${REGISTRY_URL:-localhost:5000}"

# Build statistics
BUILD_START_TIME=$(date +%s)
IMAGES_BUILT=0
BUILD_ERRORS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$BUILD_LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$BUILD_LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$BUILD_LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$BUILD_LOG_FILE"
    ((BUILD_ERRORS++))
}

# Utility functions
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_success "Docker is available and running"
}

check_build_context() {
    local component=$1
    local dockerfile_path="${PROJECT_ROOT}/${component}/Dockerfile.prod"
    
    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "Production Dockerfile not found: $dockerfile_path"
        return 1
    fi
    
    log_success "Build context validated for $component"
}

build_image() {
    local component=$1
    local build_context="${PROJECT_ROOT}/${component}"
    local dockerfile="Dockerfile.prod"
    local image_name="kong-aws-masking-${component}"
    local full_tag="${image_name}:${SERVICE_VERSION}"
    local latest_tag="${image_name}:latest"
    
    log_info "Building $component image..."
    
    # Build arguments
    local build_args=(
        --file "$build_context/$dockerfile"
        --tag "$full_tag"
        --tag "$latest_tag"
        --label "com.claude.component=$component"
        --label "com.claude.version=$SERVICE_VERSION"
        --label "com.claude.environment=$ENVIRONMENT"
        --label "com.claude.build-date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --label "com.claude.build-revision=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    )
    
    # Cache configuration
    if [[ "$BUILD_CACHE" == "true" ]]; then
        build_args+=(--cache-from "$latest_tag")
    else
        build_args+=(--no-cache)
    fi
    
    # Environment-specific optimizations
    if [[ "$ENVIRONMENT" == "production" ]]; then
        build_args+=(
            --build-arg ENVIRONMENT=production
            --build-arg OPTIMIZE_SIZE=true
        )
    fi
    
    # Execute build
    local build_start=$(date +%s)
    if docker build "${build_args[@]}" "$build_context" 2>&1 | tee -a "$BUILD_LOG_FILE"; then
        local build_end=$(date +%s)
        local build_duration=$((build_end - build_start))
        
        log_success "$component image built successfully in ${build_duration}s"
        log_info "Image tags: $full_tag, $latest_tag"
        
        # Get image size
        local image_size=$(docker images --format "table {{.Size}}" "$full_tag" | tail -n 1)
        log_info "$component image size: $image_size"
        
        ((IMAGES_BUILT++))
        
        # Security scanning if enabled
        if [[ "$SECURITY_SCAN" == "true" ]]; then
            scan_image "$full_tag"
        fi
        
        # Push to registry if enabled
        if [[ "$PUSH_IMAGES" == "true" ]]; then
            push_image "$full_tag" "$latest_tag"
        fi
        
        return 0
    else
        log_error "Failed to build $component image"
        return 1
    fi
}

scan_image() {
    local image_tag=$1
    
    log_info "Scanning image for security vulnerabilities: $image_tag"
    
    # Example using docker scout (if available)
    if command -v docker scout &> /dev/null; then
        if docker scout cves "$image_tag" 2>&1 | tee -a "$BUILD_LOG_FILE"; then
            log_success "Security scan completed for $image_tag"
        else
            log_warning "Security scan failed for $image_tag"
        fi
    else
        log_warning "Docker Scout not available, skipping security scan"
    fi
}

push_image() {
    local full_tag=$1
    local latest_tag=$2
    
    log_info "Pushing images to registry: $REGISTRY_URL"
    
    # Tag for registry
    local registry_full_tag="${REGISTRY_URL}/${full_tag}"
    local registry_latest_tag="${REGISTRY_URL}/${latest_tag}"
    
    docker tag "$full_tag" "$registry_full_tag"
    docker tag "$latest_tag" "$registry_latest_tag"
    
    if docker push "$registry_full_tag" && docker push "$registry_latest_tag"; then
        log_success "Images pushed successfully"
    else
        log_error "Failed to push images to registry"
    fi
}

cleanup_build_cache() {
    log_info "Cleaning up build cache..."
    
    # Remove dangling images
    if docker image prune -f &> /dev/null; then
        log_success "Removed dangling images"
    fi
    
    # Remove build cache if not preserving
    if [[ "$BUILD_CACHE" != "true" ]]; then
        if docker builder prune -f &> /dev/null; then
            log_success "Removed build cache"
        fi
    fi
}

generate_build_report() {
    local build_end_time=$(date +%s)
    local total_duration=$((build_end_time - BUILD_START_TIME))
    
    echo "=========================================="
    echo "Production Image Build Report"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Service Version: $SERVICE_VERSION"
    echo "Build Date: $(date)"
    echo "Total Duration: ${total_duration}s"
    echo "Images Built: $IMAGES_BUILT"
    echo "Build Errors: $BUILD_ERRORS"
    echo "Build Cache: $BUILD_CACHE"
    echo "Security Scan: $SECURITY_SCAN"
    echo "Registry Push: $PUSH_IMAGES"
    echo
    
    if [[ $BUILD_ERRORS -eq 0 ]]; then
        log_success "All images built successfully!"
        echo "Next steps:"
        echo "1. Run: docker images | grep kong-aws-masking"
        echo "2. Test deployment: ./deploy.sh $ENVIRONMENT"
        echo "3. Verify services: ./post-deploy-verify.sh"
        return 0
    else
        log_error "Build completed with $BUILD_ERRORS errors"
        echo "Check build log: $BUILD_LOG_FILE"
        return 1
    fi
}

# Main build process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Production Build"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Version: $SERVICE_VERSION"
    echo "Build Cache: $BUILD_CACHE"
    echo "Security Scan: $SECURITY_SCAN"
    echo "Registry Push: $PUSH_IMAGES"
    echo
    
    # Create logs directory
    mkdir -p "$(dirname "$BUILD_LOG_FILE")"
    
    # Pre-build checks
    check_docker
    
    # Components to build (order matters for dependencies)
    local components=("redis" "kong" "nginx" "claude-code-sdk")
    
    # Validate all build contexts first
    for component in "${components[@]}"; do
        if [[ -d "${PROJECT_ROOT}/${component}" ]]; then
            check_build_context "$component" || continue
        else
            log_warning "Component directory not found: $component"
        fi
    done
    
    # Build each component
    for component in "${components[@]}"; do
        if [[ -d "${PROJECT_ROOT}/${component}" ]]; then
            log_info "Starting build for $component..."
            build_image "$component" || log_error "Build failed for $component"
        fi
    done
    
    # Post-build cleanup
    cleanup_build_cache
    
    # Generate final report
    generate_build_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment] [version] [options]"
    echo
    echo "Build production-optimized Docker images for Kong AWS Masking MVP"
    echo
    echo "Arguments:"
    echo "  environment    Target environment (development|staging|production)"
    echo "  version        Image version tag (default: timestamp)"
    echo
    echo "Environment Variables:"
    echo "  BUILD_CACHE=true|false       Use Docker build cache (default: true)"
    echo "  SECURITY_SCAN=true|false     Run security scanning (default: false)"
    echo "  PUSH_IMAGES=true|false       Push to registry (default: false)"
    echo "  REGISTRY_URL=url             Registry URL (default: localhost:5000)"
    echo
    echo "Examples:"
    echo "  $0 production                           # Build production images"
    echo "  BUILD_CACHE=false $0 production         # Clean build"
    echo "  SECURITY_SCAN=true $0 production        # Build with security scan"
    echo "  PUSH_IMAGES=true $0 production v1.0.0  # Build and push"
    echo
    exit 0
fi

# Run main function
main "$@"