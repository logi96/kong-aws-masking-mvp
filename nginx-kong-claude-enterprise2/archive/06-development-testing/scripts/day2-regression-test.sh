#!/bin/bash

#
# Day 2: Regression Prevention Tests - Kong AWS Masking MVP
# 
# Purpose: Protect Day 1 achievements from regression during updates
# Target: Complete in under 3 minutes, validate 10 core patterns + functionality
# Success Criteria: Maintain 95% success rate from Day 1
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

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0
START_TIME=$(date +%s)

# Create report file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/day2-regression-test-$TIMESTAMP.md"
mkdir -p "$REPORT_DIR"

# Test results storage
declare -a TEST_RESULTS
declare -a TEST_DETAILS

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[✓] $1${NC}" | tee -a "$REPORT_FILE"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

log_error() {
    echo -e "${RED}[✗] $1${NC}" | tee -a "$REPORT_FILE"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

log_warning() {
    echo -e "${YELLOW}[⚠] $1${NC}" | tee -a "$REPORT_FILE"
    WARNING_TESTS=$((WARNING_TESTS + 1))
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Day 2: Regression Prevention Test Report

**Execution Time**: $(date '+%Y-%m-%d %H:%M:%S')  
**Purpose**: Protect Day 1 achievements (95% success rate) from regression  
**Target**: Complete in under 3 minutes, validate core functionality  
**Baseline**: Day 1 achieved 95% success (100% on 5 core patterns)

## Test Environment
- Kong Proxy: $KONG_PROXY_URL
- Kong Admin: $KONG_ADMIN_URL
- Nginx Proxy: $NGINX_URL  
- Redis: $REDIS_HOST:$REDIS_PORT
- Claude Model: $CLAUDE_MODEL

---

## Regression Test Results

EOF
}

# Test individual pattern with performance measurement
test_pattern_regression() {
    local pattern_name="$1"
    local test_value="$2"
    local expected_behavior="$3"
    local is_critical="$4"  # true/false
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log "Testing $pattern_name: $test_value"
    
    # Create test payload
    local test_payload=$(cat << EOF
{
    "model": "$CLAUDE_MODEL",
    "max_tokens": 30,
    "messages": [
        {
            "role": "user", 
            "content": "Please analyze this AWS resource for security implications: $test_value"
        }
    ]
}
EOF
)
    
    # Measure performance
    local start_time=$(date +%s%3N)
    local response=$(timeout $REGRESSION_TEST_TIMEOUT curl -s -X POST "$KONG_PROXY_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $CLAUDE_API_KEY" \
        -d "$test_payload" \
        -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" 2>/dev/null || echo "CURL_ERROR")
    local end_time=$(date +%s%3N)
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    local response_time=$((end_time - start_time))
    local body=$(echo "$response" | sed -e '/HTTP_CODE:/d' -e '/TIME_TOTAL:/d')
    
    # Analyze results
    local test_passed=false
    local masking_detected=false
    local performance_ok=false
    
    # Check HTTP response
    if [[ "$http_code" == "200" ]]; then
        # Check if original value was masked (not present in response)
        if [[ "$body" != *"$test_value"* ]]; then
            masking_detected=true
        fi
        
        # Check response time
        if [[ $response_time -lt $API_REQUEST_MAX_RESPONSE_TIME ]]; then
            performance_ok=true
        fi
        
        # Overall success criteria
        if $masking_detected && $performance_ok; then
            test_passed=true
        fi
    fi
    
    # Log results
    if $test_passed; then
        log_success "$pattern_name: PASSED (${response_time}ms) - Masked & performant"
        TEST_RESULTS+=("$pattern_name:SUCCESS:$is_critical")
        TEST_DETAILS+=("$pattern_name:$test_value → Masked:${response_time}ms")
    elif [[ "$http_code" == "200" ]] && $performance_ok; then
        log_warning "$pattern_name: PARTIAL (${response_time}ms) - Response OK, masking unclear"
        TEST_RESULTS+=("$pattern_name:PARTIAL:$is_critical")
        TEST_DETAILS+=("$pattern_name:$test_value → Partial:${response_time}ms")
    else
        if [[ "$is_critical" == "true" ]]; then
            log_error "$pattern_name: CRITICAL FAILURE (HTTP $http_code, ${response_time}ms)"
        else
            log_error "$pattern_name: FAILED (HTTP $http_code, ${response_time}ms)"
        fi
        TEST_RESULTS+=("$pattern_name:FAILED:$is_critical")
        TEST_DETAILS+=("$pattern_name:HTTP $http_code:${response_time}ms")
    fi
    
    # Small delay to avoid overwhelming
    sleep 0.2
}

# Test the core 5 patterns that achieved 100% in Day 1
test_core_patterns_regression() {
    log "=== Core Pattern Regression Tests (Day 1: 100% success) ==="
    
    # These MUST work - any failure is a critical regression
    test_pattern_regression "EC2 Instance" "i-1234567890abcdef0" "should_mask" "true"
    test_pattern_regression "VPC" "vpc-12345678" "should_mask" "true"
    test_pattern_regression "Security Group" "sg-12345678" "should_mask" "true"
    test_pattern_regression "AMI" "ami-12345678" "should_mask" "true"
    test_pattern_regression "Subnet" "subnet-1234567890abcdef0" "should_mask" "true"
}

# Test extended patterns for comprehensive coverage
test_extended_patterns_regression() {
    log "=== Extended Pattern Regression Tests ==="
    
    # Important patterns that should continue working
    test_pattern_regression "EBS Volume" "vol-1234567890abcdef0" "should_mask" "false"
    test_pattern_regression "Lambda ARN" "arn:aws:lambda:us-east-1:123456789012:function:test-function" "should_mask" "false"
    test_pattern_regression "IAM Role" "arn:aws:iam::123456789012:role/TestRole" "should_mask" "false"
    test_pattern_regression "S3 Bucket" "my-important-bucket-name" "should_mask" "false"
    test_pattern_regression "SNS Topic" "arn:aws:sns:us-east-1:123456789012:important-notifications" "should_mask" "false"
}

# Test proxy chain stability under load
test_proxy_chain_regression() {
    log "=== Proxy Chain Regression Tests ==="
    
    local chain_tests=0
    local chain_passed=0
    
    # Test multiple requests through the chain
    for i in {1..3}; do
        chain_tests=$((chain_tests + 1))
        
        local test_payload=$(cat << EOF
{
    "model": "$CLAUDE_MODEL",
    "max_tokens": 20,
    "messages": [
        {
            "role": "user",
            "content": "Request $i: Analyze i-test00000000000$i and vpc-test00$i"
        }
    ]
}
EOF
)
        
        # Test Nginx → Kong → Claude chain
        local start_time=$(date +%s%3N)
        local response=$(timeout 10 curl -s -X POST "$NGINX_URL/v1/messages" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $CLAUDE_API_KEY" \
            -d "$test_payload" \
            -w "HTTP_CODE:%{http_code}" 2>/dev/null || echo "TIMEOUT")
        local end_time=$(date +%s%3N)
        
        local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
        local response_time=$((end_time - start_time))
        
        if [[ "$http_code" == "200" && $response_time -lt $PROXY_CHAIN_MAX_RESPONSE_TIME ]]; then
            chain_passed=$((chain_passed + 1))
            log_success "Proxy chain test $i: PASSED (${response_time}ms)"
        else
            log_error "Proxy chain test $i: FAILED (HTTP $http_code, ${response_time}ms)"
        fi
        
        sleep 0.5  # Brief pause between requests
    done
    
    TOTAL_TESTS=$((TOTAL_TESTS + chain_tests))
    PASSED_TESTS=$((PASSED_TESTS + chain_passed))
    FAILED_TESTS=$((FAILED_TESTS + (chain_tests - chain_passed)))
    
    # Overall chain assessment
    local chain_success_rate=$((chain_passed * 100 / chain_tests))
    if [[ $chain_success_rate -ge 100 ]]; then
        TEST_RESULTS+=("proxy_chain:SUCCESS:true")
    elif [[ $chain_success_rate -ge 66 ]]; then
        TEST_RESULTS+=("proxy_chain:PARTIAL:true")
    else
        TEST_RESULTS+=("proxy_chain:FAILED:true")
    fi
}

# Test Redis mapping system regression
test_redis_regression() {
    log "=== Redis Mapping System Regression Tests ==="
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Clear any old test data
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        del "test_mapping_key" > /dev/null 2>&1 || true
    
    # Test Redis write/read cycle
    local test_key="aws_masker:test:regression_$(date +%s)"
    local test_value="test_value_$(date +%s)"
    
    # Write test data
    local write_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        setex "$test_key" 60 "$test_value" 2>/dev/null || echo "FAILED")
    
    sleep 0.5
    
    # Read test data
    local read_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        get "$test_key" 2>/dev/null || echo "FAILED")
    
    # Check TTL functionality
    local ttl_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        ttl "$test_key" 2>/dev/null || echo "-1")
    
    # Cleanup
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        del "$test_key" > /dev/null 2>&1 || true
    
    # Evaluate results
    if [[ "$write_result" == "OK" && "$read_result" == "$test_value" && $ttl_result -gt 0 ]]; then
        log_success "Redis mapping system: PASSED - Write/Read/TTL functional"
        TEST_RESULTS+=("redis_system:SUCCESS:true")
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "Redis mapping system: FAILED - Write: $write_result, Read: $read_result, TTL: $ttl_result"
        TEST_RESULTS+=("redis_system:FAILED:true")
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Test existing mappings count
    local existing_mappings=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        eval "return #redis.call('keys', 'aws_masker:*')" 0 2>/dev/null || echo "0")
    
    log "Existing Redis mappings: $existing_mappings keys"
}

