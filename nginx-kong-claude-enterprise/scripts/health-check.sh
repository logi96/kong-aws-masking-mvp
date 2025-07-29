#!/bin/bash

# Nginx-Kong-Claude Enterprise Health Check Script

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏥 Nginx-Kong-Claude Enterprise Health Check${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Function to check service
check_service() {
    local service_name=$1
    local check_command=$2
    
    echo -n -e "${YELLOW}Checking $service_name...${NC} "
    
    if eval "$check_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ Unhealthy${NC}"
        return 1
    fi
}

# Check Docker Compose services
echo -e "${BLUE}📦 Docker Services:${NC}"
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Check individual services
echo -e "${BLUE}🔍 Service Health Checks:${NC}"

# Redis
check_service "Redis" "docker-compose exec -T redis redis-cli --pass \${REDIS_PASSWORD} ping 2>/dev/null | grep -q PONG"

# Kong Admin
check_service "Kong Admin API" "curl -s -f http://localhost:8001/status"

# Kong Proxy
check_service "Kong Proxy" "curl -s -f http://localhost:8001/ | grep -q version"

# Nginx
check_service "Nginx Proxy" "curl -s -f http://localhost:8082/health"

# Kong Health via Nginx
check_service "Kong via Nginx" "curl -s -f http://localhost:8082/kong-health"

echo ""

# Check AWS Masker Plugin
echo -e "${BLUE}🔌 Plugin Status:${NC}"
if curl -s http://localhost:8001/plugins | grep -q "aws-masker"; then
    echo -e "${GREEN}✅ AWS Masker plugin is loaded${NC}"
    
    # Get plugin configuration
    echo -e "${YELLOW}  Plugin Configuration:${NC}"
    curl -s http://localhost:8001/plugins | jq -r '.data[] | select(.name == "aws-masker") | {enabled: .enabled, config: .config}' 2>/dev/null || echo "  Unable to fetch configuration"
else
    echo -e "${RED}❌ AWS Masker plugin not found${NC}"
fi

echo ""

# Check Redis connectivity from Kong
echo -e "${BLUE}🔗 Redis Connectivity:${NC}"
if docker-compose exec -T kong sh -c 'redis-cli -h redis -p 6379 -a ${REDIS_PASSWORD} ping 2>/dev/null' | grep -q PONG; then
    echo -e "${GREEN}✅ Kong can connect to Redis${NC}"
else
    echo -e "${RED}❌ Kong cannot connect to Redis${NC}"
fi

echo ""

# Resource usage
echo -e "${BLUE}📊 Resource Usage:${NC}"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(nginx|kong|redis|claude)" || true

echo ""

# Recent logs check
echo -e "${BLUE}📜 Recent Error Logs:${NC}"
echo -e "${YELLOW}Nginx errors (last 5):${NC}"
docker-compose logs nginx 2>&1 | grep -i error | tail -5 || echo "  No recent errors"

echo -e "${YELLOW}Kong errors (last 5):${NC}"
docker-compose logs kong 2>&1 | grep -i error | tail -5 || echo "  No recent errors"

echo ""
echo -e "${BLUE}💡 For detailed logs, run:${NC}"
echo "  docker-compose logs -f [service]"
echo "  Available services: nginx, kong, redis, claude-client"
echo ""