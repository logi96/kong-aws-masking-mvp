#!/bin/bash

# Kong AWS Masking MVP - Comprehensive Health Check Script
# Infrastructure Team - Validates all system components

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TIMEOUT=30
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2

# Service endpoints
readonly KONG_ADMIN_URL="http://localhost:8001"
readonly KONG_PROXY_URL="http://localhost:8000"
readonly BACKEND_URL="http://localhost:3000"

# Health check results
declare -A HEALTH_RESULTS
declare -i EXIT_CODE=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_separator() {
    echo -e "${BLUE}================================${NC}"
}

# Utility functions
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Command '$cmd' not found"
        return 1
    fi
    return 0
}

wait_for_service() {
    local url="$1"
    local service_name="$2"
    local timeout="${3:-$TIMEOUT}"
    local retries=0

    log_info "Waiting for $service_name at $url..."
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -f -s --max-time "$timeout" "$url" &>/dev/null; then
            log_success "$service_name is responding"
            return 0
        fi
        
        retries=$((retries + 1))
        log_warning "Attempt $retries/$MAX_RETRIES failed, retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    done
    
    log_error "$service_name is not responding after $MAX_RETRIES attempts"
    return 1
}

# Health check functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local prerequisites=("curl" "docker" "docker-compose")
    local missing=()
    
    for cmd in "${prerequisites[@]}"; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites: ${missing[*]}"
        HEALTH_RESULTS["prerequisites"]="FAILED"
        return 1
    fi
    
    log_success "All prerequisites are available"
    HEALTH_RESULTS["prerequisites"]="PASSED"
    return 0
}

check_docker_services() {
    log_info "Checking Docker services..."
    
    cd "$PROJECT_ROOT"
    
    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        log_error "docker-compose.yml not found in $PROJECT_ROOT"
        HEALTH_RESULTS["docker_services"]="FAILED"
        return 1
    fi
    
    # Check if services are running
    local services
    services=$(docker-compose ps --services --filter status=running)
    
    if [ -z "$services" ]; then
        log_warning "No Docker services are currently running"
        log_info "Attempting to start services..."
        
        if docker-compose up -d --build; then
            log_success "Services started successfully"
            # Wait a bit for services to initialize
            sleep 10
        else
            log_error "Failed to start Docker services"
            HEALTH_RESULTS["docker_services"]="FAILED"
            return 1
        fi
    else
        log_success "Docker services are running: $(echo "$services" | tr '\n' ' ')"
    fi
    
    HEALTH_RESULTS["docker_services"]="PASSED"
    return 0
}

check_kong_admin() {
    log_info "Checking Kong Admin API..."
    
    local status_endpoint="$KONG_ADMIN_URL/status"
    
    if wait_for_service "$status_endpoint" "Kong Admin API"; then
        # Get detailed status
        local response
        response=$(curl -s "$status_endpoint")
        
        if echo "$response" | grep -q '"database":'; then
            log_success "Kong Admin API is healthy"
            log_info "Kong status: $response"
            HEALTH_RESULTS["kong_admin"]="PASSED"
            return 0
        else
            log_error "Kong Admin API returned invalid response"
            HEALTH_RESULTS["kong_admin"]="FAILED"
            return 1
        fi
    else
        HEALTH_RESULTS["kong_admin"]="FAILED"
        return 1
    fi
}

check_kong_proxy() {
    log_info "Checking Kong Proxy..."
    
    if wait_for_service "$KONG_PROXY_URL" "Kong Proxy"; then
        # Test basic proxy functionality
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" "$KONG_PROXY_URL")
        
        # Kong proxy typically returns 404 for root path when no routes match
        if [[ "$response_code" == "404" || "$response_code" == "200" ]]; then
            log_success "Kong Proxy is healthy (HTTP $response_code)"
            HEALTH_RESULTS["kong_proxy"]="PASSED"
            return 0
        else
            log_error "Kong Proxy returned unexpected status: $response_code"
            HEALTH_RESULTS["kong_proxy"]="FAILED"
            return 1
        fi
    else
        HEALTH_RESULTS["kong_proxy"]="FAILED"
        return 1
    fi
}

