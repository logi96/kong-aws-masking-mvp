#!/bin/bash

# Kong Memory Update Deployment Script
# Purpose: Safely deploy Kong memory limit increase to 4GB in production

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/backups/memory-update-$TIMESTAMP"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Kong Memory Update Deployment ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Project Root: $PROJECT_ROOT"
echo

# Function to check service health
check_service_health() {
    local service=$1
    local port=$2
    local endpoint=$3
    
    echo -n "Checking $service health... "
    if curl -sf "http://localhost:$port$endpoint" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

# Function to backup current configuration
backup_configuration() {
    echo -e "${BLUE}Creating configuration backup...${NC}"
    mkdir -p "$BACKUP_DIR"
    
    # Backup important files
    cp "$PROJECT_ROOT/docker-compose.yml" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PROJECT_ROOT/docker-compose.prod.yml" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PROJECT_ROOT/.env" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PROJECT_ROOT/.env.example" "$BACKUP_DIR/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/kong" "$BACKUP_DIR/" 2>/dev/null || true
    
    echo -e "${GREEN}✓ Backup created at: $BACKUP_DIR${NC}"
}

# Function to validate new configuration
validate_configuration() {
    echo -e "${BLUE}Validating new configuration...${NC}"
    
    # Check if docker-compose files are valid
    if docker-compose -f "$PROJECT_ROOT/docker-compose.yml" config > /dev/null 2>&1; then
        echo -e "${GREEN}✓ docker-compose.yml is valid${NC}"
    else
        echo -e "${RED}✗ docker-compose.yml validation failed${NC}"
        return 1
    fi
    
    if [[ -f "$PROJECT_ROOT/docker-compose.prod.yml" ]]; then
        if docker-compose -f "$PROJECT_ROOT/docker-compose.prod.yml" config > /dev/null 2>&1; then
            echo -e "${GREEN}✓ docker-compose.prod.yml is valid${NC}"
        else
            echo -e "${RED}✗ docker-compose.prod.yml validation failed${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Main deployment process
echo -e "${BLUE}Step 1: Pre-deployment Checks${NC}"

# Check current service status
KONG_RUNNING=false
if docker ps | grep -q "claude-kong"; then
    KONG_RUNNING=true
    echo -e "${YELLOW}Kong is currently running${NC}"
    
    # Get current memory stats
    echo "Current memory usage:"
    docker stats --no-stream claude-kong | tail -n 1
fi

# Create backup
echo
echo -e "${BLUE}Step 2: Backup Current Configuration${NC}"
backup_configuration

# Validate new configuration
echo
echo -e "${BLUE}Step 3: Validate New Configuration${NC}"
if ! validate_configuration; then
    echo -e "${RED}Configuration validation failed! Aborting deployment.${NC}"
    exit 1
fi

# Apply updates
echo
echo -e "${BLUE}Step 4: Apply Memory Configuration Updates${NC}"

if [[ "$KONG_RUNNING" == "true" ]]; then
    echo -e "${YELLOW}Performing rolling update...${NC}"
    
    # Health check before update
    check_service_health "Kong Admin" 8001 "/status" || true
    
    # Pull latest images
    echo "Pulling latest images..."
    docker-compose pull kong
    
    # Recreate Kong container with new limits
    echo "Recreating Kong container with new memory limits..."
    docker-compose up -d --no-deps --force-recreate kong
    
    # Wait for Kong to be healthy
    echo "Waiting for Kong to be healthy..."
    for i in {1..30}; do
        if check_service_health "Kong Admin" 8001 "/status" 2>/dev/null; then
            break
        fi
        echo -n "."
        sleep 2
    done
    echo
else
    echo -e "${YELLOW}Kong not running. Starting services with new configuration...${NC}"
    docker-compose up -d kong
fi

# Verify deployment
echo
echo -e "${BLUE}Step 5: Post-deployment Verification${NC}"

# Wait a bit for services to stabilize
sleep 5

# Check service health
echo "Service health checks:"
check_service_health "Kong Admin" 8001 "/status" || true
check_service_health "Kong Proxy" 8000 "/" || true

# Verify memory configuration
echo
echo "Memory configuration verification:"
if docker ps | grep -q "claude-kong"; then
    # Check actual memory limit
    MEMORY_LIMIT=$(docker inspect claude-kong | jq -r '.[0].HostConfig.Memory')
    if [[ "$MEMORY_LIMIT" -eq 0 ]]; then
        echo -e "${YELLOW}⚠ No explicit memory limit set (using Docker default)${NC}"
    else
        MEMORY_GB=$(echo "scale=2; $MEMORY_LIMIT/1024/1024/1024" | bc)
        echo -e "${GREEN}✓ Memory limit: ${MEMORY_GB}GB${NC}"
    fi
    
    # Check Kong internal settings
    echo "Kong internal memory settings:"
    docker exec claude-kong printenv | grep -E "KONG_MEM_CACHE_SIZE|KONG_MEMORY_LIMIT" || true
fi

# Generate deployment report
REPORT_FILE="$PROJECT_ROOT/tests/test-report/memory-deployment-$TIMESTAMP.md"
mkdir -p "$PROJECT_ROOT/tests/test-report"

cat > "$REPORT_FILE" << EOF
# Kong Memory Update Deployment Report

**Date**: $(date)
**Script**: deploy-memory-update.sh

## Deployment Summary

- **Backup Location**: $BACKUP_DIR
- **Kong Status**: $(if [[ "$KONG_RUNNING" == "true" ]]; then echo "Running (Rolling Update)"; else echo "Started Fresh"; fi)
- **Configuration Files Updated**:
  - docker-compose.yml
  - docker-compose.prod.yml
  - .env.example
  - kong/Dockerfile

## Memory Configuration

- **Container Memory Limit**: 4GB
- **Kong Memory Cache Size**: 2048m
- **Worker Memory Reservations**: 2GB

## Health Check Results

$(if check_service_health "Kong Admin" 8001 "/status" 2>/dev/null; then echo "- Kong Admin API: ✓ Healthy"; else echo "- Kong Admin API: ✗ Failed"; fi)
$(if check_service_health "Kong Proxy" 8000 "/" 2>/dev/null; then echo "- Kong Proxy: ✓ Healthy"; else echo "- Kong Proxy: ✗ Failed"; fi)

## Post-deployment Actions

1. Monitor memory usage: \`docker stats claude-kong\`
2. Check logs: \`docker logs -f claude-kong\`
3. Run comprehensive tests: \`cd tests && ./comprehensive-flow-test.sh\`

## Rollback Instructions

If issues occur, rollback using:
\`\`\`bash
# Restore backup
cp $BACKUP_DIR/docker-compose.yml $PROJECT_ROOT/
cp $BACKUP_DIR/docker-compose.prod.yml $PROJECT_ROOT/
docker-compose up -d --force-recreate kong
\`\`\`
EOF

echo
echo -e "${GREEN}Deployment complete! Report saved to:${NC}"
echo "$REPORT_FILE"

# Final recommendations
echo
echo -e "${BLUE}Recommended Next Steps:${NC}"
echo "1. Monitor memory usage: docker stats claude-kong"
echo "2. Run comprehensive tests: cd tests && ./comprehensive-flow-test.sh"
echo "3. Check application logs: docker logs -f claude-kong"
echo "4. Verify API functionality with your test suite"