#!/bin/bash

# Integration Test for nginx-kong-claude-enterprise
# Tests the full flow: Nginx → Kong → Claude API with AWS masking

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_REPORT_DIR="${SCRIPT_DIR}/test-report"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${TEST_REPORT_DIR}/integration-test-report_${TIMESTAMP}.md"

# API Configuration
NGINX_URL="http://localhost:8083"
KONG_ADMIN_URL="http://localhost:8081"
REDIS_PORT=6380

# Ensure test report directory exists
mkdir -p "$TEST_REPORT_DIR"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Integration Test Report
**Generated**: $(date)
**Test Environment**: nginx-kong-claude-enterprise

## Executive Summary
This report contains the results of integration testing for the Kong AWS masking plugin.

## Test Environment
- **Nginx URL**: ${NGINX_URL}
- **Kong Admin URL**: ${KONG_ADMIN_URL}
- **Redis Port**: ${REDIS_PORT}

## Test Results

EOF
}

# Test 1: Service Health Checks
test_service_health() {
    local test_name="Service Health Checks"
    log_info "Testing: $test_name"
    
    echo "### Test 1: $test_name" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Test Nginx health
    local nginx_health=$(curl -s -w "\n%{http_code}" ${NGINX_URL}/health)
    local nginx_code=$(echo "$nginx_health" | tail -n1)
    
    if [ "$nginx_code" = "200" ]; then
        log_success "Nginx health check passed"
        echo "- ✅ Nginx health check: HTTP $nginx_code" >> "$REPORT_FILE"
    else
        log_error "Nginx health check failed: HTTP $nginx_code"
        echo "- ❌ Nginx health check: HTTP $nginx_code" >> "$REPORT_FILE"
    fi
    
    # Test Kong admin
    local kong_health=$(curl -s -w "\n%{http_code}" ${KONG_ADMIN_URL}/status)
    local kong_code=$(echo "$kong_health" | tail -n1)
    
    if [ "$kong_code" = "200" ]; then
        log_success "Kong admin API accessible"
        echo "- ✅ Kong admin API: HTTP $kong_code" >> "$REPORT_FILE"
    else
        log_error "Kong admin API not accessible: HTTP $kong_code"
        echo "- ❌ Kong admin API: HTTP $kong_code" >> "$REPORT_FILE"
    fi
    
    # Test Redis connection
    if redis-cli -p ${REDIS_PORT} ping > /dev/null 2>&1; then
        log_success "Redis connection successful"
        echo "- ✅ Redis connection: Available" >> "$REPORT_FILE"
    else
        log_error "Redis connection failed"
        echo "- ❌ Redis connection: Failed" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# Test 2: AWS Resource Masking
test_aws_masking() {
    local test_name="AWS Resource Masking"
    log_info "Testing: $test_name"
    
    echo "### Test 2: $test_name" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Create test payload with AWS resources
    local payload=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "Please analyze these AWS resources: EC2 instance i-1234567890abcdef0, S3 bucket my-test-bucket, RDS instance prod-database-1, and private IP 10.0.1.100"
    }],
    "max_tokens": 100
}
EOF
)
    
    # Send request through Nginx
    local response=$(curl -s -X POST ${NGINX_URL}/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload" \
        -w "\n%{http_code}\n%{time_total}")
    
    local http_code=$(echo "$response" | tail -n2 | head -n1)
    local response_time=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-2)
    
    log_info "Response code: $http_code, Time: ${response_time}s"
    echo "- Response Code: $http_code" >> "$REPORT_FILE"
    echo "- Response Time: ${response_time}s" >> "$REPORT_FILE"
    
    # Check if masking occurred (look for masked patterns)
    if echo "$body" | grep -q "EC2_[0-9]\+"; then
        log_success "EC2 instance masking detected"
        echo "- ✅ EC2 instance masking: Working" >> "$REPORT_FILE"
    else
        log_warning "EC2 instance masking not detected in response"
        echo "- ⚠️ EC2 instance masking: Not detected" >> "$REPORT_FILE"
    fi
    
    if echo "$body" | grep -q "BUCKET_[0-9]\+"; then
        log_success "S3 bucket masking detected"
        echo "- ✅ S3 bucket masking: Working" >> "$REPORT_FILE"
    else
        log_warning "S3 bucket masking not detected in response"
        echo "- ⚠️ S3 bucket masking: Not detected" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# Test 3: Redis Mapping Storage
