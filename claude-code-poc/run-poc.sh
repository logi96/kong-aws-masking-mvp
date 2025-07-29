#!/bin/bash

echo "🚀 Claude Code Kong Masking Proxy POC"
echo "====================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if API key is set
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "${YELLOW}⚠️  Warning: ANTHROPIC_API_KEY not set${NC}"
    echo "   Using dummy key for testing. Real API calls will fail."
    echo ""
fi

# Step 1: Build and start containers
echo -e "${BLUE}1️⃣  Building and starting Docker containers...${NC}"
docker-compose down 2>/dev/null
docker-compose build
docker-compose up -d

# Wait for services to be ready
echo -e "\n${BLUE}2️⃣  Waiting for services to be ready...${NC}"
sleep 5

# Check services
echo -e "\n${BLUE}3️⃣  Checking service status...${NC}"

# Check Kong
docker-compose exec -T kong kong health > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Kong is healthy${NC}"
else
    echo -e "${RED}❌ Kong is not healthy${NC}"
fi

# Check Masking Proxy
curl -s http://localhost:8082/health > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Masking Proxy is running${NC}"
else
    echo -e "${RED}❌ Masking Proxy is not accessible${NC}"
fi

# Step 4: Run tests in isolated container
echo -e "\n${BLUE}4️⃣  Running tests in isolated Claude Code container...${NC}"
echo ""

# Option 1: Automated test
echo -e "${YELLOW}Running automated test...${NC}"
docker-compose exec claude-test ./test-claude-code.sh

echo -e "\n${BLUE}5️⃣  Checking proxy logs for masked content...${NC}"
docker-compose logs masking-proxy | tail -20

echo -e "\n${GREEN}✅ POC setup complete!${NC}"
echo ""
echo "To run interactive tests:"
echo "  docker-compose exec claude-test /bin/bash"
echo "  Then run: ./test-claude-code.sh"
echo ""
echo "To check logs:"
echo "  docker-compose logs -f masking-proxy"
echo ""
echo "To stop everything:"
echo "  docker-compose down"