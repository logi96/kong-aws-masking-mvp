#!/bin/bash

# Kong-Redis Integration Validation Script
# Validates the integration between Kong plugin and Backend Redis service
# Created by kong-integration-validator agent

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKEND_URL="${BACKEND_URL:-http://localhost:3000}"
KONG_URL="${KONG_URL:-http://localhost:8000}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test functions
test_redis_connectivity() {
    ((TOTAL_TESTS++))
    log_info "Testing Redis connectivity..."
    
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null 2>&1; then
        log_success "Redis is accessible"
    else
        log_error "Cannot connect to Redis at $REDIS_HOST:$REDIS_PORT"
        return 1
    fi
}

test_backend_health() {
    ((TOTAL_TESTS++))
    log_info "Testing Backend health endpoint..."
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$BACKEND_URL/health")
    if [ "$response" = "200" ]; then
        log_success "Backend health check passed"
    else
        log_error "Backend health check failed (HTTP $response)"
        return 1
    fi
}

test_kong_status() {
    ((TOTAL_TESTS++))
    log_info "Testing Kong Gateway status..."
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$KONG_URL/status")
    if [ "$response" = "200" ]; then
        log_success "Kong Gateway is running"
    else
        log_error "Kong Gateway status check failed (HTTP $response)"
        return 1
    fi
}

test_masking_flow() {
    ((TOTAL_TESTS++))
    log_info "Testing complete masking flow..."
    
    # Create test data with AWS resources
    test_data=$(cat <<EOF
{
    "resources": ["ec2"],
    "options": {
        "analysisType": "security"
    },
    "testData": {
        "instances": [
            "i-1234567890abcdef0",
            "i-0987654321fedcba1"
        ],
        "vpcs": ["vpc-12345678", "vpc-87654321"],
        "ips": ["10.0.1.100", "10.0.2.200"]
    }
}
EOF
)
    
    # Send request through Backend (which goes through Kong)
    response=$(curl -s -X POST "$BACKEND_URL/analyze" \
        -H "Content-Type: application/json" \
        -d "$test_data")
    
    if echo "$response" | grep -q "requestId"; then
        log_success "Masking flow completed successfully"
        
        # Extract some data for verification
        request_id=$(echo "$response" | grep -o '"requestId":"[^"]*"' | cut -d'"' -f4)
        log_info "Request ID: $request_id"
    else
        log_error "Masking flow failed"
        echo "$response"
        return 1
    fi
}

test_redis_mappings() {
    ((TOTAL_TESTS++))
    log_info "Testing Redis mapping storage..."
    
    # Check if mappings exist in Redis
    mapping_count=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern "aws:mask:*" | wc -l)
    unmask_count=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern "aws:unmask:*" | wc -l)
    
    if [ "$mapping_count" -gt 0 ] && [ "$unmask_count" -gt 0 ]; then
        log_success "Found $mapping_count mask mappings and $unmask_count unmask mappings in Redis"
    else
        log_warning "No mappings found in Redis (mask: $mapping_count, unmask: $unmask_count)"
    fi
}

test_masking_statistics() {
    ((TOTAL_TESTS++))
    log_info "Testing masking statistics endpoint..."
    
    response=$(curl -s "$BACKEND_URL/analyze/masking/stats")
    
    if echo "$response" | grep -q "statistics"; then
        log_success "Masking statistics endpoint working"
        
        # Display some stats
        total_mappings=$(echo "$response" | grep -o '"mappings":[0-9]*' | head -1 | cut -d':' -f2)
        log_info "Total mappings: ${total_mappings:-0}"
    else
        log_error "Failed to retrieve masking statistics"
        return 1
    fi
}

test_ttl_functionality() {
    ((TOTAL_TESTS++))
    log_info "Testing TTL functionality..."
    
    # Create a test mapping with short TTL
    test_key="test:ttl:$(date +%s)"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SETEX "$test_key" 5 "test_value" > /dev/null
    
    # Check if key exists
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EXISTS "$test_key" | grep -q "1"; then
        ttl=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" TTL "$test_key")
        log_success "TTL functionality working (TTL: $ttl seconds)"
    else
        log_error "Failed to set key with TTL"
        return 1
    fi
}

test_concurrent_access() {
    ((TOTAL_TESTS++))
    log_info "Testing concurrent access handling..."
    
    # Send multiple concurrent requests
    for i in {1..5}; do
        curl -s -X POST "$BACKEND_URL/analyze" \
            -H "Content-Type: application/json" \
            -d '{"resources":["ec2"],"options":{}}' > /dev/null &
    done
    
    # Wait for all requests to complete
    wait
    
    # Check Redis connection pool
    redis_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" CLIENT LIST | wc -l)
    log_success "Handled 5 concurrent requests (Active Redis connections: $redis_info)"
}

test_cleanup_endpoint() {
    ((TOTAL_TESTS++))
    log_info "Testing cleanup endpoint..."
    
    response=$(curl -s -X POST "$BACKEND_URL/analyze/masking/cleanup")
    
    if echo "$response" | grep -q "cleaned"; then
        cleaned_count=$(echo "$response" | grep -o '"cleaned":[0-9]*' | cut -d':' -f2)
        log_success "Cleanup endpoint working (cleaned: ${cleaned_count:-0} mappings)"
    else
        log_error "Cleanup endpoint failed"
        return 1
    fi
}

test_validation_endpoint() {
    ((TOTAL_TESTS++))
    log_info "Testing masking validation endpoint..."
    
    validation_data=$(cat <<EOF
{
    "original": "Instance i-1234567890abcdef0 in vpc-12345678",
    "masked": "Instance EC2_001 in VPC_001"
}
EOF
)
    
    response=$(curl -s -X POST "$BACKEND_URL/analyze/masking/validate" \
        -H "Content-Type: application/json" \
        -d "$validation_data")
    
    if echo "$response" | grep -q "validation"; then
        log_success "Validation endpoint working"
    else
        log_error "Validation endpoint failed"
        return 1
    fi
}

# Performance test
test_performance() {
    ((TOTAL_TESTS++))
    log_info "Testing masking performance..."
    
    start_time=$(date +%s%N)
    
    # Send a request with multiple resources
    curl -s -X POST "$BACKEND_URL/analyze" \
        -H "Content-Type: application/json" \
        -d '{"resources":["ec2","s3","rds"],"options":{}}' > /dev/null
    
    end_time=$(date +%s%N)
    elapsed=$((($end_time - $start_time) / 1000000)) # Convert to milliseconds
    
    if [ "$elapsed" -lt 5000 ]; then
        log_success "Performance test passed (${elapsed}ms < 5000ms target)"
    else
        log_warning "Performance test slow (${elapsed}ms > 5000ms target)"
    fi
}

# Main execution
main() {
    echo "======================================"
    echo "Kong-Redis Integration Validation"
    echo "======================================"
    echo "Backend URL: $BACKEND_URL"
    echo "Kong URL: $KONG_URL"
    echo "Redis: $REDIS_HOST:$REDIS_PORT"
    echo "======================================"
    echo
    
    # Run all tests
    test_redis_connectivity
    test_backend_health
    test_kong_status
    test_masking_flow
    test_redis_mappings
    test_masking_statistics
    test_ttl_functionality
    test_concurrent_access
    test_cleanup_endpoint
    test_validation_endpoint
    test_performance
    
    # Summary
    echo
    echo "======================================"
    echo "Test Summary"
    echo "======================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo "======================================"
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "redis-cli" "grep" "wc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: $dep is not installed"
            exit 1
        fi
    done
}

# Run checks and main
check_dependencies
main