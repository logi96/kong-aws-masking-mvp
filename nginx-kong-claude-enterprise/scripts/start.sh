#!/bin/bash

# Nginx-Kong-Claude Enterprise Start Script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Nginx-Kong-Claude Enterprise...${NC}"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠️  .env file not found. Creating from example...${NC}"
    cp .env.example .env
    echo -e "${RED}❗ Please edit .env file with your API key before continuing.${NC}"
    exit 1
fi

# Check if ANTHROPIC_API_KEY is set
if ! grep -q "ANTHROPIC_API_KEY=sk-ant" .env; then
    echo -e "${RED}❗ ANTHROPIC_API_KEY not set in .env file${NC}"
    exit 1
fi

# Create necessary directories
echo -e "${BLUE}📁 Creating directories...${NC}"
mkdir -p logs/{nginx,kong,redis,claude-client}
mkdir -p redis/data

# Start services in order
echo -e "${BLUE}🔄 Starting Redis...${NC}"
docker-compose up -d redis

echo -e "${BLUE}⏳ Waiting for Redis to be healthy...${NC}"
timeout 30 bash -c 'until docker-compose ps redis | grep -q "healthy"; do sleep 1; done' || {
    echo -e "${RED}❌ Redis failed to start${NC}"
    docker-compose logs redis
    exit 1
}
echo -e "${GREEN}✅ Redis is healthy${NC}"

echo -e "${BLUE}🔄 Starting Kong...${NC}"
docker-compose up -d kong

echo -e "${BLUE}⏳ Waiting for Kong to be healthy...${NC}"
timeout 60 bash -c 'until docker-compose ps kong | grep -q "healthy"; do sleep 1; done' || {
    echo -e "${RED}❌ Kong failed to start${NC}"
    docker-compose logs kong
    exit 1
}
echo -e "${GREEN}✅ Kong is healthy${NC}"

echo -e "${BLUE}🔄 Starting Nginx...${NC}"
docker-compose up -d nginx

echo -e "${BLUE}⏳ Waiting for Nginx to be healthy...${NC}"
timeout 30 bash -c 'until docker-compose ps nginx | grep -q "healthy"; do sleep 1; done' || {
    echo -e "${RED}❌ Nginx failed to start${NC}"
    docker-compose logs nginx
    exit 1
}
echo -e "${GREEN}✅ Nginx is healthy${NC}"

echo -e "${BLUE}🔄 Starting Claude Client...${NC}"
docker-compose up -d claude-client

echo ""
echo -e "${GREEN}✨ All services started successfully!${NC}"
echo ""
echo -e "${BLUE}📊 Service Status:${NC}"
docker-compose ps

echo ""
echo -e "${BLUE}🔍 Quick Tests:${NC}"
echo -n "  Nginx Health: "
curl -s -f http://localhost:8082/health > /dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Failed${NC}"

echo -n "  Kong Admin: "
curl -s -f http://localhost:8001/status > /dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Failed${NC}"

echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo "  1. Run tests: ./scripts/test-e2e.sh"
echo "  2. Check logs: docker-compose logs -f"
echo "  3. Access Kong Admin: http://localhost:8001"
echo ""