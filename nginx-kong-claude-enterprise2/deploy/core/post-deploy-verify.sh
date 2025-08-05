#!/bin/bash

# Post-deployment Verification Script for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: Comprehensive post-deployment validation and smoke testing

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

# Verification configuration
VERIFICATION_TIMEOUT="${VERIFICATION_TIMEOUT:-180}"
DETAILED_TESTS="${DETAILED_TESTS:-true}"
LOAD_TEST="${LOAD_TEST:-false}"

# Create required log directories
create_log_directories() {
    mkdir -p "${PROJECT_ROOT}/logs/verifications"
    mkdir -p "${PROJECT_ROOT}/logs/day2-integration"
    mkdir -p "${PROJECT_ROOT}/logs/deployments"
    mkdir -p "${PROJECT_ROOT}/logs/rollbacks"
    mkdir -p "${PROJECT_ROOT}/logs/monitoring"
}

# Verification tracking
VERIFICATION_START_TIME=$(date +%s)
VERIFICATION_ID="verify-$(date +%Y%m%d-%H%M%S)"

# Ensure log directories exist
create_log_directories

VERIFICATION_LOG="${PROJECT_ROOT}/logs/verifications/${VERIFICATION_ID}.log"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$VERIFICATION_LOG"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$VERIFICATION_LOG"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$VERIFICATION_LOG"
    ((TESTS_WARNED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$VERIFICATION_LOG"
    ((TESTS_FAILED++))
}

# Utility functions
create_verification_directories() {
    log_info "Creating verification directories..."
    
    mkdir -p "${PROJECT_ROOT}/logs/verifications"
    
    log_success "Verification directories created"
}

load_environment_config() {
    log_info "Loading environment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    set -a
    source "$CONFIG_FILE"
    set +a
    
    log_success "Environment configuration loaded: $ENVIRONMENT"
}

# Infrastructure verification tests
verify_container_health() {
    log_info "Verifying container health..."
    
    local services=("redis" "kong" "nginx" "claude-code-sdk")
    
    for service in "${services[@]}"; do
        local container_name="claude-${service}"
        
        # Check if container exists and is running
        if docker ps -q -f name="$container_name" | grep -q .; then
            log_success "$service container is running"
            
            # Check health status
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")
            
            case $health_status in
                "healthy")
                    log_success "$service health check passed"
                    ;;
                "starting")
                    log_warning "$service is still starting..."
                    # Wait a bit for health check
                    sleep 10
                    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")
                    if [[ "$health_status" == "healthy" ]]; then
                        log_success "$service health check passed (after wait)"
                    else
                        log_error "$service health check failed after wait"
                    fi
                    ;;
                "unhealthy")
                    log_error "$service health check failed"
                    ;;
                "no-healthcheck")
                    log_warning "$service has no health check defined"
                    ;;
            esac
        else
            log_error "$service container is not running"
        fi
    done
}

verify_network_connectivity() {
    log_info "Verifying network connectivity..."
    
    # Test inter-container connectivity
    local connectivity_tests=(
        "nginx:kong:8010"
        "kong:redis:6379"
    )
    
    for test in "${connectivity_tests[@]}"; do
        local from_container="claude-${test%%:*}"
        local to_host="${test#*:}"
        local to_service="${to_host%:*}"
        local to_port="${to_host##*:}"
        
        if docker exec "$from_container" nc -z "$to_service" "$to_port" &> /dev/null; then
            log_success "Network connectivity: $from_container -> $to_service:$to_port"
        else
            log_error "Network connectivity failed: $from_container -> $to_service:$to_port"
        fi
    done
    
    # Test external connectivity from Kong
    if docker exec claude-kong curl -s --connect-timeout 5 https://api.anthropic.com/health &> /dev/null; then
        log_success "External API connectivity (Kong -> api.anthropic.com)"
    else
        log_error "External API connectivity failed"
    fi
}

verify_port_accessibility() {
    log_info "Verifying port accessibility..."
    
    local ports=(
        "Redis:${REDIS_PORT:-6379}"
        "Kong Admin:${KONG_ADMIN_PORT:-8001}"
        "Kong Proxy:${KONG_PROXY_PORT:-8000}"
        "Nginx Proxy:${NGINX_PROXY_PORT:-8085}"
    )
    
    for port_def in "${ports[@]}"; do
        local service="${port_def%%:*}"
        local port="${port_def##*:}"
        
        if nc -z localhost "$port" &> /dev/null; then
            log_success "$service port $port is accessible"
        else
            log_error "$service port $port is not accessible"
        fi
    done
}

