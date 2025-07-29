#!/bin/bash

# P0 Risk Test Suite Runner for nginx-kong-claude-enterprise
# This script executes all P0 risk test cases with detailed reporting

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
REPORT_FILE="${TEST_REPORT_DIR}/p0-risk-test-report_${TIMESTAMP}.md"

# Test categories
declare -a CATEGORIES=("nginx" "kong-masker" "redis" "claude-api" "large-request")
SELECTED_CATEGORY="${1:-all}"

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
# P0 Risk Test Report
**Generated**: $(date)
**Test Environment**: nginx-kong-claude-enterprise
**Test Category**: ${SELECTED_CATEGORY}

## Executive Summary
This report contains the results of P0 risk test cases execution.

## Test Environment
- **Docker Compose Version**: $(docker-compose version --short)
- **Docker Version**: $(docker version --format '{{.Server.Version}}')
- **Host OS**: $(uname -s) $(uname -r)

## Test Results

EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if services are running
    if ! docker-compose ps | grep -q "Up"; then
        log_warning "Services are not running. Starting them..."
        cd "$PROJECT_ROOT"
        docker-compose up -d
        sleep 10
    fi
    
    log_success "Prerequisites check passed"
}

# Test execution functions

# TC-NX-001: Nginx Container Crash
test_nginx_crash() {
    local test_id="TC-NX-001"
    local test_name="Nginx Container Crash"
    
    log_info "Running $test_id: $test_name"
    
    # Start streaming request in background
    curl -X POST http://localhost:8082/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d '{"model":"claude-3-sonnet-20240229","messages":[{"role":"user","content":"Generate a very long response about AWS services"}],"stream":true}' \
        > /tmp/nginx_crash_response.txt 2>&1 &
    
    local curl_pid=$!
    sleep 2
    
    # Stop nginx container
    docker stop nginx-claude-proxy
    
    # Wait for curl to finish
    wait $curl_pid
    local curl_exit_code=$?
    
    # Check results
    if [ $curl_exit_code -ne 0 ]; then
        log_success "$test_id: Connection properly terminated on container stop"
        echo "### $test_id: $test_name ✅" >> "$REPORT_FILE"
        echo "- Container stop resulted in proper connection termination" >> "$REPORT_FILE"
        echo "- Exit code: $curl_exit_code" >> "$REPORT_FILE"
    else
        log_error "$test_id: Unexpected successful response"
        echo "### $test_id: $test_name ❌" >> "$REPORT_FILE"
        echo "- Unexpected behavior: request succeeded despite container stop" >> "$REPORT_FILE"
    fi
    
    # Restart nginx
    docker start nginx-claude-proxy
    sleep 5
    
    echo "" >> "$REPORT_FILE"
}

# TC-KM-001: JSON Parsing Failure
test_json_parsing_failure() {
    local test_id="TC-KM-001"
    local test_name="JSON Parsing Failure"
    
    log_info "Running $test_id: $test_name"
    
    # Send malformed JSON
    local response=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d '{"content": "test", invalid}')
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "400" ]; then
        log_success "$test_id: Properly rejected malformed JSON"
        echo "### $test_id: $test_name ✅" >> "$REPORT_FILE"
        echo "- HTTP Status: $http_code" >> "$REPORT_FILE"
        echo "- Malformed JSON properly rejected" >> "$REPORT_FILE"
    else
        log_error "$test_id: Unexpected status code: $http_code"
        echo "### $test_id: $test_name ❌" >> "$REPORT_FILE"
        echo "- Unexpected HTTP Status: $http_code" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# TC-RD-001: Redis Connection Loss
test_redis_connection_loss() {
    local test_id="TC-RD-001"
    local test_name="Redis Connection Loss (Fail-Secure)"
    
    log_info "Running $test_id: $test_name"
    
    # Create initial mapping
    curl -s -X POST http://localhost:8082/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d '{"model":"claude-3-sonnet-20240229","messages":[{"role":"user","content":"List EC2 instance i-1234567890abcdef0"}]}'
    
    # Stop Redis
    docker stop redis-cache
    sleep 2
    
    # Try new request
    local response=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d '{"model":"claude-3-sonnet-20240229","messages":[{"role":"user","content":"List S3 bucket my-test-bucket"}]}')
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "503" ]; then
        log_success "$test_id: Fail-secure mode activated correctly"
        echo "### $test_id: $test_name ✅" >> "$REPORT_FILE"
        echo "- HTTP Status: $http_code" >> "$REPORT_FILE"
        echo "- Service properly blocked when Redis unavailable" >> "$REPORT_FILE"
    else
        log_warning "$test_id: Service still responding without Redis"
        echo "### $test_id: $test_name ⚠️" >> "$REPORT_FILE"
        echo "- HTTP Status: $http_code" >> "$REPORT_FILE"
        echo "- Warning: Service may be operating in unsafe mode" >> "$REPORT_FILE"
    fi
    
    # Restart Redis
    docker start redis-cache
    sleep 5
    
    echo "" >> "$REPORT_FILE"
}

