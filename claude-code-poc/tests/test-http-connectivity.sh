#!/bin/bash

echo "🧪 Claude Code HTTP Connectivity Test"
echo "===================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Start test HTTP proxy
echo "1️⃣  Starting test HTTP proxy..."
cd ../kong-masking-proxy
python test-http-proxy.py &
PROXY_PID=$!
sleep 3

# Test 2: Check if proxy is running
echo -e "\n2️⃣  Checking if proxy is accessible..."
curl -s http://localhost:8082/health > /dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Test proxy is running${NC}"
else
    echo -e "${RED}❌ Test proxy is not accessible${NC}"
    kill $PROXY_PID 2>/dev/null
    exit 1
fi

# Test 3: Test Claude Code with HTTP BASE_URL
echo -e "\n3️⃣  Testing Claude Code with HTTP BASE_URL..."
echo -e "${YELLOW}Please run this command in another terminal:${NC}"
echo ""
echo "    ANTHROPIC_BASE_URL=http://localhost:8082 claude"
echo ""
echo "Then try sending a message like: 'Hello, can you see this?'"
echo ""
echo "Watch this terminal for incoming requests..."
echo ""
echo "Press Ctrl+C to stop the test proxy when done."
echo ""

# Wait for user to test
wait $PROXY_PID