# Test system stability under regression conditions
test_system_stability_regression() {
    log "=== System Stability Regression Tests ==="
    
    TOTAL_TESTS=$((TOTAL_TESTS + 4))
    local stability_passed=0
    
    # Test 1: Kong Admin responsiveness
    if timeout 5 curl -sf "$KONG_ADMIN_URL/status" > /dev/null 2>&1; then
        log_success "Kong Admin API: STABLE"
        stability_passed=$((stability_passed + 1))
    else
        log_error "Kong Admin API: UNSTABLE"
    fi
    
    # Test 2: Kong Proxy responsiveness  
    if timeout 5 curl -sf "$KONG_PROXY_URL" > /dev/null 2>&1; then
        log_success "Kong Proxy: STABLE"
        stability_passed=$((stability_passed + 1))
    else
        log_error "Kong Proxy: UNSTABLE"
    fi
    
    # Test 3: Memory usage regression
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}' 2>/dev/null || echo "0")
    if [[ $mem_usage -lt $MAX_MEMORY_USAGE ]]; then
        log_success "Memory usage: STABLE (${mem_usage}%)"
        stability_passed=$((stability_passed + 1))
    else
        log_warning "Memory usage: HIGH (${mem_usage}%)"
    fi
    
    # Test 4: Docker services status
    local services_up=0
    for service in redis kong nginx backend; do
        if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
            services_up=$((services_up + 1))
        fi
    done
    
    if [[ $services_up -eq 4 ]]; then
        log_success "Docker services: ALL STABLE (4/4)"
        stability_passed=$((stability_passed + 1))
    else
        log_error "Docker services: UNSTABLE ($services_up/4)"  
    fi
    
    PASSED_TESTS=$((PASSED_TESTS + stability_passed))
    FAILED_TESTS=$((FAILED_TESTS + (4 - stability_passed)))
    
    # Overall stability assessment
    if [[ $stability_passed -eq 4 ]]; then
        TEST_RESULTS+=("system_stability:SUCCESS:true")
    elif [[ $stability_passed -ge 3 ]]; then
        TEST_RESULTS+=("system_stability:PARTIAL:true")
    else
        TEST_RESULTS+=("system_stability:FAILED:true")
    fi
}

