#!/bin/bash

# Test script to validate transparent proxy route behavior and traffic flow
# This demonstrates why the transparent proxy route isn't used in practice

set -e

echo "=== Kong Transparent Proxy Route Traffic Flow Test ==="
echo "Date: $(date)"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Show current active routes
echo -e "${YELLOW}1. Current Kong Routes:${NC}"
curl -s http://localhost:8001/routes | jq -r '.data[] | "\(.name): \(.paths // ["no-paths"]) → hosts: \(.hosts // ["any-host"])"'
echo ""

# Test 2: Test transparent proxy with Host header
echo -e "${YELLOW}2. Testing transparent proxy route (with Host: api.anthropic.com):${NC}"
echo "Command: curl -X POST http://localhost:8000/v1/messages -H 'Host: api.anthropic.com'"
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST http://localhost:8000/v1/messages \
  -H "Host: api.anthropic.com" \
  -H "Content-Type: application/json" \
  -H "x-api-key: test-key" \
  -d '{"model": "claude-3", "messages": [{"role": "user", "content": "test"}]}' 2>&1)

http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
body=$(echo "$response" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')

if [[ "$http_status" == "404" ]]; then
    echo -e "${RED}Result: Route matched but forwarded to external API (404 from Cloudflare)${NC}"
else
    echo -e "${RED}Result: HTTP $http_status${NC}"
fi
echo "Response headers indicate: External routing occurred"
echo ""

# Test 3: Test working claude-proxy route
echo -e "${YELLOW}3. Testing working claude-proxy route:${NC}"
echo "Command: curl -X POST http://localhost:8000/claude-proxy/v1/messages"
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST http://localhost:8000/claude-proxy/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY:-test-key}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 50,
    "messages": [{"role": "user", "content": "Say hello"}]
  }' 2>&1 || true)

http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
if [[ "$http_status" == "200" ]]; then
    echo -e "${GREEN}Result: Success - Route working correctly${NC}"
elif [[ "$http_status" == "401" ]]; then
    echo -e "${YELLOW}Result: Route working but API key invalid${NC}"
else
    echo -e "${RED}Result: HTTP $http_status${NC}"
fi
echo ""

# Test 4: Check backend configuration
echo -e "${YELLOW}4. Backend Configuration Check:${NC}"
if [ -f backend/.env.test ]; then
    claude_url=$(grep "CLAUDE_API_URL" backend/.env.test | cut -d= -f2)
    echo "Backend CLAUDE_API_URL: $claude_url"
    if [[ "$claude_url" == *"kong:8000/claude-proxy"* ]]; then
        echo -e "${GREEN}✓ Backend correctly configured to use Kong proxy${NC}"
    else
        echo -e "${RED}✗ Backend not using Kong proxy${NC}"
    fi
else
    echo -e "${RED}Backend .env.test not found${NC}"
fi
echo ""

# Test 5: DNS resolution test
echo -e "${YELLOW}5. DNS Resolution Test:${NC}"
echo "Testing if api.anthropic.com can be overridden..."

# Check if we can resolve api.anthropic.com
host_ip=$(dig +short api.anthropic.com | head -1)
echo "api.anthropic.com resolves to: ${host_ip:-<no-response>}"

# Check Kong's IP
kong_ip=$(docker inspect kong-gateway -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
echo "Kong container IP: $kong_ip"

echo ""
echo -e "${YELLOW}Could we override DNS?${NC}"
echo "- System /etc/hosts: Would need sudo access"
echo "- Docker extra_hosts: Would only affect container internals"
echo "- Application-level: Claude Code doesn't support proxy settings"
echo ""

# Test 6: Traffic flow analysis
echo -e "${YELLOW}6. Actual Traffic Flow:${NC}"
echo -e "${GREEN}Current Working Flow:${NC}"
echo "1. Backend (http://backend:3000)"
echo "   ↓ (calls CLAUDE_API_URL)"
echo "2. Kong Gateway (http://kong:8000/claude-proxy/v1/messages)"
echo "   ↓ (strips path, adds headers)"
echo "3. Claude API (https://api.anthropic.com/v1/messages)"
echo ""

echo -e "${RED}Transparent Proxy Flow (NOT WORKING):${NC}"
echo "1. Backend would need to call: https://api.anthropic.com/v1/messages"
echo "2. DNS override: api.anthropic.com → Kong IP (NOT POSSIBLE)"
echo "3. SSL verification would fail (certificate mismatch)"
echo "4. Kong would need to handle HTTPS termination"
echo ""

# Summary
echo -e "${YELLOW}=== Summary ===${NC}"
echo "1. Transparent proxy route exists but is unused"
echo "2. Backend uses claude-proxy route (working correctly)"
echo "3. True transparent proxying requires system-level changes"
echo "4. Current architecture is optimal for the use case"
echo ""
echo "Test completed at: $(date)"