#!/bin/bash

# Phase 3 Step 7 Validation Script
# Validates proxy environment variables and infrastructure configuration

set -e

echo "==========================================="
echo "Phase 3 Step 7 Configuration Validation"
echo "==========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a service is healthy
check_service_health() {
    local service=$1
    local health_endpoint=$2
    
    echo -n "Checking $service health... "
    
    if curl -s -f "$health_endpoint" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Unhealthy${NC}"
        return 1
    fi
}

# Function to validate configuration files
validate_config() {
    local file=$1
    local description=$2
    
    echo -n "Validating $description... "
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ Found${NC}"
        return 0
    else
        echo -e "${RED}✗ Missing${NC}"
        return 1
    fi
}

# Function to check docker network connectivity
check_network_connectivity() {
    local from_service=$1
    local to_service=$2
    local port=$3
    
    echo -n "Checking connectivity from $from_service to $to_service:$port... "
    
    if docker exec "$from_service" nc -z "$to_service" "$port" 2>/dev/null; then
        echo -e "${GREEN}✓ Connected${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Unable to verify (service may not be running)${NC}"
        return 1
    fi
}

echo ""
echo "1. Configuration Files Validation"
echo "---------------------------------"

validate_config "docker-compose.yml" "docker-compose.yml"
validate_config "nginx/conf.d/claude-proxy.conf" "Nginx proxy configuration"
validate_config "kong/kong.yml" "Kong declarative configuration"

echo ""
echo "2. Docker Compose Configuration"
echo "-------------------------------"

# Check Claude Code SDK environment variables
echo -n "Checking Claude Code SDK environment config... "
if grep -q "HTTP_PROXY=http://nginx:8082" docker-compose.yml && \
   grep -q "ANTHROPIC_BASE_URL=http://nginx:8082/v1" docker-compose.yml && \
   ! grep -q "HTTPS_PROXY" docker-compose.yml; then
    echo -e "${GREEN}✓ Correct${NC}"
else
    echo -e "${RED}✗ Incorrect${NC}"
fi

# Check Kong port configuration
echo -n "Checking Kong port configuration... "
if grep -q "KONG_PROXY_LISTEN=0.0.0.0:8010" docker-compose.yml && \
   grep -q "8010:8010" docker-compose.yml; then
    echo -e "${GREEN}✓ Port 8010 configured${NC}"
else
    echo -e "${RED}✗ Port configuration incorrect${NC}"
fi

echo ""
echo "3. Nginx Configuration"
echo "---------------------"

# Check upstream configuration
echo -n "Checking Nginx upstream configuration... "
if grep -q "server kong:8010" nginx/conf.d/claude-proxy.conf; then
    echo -e "${GREEN}✓ Points to Kong on port 8010${NC}"
else
    echo -e "${RED}✗ Incorrect upstream configuration${NC}"
fi

# Check /v1/* location block
echo -n "Checking /v1/* location configuration... "
if grep -q "location ~ \^/v1/" nginx/conf.d/claude-proxy.conf && \
   grep -q "proxy_set_header Host api.anthropic.com" nginx/conf.d/claude-proxy.conf; then
    echo -e "${GREEN}✓ Configured with proper Host header${NC}"
else
    echo -e "${RED}✗ Missing or incorrect /v1/* configuration${NC}"
fi

echo ""
echo "4. Kong Configuration"
echo "--------------------"

# Check service configuration
echo -n "Checking Kong service configuration... "
if grep -q "url: https://api.anthropic.com" kong/kong.yml && \
   grep -q "host: api.anthropic.com" kong/kong.yml; then
    echo -e "${GREEN}✓ Claude API service configured${NC}"
else
    echo -e "${RED}✗ Service configuration incorrect${NC}"
fi

# Check route configuration
echo -n "Checking Kong route configuration... "
if grep -q "paths:" kong/kong.yml && grep -q "/v1" kong/kong.yml; then
    echo -e "${GREEN}✓ /v1 route configured${NC}"
else
    echo -e "${RED}✗ Route configuration incorrect${NC}"
fi

# Check AWS Masker plugin
echo -n "Checking AWS Masker plugin configuration... "
if grep -q "name: aws-masker" kong/kong.yml && \
   grep -q "route: claude-proxy-route" kong/kong.yml; then
    echo -e "${GREEN}✓ Plugin enabled on route${NC}"
else
    echo -e "${RED}✗ Plugin not properly configured${NC}"
fi

echo ""
echo "5. Service Health Checks (if running)"
echo "------------------------------------"

# Check if services are running
if docker ps | grep -q "claude-nginx"; then
    check_service_health "Nginx" "http://localhost:8082/health"
fi

if docker ps | grep -q "claude-kong"; then
    check_service_health "Kong Admin" "http://localhost:8001/status"
fi

if docker ps | grep -q "claude-redis"; then
    echo -n "Checking Redis health... "
    if docker exec claude-redis redis-cli -a "${REDIS_PASSWORD:-changeme}" ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✓ Healthy${NC}"
    else
        echo -e "${RED}✗ Unhealthy${NC}"
    fi
fi

echo ""
echo "6. Network Connectivity (if services running)"
echo "--------------------------------------------"

if docker ps | grep -q "claude-"; then
    # Check network existence
    echo -n "Checking Docker network... "
    if docker network ls | grep -q "claude-enterprise"; then
        echo -e "${GREEN}✓ Network exists${NC}"
        
        # Test connectivity between services
        if docker ps | grep -q "claude-nginx" && docker ps | grep -q "claude-kong"; then
            check_network_connectivity "claude-nginx" "kong" "8010"
        fi
        
        if docker ps | grep -q "claude-kong" && docker ps | grep -q "claude-redis"; then
            check_network_connectivity "claude-kong" "redis" "6379"
        fi
    else
        echo -e "${YELLOW}⚠ Network not found${NC}"
    fi
fi

echo ""
echo "==========================================="
echo "Configuration Validation Summary"
echo "==========================================="

# Summary
errors=0

# Check critical configurations
if ! grep -q "HTTP_PROXY=http://nginx:8082" docker-compose.yml || \
   ! grep -q "ANTHROPIC_BASE_URL=http://nginx:8082/v1" docker-compose.yml; then
    echo -e "${RED}✗ Claude Code SDK environment variables incorrect${NC}"
    ((errors++))
fi

if ! grep -q "server kong:8010" nginx/conf.d/claude-proxy.conf; then
    echo -e "${RED}✗ Nginx upstream configuration incorrect${NC}"
    ((errors++))
fi

if ! grep -q "KONG_PROXY_LISTEN=0.0.0.0:8010" docker-compose.yml; then
    echo -e "${RED}✗ Kong port configuration incorrect${NC}"
    ((errors++))
fi

if [ $errors -eq 0 ]; then
    echo -e "${GREEN}✓ All configurations are valid!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Start the services: docker-compose up -d"
    echo "2. Wait for services to be healthy"
    echo "3. Test the proxy chain with: ./scripts/test-phase3-step8.sh"
else
    echo -e "${RED}✗ Found $errors configuration errors. Please fix them before proceeding.${NC}"
    exit 1
fi