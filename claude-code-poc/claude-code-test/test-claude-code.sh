#!/bin/bash

echo "🧪 Claude Code Proxy Test Inside Docker"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
PROXY_HOST=${PROXY_HOST:-masking-proxy}
PROXY_PORT=${PROXY_PORT:-8082}
API_KEY=${ANTHROPIC_API_KEY:-dummy-key-for-testing}

echo -e "${BLUE}📋 Test Configuration:${NC}"
echo "   Proxy: http://$PROXY_HOST:$PROXY_PORT"
echo "   API Key: ${API_KEY:0:10}..."
echo ""

# Test 1: Check proxy connectivity
echo -e "${YELLOW}1️⃣  Testing proxy connectivity...${NC}"
curl -s http://$PROXY_HOST:$PROXY_PORT/health > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Proxy is reachable${NC}"
else
    echo -e "${RED}❌ Cannot reach proxy at http://$PROXY_HOST:$PROXY_PORT${NC}"
    exit 1
fi

# Test 2: Test Claude Code with HTTP BASE_URL
echo -e "\n${YELLOW}2️⃣  Testing Claude Code with HTTP BASE_URL...${NC}"
export ANTHROPIC_BASE_URL="http://$PROXY_HOST:$PROXY_PORT"
export ANTHROPIC_API_KEY="$API_KEY"

echo -e "${BLUE}Environment variables set:${NC}"
echo "   ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
echo ""

# Test 3: Send a request with AWS resources
echo -e "${YELLOW}3️⃣  Sending test request with AWS resources...${NC}"
echo ""

# Create a test prompt with AWS resources
TEST_PROMPT="Please analyze these AWS resources:
- EC2 instance i-1234567890abcdef0
- S3 bucket my-sensitive-data-bucket
- RDS instance prod-database.rds.amazonaws.com
- Private IP 10.0.1.50
- AWS Account 123456789012"

# Method 1: Try using claude command directly
echo -e "${BLUE}Method 1: Using claude command${NC}"
echo "$TEST_PROMPT" | timeout 10 claude 2>&1 | tee claude-output.log

# Check if request went through proxy
if grep -q "EC2_INSTANCE_" claude-output.log || grep -q "Error" claude-output.log; then
    echo -e "${GREEN}✅ Claude Code attempted to connect${NC}"
else
    echo -e "${YELLOW}⚠️  No clear response from Claude${NC}"
fi

# Method 2: Use Node.js with @anthropic-ai/sdk
echo -e "\n${BLUE}Method 2: Using Node.js SDK${NC}"
cat > test-sdk.js << 'EOF'
const Anthropic = require('@anthropic-ai/sdk');

const client = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
  baseURL: process.env.ANTHROPIC_BASE_URL
});

async function test() {
  try {
    console.log('Sending request to:', process.env.ANTHROPIC_BASE_URL);
    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 100,
      messages: [{
        role: 'user',
        content: process.argv[2] || 'Hello'
      }]
    });
    console.log('Response:', response);
  } catch (error) {
    console.error('Error:', error.message);
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Headers:', error.response.headers);
    }
  }
}

test();
EOF

npm install @anthropic-ai/sdk > /dev/null 2>&1
node test-sdk.js "$TEST_PROMPT"

echo -e "\n${GREEN}Test completed!${NC}"
echo "Check the proxy logs to see if requests were intercepted and masked."