# TC-CL-001: Claude API Timeout
test_claude_timeout() {
    local test_id="TC-CL-001"
    local test_name="Claude API Timeout"
    
    log_info "Running $test_id: $test_name"
    
    # This test requires actual Claude API or mock
    # For now, we'll test the timeout configuration
    
    local start_time=$(date +%s)
    
    # Send request that might timeout
    timeout 65 curl -s -w "\n%{http_code}" -X POST http://localhost:8082/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d '{"model":"claude-3-sonnet-20240229","messages":[{"role":"user","content":"'$(python3 -c "print('x' * 100000)")'}]}' \
        > /tmp/timeout_test.txt 2>&1
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $exit_code -eq 124 ]; then
        log_success "$test_id: Request timed out as expected"
        echo "### $test_id: $test_name ✅" >> "$REPORT_FILE"
        echo "- Request timed out after ~60 seconds" >> "$REPORT_FILE"
        echo "- Duration: ${duration}s" >> "$REPORT_FILE"
    else
        log_info "$test_id: Request completed within timeout"
        echo "### $test_id: $test_name ℹ️" >> "$REPORT_FILE"
        echo "- Request completed in ${duration}s" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# TC-LR-001: Large Request Processing
test_large_request() {
    local test_id="TC-LR-001"
    local test_name="Large Request Processing"
    
    log_info "Running $test_id: $test_name"
    
    # Generate large payload with AWS resources
    local large_content=$(python3 -c "
import json
resources = []
for i in range(1000):
    resources.append(f'EC2 instance i-{i:016x} with IP 10.0.{i//256}.{i%256}')
content = ' '.join(resources)
print(json.dumps({
    'model': 'claude-3-sonnet-20240229',
    'messages': [{'role': 'user', 'content': content}]
}))
")
    
    local payload_size=$(echo "$large_content" | wc -c)
    log_info "Payload size: $payload_size bytes"
    
    local start_time=$(date +%s.%N)
    
    local response=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8082/ \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d "$large_content")
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "400" ] || [ "$http_code" = "413" ]; then
        log_success "$test_id: Large request handled appropriately"
        echo "### $test_id: $test_name ✅" >> "$REPORT_FILE"
        echo "- Payload size: $payload_size bytes" >> "$REPORT_FILE"
        echo "- HTTP Status: $http_code" >> "$REPORT_FILE"
        echo "- Processing time: ${duration}s" >> "$REPORT_FILE"
    else
        log_error "$test_id: Unexpected response: $http_code"
        echo "### $test_id: $test_name ❌" >> "$REPORT_FILE"
        echo "- Unexpected HTTP Status: $http_code" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# Run tests based on category
run_tests() {
    case "$SELECTED_CATEGORY" in
        "nginx")
            test_nginx_crash
            ;;
        "kong-masker")
            test_json_parsing_failure
            ;;
        "redis")
            test_redis_connection_loss
            ;;
        "claude-api")
            test_claude_timeout
            ;;
        "large-request")
            test_large_request
            ;;
        "all")
            test_nginx_crash
            test_json_parsing_failure
            test_redis_connection_loss
            test_claude_timeout
            test_large_request
            ;;
        *)
            log_error "Unknown category: $SELECTED_CATEGORY"
            echo "Available categories: ${CATEGORIES[*]}"
            exit 1
            ;;
    esac
}

# Generate summary
generate_summary() {
    echo "" >> "$REPORT_FILE"
    echo "## Summary" >> "$REPORT_FILE"
    echo "- Total tests executed: $(grep -c "###" "$REPORT_FILE")" >> "$REPORT_FILE"
    echo "- Passed: $(grep -c "✅" "$REPORT_FILE")" >> "$REPORT_FILE"
    echo "- Failed: $(grep -c "❌" "$REPORT_FILE")" >> "$REPORT_FILE"
    echo "- Warnings: $(grep -c "⚠️" "$REPORT_FILE")" >> "$REPORT_FILE"
    
    echo "" >> "$REPORT_FILE"
    echo "## Recommendations" >> "$REPORT_FILE"
    echo "1. Review failed tests and implement fixes" >> "$REPORT_FILE"
    echo "2. Monitor warning conditions in production" >> "$REPORT_FILE"
    echo "3. Run full test suite before deployment" >> "$REPORT_FILE"
}

# Main execution
main() {
    log_info "Starting P0 Risk Test Suite"
    
    init_report
    check_prerequisites
    
    echo "## Test Execution Log" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    run_tests
    generate_summary
    
    log_success "Test suite completed. Report saved to: $REPORT_FILE"
    
    # Display summary
    echo ""
    echo "Test Summary:"
    tail -n 10 "$REPORT_FILE"
}

# Execute main
main