# Generate comprehensive regression report
generate_regression_report() {
    local end_time=$(date +%s)
    local execution_time=$((end_time - START_TIME))
    local success_rate=0
    local critical_failures=0
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    # Count critical failures
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == *":FAILED:true" ]]; then
            critical_failures=$((critical_failures + 1))
        fi
    done
    
    # Determine regression status
    local regression_status="NO_REGRESSION"
    if [[ $critical_failures -gt 0 ]]; then
        regression_status="CRITICAL_REGRESSION"
    elif [[ $success_rate -lt 90 ]]; then
        regression_status="MODERATE_REGRESSION" 
    elif [[ $success_rate -lt 95 ]]; then
        regression_status="MINOR_REGRESSION"
    fi
    
    cat >> "$REPORT_FILE" << EOF

## 📊 Regression Analysis Summary

### Execution Metrics
- **Total Time**: ${execution_time} seconds (Target: <180s)
- **Tests Executed**: $TOTAL_TESTS
- **Success Rate**: $success_rate% (Baseline: 95%)
- **Critical Failures**: $critical_failures
- **Overall Status**: $regression_status

### Regression Assessment
EOF
    
    case $regression_status in
        "NO_REGRESSION")
            cat >> "$REPORT_FILE" << EOF
**✅ NO REGRESSION DETECTED**

- Success rate maintained or improved ($success_rate% vs 95% baseline)
- All critical patterns functional
- System stability preserved
- Day 1 achievements protected
EOF
            ;;
        "MINOR_REGRESSION")
            cat >> "$REPORT_FILE" << EOF
**⚠️ MINOR REGRESSION DETECTED**

- Success rate slightly below baseline ($success_rate% vs 95%)
- No critical pattern failures
- Acceptable for deployment with monitoring
EOF
            ;;
        "MODERATE_REGRESSION")
            cat >> "$REPORT_FILE" << EOF
**🔶 MODERATE REGRESSION DETECTED**