test_redis_mapping() {
    local test_name="Redis Mapping Storage"
    log_info "Testing: $test_name"
    
    echo "### Test 3: $test_name" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Check Redis for stored mappings
    local redis_keys=$(redis-cli -p ${REDIS_PORT} --scan --pattern "aws:*" 2>/dev/null | wc -l)
    
    if [ "$redis_keys" -gt 0 ]; then
        log_success "Found $redis_keys AWS mappings in Redis"
        echo "- ✅ Redis mappings found: $redis_keys entries" >> "$REPORT_FILE"
        
        # Sample some mappings
        echo "- Sample mappings:" >> "$REPORT_FILE"
        redis-cli -p ${REDIS_PORT} --scan --pattern "aws:*" 2>/dev/null | head -5 | while read key; do
            local value=$(redis-cli -p ${REDIS_PORT} GET "$key" 2>/dev/null)
            echo "  - $key → $value" >> "$REPORT_FILE"
        done
    else
        log_warning "No AWS mappings found in Redis"
        echo "- ⚠️ No mappings found in Redis" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# Test 4: Performance Benchmark
test_performance() {
    local test_name="Performance Benchmark"
    log_info "Testing: $test_name"
    
    echo "### Test 4: $test_name" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Create payload with many AWS resources
    local large_content=""
    for i in {1..50}; do
        large_content+="EC2 instance i-$(printf '%016x' $i), "
    done
    
    local payload=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "Analyze: $large_content"
    }],
    "max_tokens": 50
}
EOF
)
    
    # Measure response times
    local total_time=0
    local count=5
    
    echo "- Running $count performance tests..." >> "$REPORT_FILE"
    
    for i in $(seq 1 $count); do
        local start_time=$(date +%s.%N)
        
        curl -s -X POST ${NGINX_URL}/ \
            -H "Content-Type: application/json" \
            -H "x-api-key: test-key" \
            -H "anthropic-version: 2023-06-01" \
            -d "$payload" > /dev/null
        
        local end_time=$(date +%s.%N)
        local elapsed=$(echo "$end_time - $start_time" | bc)
        total_time=$(echo "$total_time + $elapsed" | bc)
        
        echo "  - Test $i: ${elapsed}s" >> "$REPORT_FILE"
    done
    
    local avg_time=$(echo "scale=3; $total_time / $count" | bc)
    echo "- Average response time: ${avg_time}s" >> "$REPORT_FILE"
    
    # Check against target
    if (( $(echo "$avg_time < 0.1" | bc -l) )); then
        log_success "Performance target met: ${avg_time}s < 100ms"
        echo "- ✅ Performance target: Met (< 100ms)" >> "$REPORT_FILE"
    else
        log_warning "Performance target not met: ${avg_time}s > 100ms"
        echo "- ⚠️ Performance target: Not met (> 100ms)" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# Test 5: Fail-Secure Mode
test_fail_secure() {
    local test_name="Fail-Secure Mode (Circuit Breaker)"
    log_info "Testing: $test_name"
    
    echo "### Test 5: $test_name" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Stop Redis to trigger fail-secure
    log_info "Stopping Redis to test fail-secure mode..."
    docker stop redis-cache > /dev/null 2>&1
    
    sleep 2
    
    # Try to make a request
    local response=$(curl -s -w "\n%{http_code}" -X POST ${NGINX_URL}/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d '{"model":"claude-3-sonnet-20240229","messages":[{"role":"user","content":"test"}]}')
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "503" ]; then
        log_success "Fail-secure mode activated correctly (HTTP 503)"
        echo "- ✅ Fail-secure mode: Activated (HTTP 503)" >> "$REPORT_FILE"
        
        if echo "$body" | grep -q "REDIS_UNAVAILABLE"; then
            echo "- ✅ Error code: REDIS_UNAVAILABLE detected" >> "$REPORT_FILE"
        fi
    else
        log_error "Fail-secure mode not working properly (HTTP $http_code)"
        echo "- ❌ Fail-secure mode: Not working (HTTP $http_code)" >> "$REPORT_FILE"
    fi
    
    # Restart Redis
    log_info "Restarting Redis..."
    docker start redis-cache > /dev/null 2>&1
    sleep 5
    
    echo "" >> "$REPORT_FILE"
}

# Generate summary
generate_summary() {
    echo "" >> "$REPORT_FILE"
    echo "## Summary" >> "$REPORT_FILE"
    
    local passed=$(grep -c "✅" "$REPORT_FILE")
    local failed=$(grep -c "❌" "$REPORT_FILE")
    local warnings=$(grep -c "⚠️" "$REPORT_FILE")
    
    echo "- Tests Passed: $passed" >> "$REPORT_FILE"
    echo "- Tests Failed: $failed" >> "$REPORT_FILE"
    echo "- Warnings: $warnings" >> "$REPORT_FILE"
    
    echo "" >> "$REPORT_FILE"
    echo "## Recommendations" >> "$REPORT_FILE"
    
    if [ "$failed" -gt 0 ]; then
        echo "1. Fix failed tests before deployment" >> "$REPORT_FILE"
    fi
    
    if [ "$warnings" -gt 0 ]; then
        echo "2. Investigate warning conditions" >> "$REPORT_FILE"
    fi
    
    echo "3. Monitor Redis availability in production" >> "$REPORT_FILE"
    echo "4. Consider implementing request queuing for better performance" >> "$REPORT_FILE"
}

# Main execution
main() {
    log_info "Starting Kong Integration Tests"
    
    init_report
    
    # Check prerequisites
    if ! command -v redis-cli &> /dev/null; then
        log_warning "redis-cli not found, some tests will be skipped"
    fi
    
    if ! command -v bc &> /dev/null; then
        log_error "bc not found, performance tests will fail"
        exit 1
    fi
    
    # Run tests
    test_service_health
    test_aws_masking
    test_redis_mapping
    test_performance
    test_fail_secure
    
    # Generate summary
    generate_summary
    
    log_success "Test suite completed. Report saved to: $REPORT_FILE"
    
    # Display summary
    echo ""
    echo "Test Summary:"
    tail -n 15 "$REPORT_FILE"
}

# Execute main
main