#!/bin/bash

# Pre-deployment Check Script for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: Comprehensive pre-deployment validation and readiness check

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
ENVIRONMENT="${1:-production}"
CONFIG_FILE="${PROJECT_ROOT}/config/${ENVIRONMENT}.env"

# Check results tracking
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

# Infrastructure checks
check_docker_system() {
    log_info "Checking Docker system requirements..."
    
    # Docker daemon running
    if docker info &> /dev/null; then
        log_success "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Docker version check
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    if [[ -n "$docker_version" ]]; then
        log_success "Docker version: $docker_version"
    else
        log_error "Could not determine Docker version"
    fi
    
    # Docker Compose check
    if command -v docker-compose &> /dev/null; then
        local compose_version=$(docker-compose version --short 2>/dev/null)
        log_success "Docker Compose version: $compose_version"
    else
        log_error "Docker Compose not found"
    fi
    
    # System resources
    local total_memory=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    local memory_gb=$((total_memory / 1024 / 1024 / 1024))
    if [[ $memory_gb -ge 4 ]]; then
        log_success "System memory: ${memory_gb}GB (sufficient)"
    else
        log_warning "System memory: ${memory_gb}GB (minimum 4GB recommended)"
    fi
    
    # Disk space check
    local available_space=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -ge 10 ]]; then
        log_success "Disk space: ${available_space}GB available"
    else
        log_error "Disk space: ${available_space}GB (minimum 10GB required)"
    fi
}

check_network_requirements() {
    log_info "Checking network requirements..."
    
    # Port availability check
    local ports=(6379 8000 8001 8082 8085)
    for port in "${ports[@]}"; do
        if ss -tln | grep -q ":$port "; then
            log_warning "Port $port is already in use"
        else
            log_success "Port $port is available"
        fi
    done
    
    # External connectivity check
    if curl -s --connect-timeout 5 https://api.anthropic.com/health &> /dev/null; then
        log_success "External API connectivity (anthropic.com) is working"
    else
        log_error "Cannot reach api.anthropic.com (check internet connectivity)"
    fi
    
    # DNS resolution
    if nslookup api.anthropic.com &> /dev/null; then
        log_success "DNS resolution is working"
    else
        log_error "DNS resolution failed"
    fi
}

check_configuration_files() {
    log_info "Checking configuration files..."
    
    # Environment config validation
    if [[ -f "$CONFIG_FILE" ]]; then
        log_success "Environment config found: $CONFIG_FILE"
        
        # Run config validation
        if "${PROJECT_ROOT}/config/validate-config.sh" "$ENVIRONMENT" &> /dev/null; then
            log_success "Configuration validation passed"
        else
            log_error "Configuration validation failed"
        fi
    else
        log_error "Environment config not found: $CONFIG_FILE"
    fi
    
    # Docker Compose files
    local compose_files=("docker-compose.yml" "docker-compose.prod.yml")
    for compose_file in "${compose_files[@]}"; do
        local file_path="${PROJECT_ROOT}/${compose_file}"
        if [[ -f "$file_path" ]]; then
            log_success "Docker Compose file found: $compose_file"
            
            # Validate compose file syntax
            if docker-compose -f "$file_path" config &> /dev/null; then
                log_success "Docker Compose syntax valid: $compose_file"
            else
                log_error "Docker Compose syntax invalid: $compose_file"
            fi
        else
            log_warning "Docker Compose file not found: $compose_file"
        fi
    done
    
    # Kong configuration
    if [[ -f "${PROJECT_ROOT}/kong/kong.yml" ]]; then
        log_success "Kong declarative config found"
    else
        log_error "Kong declarative config not found"
    fi
    
    # Plugin files
    local plugin_files=(
        "handler.lua"
        "patterns.lua"
        "masker_ngx_re.lua"
        "redis_integration.lua"
    )
    
    for plugin_file in "${plugin_files[@]}"; do
        local file_path="${PROJECT_ROOT}/kong/plugins/aws-masker/${plugin_file}"
        if [[ -f "$file_path" ]]; then
            log_success "Kong plugin file found: $plugin_file"
        else
            log_error "Kong plugin file missing: $plugin_file"
        fi
    done
}

