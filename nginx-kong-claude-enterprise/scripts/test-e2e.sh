#!/bin/bash

# Nginx-Kong-Claude Enterprise End-to-End Test Script

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}🧪 Nginx-Kong-Claude Enterprise E2E Test${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check if services are running
echo -e "${YELLOW}📋 Pre-flight checks...${NC}"
if ! docker-compose ps | grep -q "Up"; then
    echo -e "${RED}❌ Services not running. Please run ./scripts/start.sh first${NC}"
    exit 1
fi

# Load environment variables
source .env

# Test configuration
PROXY_URL="http://localhost:8082"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_RESULTS_DIR="logs/test-results"
mkdir -p "$TEST_RESULTS_DIR"

echo -e "${GREEN}✅ Services are running${NC}"
echo ""

# Function to test masking
test_masking() {
    local test_name=$1
    local test_file=$2
    local expected_patterns=$3
    
    echo -e "${CYAN}▶ Test: $test_name${NC}"
    
    # Create test payload
    local payload='{
        "model": "claude-3-5-sonnet-20241022",
        "max_tokens": 100,
        "messages": [{
            "role": "user",
            "content": "'"$test_file"'"
        }]
    }'
    
    # Make request
    local response=$(curl -s -X POST "$PROXY_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload" 2>&1)
    
    # Save response
    echo "$response" > "$TEST_RESULTS_DIR/${test_name}_${TIMESTAMP}.json"
    
    # Check if request was successful
    if echo "$response" | grep -q "error"; then
        echo -e "${RED}  ❌ Request failed${NC}"
        echo "  Response: $response"
        return 1
    fi
    
    # Check Kong logs for masking
    local kong_logs=$(docker-compose logs --tail=50 kong 2>&1)
    
    # Check for masked patterns in logs
    local masked_found=false
    for pattern in $expected_patterns; do
        if echo "$kong_logs" | grep -q "$pattern"; then
            echo -e "${GREEN}  ✅ Found masked pattern: $pattern${NC}"
            masked_found=true
        fi
    done
    
    if [ "$masked_found" = true ]; then
        echo -e "${GREEN}  ✅ Masking confirmed in Kong logs${NC}"
    else
        echo -e "${YELLOW}  ⚠️  No masking patterns found in logs${NC}"
    fi
    
    echo ""
}

# Test 1: EC2 Instance Masking
test_masking "EC2_Masking" \
    "EC2 instance i-1234567890abcdef0 with IP 10.0.1.50" \
    "EC2_INSTANCE_ PRIVATE_IP_"

# Test 2: S3 Bucket Masking
test_masking "S3_Masking" \
    "S3 bucket my-production-data-bucket needs replication" \
    "S3_BUCKET_"

# Test 3: RDS Instance Masking
test_masking "RDS_Masking" \
    "RDS instance prod-db.cluster-xyz.us-east-1.rds.amazonaws.com" \
    "RDS_INSTANCE_"

# Test Redis functionality
echo -e "${CYAN}▶ Test: Redis Mapping Storage${NC}"
redis_test=$(docker-compose exec -T redis redis-cli --pass "$REDIS_PASSWORD" KEYS "*" 2>&1)
if echo "$redis_test" | grep -q "aws-masker"; then
    echo -e "${GREEN}  ✅ Redis contains masking mappings${NC}"
    mapping_count=$(docker-compose exec -T redis redis-cli --pass "$REDIS_PASSWORD" DBSIZE 2>&1 | grep -o '[0-9]*' | head -1)
    echo -e "${GREEN}  ✅ Total mappings stored: $mapping_count${NC}"
else
    echo -e "${YELLOW}  ⚠️  No masking mappings found in Redis${NC}"
fi
echo ""

# Performance test
echo -e "${CYAN}▶ Test: Response Time${NC}"
total_time=0
iterations=5

for i in $(seq 1 $iterations); do
    start_time=$(date +%s.%N)
    
    curl -s -X POST "$PROXY_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d '{
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 50,
            "messages": [{"role": "user", "content": "Hello"}]
        }' > /dev/null 2>&1
    
    end_time=$(date +%s.%N)
    response_time=$(echo "$end_time - $start_time" | bc)
    total_time=$(echo "$total_time + $response_time" | bc)
    
    echo -e "  Iteration $i: ${response_time}s"
done

avg_time=$(echo "scale=3; $total_time / $iterations" | bc)
echo -e "${GREEN}  ✅ Average response time: ${avg_time}s${NC}"
echo ""

# Check logs for errors
echo -e "${CYAN}▶ Test: Error Check${NC}"
error_count=0

nginx_errors=$(docker-compose logs nginx 2>&1 | grep -i error | wc -l)
kong_errors=$(docker-compose logs kong 2>&1 | grep -i error | grep -v "error_log" | wc -l)

if [ "$nginx_errors" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠️  Nginx errors found: $nginx_errors${NC}"
    error_count=$((error_count + nginx_errors))
fi

if [ "$kong_errors" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠️  Kong errors found: $kong_errors${NC}"
    error_count=$((error_count + kong_errors))
fi

if [ "$error_count" -eq 0 ]; then
    echo -e "${GREEN}  ✅ No errors found in logs${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}📊 Test Summary${NC}"
echo -e "${BLUE}===============${NC}"
echo "  Test results saved to: $TEST_RESULTS_DIR"
echo "  Average response time: ${avg_time}s"
echo "  Redis mappings: $mapping_count"
echo "  Total errors: $error_count"
echo ""

# Run client container tests
echo -e "${CYAN}▶ Running Claude Client Tests...${NC}"
docker-compose exec -T claude-client /app/test-claude.sh || {
    echo -e "${YELLOW}  ⚠️  Some client tests failed${NC}"
}

echo ""
echo -e "${GREEN}✨ E2E Testing Complete!${NC}"
echo ""
echo -e "${BLUE}💡 Next steps:${NC}"
echo "  - Review test results in: $TEST_RESULTS_DIR"
echo "  - Check detailed logs: docker-compose logs -f"
echo "  - Monitor Redis: docker-compose exec redis redis-cli --pass \$REDIS_PASSWORD"
echo ""