#!/bin/bash

# Claude Code Enterprise Integration Test Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROXY_URL="${ANTHROPIC_BASE_URL:-http://nginx:8082}"
API_KEY="${ANTHROPIC_API_KEY}"
LOG_DIR="/app/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}🧪 Claude Code Enterprise Integration Test${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# Check environment
echo -e "${YELLOW}📋 Environment Check:${NC}"
echo "   Proxy URL: $PROXY_URL"
echo "   API Key: ${API_KEY:0:10}..."
echo "   Timestamp: $TIMESTAMP"
echo ""

# Create log directory
mkdir -p "$LOG_DIR"

# Function to test API endpoint
test_endpoint() {
    local test_name=$1
    local payload_file=$2
    local log_file="$LOG_DIR/${test_name}_${TIMESTAMP}.log"
    
    echo -e "${YELLOW}▶ Testing: $test_name${NC}"
    
    # Read payload
    if [ ! -f "$payload_file" ]; then
        echo -e "${RED}  ❌ Payload file not found: $payload_file${NC}"
        return 1
    fi
    
    # Make request
    response=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d @"$payload_file" 2>&1 | tee "$log_file")
    
    # Extract HTTP status code
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')
    
    # Check response
    if [ "$http_code" -eq 200 ]; then
        echo -e "${GREEN}  ✅ Success (HTTP $http_code)${NC}"
        
        # Check for masked content
        if echo "$response_body" | grep -q "EC2_INSTANCE_\|S3_BUCKET_\|RDS_INSTANCE_\|PRIVATE_IP_"; then
            echo -e "${GREEN}  ✅ Masking detected in response${NC}"
        else
            echo -e "${YELLOW}  ⚠️  No masked content detected${NC}"
        fi
    else
        echo -e "${RED}  ❌ Failed (HTTP $http_code)${NC}"
        echo -e "${RED}  Response: $response_body${NC}"
        return 1
    fi
    
    echo ""
}

# Test 1: EC2 Instance Test
test_endpoint "ec2-test" "/app/test-scenarios/ec2-test.json"

# Test 2: S3 Bucket Test
test_endpoint "s3-test" "/app/test-scenarios/s3-test.json"

# Test 3: Multi-Resource Test
test_endpoint "multi-resource" "/app/test-scenarios/multi-resource.json"

# Test direct connectivity
echo -e "${YELLOW}▶ Testing direct connectivity:${NC}"
echo -n "  Nginx health: "
curl -s -f http://nginx:8082/health && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Failed${NC}"

echo -n "  Kong health: "
curl -s -f http://nginx:8082/kong-health && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Failed${NC}"

echo ""
echo -e "${GREEN}✨ Test completed!${NC}"
echo -e "Logs saved to: $LOG_DIR"