#!/bin/bash
# Smoke Tests for Production Deployment

set -euo pipefail

# Configuration
NGINX_URL="http://localhost:8082"
KONG_ADMIN_URL="http://localhost:8001"
API_KEY="${ANTHROPIC_API_KEY}"
TEST_TIMEOUT=30

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Log function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Test function
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Nginx health check
test_nginx_health() {
    curl -sf --max-time $TEST_TIMEOUT "$NGINX_URL/health"
}

# Test 2: Kong admin API
test_kong_admin() {
    curl -sf --max-time $TEST_TIMEOUT "$KONG_ADMIN_URL/status" | grep -q "database"
}

# Test 3: Kong plugin verification
test_kong_plugin() {
    curl -sf --max-time $TEST_TIMEOUT "$KONG_ADMIN_URL/plugins/enabled" | grep -q "aws-masker"
}

# Test 4: Redis connectivity
test_redis_connectivity() {
    docker-compose exec -T redis redis-cli ping | grep -q "PONG"
}

# Test 5: End-to-end API test
test_api_endpoint() {
    local response=$(curl -sf --max-time $TEST_TIMEOUT \
        -X POST "$NGINX_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d '{
            "model": "claude-3-haiku-20240307",
            "max_tokens": 10,
            "messages": [{"role": "user", "content": "test"}]
        }' 2>&1)
    
    # Check if we got a response (either success or API error)
    echo "$response" | grep -qE "(content|error)"
}

# Test 6: AWS masking functionality
test_aws_masking() {
    # Check if masking patterns are loaded
    docker-compose exec -T kong cat /usr/local/kong/plugins/patterns.lua | grep -q "EC2_INSTANCE"
}

# Test 7: Response time check
test_response_time() {
    local start_time=$(date +%s%3N)
    curl -sf --max-time $TEST_TIMEOUT "$NGINX_URL/health" >/dev/null
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    # Check if response time is under 1000ms
    [ $response_time -lt 1000 ]
}

# Test 8: Memory usage check
test_memory_usage() {
    local memory_usage=$(docker stats --no-stream --format "table {{.Container}}\t{{.MemPerc}}" | \
        grep -E "(kong|nginx|redis)" | \
        awk '{print $2}' | sed 's/%//' | \
        awk '{sum += $1} END {print sum}')
    
    # Check if total memory usage is under 80%
    (( $(echo "$memory_usage < 80" | bc -l) ))
}

# Test 9: Log accessibility
test_logs_accessible() {
    [ -d "./logs/nginx" ] && [ -d "./logs/kong" ] && [ -d "./logs/redis" ]
}

# Test 10: Blue-green deployment readiness
test_blue_green_ready() {
    # Check if blue-green configuration exists
    [ -f "./nginx/conf.d/blue-green.conf" ] || [ -f "./docker-compose.override.yml" ]
}

# Main test execution
main() {
    log "${YELLOW}Starting smoke tests...${NC}"
    
    # Basic connectivity tests
    run_test "Nginx Health Check" test_nginx_health
    run_test "Kong Admin API" test_kong_admin
    run_test "Kong AWS Masker Plugin" test_kong_plugin
    run_test "Redis Connectivity" test_redis_connectivity
    
    # Functional tests
    run_test "API Endpoint" test_api_endpoint
    run_test "AWS Masking Patterns" test_aws_masking
    
    # Performance tests
    run_test "Response Time" test_response_time
    run_test "Memory Usage" test_memory_usage
    
    # Operational tests
    run_test "Log Accessibility" test_logs_accessible
    run_test "Blue-Green Deployment" test_blue_green_ready
    
    # Summary
    echo
    log "Test Summary:"
    log "${GREEN}Passed: $TESTS_PASSED${NC}"
    log "${RED}Failed: $TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log "${GREEN}All smoke tests passed!${NC}"
        exit 0
    else
        log "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
main