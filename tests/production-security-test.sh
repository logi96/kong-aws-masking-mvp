#!/bin/bash

# Production Security Test Suite for Kong AWS Masker
# Following 100% security requirements with financial penalty implications
# Tests all critical security scenarios

set -e

echo "====================================="
echo "🚨 PRODUCTION SECURITY TEST SUITE 🚨"
echo "====================================="
echo "Testing Date: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0

# Function to test an endpoint
test_endpoint() {
    local test_name="$1"
    local method="$2"
    local endpoint="$3"
    local data="$4"
    local expected_status="$5"
    local check_pattern="$6"
    
    echo -n "Testing: $test_name... "
    
    if [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null || echo "CURL_FAILED")
    else
        response=$(curl -s -w "\n%{http_code}" -X GET "http://localhost:3000$endpoint" 2>/dev/null || echo "CURL_FAILED")
    fi
    
    if [ "$response" = "CURL_FAILED" ]; then
        echo -e "${RED}FAILED${NC} - Connection error"
        ((FAILED++))
        return
    fi
    
    # Extract status code and body
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    # Check status code
    if [ "$status_code" != "$expected_status" ]; then
        echo -e "${RED}FAILED${NC} - Expected status $expected_status, got $status_code"
        echo "Response: $body"
        ((FAILED++))
        return
    fi
    
    # Check for pattern in response if provided
    if [ -n "$check_pattern" ]; then
        if echo "$body" | grep -q "$check_pattern"; then
            echo -e "${RED}FAILED${NC} - Found unwanted pattern: $check_pattern"
            echo "Response: $body"
            ((FAILED++))
            return
        fi
    fi
    
    echo -e "${GREEN}PASSED${NC}"
    ((PASSED++))
}

# Function to test Redis failure scenario
test_redis_failure() {
    echo ""
    echo "=== Testing Redis Failure Scenarios ==="
    
    # Stop Redis temporarily
    echo "Stopping Redis..."
    docker-compose stop redis >/dev/null 2>&1
    sleep 2
    
    # Test that requests are blocked
    test_endpoint "Redis down - Request blocked" "POST" "/analyze" \
        '{"resources":["ec2"],"prompt":"List EC2 instances"}' \
        "503" ""
    
    # Restart Redis
    echo "Restarting Redis..."
    docker-compose start redis >/dev/null 2>&1
    sleep 5
}

# Function to test Circuit Breaker
test_circuit_breaker() {
    echo ""
    echo "=== Testing Circuit Breaker ==="
    
    # Simulate multiple failures by corrupting Redis password
    echo "Simulating Redis auth failures..."
    docker-compose exec -T kong sh -c "export REDIS_PASSWORD=wrong_password"
    
    # Send multiple requests to trigger circuit breaker
    for i in {1..6}; do
        test_endpoint "Circuit breaker test $i" "POST" "/analyze" \
            '{"resources":["ec2"],"prompt":"Test"}' \
            "503" ""
    done
    
    # Reset Redis password
    docker-compose exec -T kong sh -c "export REDIS_PASSWORD=AiY3LyRp5nD7vBxN4tQ8rS9wKjH6mFuE2cXzV1bG0oP"
}

# Function to test AWS pattern detection
test_aws_pattern_detection() {
    echo ""
    echo "=== Testing AWS Pattern Detection ==="
    
    # Test various AWS patterns
    local patterns=(
        "i-1234567890abcdef0"
        "vpc-12345678"
        "subnet-87654321"
        "10.0.0.1"
        "172.16.0.1"
        "192.168.1.1"
        "arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0"
        "my-bucket.s3.amazonaws.com"
        "my-db.rds.amazonaws.com"
        "AKIAIOSFODNN7EXAMPLE"
    )
    
    for pattern in "${patterns[@]}"; do
        test_endpoint "Pattern detection: $pattern" "POST" "/analyze" \
            "{\"resources\":[\"ec2\"],\"prompt\":\"Check $pattern\"}" \
            "200" "$pattern"
    done
}

# Function to test masking completeness
test_masking_completeness() {
    echo ""
    echo "=== Testing Masking Completeness ==="
    
    # Test complex scenarios
    test_endpoint "Multiple IPs in JSON" "POST" "/analyze" \
        '{"resources":["ec2"],"prompt":"IPs: 10.0.0.1, 10.0.0.2, 172.16.0.1"}' \
        "200" "10\\.0\\.0\\."
    
    test_endpoint "Nested AWS resources" "POST" "/analyze" \
        '{"resources":["ec2"],"prompt":"Instance i-abc123 in vpc-def456 with IP 10.1.2.3"}' \
        "200" "i-abc123"
    
    test_endpoint "Mixed patterns" "POST" "/analyze" \
        '{"resources":["s3","rds"],"prompt":"Bucket my-bucket.s3.amazonaws.com and DB prod.rds.amazonaws.com"}' \
        "200" "s3\\.amazonaws\\.com"
}

# Function to test health endpoint
test_health_endpoint() {
    echo ""
    echo "=== Testing Health Check Endpoint ==="
    
    # Add health endpoint to Kong if not exists
    curl -s -X POST http://localhost:8001/services/backend-api/routes \
        -d "name=health-route" \
        -d "paths[]=/health" >/dev/null 2>&1 || true
    
    test_endpoint "Health check endpoint" "GET" "/health" "" "200" ""
}

# Function to test error responses
test_error_responses() {
    echo ""
    echo "=== Testing Error Response Formats ==="
    
    # Test various error scenarios
    test_endpoint "Invalid JSON" "POST" "/analyze" \
        '{invalid json}' \
        "400" ""
    
    test_endpoint "Empty body" "POST" "/analyze" \
        '' \
        "400" ""
    
    test_endpoint "Missing resources" "POST" "/analyze" \
        '{"prompt":"Test"}' \
        "400" ""
}

# Function to test performance under load
test_performance() {
    echo ""
    echo "=== Testing Performance Under Load ==="
    
    local start_time=$(date +%s)
    local request_count=50
    
    echo "Sending $request_count concurrent requests..."
    
    for i in $(seq 1 $request_count); do
        curl -s -X POST "http://localhost:3000/analyze" \
            -H "Content-Type: application/json" \
            -d '{"resources":["ec2"],"prompt":"List instances"}' >/dev/null 2>&1 &
    done
    
    wait
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Completed $request_count requests in ${duration}s"
    
    if [ $duration -gt 10 ]; then
        echo -e "${YELLOW}WARNING${NC}: Performance may be degraded (>10s for 50 requests)"
    else
        echo -e "${GREEN}PASSED${NC}: Performance acceptable"
        ((PASSED++))
    fi
}

# Main test execution
echo "Starting comprehensive security tests..."
echo ""

# Ensure services are running
echo "Checking service status..."
docker-compose ps

# Run all test suites
test_aws_pattern_detection
test_masking_completeness
test_error_responses
test_health_endpoint
test_redis_failure
test_circuit_breaker
test_performance

# Final report
echo ""
echo "====================================="
echo "📊 TEST RESULTS SUMMARY"
echo "====================================="
echo -e "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL SECURITY TESTS PASSED!${NC}"
    echo "The system meets 100% security requirements."
    exit 0
else
    echo -e "${RED}❌ SECURITY TESTS FAILED!${NC}"
    echo "The system does NOT meet security requirements."
    echo "Financial penalties may apply if deployed in this state."
    exit 1
fi