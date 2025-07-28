#!/bin/bash

# Nginx Proxy Test Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NGINX_URL="http://localhost:8082"
MONITORING_URL="http://localhost:9090"
REPORT_DIR="../tests/test-report"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$REPORT_DIR/nginx-proxy-test-${TIMESTAMP}.md"

# Ensure report directory exists
mkdir -p "$REPORT_DIR"

# Function to write to report
write_report() {
    echo "$1" >> "$REPORT_FILE"
}

# Function to test endpoint
test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=$3
    local method=${4:-GET}
    local data=${5:-}
    local headers=${6:-}
    
    echo -e "\n${YELLOW}Testing: $name${NC}"
    write_report "### Test: $name"
    write_report "- URL: $url"
    write_report "- Method: $method"
    write_report "- Expected Status: $expected_status"
    
    # Build curl command
    local curl_cmd="curl -s -w '\n%{http_code}' -X $method"
    
    if [ -n "$headers" ]; then
        curl_cmd="$curl_cmd $headers"
    fi
    
    if [ -n "$data" ]; then
        curl_cmd="$curl_cmd -d '$data'"
    fi
    
    curl_cmd="$curl_cmd '$url'"
    
    # Execute request
    local response=$(eval $curl_cmd)
    local body=$(echo "$response" | sed '$d')
    local status=$(echo "$response" | tail -1)
    
    write_report "- Actual Status: $status"
    write_report "- Response: \`\`\`json"
    write_report "$body"
    write_report "\`\`\`"
    
    if [ "$status" = "$expected_status" ]; then
        echo -e "${GREEN}✓ Status: $status (expected)${NC}"
        write_report "- Result: ✅ PASS"
        return 0
    else
        echo -e "${RED}✗ Status: $status (expected $expected_status)${NC}"
        write_report "- Result: ❌ FAIL"
        return 1
    fi
}

# Function to test rate limiting
test_rate_limit() {
    local endpoint=$1
    local rate=$2
    local burst=$3
    
    echo -e "\n${YELLOW}Testing rate limiting on $endpoint${NC}"
    write_report "### Test: Rate Limiting - $endpoint"
    write_report "- Rate: $rate req/s"
    write_report "- Burst: $burst"
    
    local success=0
    local rate_limited=0
    
    # Send burst + 5 requests rapidly
    for i in $(seq 1 $((burst + 5))); do
        local status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$NGINX_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d '{"test": "rate limit"}')
        
        if [ "$status" = "429" ]; then
            ((rate_limited++))
        else
            ((success++))
        fi
    done
    
    write_report "- Successful requests: $success"
    write_report "- Rate limited requests: $rate_limited"
    
    if [ $rate_limited -gt 0 ]; then
        echo -e "${GREEN}✓ Rate limiting is working ($rate_limited requests limited)${NC}"
        write_report "- Result: ✅ PASS"
        return 0
    else
        echo -e "${RED}✗ Rate limiting not triggered${NC}"
        write_report "- Result: ❌ FAIL"
        return 1
    fi
}

# Function to test CORS
test_cors() {
    local endpoint=$1
    
    echo -e "\n${YELLOW}Testing CORS on $endpoint${NC}"
    write_report "### Test: CORS - $endpoint"
    
    # Preflight request
    local response=$(curl -s -i -X OPTIONS "$NGINX_URL$endpoint" \
        -H "Origin: http://example.com" \
        -H "Access-Control-Request-Method: POST" \
        -H "Access-Control-Request-Headers: Content-Type")
    
    local cors_headers=$(echo "$response" | grep -i "access-control-")
    
    write_report "- CORS Headers:"
    write_report "\`\`\`"
    write_report "$cors_headers"
    write_report "\`\`\`"
    
    if echo "$cors_headers" | grep -q "Access-Control-Allow-Origin"; then
        echo -e "${GREEN}✓ CORS headers present${NC}"
        write_report "- Result: ✅ PASS"
        return 0
    else
        echo -e "${RED}✗ CORS headers missing${NC}"
        write_report "- Result: ❌ FAIL"
        return 1
    fi
}

# Start test report
echo -e "${BLUE}=== Nginx Proxy Test Suite ===${NC}"
write_report "# Nginx Proxy Test Report"
write_report "- Date: $(date)"
write_report "- Nginx URL: $NGINX_URL"
write_report ""
write_report "## Test Results"

# Check if services are running
echo -e "${YELLOW}Checking service availability...${NC}"
if ! curl -s -f "$NGINX_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: Nginx proxy is not accessible at $NGINX_URL${NC}"
    write_report "## Error: Nginx proxy is not accessible"
    exit 1
fi

# 1. Health Check Tests
write_report ""
write_report "## 1. Health Check Tests"

test_endpoint "Basic Health Check" \
    "$NGINX_URL/health" \
    "200"

