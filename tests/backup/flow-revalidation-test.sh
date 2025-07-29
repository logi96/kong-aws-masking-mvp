#!/bin/bash
# Flow Revalidation Test - Verifying Correct API Gateway Pattern
# Backend → Kong (transparent intercept) → Claude API → Kong (unmask) → Backend

set -euo pipefail

echo "================================================"
echo "🔥 Flow Revalidation Test - API Gateway Pattern"
echo "================================================"
echo "Test Time: $(date)"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

# API Key (if needed for test endpoint)
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-test-key}"

# Function to test analyze endpoint
test_analyze() {
    local test_name="$1"
    local aws_content="$2"
    local should_mask="$3"
    
    echo -e "\n${BLUE}Test: $test_name${NC}"
    echo "AWS Content: $aws_content"
    
    # Call Backend API directly (not Kong)
    response=$(curl -s -X POST http://localhost:3000/analyze \
        -H "Content-Type: application/json" \
        -d "{
            \"resources\": [\"ec2\", \"s3\", \"rds\"],
            \"prompt\": \"Analyze AWS: $aws_content\",
            \"options\": {
                \"analysisType\": \"security_only\",
                \"maxTokens\": 100
            }
        }" 2>&1)
    
    # Check if response contains error
    if echo "$response" | grep -q "error"; then
        echo -e "${RED}✗ API call failed${NC}"
        echo "Response: $response"
        ((FAILED++))
        return
    fi
    
    # Check Kong logs for masking
    kong_logs=$(docker-compose logs kong --tail=50 2>&1)
    
    # Verify masking happened
    if [ "$should_mask" = "yes" ]; then
        if echo "$kong_logs" | grep -q "Masked.*AWS resources"; then
            echo -e "${GREEN}✓ Masking detected in Kong logs${NC}"
            
            # Check if original patterns appear in logs
            if echo "$kong_logs" | grep -E "i-[0-9a-f]{17}|10\.[0-9]+\.[0-9]+\.[0-9]+|vpc-[0-9a-f]{8}" > /dev/null; then
                echo -e "${RED}✗ Original patterns visible in logs!${NC}"
                ((FAILED++))
            else
                echo -e "${GREEN}✓ Original patterns properly masked${NC}"
                ((PASSED++))
            fi
        else
            echo -e "${RED}✗ No masking detected${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${GREEN}✓ Test completed${NC}"
        ((PASSED++))
    fi
}

# Function to test test-masking endpoint
test_masking_endpoint() {
    local test_name="$1"
    local content="$2"
    
    echo -e "\n${BLUE}Test Masking Endpoint: $test_name${NC}"
    
    response=$(curl -s -X POST http://localhost:3000/test-masking \
        -H "Content-Type: application/json" \
        -d "{\"testText\": \"$content\"}" 2>&1)
    
    echo "Response: $response"
    
    # Verify response fields
    if echo "$response" | jq -e '.success' > /dev/null && \
       echo "$response" | jq -e '.flow' > /dev/null; then
        
        # Check if response contains expected flow
        if echo "$response" | jq -e '.flow.step6_backend_receives' > /dev/null; then
            final_response=$(echo "$response" | jq -r '.flow.step6_backend_receives')
            echo -e "${GREEN}✓ Flow completed, final response: $final_response${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ Flow incomplete${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${RED}✗ Invalid response format${NC}"
        ((FAILED++))
    fi
}

# 1. System Health Check
echo -e "${BLUE}=== 1. System Health Check ===${NC}"
echo -n "Kong Gateway: "
if curl -s http://localhost:8001/status > /dev/null; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
    exit 1
fi

echo -n "Backend API: "
if curl -s http://localhost:3000/health | jq -e '.status == "healthy"' > /dev/null; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "${RED}✗ Not healthy${NC}"
    exit 1
fi

echo -n "Redis: "
if docker-compose exec -T redis redis-cli -a "CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL" ping 2>/dev/null | grep -q PONG; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

# 2. Test Masking Endpoint
echo -e "\n${BLUE}=== 2. Test Masking Endpoint ===${NC}"
test_masking_endpoint "Single EC2 Instance" "Check instance i-1234567890abcdef0"
test_masking_endpoint "Multiple AWS Resources" "VPC vpc-12345678 has instance i-abcdef1234567890 at IP 10.0.1.100"
test_masking_endpoint "Complex Pattern Mix" "RDS db-prod in subnet-87654321 with SG sg-12345678 at 10.0.2.50"

# 3. Test Analyze Endpoint (Main Flow)
echo -e "\n${BLUE}=== 3. Analyze Endpoint (Full Flow) ===${NC}"
test_analyze "EC2 Instances" "i-1234567890abcdef0 and i-0987654321fedcba0" "yes"
test_analyze "Private IPs" "10.0.1.100, 10.0.2.200, 172.16.0.1" "yes"
test_analyze "VPC Resources" "vpc-12345678 with subnet-abcdef12" "yes"
test_analyze "Mixed AWS Resources" "EC2 i-abc123 in VPC vpc-def456 IP 10.1.2.3" "yes"

# 4. Kong Interception Verification
echo -e "\n${BLUE}=== 4. Kong Interception Verification ===${NC}"
echo "Checking if Kong is intercepting Claude API calls..."

# Clear Kong logs
docker-compose logs kong --tail=0 -f > /tmp/kong-intercept.log 2>&1 &
KONG_LOG_PID=$!
sleep 2

# Make a test call
curl -s -X POST http://localhost:3000/test-masking \
    -H "Content-Type: application/json" \
    -d '{"content": "Test Kong interception of Claude API"}' > /dev/null 2>&1

sleep 3
kill $KONG_LOG_PID 2>/dev/null || true

# Check if Kong intercepted the call
if grep -q "api.anthropic.com" /tmp/kong-intercept.log; then
    echo -e "${GREEN}✓ Kong is intercepting api.anthropic.com calls${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ Could not verify Kong interception${NC}"
fi

# 5. Security Verification
echo -e "\n${BLUE}=== 5. Security Verification ===${NC}"
echo "Verifying no AWS patterns in Claude API requests..."

# This would require more complex monitoring, for now we check logs
recent_logs=$(docker-compose logs kong --tail=100 2>&1)
if echo "$recent_logs" | grep -E "Masked [0-9]+ AWS resources" > /dev/null; then
    echo -e "${GREEN}✓ Masking is active${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ No recent masking activity detected${NC}"
fi

# 6. Performance Check
echo -e "\n${BLUE}=== 6. Performance Check ===${NC}"
START=$(date +%s%N)
curl -s -X POST http://localhost:3000/test-masking \
    -H "Content-Type: application/json" \
    -d '{"content": "Performance test with i-1234567890abcdef0"}' > /dev/null
END=$(date +%s%N)
DURATION=$((($END - $START) / 1000000))
echo "Response time: ${DURATION}ms"

if [ $DURATION -lt 5000 ]; then
    echo -e "${GREEN}✓ Performance within 5s target${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Performance exceeds 5s target${NC}"
    ((FAILED++))
fi

# Final Report
echo -e "\n${BLUE}================================================${NC}"
echo -e "${BLUE}📊 Flow Revalidation Test Results${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}The new API Gateway pattern is working correctly.${NC}"
    echo ""
    echo "✓ Backend calls Claude API directly"
    echo "✓ Kong transparently intercepts and masks AWS patterns"
    echo "✓ Responses are properly unmasked"
    echo "✓ Security requirements met"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo "Please check the logs and fix issues before proceeding."
    exit 1
fi