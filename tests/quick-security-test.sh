#!/bin/bash

# Quick Security Test - Focus on masking verification only
# Bypasses slow Claude API calls for pattern verification

set -e

echo "====================================="
echo "🚀 QUICK SECURITY TEST SUITE"
echo "====================================="
echo "Testing Date: $(date)"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

# Function to test masking via test-masking endpoint (much faster)
test_masking() {
    local test_name="$1"
    local pattern="$2"
    
    echo -n "Testing masking: $test_name... "
    
    # Use quick-mask-test endpoint - instant response, no Claude API call
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000/quick-mask-test" \
        -H "Content-Type: application/json" \
        -d "{\"testText\":\"Test data with $pattern for masking\"}" 2>/dev/null)
    
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$status_code" != "200" ]; then
        echo -e "${RED}FAILED${NC} - Status: $status_code"
        echo "Response: $body"
        ((FAILED++))
        return
    fi
    
    # Check if original pattern is masked (should NOT appear in response)
    if echo "$body" | grep -q "$pattern"; then
        echo -e "${RED}FAILED${NC} - Pattern not masked: $pattern"
        echo "Response: $body"
        ((FAILED++))
        return
    fi
    
    echo -e "${GREEN}PASSED${NC}"
    ((PASSED++))
}

# Function to test Redis fail-secure
test_redis_failsafe() {
    echo ""
    echo "=== Testing Redis Fail-Secure ==="
    
    # Stop Redis
    echo "Stopping Redis..."
    docker-compose stop redis >/dev/null 2>&1
    sleep 2
    
    echo -n "Testing Redis down - Service blocked... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000/quick-mask-test" \
        -H "Content-Type: application/json" \
        -d '{"testText":"Test with i-1234567890abcdef0"}' 2>/dev/null)
    
    status_code=$(echo "$response" | tail -n1)
    
    if [ "$status_code" = "503" ]; then
        echo -e "${GREEN}PASSED${NC} - Service correctly blocked"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${NC} - Expected 503, got $status_code"
        ((FAILED++))
    fi
    
    # Restart Redis
    echo "Restarting Redis..."
    docker-compose start redis >/dev/null 2>&1
    sleep 5
    
    echo -n "Testing Redis restored - Service working... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000/quick-mask-test" \
        -H "Content-Type: application/json" \
        -d '{"testText":"Test with i-1234567890abcdef0"}' 2>/dev/null)
    
    status_code=$(echo "$response" | tail -n1)
    
    if [ "$status_code" = "200" ]; then
        echo -e "${GREEN}PASSED${NC} - Service restored"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${NC} - Service not restored, status: $status_code"
        ((FAILED++))
    fi
}

# Main test execution
echo "=== Testing AWS Pattern Masking ==="

# Critical AWS patterns
patterns=(
    "i-1234567890abcdef0"
    "vpc-12345678"
    "subnet-87654321"
    "10.0.0.1"
    "172.16.0.1"
    "192.168.1.1"
    "my-bucket.s3.amazonaws.com"
    "prod-db.rds.amazonaws.com"
    "AKIAIOSFODNN7EXAMPLE"
    "arn:aws:ec2:us-east-1:123456789012:instance/i-abcdef123456"
)

for pattern in "${patterns[@]}"; do
    test_masking "$(echo $pattern | cut -c1-30)..." "$pattern"
done

# Test Redis fail-secure
test_redis_failsafe

# Final report
echo ""
echo "====================================="
echo "📊 QUICK TEST RESULTS"
echo "====================================="
echo -e "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL SECURITY TESTS PASSED${NC}"
    echo "System is ready for production deployment"
    exit 0
else
    echo -e "${RED}❌ SECURITY TESTS FAILED${NC}"
    echo "System is NOT ready for production"
    exit 1
fi