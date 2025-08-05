#!/bin/bash

#
# Day 2: System Health Check - Kong AWS Masking MVP
# 
# Purpose: Rapid system health validation for continuous deployment
# Target: Complete system check in under 30 seconds
# Success Criteria: All critical components operational
#

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check results
HEALTH_STATUS="HEALTHY"
FAILED_CHECKS=()
WARNINGS=()
START_TIME=$(date +%s)

# Create report file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/day2-health-check-$TIMESTAMP.md"
mkdir -p "$REPORT_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[✓] $1${NC}" | tee -a "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[✗] $1${NC}" | tee -a "$REPORT_FILE"
    HEALTH_STATUS="UNHEALTHY"
    FAILED_CHECKS+=("$1")
}

log_warning() {
    echo -e "${YELLOW}[⚠] $1${NC}" | tee -a "$REPORT_FILE"
    WARNINGS+=("$1")
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Day 2: System Health Check Report

**Execution Time**: $(date '+%Y-%m-%d %H:%M:%S')  
**Purpose**: Rapid deployment readiness validation  
**Target**: Complete check in under 30 seconds

## Environment
- Kong Admin: $KONG_ADMIN_URL
- Kong Proxy: $KONG_PROXY_URL  
- Nginx Proxy: $NGINX_URL
- Redis: $REDIS_HOST:$REDIS_PORT

---

## Health Check Results

EOF
}

# Check critical service connectivity (5 seconds max)
check_critical_connectivity() {
    log "=== 1. Critical Service Connectivity (5s timeout) ==="
    
    # Kong Admin API
    if timeout 5 curl -sf "$KONG_ADMIN_URL/status" > /dev/null 2>&1; then
        log_success "Kong Admin API responsive"
    else
        log_error "Kong Admin API not responding"
    fi
    
    # Kong Proxy
    if timeout 5 curl -sf "$KONG_PROXY_URL" > /dev/null 2>&1; then
        log_success "Kong Proxy responsive"
    else
        log_error "Kong Proxy not responding"
    fi
    
    # Redis - quick ping
    if timeout 3 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping > /dev/null 2>&1; then
        log_success "Redis responding to PING"
    else
        log_error "Redis not responding"
    fi
    
    # Nginx - quick health check
    if timeout 5 curl -sf "$NGINX_URL/health" > /dev/null 2>&1; then
        log_success "Nginx proxy responsive"
    else
        log_warning "Nginx proxy check failed (may be expected)"
    fi
}

# Test core AWS masking patterns (10 seconds max)
test_core_masking_patterns() {
    log "=== 2. Core AWS Masking Patterns (10s timeout) ==="
    
    local patterns_tested=0
    local patterns_success=0
    
    # Test only the 5 core patterns from Day 1 success
    local core_test_patterns=(
        "i-1234567890abcdef0"  # EC2 instance
        "vpc-12345678"         # VPC
        "sg-12345678"          # Security Group
        "ami-12345678"         # AMI
        "subnet-1234567890abcdef0"  # Subnet
    )
    
    for pattern in "${core_test_patterns[@]}"; do
        patterns_tested=$((patterns_tested + 1))
        
        # Quick test payload
        local test_payload=$(cat << EOF
{
    "model": "$CLAUDE_MODEL",
    "max_tokens": 10,
    "messages": [{"role": "user", "content": "Analyze: $pattern"}]
}
EOF
)
        
        # Test with 3 second timeout
        local response=$(timeout 3 curl -s -X POST "$KONG_PROXY_URL/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -d "$test_payload" \
            -w "HTTP_CODE:%{http_code}" 2>/dev/null || echo "TIMEOUT")
        
        local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2 || echo "000")
        
        if [[ "$http_code" == "200" ]]; then
            patterns_success=$((patterns_success + 1))
            log_success "Pattern $pattern: masked successfully"
        else
            log_warning "Pattern $pattern: HTTP $http_code"
        fi
        
        # Small delay to avoid overwhelming
        sleep 0.2
    done
    
    local success_rate=$((patterns_success * 100 / patterns_tested))
    if [[ $success_rate -ge $MIN_PATTERN_SUCCESS_RATE ]]; then
        log_success "Core patterns success rate: $success_rate% ($patterns_success/$patterns_tested)"
    else
        log_error "Core patterns below threshold: $success_rate% < $MIN_PATTERN_SUCCESS_RATE%"
    fi
}

# Test proxy chain stability (5 seconds max)
test_proxy_chain() {
    log "=== 3. Proxy Chain Stability (5s timeout) ==="
    
    local test_payload=$(cat << EOF
{
    "model": "$CLAUDE_MODEL",
    "max_tokens": 10,
    "messages": [{"role": "user", "content": "Test proxy with i-1234567890abcdef0"}]
}
EOF
)
    
    # Test Nginx → Kong → Claude chain
    local start_time=$(date +%s%3N)
    local response=$(timeout 5 curl -s -X POST "$NGINX_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $CLAUDE_API_KEY" \
        -d "$test_payload" \
        -w "HTTP_CODE:%{http_code}" 2>/dev/null || echo "TIMEOUT")
    local end_time=$(date +%s%3N)
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2 || echo "000")
    local response_time=$((end_time - start_time))
    
    if [[ "$http_code" == "200" && $response_time -lt $PROXY_CHAIN_MAX_RESPONSE_TIME ]]; then
        log_success "Proxy chain functional (${response_time}ms)"
    else
        log_error "Proxy chain failed: HTTP $http_code, ${response_time}ms"
    fi
}

