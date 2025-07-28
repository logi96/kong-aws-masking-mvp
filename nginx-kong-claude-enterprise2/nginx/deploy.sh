#!/bin/bash

# Nginx Proxy Deployment Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Nginx Reverse Proxy Deployment ===${NC}"

# Function to check if service is healthy
check_health() {
    local service=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}Checking health of $service...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ $service is healthy${NC}"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "\n${RED}✗ $service failed to become healthy${NC}"
    return 1
}

# Step 1: Validate configuration
echo -e "\n${YELLOW}1. Validating Nginx configuration...${NC}"
docker run --rm -v "$PWD/nginx.conf:/etc/nginx/nginx.conf:ro" -v "$PWD/conf.d:/etc/nginx/conf.d:ro" nginx:1.27-alpine nginx -t
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration is valid${NC}"
else
    echo -e "${RED}✗ Configuration validation failed${NC}"
    exit 1
fi

# Step 2: Build Docker image
echo -e "\n${YELLOW}2. Building Docker image...${NC}"
docker build -t nginx-kong-proxy:latest .
echo -e "${GREEN}✓ Image built successfully${NC}"

# Step 3: Create network if it doesn't exist
echo -e "\n${YELLOW}3. Checking Docker network...${NC}"
if ! docker network inspect kong-net >/dev/null 2>&1; then
    echo "Creating kong-net network..."
    docker network create kong-net
fi
echo -e "${GREEN}✓ Network ready${NC}"

# Step 4: Stop existing container if running
echo -e "\n${YELLOW}4. Checking for existing container...${NC}"
if docker ps -a | grep -q nginx-proxy; then
    echo "Stopping existing nginx-proxy container..."
    docker-compose -f docker-compose.nginx.yml down
fi

# Step 5: Start Nginx proxy
echo -e "\n${YELLOW}5. Starting Nginx proxy...${NC}"
docker-compose -f docker-compose.nginx.yml up -d

# Step 6: Wait for services to be healthy
echo -e "\n${YELLOW}6. Waiting for services to be ready...${NC}"
sleep 5

# Check Nginx health
check_health "Nginx" "http://localhost:8082/health"

# Step 7: Run basic tests
echo -e "\n${YELLOW}7. Running basic tests...${NC}"

# Test health endpoint
echo -e "\n${YELLOW}Testing health endpoint:${NC}"
curl -s http://localhost:8082/health | jq .

# Test metrics endpoint
echo -e "\n${YELLOW}Testing metrics endpoint:${NC}"
curl -s http://localhost:8082/metrics | head -20

# Test nginx status
echo -e "\n${YELLOW}Testing nginx status:${NC}"
curl -s http://localhost:8082/nginx_status

# Step 8: Show logs
echo -e "\n${YELLOW}8. Recent logs:${NC}"
docker logs --tail 20 nginx-proxy

# Step 9: Show running containers
echo -e "\n${YELLOW}9. Running containers:${NC}"
docker ps | grep -E "(nginx-proxy|kong)"

echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
echo -e "${GREEN}Nginx proxy is running on port 8082${NC}"
echo -e "${GREEN}Monitoring port: 9090${NC}"
echo -e "\n${YELLOW}Useful commands:${NC}"
echo "- View logs: docker logs -f nginx-proxy"
echo "- Check health: curl http://localhost:8082/health"
echo "- View metrics: curl http://localhost:9090/metrics"
echo "- Stop proxy: docker-compose -f docker-compose.nginx.yml down"
echo "- Restart proxy: docker-compose -f docker-compose.nginx.yml restart"