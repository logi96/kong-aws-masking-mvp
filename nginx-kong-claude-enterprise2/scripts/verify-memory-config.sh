#!/bin/bash

# Kong Memory Configuration Verification Script
# Purpose: Verify Kong memory limits are properly configured to 4GB

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Kong Memory Configuration Verification ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Project Root: $PROJECT_ROOT"
echo

# Function to check memory configuration in files
check_memory_config() {
    local file=$1
    local expected_limit="4G"
    local expected_cache="2048m"
    
    echo -e "${YELLOW}Checking: $file${NC}"
    
    if [[ -f "$file" ]]; then
        # Check KONG_MEMORY_LIMIT
        if grep -q "KONG_MEMORY_LIMIT.*4G" "$file"; then
            echo -e "${GREEN}✓ KONG_MEMORY_LIMIT set to 4G${NC}"
        else
            echo -e "${RED}✗ KONG_MEMORY_LIMIT not set to 4G${NC}"
            grep "KONG_MEMORY_LIMIT" "$file" || echo "  Not found"
        fi
        
        # Check KONG_MEM_CACHE_SIZE
        if grep -q "KONG_MEM_CACHE_SIZE.*2048m" "$file"; then
            echo -e "${GREEN}✓ KONG_MEM_CACHE_SIZE set to 2048m${NC}"
        else
            echo -e "${RED}✗ KONG_MEM_CACHE_SIZE not set to 2048m${NC}"
            grep "KONG_MEM_CACHE_SIZE" "$file" || echo "  Not found"
        fi
    else
        echo -e "${RED}✗ File not found${NC}"
    fi
    echo
}

# Check configuration files
echo -e "${BLUE}1. Checking Configuration Files${NC}"
check_memory_config "$PROJECT_ROOT/docker-compose.yml"
check_memory_config "$PROJECT_ROOT/docker-compose.prod.yml"
check_memory_config "$PROJECT_ROOT/.env.example"

# Check if .env exists and has correct values
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    echo -e "${BLUE}2. Checking Active .env Configuration${NC}"
    check_memory_config "$PROJECT_ROOT/.env"
else
    echo -e "${YELLOW}2. No .env file found (using defaults from docker-compose)${NC}"
fi

# Check Kong Dockerfile
echo -e "${BLUE}3. Checking Kong Dockerfile Optimizations${NC}"
if grep -q "KONG_MEM_CACHE_SIZE=2048m" "$PROJECT_ROOT/kong/Dockerfile"; then
    echo -e "${GREEN}✓ Kong Dockerfile has memory optimization settings${NC}"
else
    echo -e "${RED}✗ Kong Dockerfile missing memory optimization settings${NC}"
fi

# If Kong is running, check actual memory usage
if docker ps | grep -q "claude-kong"; then
    echo
    echo -e "${BLUE}4. Checking Running Kong Container${NC}"
    
    # Get container stats
    echo -e "${YELLOW}Container Resource Usage:${NC}"
    docker stats --no-stream claude-kong | tail -n 1
    
    # Check configured limits
    echo -e "${YELLOW}Container Memory Limits:${NC}"
    docker inspect claude-kong | jq -r '.[0].HostConfig.Memory' | awk '{
        if ($1 == 0) print "No memory limit set (using Docker default)"
        else printf "Memory limit: %.2f GB\n", $1/1024/1024/1024
    }'
    
    # Check Kong internal memory settings
    echo -e "${YELLOW}Kong Internal Memory Settings:${NC}"
    docker exec claude-kong kong config | grep -E "(mem_cache_size|worker)" || true
else
    echo -e "${YELLOW}4. Kong container not running - start services to verify runtime config${NC}"
fi

# Generate verification report
REPORT_FILE="$PROJECT_ROOT/tests/test-report/memory-config-verification-$TIMESTAMP.md"
mkdir -p "$PROJECT_ROOT/tests/test-report"

cat > "$REPORT_FILE" << EOF
# Kong Memory Configuration Verification Report

**Date**: $(date)
**Script**: verify-memory-config.sh

## Configuration Files Checked

1. **docker-compose.yml**
   - KONG_MEMORY_LIMIT: $(grep "KONG_MEMORY_LIMIT" "$PROJECT_ROOT/docker-compose.yml" | grep -o '[0-9]*[GM]' | head -1 || echo "Not found")
   - KONG_MEM_CACHE_SIZE: $(grep "KONG_MEM_CACHE_SIZE" "$PROJECT_ROOT/docker-compose.yml" | grep -o '[0-9]*m' | head -1 || echo "Not found")

2. **docker-compose.prod.yml**
   - KONG_MEMORY_LIMIT: $(grep "KONG_MEMORY_LIMIT" "$PROJECT_ROOT/docker-compose.prod.yml" | grep -o '[0-9]*[GM]' | head -1 || echo "Not found")
   - KONG_MEM_CACHE_SIZE: $(grep "KONG_MEM_CACHE_SIZE" "$PROJECT_ROOT/docker-compose.prod.yml" | grep -o '[0-9]*m' | head -1 || echo "Not found")

3. **.env.example**
   - KONG_MEMORY_LIMIT: $(grep "^KONG_MEMORY_LIMIT" "$PROJECT_ROOT/.env.example" | cut -d= -f2 || echo "Not found")
   - KONG_MEM_CACHE_SIZE: $(grep "^KONG_MEM_CACHE_SIZE" "$PROJECT_ROOT/.env.example" | cut -d= -f2 || echo "Not found")

## Dockerfile Optimizations

$(grep -E "KONG_(MEM_CACHE_SIZE|NGINX_WORKER)" "$PROJECT_ROOT/kong/Dockerfile" | sed 's/^/- /')

## Recommendations

1. Ensure all environment files have consistent memory settings
2. Restart Kong container after configuration changes
3. Monitor actual memory usage under load
4. Consider adjusting worker processes based on CPU cores

## Next Steps

\`\`\`bash
# Apply new configuration
docker-compose down
docker-compose up -d

# Monitor memory usage
docker stats claude-kong

# Check Kong health
curl http://localhost:8001/status
\`\`\`
EOF

echo
echo -e "${GREEN}Verification complete! Report saved to:${NC}"
echo "$REPORT_FILE"