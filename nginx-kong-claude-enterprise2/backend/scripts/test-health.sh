#!/bin/bash

# Health check test script for nginx-kong-claude-enterprise2 backend

echo "====================================="
echo "Health Check Test Suite"
echo "====================================="
echo ""

BASE_URL="http://localhost:3000"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check endpoint
check_endpoint() {
    local endpoint=$1
    local description=$2
    
    echo -n "Testing $description... "
    
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint" 2>/dev/null)
    body=$(echo "$response" | head -n -1)
    status_code=$(echo "$response" | tail -n 1)
    
    if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 503 ]; then
        if [ "$status_code" -eq 200 ]; then
            echo -e "${GREEN}✓ OK (200)${NC}"
        else
            echo -e "${YELLOW}✓ OK (503 - Service degraded)${NC}"
        fi
        echo "Response: $body" | jq . 2>/dev/null || echo "Response: $body"
    else
        echo -e "${RED}✗ FAILED (HTTP $status_code)${NC}"
        echo "Response: $body"
    fi
    echo ""
}

# Check if service is running
echo "Checking if backend service is running..."
if ! curl -s -f "$BASE_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}Backend service is not running on port 3000${NC}"
    echo "Please start the service first: npm start"
    exit 1
fi

echo -e "${GREEN}Backend service is running${NC}"
echo ""

# Test all health endpoints
echo "1. Basic Health Check"
check_endpoint "/health" "GET /health"

echo "2. Detailed Health Check"
check_endpoint "/health/detailed" "GET /health/detailed"

echo "3. Liveness Probe"
check_endpoint "/health/live" "GET /health/live"

echo "4. Readiness Probe"
check_endpoint "/health/ready" "GET /health/ready"

echo "5. Kong Health Check"
check_endpoint "/health/dependencies/kong" "GET /health/dependencies/kong"

echo "6. Redis Health Check"
check_endpoint "/health/dependencies/redis" "GET /health/dependencies/redis"

echo "7. Claude API Health Check"
check_endpoint "/health/dependencies/claude" "GET /health/dependencies/claude"

echo "8. Service Metrics"
check_endpoint "/health/metrics" "GET /health/metrics"

echo "====================================="
echo "Health Check Test Complete"
echo "====================================="