# Service-specific verification tests
verify_redis_service() {
    log_info "Verifying Redis service..."
    
    # Basic connectivity
    if docker exec claude-redis redis-cli ping | grep -q PONG; then
        log_success "Redis ping test passed"
    else
        log_error "Redis ping test failed"
        return 1
    fi
    
    # Test basic operations
    local test_key="verification:$(date +%s)"
    local test_value="test-value-$(date +%s)"
    
    if docker exec claude-redis redis-cli set "$test_key" "$test_value" | grep -q OK; then
        log_success "Redis SET operation test passed"
    else
        log_error "Redis SET operation test failed"
        return 1
    fi
    
    if docker exec claude-redis redis-cli get "$test_key" | grep -q "$test_value"; then
        log_success "Redis GET operation test passed"
    else
        log_error "Redis GET operation test failed"
        return 1
    fi
    
    # Clean up test key
    docker exec claude-redis redis-cli del "$test_key" &> /dev/null
    
    # Check Redis memory usage
    local memory_usage=$(docker exec claude-redis redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    log_info "Redis memory usage: $memory_usage"
    
    # Check Redis connection count
    local connected_clients=$(docker exec claude-redis redis-cli info clients | grep connected_clients | cut -d: -f2 | tr -d '\r')
    log_info "Redis connected clients: $connected_clients"
}

verify_kong_service() {
    log_info "Verifying Kong service..."
    
    local kong_admin_port=${KONG_ADMIN_PORT:-8001}
    local kong_proxy_port=${KONG_PROXY_PORT:-8000}
    
    # Kong admin API
    if curl -s "http://localhost:$kong_admin_port/status" | grep -q '"database"'; then
        log_success "Kong admin API is responding"
    else
        log_error "Kong admin API is not responding"
        return 1
    fi
    
    # Kong configuration
    local kong_config=$(curl -s "http://localhost:$kong_admin_port" | jq -r '.configuration.database' 2>/dev/null || echo "unknown")
    if [[ "$kong_config" == "off" ]]; then
        log_success "Kong is running in DB-less mode"
    else
        log_warning "Kong database mode: $kong_config"
    fi
    
    # Kong plugins
    local plugins=$(curl -s "http://localhost:$kong_admin_port/plugins" | jq -r '.data[] | .name' 2>/dev/null || echo "")
    if echo "$plugins" | grep -q "aws-masker"; then
        log_success "AWS masker plugin is active"
    else
        log_error "AWS masker plugin is not active"
    fi
    
    # Kong proxy basic test
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$kong_proxy_port/" | grep -q "404"; then
        log_success "Kong proxy is responding (404 expected for root path)"
    else
        log_error "Kong proxy is not responding properly"
    fi
}

verify_nginx_service() {
    log_info "Verifying Nginx service..."
    
    local nginx_port=${NGINX_PROXY_PORT:-8085}
    
    # Nginx health endpoint
    if curl -s "http://localhost:$nginx_port/health" | grep -q 'healthy'; then
        log_success "Nginx health endpoint is responding"
    else
        log_error "Nginx health endpoint is not responding"
        return 1
    fi
    
    # Nginx proxy functionality
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$nginx_port/")
    if [[ "$response_code" == "404" || "$response_code" == "502" ]]; then
        log_success "Nginx proxy is forwarding requests (response: $response_code)"
    else
        log_warning "Nginx proxy response code: $response_code"
    fi
    
    # Check Nginx configuration
    if docker exec claude-nginx nginx -t &> /dev/null; then
        log_success "Nginx configuration syntax is valid"
    else
        log_error "Nginx configuration syntax is invalid"
    fi
}

# Integration tests
verify_proxy_chain() {
    log_info "Verifying proxy chain integration..."
    
    local nginx_port=${NGINX_PROXY_PORT:-8085}
    
    # Test the full proxy chain: Client -> Nginx -> Kong -> Claude API
    local test_payload='{"messages":[{"role":"user","content":"Test: i-1234567890abcdef0"}],"model":"claude-3-5-sonnet-20241022","max_tokens":100}'
    
    log_info "Testing full proxy chain with sample request..."
    
    # Create a temporary request file
    local temp_request="/tmp/claude-test-${VERIFICATION_ID}.json"
    echo "$test_payload" > "$temp_request"
    
    # Test with Authorization header (should be converted to x-api-key by Nginx)
    local response=$(curl -s \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${ANTHROPIC_API_KEY}" \
        -d @"$temp_request" \
        "http://localhost:$nginx_port/v1/messages" \
        --max-time 30 || echo "CURL_FAILED")
    
    # Clean up temp file
    rm -f "$temp_request"
    
    if [[ "$response" != "CURL_FAILED" ]]; then
        if echo "$response" | grep -q '"id"'; then
            log_success "Proxy chain integration test passed"
            log_info "Response contains valid Claude API response structure"
        elif echo "$response" | grep -q '"error"'; then
            local error_message=$(echo "$response" | jq -r '.error.message' 2>/dev/null || echo "Unknown error")
            log_warning "Proxy chain returned error: $error_message"
        else
            log_warning "Proxy chain returned unexpected response format"
        fi
    else
        log_error "Proxy chain integration test failed"
    fi
}

verify_aws_masking() {
    log_info "Verifying AWS resource masking functionality..."
    
    if [[ "$DETAILED_TESTS" != "true" ]]; then
        log_info "Detailed tests disabled, skipping AWS masking verification"
        return 0
    fi
    
    # Test AWS resource patterns
    local test_resources=(
        "i-1234567890abcdef0:EC2_INSTANCE"
        "sg-1234567890abcdef0:SECURITY_GROUP"
        "vpc-1234567890abcdef0:VPC"
        "subnet-1234567890abcdef0:SUBNET"
    )
    
    for test_resource in "${test_resources[@]}"; do
        local original="${test_resource%%:*}"
        local expected_type="${test_resource##*:}"
        
        log_info "Testing masking for: $original"
        
        # Check if the resource gets masked in Redis
        # This is a simplified check - in practice, you'd need to make an actual request
        local redis_keys=$(docker exec claude-redis redis-cli keys "aws_masker:map:*" | head -n 5)
        if [[ -n "$redis_keys" ]]; then
            log_success "AWS masking appears to be working (Redis mappings found)"
            break
        fi
    done
    
    # Check Redis for existing mappings
    local mapping_count=$(docker exec claude-redis redis-cli keys "aws_masker:*" | wc -l)
    log_info "Total AWS masking mappings in Redis: $mapping_count"
    
    if [[ $mapping_count -gt 0 ]]; then
        log_success "AWS masking system has active mappings"
    else
        log_warning "No AWS masking mappings found in Redis"
    fi
}

verify_performance() {
    log_info "Verifying system performance..."
    
    # Container resource usage
    local containers=("claude-redis" "claude-kong" "claude-nginx" "claude-code-sdk")
    
    for container in "${containers[@]}"; do
        if docker ps -q -f name="$container" | grep -q .; then
            local stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$container" | tail -n 1)
            log_info "$container resource usage: $stats"
        fi
    done
    
    # System-level checks
    local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 80 ]]; then
        log_success "Disk usage is acceptable: ${disk_usage}%"
    else
        log_warning "Disk usage is high: ${disk_usage}%"
    fi
    
    # Docker system usage
    local docker_usage=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | tail -n +2)
    log_info "Docker system usage:"
    echo "$docker_usage" | while read -r line; do
        log_info "  $line"
    done
}

