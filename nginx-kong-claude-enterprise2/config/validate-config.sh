#!/bin/bash

# Config Validation Script for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: Validate environment configuration before deployment

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

# Default environment
ENVIRONMENT="${1:-development}"
CONFIG_FILE="$SCRIPT_DIR/${ENVIRONMENT}.env"

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((VALIDATION_WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((VALIDATION_ERRORS++))
}

# Validation functions
validate_file_exists() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    log_success "Configuration file found: $CONFIG_FILE"
}

validate_required_variables() {
    log_info "Validating required environment variables..."
    
    # Source the config file
    set -a
    source "$CONFIG_FILE" 2>/dev/null || {
        log_error "Failed to source configuration file"
        return 1
    }
    set +a
    
    # Required variables
    local required_vars=(
        "NODE_ENV"
        "DEPLOYMENT_ENV"
        "ANTHROPIC_API_KEY"
        "REDIS_HOST"
        "REDIS_PORT"
        "REDIS_PASSWORD"
        "KONG_ADMIN_PORT"
        "KONG_PROXY_PORT"
        "NGINX_PROXY_PORT"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set"
        else
            log_success "Required variable $var is set"
        fi
    done
}

validate_api_key_format() {
    log_info "Validating API key format..."
    
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        if [[ "$ANTHROPIC_API_KEY" =~ ^\$\{.*\}$ ]]; then
            log_warning "ANTHROPIC_API_KEY appears to be a placeholder variable"
        elif [[ "$ANTHROPIC_API_KEY" =~ ^sk-ant-api03- ]]; then
            log_success "ANTHROPIC_API_KEY format is valid"
        else
            log_error "ANTHROPIC_API_KEY format is invalid (should start with sk-ant-api03-)"
        fi
    fi
}

validate_port_configuration() {
    log_info "Validating port configuration..."
    
    local ports=(
        "REDIS_PORT:${REDIS_PORT:-}"
        "KONG_ADMIN_PORT:${KONG_ADMIN_PORT:-}"
        "KONG_PROXY_PORT:${KONG_PROXY_PORT:-}"
        "NGINX_PROXY_PORT:${NGINX_PROXY_PORT:-}"
    )
    
    for port_def in "${ports[@]}"; do
        local port_name="${port_def%%:*}"
        local port_value="${port_def##*:}"
        
        if [[ -n "$port_value" ]]; then
            if [[ "$port_value" =~ ^[0-9]+$ ]] && [ "$port_value" -ge 1024 ] && [ "$port_value" -le 65535 ]; then
                log_success "$port_name ($port_value) is valid"
            else
                log_error "$port_name ($port_value) is invalid (should be 1024-65535)"
            fi
        fi
    done
}

validate_memory_settings() {
    log_info "Validating memory settings..."
    
    local memory_vars=(
        "KONG_MEM_CACHE_SIZE:${KONG_MEM_CACHE_SIZE:-}"
        "KONG_MEMORY_LIMIT:${KONG_MEMORY_LIMIT:-}"
    )
    
    for memory_def in "${memory_vars[@]}"; do
        local memory_name="${memory_def%%:*}"
        local memory_value="${memory_def##*:}"
        
        if [[ -n "$memory_value" ]]; then
            if [[ "$memory_value" =~ ^[0-9]+[MGmg]$ ]]; then
                log_success "$memory_name ($memory_value) format is valid"
            else
                log_warning "$memory_name ($memory_value) format may be invalid (expected: number + M/G)"
            fi
        fi
    done
}

validate_network_settings() {
    log_info "Validating network settings..."
    
    if [[ -n "${SUBNET_RANGE:-}" ]]; then
        if [[ "$SUBNET_RANGE" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            log_success "SUBNET_RANGE ($SUBNET_RANGE) format is valid"
        else
            log_error "SUBNET_RANGE ($SUBNET_RANGE) format is invalid"
        fi
    fi
    
    if [[ -n "${NETWORK_NAME:-}" ]]; then
        if [[ "$NETWORK_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log_success "NETWORK_NAME ($NETWORK_NAME) format is valid"
        else
            log_error "NETWORK_NAME ($NETWORK_NAME) contains invalid characters"
        fi
    fi
}

validate_security_settings() {
    log_info "Validating security settings..."
    
    # Check Redis password strength
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        if [[ "${#REDIS_PASSWORD}" -ge 32 ]]; then
            log_success "REDIS_PASSWORD length is sufficient (${#REDIS_PASSWORD} characters)"
        else
            log_warning "REDIS_PASSWORD is short (${#REDIS_PASSWORD} characters, recommended: 32+)"
        fi
    fi
    
    # Environment-specific security checks
    if [[ "$ENVIRONMENT" == "production" ]]; then
        if [[ "${ENABLE_DEBUG_LOGS:-}" == "true" ]]; then
            log_error "Debug logs should be disabled in production"
        fi
        
        if [[ "${KONG_LOG_LEVEL:-}" != "warn" && "${KONG_LOG_LEVEL:-}" != "error" ]]; then
            log_warning "Consider using 'warn' or 'error' log level in production"
        fi
    fi
}

validate_docker_compose_compatibility() {
    log_info "Validating Docker Compose compatibility..."
    
    local compose_file="$PROJECT_ROOT/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log_success "Docker Compose file found"
        
        # Check if required services are defined
        local required_services=("redis" "kong" "nginx" "claude-code-sdk")
        for service in "${required_services[@]}"; do
            if grep -q "^  $service:" "$compose_file"; then
                log_success "Service '$service' found in docker-compose.yml"
            else
                log_error "Service '$service' not found in docker-compose.yml"
            fi
        done
    else
        log_error "Docker Compose file not found: $compose_file"
    fi
}

generate_validation_report() {
    echo
    echo "=========================================="
    echo "Configuration Validation Report"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Config File: $CONFIG_FILE"
    echo "Timestamp: $(date)"
    echo
    echo "Results:"
    echo "  Errors: $VALIDATION_ERRORS"
    echo "  Warnings: $VALIDATION_WARNINGS"
    echo
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log_success "Configuration validation PASSED"
        if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
            log_warning "$VALIDATION_WARNINGS warnings found - review recommended"
        fi
        return 0
    else
        log_error "Configuration validation FAILED with $VALIDATION_ERRORS errors"
        return 1
    fi
}

# Main validation process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Config Validator"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo
    
    # Run all validations
    validate_file_exists || exit 1
    validate_required_variables
    validate_api_key_format
    validate_port_configuration
    validate_memory_settings
    validate_network_settings
    validate_security_settings
    validate_docker_compose_compatibility
    
    # Generate report and exit with appropriate code
    generate_validation_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment]"
    echo
    echo "Validates environment configuration for Kong AWS Masking MVP"
    echo
    echo "Arguments:"
    echo "  environment    Environment to validate (development|staging|production)"
    echo "                 Default: development"
    echo
    echo "Examples:"
    echo "  $0                    # Validate development environment"
    echo "  $0 staging           # Validate staging environment"
    echo "  $0 production        # Validate production environment"
    echo
    exit 0
fi

# Run main function
main "$@"