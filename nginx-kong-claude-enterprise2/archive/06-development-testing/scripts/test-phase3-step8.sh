#!/bin/bash

# Phase 3 Step 8 Test Script
# Tests the proxy chain: Claude Code SDK → Nginx (8082) → Kong (8010) → Claude API

set -e

echo "==========================================="
echo "Phase 3 Step 8 Proxy Chain Test"
echo "==========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if services are running
check_service() {
    local service=$1
    echo -n "Checking if $service is running... "
    if docker ps | grep -q "$service"; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Not running${NC}"
        return 1
    fi
}

echo ""
echo "1. Service Status Check"
echo "----------------------"

services_running=true
check_service "claude-redis" || services_running=false
check_service "claude-kong" || services_running=false
check_service "claude-nginx" || services_running=false
check_service "claude-code-sdk" || services_running=false

if [ "$services_running" = false ]; then
    echo ""
    echo -e "${YELLOW}⚠ Some services are not running. Please start them with:${NC}"
    echo "  docker-compose up -d"
    echo ""
    exit 1
fi

echo ""
echo "2. Health Check Endpoints"
echo "------------------------"

# Test Nginx health
echo -n "Testing Nginx health endpoint... "
if curl -s -f http://localhost:8082/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

# Test Kong health
echo -n "Testing Kong Admin API... "
if curl -s -f http://localhost:8001/status > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Healthy${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

echo ""
echo "3. Proxy Chain Connectivity Test"
echo "--------------------------------"

# Test from Claude Code SDK to Nginx
echo -n "Testing Claude Code SDK → Nginx connectivity... "
if docker exec claude-code-sdk curl -s -f http://nginx:8082/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

# Test from Nginx to Kong
echo -n "Testing Nginx → Kong connectivity... "
if docker exec claude-nginx curl -s -f http://kong:8010/status > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

echo ""
echo "4. Claude API Configuration Test"
echo "--------------------------------"

# Check if API key is set
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "${YELLOW}⚠ ANTHROPIC_API_KEY not set in environment${NC}"
    echo "  Please set it in your .env file or export it"
    exit 1
fi

# Test a simple Claude API call through the proxy chain
echo "Testing Claude API call through proxy chain..."
echo ""

# Create a test request
cat > /tmp/claude-test-request.json << EOF
{
  "model": "claude-3-5-sonnet-20241022",
  "messages": [
    {
      "role": "user",
      "content": "Say 'Proxy chain test successful!' and nothing else."
    }
  ],
  "max_tokens": 50
}
EOF

# Execute test from Claude Code SDK container
echo "Executing test request from Claude Code SDK..."
docker exec claude-code-sdk sh -c '
    curl -X POST http://nginx:8082/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d '"'"'{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"Say \"Proxy chain test successful!\" and nothing else."}],"max_tokens":50}'"'"' \
        -w "\n\nHTTP Status: %{http_code}\nTotal Time: %{time_total}s\n" \
        -o /tmp/response.json \
        2>/dev/null
'

# Check response
echo ""
echo "Response:"
docker exec claude-code-sdk cat /tmp/response.json 2>/dev/null || echo "No response received"

echo ""
echo "5. Kong Plugin Verification"
echo "---------------------------"

# Check if AWS Masker plugin is active
echo -n "Checking AWS Masker plugin status... "
if curl -s http://localhost:8001/routes/claude-proxy-route/plugins | grep -q "aws-masker"; then
    echo -e "${GREEN}✓ Plugin is active${NC}"
else
    echo -e "${YELLOW}⚠ Plugin may not be active${NC}"
fi

# Check Redis connectivity from Kong
echo -n "Checking Kong → Redis connectivity... "
if docker exec claude-kong redis-cli -h redis -p 6379 -a "${REDIS_PASSWORD:-changeme}" ping 2>/dev/null | grep -q "PONG"; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

echo ""
echo "==========================================="
echo "Test Summary"
echo "==========================================="

echo ""
echo "Proxy Chain: Claude Code SDK → Nginx (8082) → Kong (8010) → Claude API"
echo ""
echo "If all tests passed, your Phase 3 Step 7 configuration is working correctly!"
echo ""
echo "Next steps:"
echo "1. Test AWS resource masking with actual AWS data"
echo "2. Monitor logs for any issues: docker-compose logs -f"
echo "3. Check Redis for masked mappings: docker exec claude-redis redis-cli"

# Clean up
rm -f /tmp/claude-test-request.json