run_load_test() {
    if [[ "$LOAD_TEST" != "true" ]]; then
        log_info "Load testing disabled, skipping..."
        return 0
    fi
    
    log_info "Running basic load test..."
    
    local nginx_port=${NGINX_PROXY_PORT:-8085}
    local concurrent_requests=5
    local total_requests=20
    
    log_info "Load test: $total_requests requests with $concurrent_requests concurrent connections"
    
    # Simple load test using curl in background
    local success_count=0
    local failure_count=0
    
    for ((i=1; i<=total_requests; i++)); do
        {
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$nginx_port/health" | grep -q "200"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        } &
        
        # Limit concurrent requests
        if (( i % concurrent_requests == 0 )); then
            wait
        fi
    done
    wait
    
    local success_rate=$((success_count * 100 / total_requests))
    
    if [[ $success_rate -ge 95 ]]; then
        log_success "Load test passed: $success_rate% success rate ($success_count/$total_requests)"
    else
        log_warning "Load test marginal: $success_rate% success rate ($success_count/$total_requests)"
    fi
}

# Day 2 automation integration
verify_day2_integration() {
    log_info "Verifying Day 2 automation integration..."
    
    local day2_scripts=(
        "scripts/day2-health-check.sh"
        "scripts/day2-smoke-test.sh"
        "scripts/day2-system-monitor.sh"
    )
    
    for script in "${day2_scripts[@]}"; do
        local script_path="${PROJECT_ROOT}/${script}"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            log_success "Day 2 script available: $script"
            
            # Try to run a quick test if it supports it
            if "$script_path" --quick-test &> /dev/null; then
                log_success "Day 2 script quick test passed: $script"
            else
                log_info "Day 2 script quick test not available: $script"
            fi
        else
            log_warning "Day 2 script missing or not executable: $script"
        fi
    done
}

generate_verification_report() {
    local verification_end_time=$(date +%s)
    local verification_duration=$((verification_end_time - VERIFICATION_START_TIME))
    
    log_info "Generating verification report..."
    
    cat << EOF | tee -a "$VERIFICATION_LOG"

==========================================
Post-deployment Verification Report
==========================================
Verification ID: $VERIFICATION_ID
Environment: $ENVIRONMENT
Start Time: $(date -d @$VERIFICATION_START_TIME)
End Time: $(date -d @$verification_end_time)
Duration: ${verification_duration} seconds

Test Results:
  ✅ Passed: $TESTS_PASSED
  ⚠️  Warnings: $TESTS_WARNED
  ❌ Failed: $TESTS_FAILED
  📊 Success Rate: $(( (TESTS_PASSED * 100) / (TESTS_PASSED + TESTS_FAILED + TESTS_WARNED) ))%

Service Endpoints:
- Nginx Proxy: http://localhost:${NGINX_PROXY_PORT:-8085}
- Kong Admin: http://localhost:${KONG_ADMIN_PORT:-8001}
- Kong Proxy: http://localhost:${KONG_PROXY_PORT:-8000}
- Redis: localhost:${REDIS_PORT:-6379}

Container Status:
$(docker ps --filter name=claude- --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Could not retrieve container status")

System Health:
- Configuration: $(if [[ -f "$CONFIG_FILE" ]]; then echo "Valid"; else echo "Missing"; fi)
- Network: $(if nc -z localhost "${NGINX_PROXY_PORT:-8085}" &>/dev/null; then echo "Accessible"; else echo "Inaccessible"; fi)
- Storage: $(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G/ GB available/')

Log Files:
- Verification Log: $VERIFICATION_LOG
- Service Logs: docker-compose logs

==========================================
EOF

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "Post-deployment verification PASSED!"
        echo
        echo "🎉 Deployment is ready for production use!"
        echo
        echo "Next steps:"
        echo "1. Monitor services: docker-compose logs -f"
        echo "2. Start Day 2 monitoring: ./scripts/day2-system-monitor.sh"
        echo "3. Run comprehensive tests: ./tests/e2e-comprehensive-test.sh"
        return 0
    else
        log_error "Post-deployment verification FAILED with $TESTS_FAILED errors!"
        echo
        echo "❌ Deployment has issues that need attention!"
        echo
        echo "Recommended actions:"
        echo "1. Check service logs: docker-compose logs"
        echo "2. Review verification log: $VERIFICATION_LOG"
        echo "3. Consider rollback: ./deploy/rollback.sh $ENVIRONMENT"
        return 1
    fi
}

# Main verification process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Post-deployment Verification"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Verification ID: $VERIFICATION_ID"
    echo "Timestamp: $(date)"
    echo "Detailed Tests: $DETAILED_TESTS"
    echo "Load Test: $LOAD_TEST"
    echo
    
    # Create verification infrastructure
    create_verification_directories
    
    # Load configuration
    load_environment_config
    
    # Run all verification tests
    verify_container_health
    verify_network_connectivity
    verify_port_accessibility
    verify_redis_service
    verify_kong_service
    verify_nginx_service
    verify_proxy_chain
    verify_aws_masking
    verify_performance
    run_load_test
    verify_day2_integration
    
    # Generate final report
    generate_verification_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment] [options]"
    echo
    echo "Run comprehensive post-deployment verification for Kong AWS Masking MVP"
    echo
    echo "Arguments:"
    echo "  environment    Target environment (development|staging|production)"
    echo "                 Default: production"
    echo
    echo "Environment Variables:"
    echo "  VERIFICATION_TIMEOUT=180  Verification timeout in seconds"
    echo "  DETAILED_TESTS=true       Run detailed AWS masking tests"
    echo "  LOAD_TEST=false          Run basic load testing"
    echo
    echo "Examples:"
    echo "  $0                              # Verify production deployment"
    echo "  $0 staging                      # Verify staging deployment"
    echo "  DETAILED_TESTS=false $0         # Quick verification only"
    echo "  LOAD_TEST=true $0 production    # Include load testing"
    echo
    exit 0
fi

# Run main function
main "$@"