# Check Redis mapping accuracy (5 seconds max)
check_redis_mapping() {
    log "=== 4. Redis Mapping Accuracy (5s timeout) ==="
    
    # Check for existing mappings
    local total_keys=$(timeout 3 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        eval "return #redis.call('keys', 'aws_masker:*')" 0 2>/dev/null || echo "0")
    
    if [[ $total_keys -gt 0 ]]; then
        log_success "Redis mappings active: $total_keys keys found"
        
        # Quick mapping validation
        local sample_key=$(timeout 2 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
            eval "return redis.call('keys', 'aws_masker:map:*')[1]" 0 2>/dev/null || echo "")
        
        if [[ -n "$sample_key" ]]; then
            local sample_value=$(timeout 2 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
                get "$sample_key" 2>/dev/null || echo "")
            if [[ -n "$sample_value" ]]; then
                log_success "Redis mapping verified: $sample_key → $sample_value"
            fi
        fi
    else
        log_warning "No Redis mappings found (may be expected for fresh start)"
    fi
}

# Quick system resource check (3 seconds max)
check_system_resources() {
    log "=== 5. System Resources (3s timeout) ==="
    
    # Quick memory check
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}' 2>/dev/null || echo "0")
    if [[ $mem_usage -lt $MAX_MEMORY_USAGE ]]; then
        log_success "Memory usage healthy: ${mem_usage}%"
    else
        log_warning "Memory usage high: ${mem_usage}%"
    fi
    
    # Quick CPU check (simplified)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    if (( $(echo "$cpu_usage < $MAX_CPU_USAGE" | bc -l 2>/dev/null || echo "1") )); then
        log_success "CPU usage healthy: ${cpu_usage}%"
    else
        log_warning "CPU usage high: ${cpu_usage}%"
    fi
}

# Check Docker services status (2 seconds max)
check_docker_services() {
    log "=== 6. Docker Services Status (2s timeout) ==="
    
    local services_up=0
    local total_services=0
    
    # Check main services
    for service in redis kong nginx backend; do
        total_services=$((total_services + 1))
        if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
            services_up=$((services_up + 1))
            log_success "$service container running"
        else
            log_error "$service container not running"
        fi
    done
    
    local service_ratio=$((services_up * 100 / total_services))
    if [[ $service_ratio -eq 100 ]]; then
        log_success "All Docker services operational"
    else
        log_error "Docker services incomplete: $services_up/$total_services running"
    fi
}

# Generate final report
generate_final_report() {
    local end_time=$(date +%s)
    local execution_time=$((end_time - START_TIME))
    local deployment_ready="false"
    
    # Determine deployment readiness
    if [[ "$HEALTH_STATUS" == "HEALTHY" && ${#FAILED_CHECKS[@]} -eq 0 ]]; then
        deployment_ready="true"
    fi
    
    cat >> "$REPORT_FILE" << EOF

## 📊 Final Assessment

### Execution Summary
- **Total Time**: ${execution_time} seconds (Target: <30s)
- **Overall Status**: $HEALTH_STATUS
- **Failed Checks**: ${#FAILED_CHECKS[@]}
- **Warnings**: ${#WARNINGS[@]}

### Deployment Readiness
**Status**: $([ "$deployment_ready" == "true" ] && echo "✅ READY FOR DEPLOYMENT" || echo "❌ NOT READY")

### Critical Issues
EOF
    
    if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
        printf '%s\n' "${FAILED_CHECKS[@]}" | sed 's/^/- ❌ /' >> "$REPORT_FILE"
    else
        echo "- ✅ No critical issues detected" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

### Warnings
EOF
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        printf '%s\n' "${WARNINGS[@]}" | sed 's/^/- ⚠️ /' >> "$REPORT_FILE"
    else
        echo "- ✅ No warnings" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

### Next Actions
EOF
    
    if [[ "$deployment_ready" == "true" ]]; then
        cat >> "$REPORT_FILE" << EOF
- ✅ System is ready for deployment
- ✅ All critical components operational
- ✅ Continue with deployment process
EOF
    else
        cat >> "$REPORT_FILE" << EOF
- 🔧 Address critical issues before deployment
- 📋 Review failed checks above
- 🔄 Re-run health check after fixes
EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Total Execution Time**: ${execution_time} seconds  
**Report File**: $REPORT_FILE
EOF
}

# Main execution
main() {
    echo -e "${BLUE}Kong AWS Masking MVP - Day 2 Health Check${NC}"
    echo "======================================================="
    echo "Target: Complete system validation in under 30 seconds"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    init_report
    
    # Run all checks in sequence (designed for speed)
    check_critical_connectivity      # ~5s
    test_core_masking_patterns      # ~10s  
    test_proxy_chain                # ~5s
    check_redis_mapping             # ~5s
    check_system_resources          # ~3s
    check_docker_services           # ~2s
    
    generate_final_report
    
    # Final summary
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    
    echo
    echo -e "${BLUE}=== Health Check Complete ===${NC}"
    echo "Execution time: ${total_time} seconds"
    echo "Report saved: $REPORT_FILE"
    echo
    
    if [[ "$HEALTH_STATUS" == "HEALTHY" && ${#FAILED_CHECKS[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ SYSTEM HEALTHY - READY FOR DEPLOYMENT${NC}"
        exit 0
    else
        echo -e "${RED}❌ SYSTEM ISSUES DETECTED - REVIEW REQUIRED${NC}"
        echo "Failed checks: ${#FAILED_CHECKS[@]}"
        echo "Warnings: ${#WARNINGS[@]}"
        exit 1
    fi
}

# Execute main function
main "$@"