check_backend_api() {
    log_info "Checking Backend API..."
    
    local health_endpoint="$BACKEND_URL/health"
    
    if wait_for_service "$health_endpoint" "Backend API"; then
        # Get detailed health information
        local response
        response=$(curl -s "$health_endpoint")
        
        if echo "$response" | grep -q '"status":"healthy"'; then
            log_success "Backend API is healthy"
            log_info "Backend response: $response"
            HEALTH_RESULTS["backend_api"]="PASSED"
            return 0
        else
            log_error "Backend API health check failed"
            log_error "Response: $response"
            HEALTH_RESULTS["backend_api"]="FAILED"
            return 1
        fi
    else
        HEALTH_RESULTS["backend_api"]="FAILED"
        return 1
    fi
}

check_integration() {
    log_info "Checking service integration..."
    
    # Test if Kong can proxy to backend
    local test_endpoint="$KONG_PROXY_URL/health"
    
    local response
    if response=$(curl -s --max-time $TIMEOUT "$test_endpoint" 2>&1); then
        if echo "$response" | grep -q '"status":"healthy"'; then
            log_success "Kong -> Backend integration working"
            HEALTH_RESULTS["integration"]="PASSED"
            return 0
        else
            log_warning "Integration test returned unexpected response: $response"
            HEALTH_RESULTS["integration"]="WARNING"
            return 0
        fi
    else
        log_error "Integration test failed: $response"
        HEALTH_RESULTS["integration"]="FAILED"
        return 1
    fi
}

check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    # Test AWS CLI access in backend container
    if docker-compose exec -T backend aws sts get-caller-identity &>/dev/null; then
        log_success "AWS credentials are configured and accessible"
        HEALTH_RESULTS["aws_credentials"]="PASSED"
        return 0
    else
        log_warning "AWS credentials not configured or inaccessible"
        log_info "This is expected in development environments without AWS access"
        HEALTH_RESULTS["aws_credentials"]="WARNING"
        return 0
    fi
}

check_logs() {
    log_info "Checking service logs for errors..."
    
    cd "$PROJECT_ROOT"
    
    # Check for recent error logs
    local error_count
    error_count=$(docker-compose logs --tail=50 2>&1 | grep -i error | wc -l)
    
    if [ "$error_count" -gt 10 ]; then
        log_warning "Found $error_count recent error messages in logs"
        log_info "Run 'docker-compose logs' to review"
        HEALTH_RESULTS["logs"]="WARNING"
    else
        log_success "Log check passed (found $error_count error messages)"
        HEALTH_RESULTS["logs"]="PASSED"
    fi
    
    return 0
}

check_resources() {
    log_info "Checking resource usage..."
    
    # Check Docker container resource usage
    local stats
    stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true)
    
    if [ -n "$stats" ]; then
        log_info "Container resource usage:"
        echo "$stats"
        HEALTH_RESULTS["resources"]="PASSED"
    else
        log_warning "Could not retrieve resource usage statistics"
        HEALTH_RESULTS["resources"]="WARNING"
    fi
    
    return 0
}

# Report generation
generate_report() {
    log_separator
    log_info "Health Check Summary"
    log_separator
    
    local total_checks=0
    local passed_checks=0
    local warning_checks=0
    local failed_checks=0
    
    for check in "${!HEALTH_RESULTS[@]}"; do
        total_checks=$((total_checks + 1))
        case "${HEALTH_RESULTS[$check]}" in
            "PASSED")
                log_success "$check: PASSED"
                passed_checks=$((passed_checks + 1))
                ;;
            "WARNING")
                log_warning "$check: WARNING"
                warning_checks=$((warning_checks + 1))
                ;;
            "FAILED")
                log_error "$check: FAILED"
                failed_checks=$((failed_checks + 1))
                EXIT_CODE=1
                ;;
        esac
    done
    
    log_separator
    log_info "Results: $passed_checks passed, $warning_checks warnings, $failed_checks failed"
    
    if [ $failed_checks -eq 0 ]; then
        log_success "Overall health check: PASSED"
        if [ $warning_checks -gt 0 ]; then
            log_warning "Some non-critical issues detected"
        fi
    else
        log_error "Overall health check: FAILED"
        log_error "Please address the failed checks before proceeding"
    fi
}

# Main execution
main() {
    log_info "Starting Kong AWS Masking MVP Health Check"
    log_info "Timestamp: $(date -Iseconds)"
    log_separator
    
    # Run all health checks
    check_prerequisites
    check_docker_services
    check_kong_admin
    check_kong_proxy  
    check_backend_api
    check_integration
    check_aws_credentials
    check_logs
    check_resources
    
    # Generate final report
    generate_report
    
    exit $EXIT_CODE
}

# Handle script interruption
trap 'log_error "Health check interrupted"; exit 130' INT TERM

# Run main function
main "$@"