test_endpoint "Monitoring Health Check" \
    "$MONITORING_URL/health/full" \
    "200" || true  # Don't fail if monitoring port not exposed

# 2. Monitoring Endpoints
write_report ""
write_report "## 2. Monitoring Endpoints"

test_endpoint "Metrics Endpoint" \
    "$NGINX_URL/metrics" \
    "200"

test_endpoint "Nginx Status" \
    "$NGINX_URL/nginx_status" \
    "200"

# 3. Claude API Proxy Tests
write_report ""
write_report "## 3. Claude API Proxy Tests"

# Test without required headers (should fail)
test_endpoint "Claude API - Missing Headers" \
    "$NGINX_URL/v1/messages" \
    "400" \
    "POST" \
    '{"messages": [{"role": "user", "content": "test"}]}' \
    "-H 'Content-Type: application/json'" || true

# Test CORS
test_cors "/v1/messages"

# 4. AWS Analyze Proxy Tests
write_report ""
write_report "## 4. AWS Analyze Proxy Tests"

test_endpoint "Analyze Endpoint - OPTIONS" \
    "$NGINX_URL/analyze" \
    "204" \
    "OPTIONS"

test_cors "/analyze"

# 5. Rate Limiting Tests
write_report ""
write_report "## 5. Rate Limiting Tests"

test_rate_limit "/v1/messages" 10 20
sleep 2  # Wait for rate limit to reset
test_rate_limit "/analyze" 10 10

# 6. Error Handling Tests
write_report ""
write_report "## 6. Error Handling Tests"

test_endpoint "Non-existent Endpoint" \
    "$NGINX_URL/non-existent" \
    "502" || test_endpoint "Non-existent Endpoint" \
    "$NGINX_URL/non-existent" \
    "404"

# 7. Security Headers Test
write_report ""
write_report "## 7. Security Headers Test"

echo -e "\n${YELLOW}Testing security headers...${NC}"
write_report "### Test: Security Headers"

response_headers=$(curl -s -I "$NGINX_URL/health")
write_report "- Headers:"
write_report "\`\`\`"
write_report "$response_headers"
write_report "\`\`\`"

security_headers=("X-Content-Type-Options" "X-Frame-Options" "X-XSS-Protection")
missing_headers=()

for header in "${security_headers[@]}"; do
    if ! echo "$response_headers" | grep -qi "$header"; then
        missing_headers+=("$header")
    fi
done

if [ ${#missing_headers[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All security headers present${NC}"
    write_report "- Result: ✅ PASS - All security headers present"
else
    echo -e "${RED}✗ Missing headers: ${missing_headers[*]}${NC}"
    write_report "- Result: ❌ FAIL - Missing: ${missing_headers[*]}"
fi

# 8. Performance Test
write_report ""
write_report "## 8. Performance Test"

echo -e "\n${YELLOW}Testing response time...${NC}"
write_report "### Test: Response Time"

total_time=0
num_requests=10

for i in $(seq 1 $num_requests); do
    time=$(curl -s -o /dev/null -w "%{time_total}" "$NGINX_URL/health")
    total_time=$(echo "$total_time + $time" | bc)
done

avg_time=$(echo "scale=3; $total_time / $num_requests" | bc)
write_report "- Average response time: ${avg_time}s"

if (( $(echo "$avg_time < 0.1" | bc -l) )); then
    echo -e "${GREEN}✓ Average response time: ${avg_time}s${NC}"
    write_report "- Result: ✅ PASS"
else
    echo -e "${YELLOW}⚠ Average response time: ${avg_time}s${NC}"
    write_report "- Result: ⚠️ WARNING - Response time higher than expected"
fi

# 9. Log Check
write_report ""
write_report "## 9. Log Analysis"

echo -e "\n${YELLOW}Checking logs...${NC}"
write_report "### Recent Logs"

if docker logs nginx-proxy --tail 10 2>&1 | grep -q "error"; then
    echo -e "${YELLOW}⚠ Errors found in logs${NC}"
    write_report "- Errors found in recent logs"
    write_report "\`\`\`"
    docker logs nginx-proxy --tail 20 2>&1 | grep -i error >> "$REPORT_FILE"
    write_report "\`\`\`"
else
    echo -e "${GREEN}✓ No errors in recent logs${NC}"
    write_report "- No errors found in recent logs"
fi

# Summary
write_report ""
write_report "## Summary"
write_report "Test completed at: $(date)"

echo -e "\n${GREEN}=== Test Complete ===${NC}"
echo -e "${YELLOW}Report saved to: $REPORT_FILE${NC}"

# Show summary
echo -e "\n${BLUE}Test Summary:${NC}"
grep -E "(✅|❌|⚠️)" "$REPORT_FILE" | tail -20