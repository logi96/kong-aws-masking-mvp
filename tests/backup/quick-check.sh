#!/bin/bash

echo "Kong AWS Masking MVP - Quick Health Check"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check Backend API
echo -n "Checking Backend API (port 3000)... "
if curl -s http://localhost:3000/health > /dev/null; then
    echo -e "${GREEN}✓ Online${NC}"
else
    echo -e "${RED}✗ Offline${NC}"
fi

# Check Kong Gateway
echo -n "Checking Kong Gateway (port 8000)... "
if curl -s http://localhost:8000 > /dev/null; then
    echo -e "${GREEN}✓ Online${NC}"
else
    echo -e "${RED}✗ Offline${NC}"
fi

# Check Kong Admin API
echo -n "Checking Kong Admin API (port 8001)... "
if curl -s http://localhost:8001/status > /dev/null; then
    echo -e "${GREEN}✓ Online${NC}"
else
    echo -e "${RED}✗ Offline${NC}"
fi

# Check Docker containers
echo -e "\nDocker Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(kong|backend)"

echo -e "\nQuick check completed!"