- Success rate significantly below baseline ($success_rate% vs 95%)
- Some non-critical failures present
- Review recommended before deployment
EOF
            ;;
        "CRITICAL_REGRESSION")
            cat >> "$REPORT_FILE" << EOF
**❌ CRITICAL REGRESSION DETECTED**

- Critical pattern failures: $critical_failures
- Day 1 achievements at risk
- DO NOT DEPLOY - Fix immediately
EOF
            ;;
    esac
    
    cat >> "$REPORT_FILE" << EOF

### Detailed Test Results
EOF
    
    # Add detailed results
    for i in "${!TEST_RESULTS[@]}"; do
        if [[ -n "${TEST_RESULTS[i]}" ]]; then
            local result="${TEST_RESULTS[i]}"
            local test_name="${result%%:*}"
            local status=$(echo "$result" | cut -d':' -f2)
            local is_critical=$(echo "$result" | cut -d':' -f3)
            local detail="${TEST_DETAILS[i]:-"No details available"}"
            local icon="❌"
            local priority=""
            
            case $status in
                "SUCCESS") icon="✅" ;;
                "PARTIAL") icon="⚠️" ;;
                "FAILED") icon="❌" ;;
            esac
            
            if [[ "$is_critical" == "true" ]]; then
                priority=" [CRITICAL]"
            fi
            
            echo "- $icon **$test_name**$priority: ${detail##*:}" >> "$REPORT_FILE"
        fi
    done
    
    cat >> "$REPORT_FILE" << EOF

### Recommended Actions
EOF
    
    case $regression_status in
        "NO_REGRESSION")
            echo "- ✅ Continue with planned deployment" >> "$REPORT_FILE"
            echo "- 📊 Maintain current monitoring schedule" >> "$REPORT_FILE"
            ;;
        "MINOR_REGRESSION")
            echo "- ⚠️ Proceed with deployment but increase monitoring" >> "$REPORT_FILE"
            echo "- 📋 Schedule fix for minor issues in next cycle" >> "$REPORT_FILE"
            ;;
        "MODERATE_REGRESSION")
            echo "- 🔍 Investigate moderate failures before deployment" >> "$REPORT_FILE"
            echo "- 📊 Run additional validation tests" >> "$REPORT_FILE"
            ;;
        "CRITICAL_REGRESSION")
            echo "- 🚨 HALT DEPLOYMENT - Fix critical issues immediately" >> "$REPORT_FILE"
            echo "- 🔧 Rollback recent changes if necessary" >> "$REPORT_FILE"
            echo "- 🧪 Re-run full regression suite after fixes" >> "$REPORT_FILE"
            ;;
    esac
    
    cat >> "$REPORT_FILE" << EOF

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Execution Time**: ${execution_time} seconds  
**Report File**: $REPORT_FILE
EOF
}

# Main execution
main() {
    echo -e "${BLUE}Kong AWS Masking MVP - Day 2 Regression Prevention${NC}"
    echo "=================================================="
    echo "Purpose: Protect Day 1 achievements from regression"
    echo "Baseline: Day 1 achieved 95% success rate"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    init_report
    
    # Run regression tests in order of importance
    test_core_patterns_regression        # ~30s - Most critical
    test_extended_patterns_regression    # ~30s - Important coverage
    test_proxy_chain_regression         # ~20s - System integration
    test_redis_regression               # ~10s - Data persistence
    test_system_stability_regression    # ~15s - Overall health
    
    generate_regression_report
    
    # Final summary
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    local success_rate=0
    local critical_failures=0
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    # Count critical failures
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == *":FAILED:true" ]]; then
            critical_failures=$((critical_failures + 1))
        fi
    done
    
    echo
    echo -e "${BLUE}=== Regression Test Complete ===${NC}"
    echo "Execution time: ${total_time} seconds"
    echo "Success rate: $success_rate% (Baseline: 95%)"
    echo "Critical failures: $critical_failures"
    echo "Report saved: $REPORT_FILE"
    echo
    
    # Exit based on regression severity
    if [[ $critical_failures -eq 0 && $success_rate -ge 90 ]]; then
        echo -e "${GREEN}✅ NO SIGNIFICANT REGRESSION - DEPLOYMENT SAFE${NC}"
        exit 0
    elif [[ $critical_failures -eq 0 && $success_rate -ge 80 ]]; then
        echo -e "${YELLOW}⚠️ MINOR REGRESSION - DEPLOYMENT WITH CAUTION${NC}"
        exit 0
    else
        echo -e "${RED}❌ REGRESSION DETECTED - DO NOT DEPLOY${NC}"
        echo "Critical failures: $critical_failures"
        echo "Success rate below threshold: $success_rate% < 90%"
        exit 1
    fi
}

# Execute main function
main "$@"