check_security_requirements() {
    log_info "Checking security requirements..."
    
    # Load environment variables
    if [[ -f "$CONFIG_FILE" ]]; then
        set -a
        source "$CONFIG_FILE" 2>/dev/null || true
        set +a
    fi
    
    # API key validation
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        if [[ "$ANTHROPIC_API_KEY" =~ ^sk-ant-api03- ]]; then
            log_success "Anthropic API key format is valid"
        else
            log_error "Anthropic API key format is invalid"
        fi
        
        # API key length check
        if [[ ${#ANTHROPIC_API_KEY} -ge 50 ]]; then
            log_success "API key length is sufficient"
        else
            log_warning "API key length seems short"
        fi
    else
        log_error "ANTHROPIC_API_KEY is not set"
    fi
    
    # Redis password validation
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        if [[ ${#REDIS_PASSWORD} -ge 32 ]]; then
            log_success "Redis password length is sufficient"
        else
            log_warning "Redis password is too short (recommend 32+ characters)"
        fi
    else
        log_error "REDIS_PASSWORD is not set"
    fi
    
    # File permissions check
    local sensitive_files=(
        "$CONFIG_FILE"
        "${PROJECT_ROOT}/.env"
    )
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c %a "$file" 2>/dev/null || stat -f %A "$file" 2>/dev/null)
            if [[ "$perms" == "600" || "$perms" == "644" ]]; then
                log_success "File permissions secure: $file ($perms)"
            else
                log_warning "File permissions may be too open: $file ($perms)"
            fi
        fi
    done
}

check_existing_services() {
    log_info "Checking for existing services..."
    
    # Check for running containers with same names
    local container_names=("claude-redis" "claude-kong" "claude-nginx" "claude-code-sdk")
    local running_containers=0
    
    for container in "${container_names[@]}"; do
        if docker ps -q -f name="$container" | grep -q .; then
            log_warning "Container already running: $container"
            ((running_containers++))
        else
            log_success "Container not running: $container"
        fi
    done
    
    if [[ $running_containers -gt 0 ]]; then
        log_warning "$running_containers containers are already running"
        log_info "Consider running: docker-compose down before deployment"
    fi
    
    # Check for existing networks
    if docker network ls --format '{{.Name}}' | grep -q "claude-enterprise"; then
        log_warning "Claude network already exists"
    else
        log_success "Claude network is available"
    fi
    
    # Check for existing volumes
    local volumes=("redis-data" "kong-logs" "nginx-logs")
    for volume in "${volumes[@]}"; do
        if docker volume ls --format '{{.Name}}' | grep -q "$volume"; then
            log_info "Volume exists: $volume (will be reused)"
        else
            log_success "Volume available: $volume"
        fi
    done
}

check_day2_automation() {
    log_info "Checking Day 2 automation integration..."
    
    # Check for Day 2 scripts
    local day2_scripts=(
        "scripts/day2-health-check.sh"
        "scripts/day2-smoke-test.sh"
        "scripts/day2-system-monitor.sh"
    )
    
    for script in "${day2_scripts[@]}"; do
        local script_path="${PROJECT_ROOT}/${script}"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            log_success "Day 2 script ready: $script"
        else
            log_warning "Day 2 script missing or not executable: $script"
        fi
    done
    
    # Check test scripts
    local test_scripts=(
        "tests/e2e-comprehensive-test.sh"
        "tests/proxy-integration-test.sh"
    )
    
    for script in "${test_scripts[@]}"; do
        local script_path="${PROJECT_ROOT}/${script}"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            log_success "Test script ready: $script"
        else
            log_warning "Test script missing: $script"
        fi
    done
}

check_backup_readiness() {
    log_info "Checking backup and recovery readiness..."
    
    # Backup directories
    local backup_dirs=("backups" "backups/redis" "backups/config")
    for dir in "${backup_dirs[@]}"; do
        local dir_path="${PROJECT_ROOT}/${dir}"
        if [[ -d "$dir_path" ]]; then
            log_success "Backup directory exists: $dir"
        else
            mkdir -p "$dir_path" 2>/dev/null && log_success "Created backup directory: $dir" || log_warning "Could not create backup directory: $dir"
        fi
    done
    
    # Redis backup script
    if [[ -f "${PROJECT_ROOT}/scripts/redis-backup.sh" ]]; then
        log_success "Redis backup script found"
    else
        log_warning "Redis backup script not found"
    fi
    
    # Config backup
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_file="${PROJECT_ROOT}/backups/config/${ENVIRONMENT}-$(date +%Y%m%d).env"
        if cp "$CONFIG_FILE" "$backup_file" 2>/dev/null; then
            log_success "Configuration backed up: $backup_file"
        else
            log_warning "Could not backup configuration"
        fi
    fi
}

generate_readiness_report() {
    echo
    echo "=========================================="
    echo "Pre-deployment Readiness Report"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Timestamp: $(date)"
    echo "Config File: $CONFIG_FILE"
    echo
    echo "Check Results:"
    echo "  ✅ Passed: $CHECKS_PASSED"
    echo "  ⚠️  Warnings: $CHECKS_WARNED"
    echo "  ❌ Failed: $CHECKS_FAILED"
    echo
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_success "System is READY for deployment!"
        echo
        echo "Next steps:"
        echo "1. Run: ./deploy.sh $ENVIRONMENT"
        echo "2. Monitor: docker-compose logs -f"
        echo "3. Verify: ./post-deploy-verify.sh"
        return 0
    else
        log_error "System is NOT READY for deployment"
        echo
        echo "Please resolve the failed checks before proceeding."
        echo "Run this script again after fixes: $0 $ENVIRONMENT"
        return 1
    fi
}

# Main check process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Pre-deployment Check"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Timestamp: $(date)"
    echo
    
    # Run all checks
    check_docker_system
    check_network_requirements
    check_configuration_files
    check_security_requirements
    check_existing_services
    check_day2_automation
    check_backup_readiness
    
    # Generate final report
    generate_readiness_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment]"
    echo
    echo "Run comprehensive pre-deployment checks for Kong AWS Masking MVP"
    echo
    echo "Arguments:"
    echo "  environment    Target environment (development|staging|production)"
    echo "                 Default: production"
    echo
    echo "Examples:"
    echo "  $0                    # Check production readiness"
    echo "  $0 staging           # Check staging readiness"
    echo "  $0 development       # Check development readiness"
    echo
    exit 0
fi

# Run main function
main "$@"