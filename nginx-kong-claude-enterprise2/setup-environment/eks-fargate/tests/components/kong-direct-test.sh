#!/bin/bash
# Direct Kong Integration Test
# Tests Kong → Claude API with AWS masking

echo "=== Direct Kong Integration Test ==="
echo "Testing Kong Gateway AWS masking..."
echo ""

# Source environment variables
source ../.env

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test report setup
TEST_REPORT_DIR="./test-report"
mkdir -p "$TEST_REPORT_DIR"
REPORT_FILE="$TEST_REPORT_DIR/kong-direct-test-$(date +%Y%m%d_%H%M%S).md"

# Initialize report
cat > "$REPORT_FILE" << EOF
# Kong Direct Integration Test Report

**Test Time**: $(date -Iseconds)
**Purpose**: Test Kong AWS masking without Nginx proxy

## Test Results

EOF

# Function to test AWS pattern
test_pattern() {
  local pattern_name="$1"
  local aws_resource="$2"
  
  echo -e "${YELLOW}Testing: $pattern_name${NC}"
  echo "  Resource: $aws_resource"
  
  # Send request directly to Kong
  response=$(curl -s -X POST http://localhost:${KONG_PROXY_PORT:-8010}/v1/messages \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"Please repeat this AWS resource ID exactly: $aws_resource\"
        }
      ],
      \"max_tokens\": 100
    }" 2>&1)
  
  # Check response
  if echo "$response" | jq . >/dev/null 2>&1; then
    content=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
    if [ -n "$content" ]; then
      if [[ "$content" == *"$aws_resource"* ]]; then
        echo -e "  ${GREEN}✅ PASSED - Resource found in response${NC}"
        echo "### ✅ $pattern_name" >> "$REPORT_FILE"
        echo "- Resource: \`$aws_resource\`" >> "$REPORT_FILE"
        echo "- Status: Successfully unmasked" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        return 0
      else
        echo -e "  ${RED}❌ FAILED - Resource not found in response${NC}"
        echo "  Response: ${content:0:100}..."
        echo "### ❌ $pattern_name" >> "$REPORT_FILE"
        echo "- Resource: \`$aws_resource\`" >> "$REPORT_FILE"
        echo "- Error: Resource not unmasked" >> "$REPORT_FILE"
        echo "- Response: \`${content:0:100}...\`" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        return 1
      fi
    else
      echo -e "  ${RED}❌ ERROR - No content in response${NC}"
      echo "### ❌ $pattern_name" >> "$REPORT_FILE"
      echo "- Resource: \`$aws_resource\`" >> "$REPORT_FILE"
      echo "- Error: No content in response" >> "$REPORT_FILE"
      echo "" >> "$REPORT_FILE"
      return 1
    fi
  else
    echo -e "  ${RED}❌ ERROR - Invalid response${NC}"
    echo "  Response: ${response:0:100}..."
    echo "### ❌ $pattern_name" >> "$REPORT_FILE"
    echo "- Resource: \`$aws_resource\`" >> "$REPORT_FILE"
    echo "- Error: Invalid JSON response" >> "$REPORT_FILE"
    echo "- Response: \`${response:0:100}...\`" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    return 1
  fi
}

# Run tests
echo "Starting AWS pattern tests..."
echo ""

TOTAL=0
PASSED=0

# Test key patterns
test_pattern "EC2 Instance" "i-1234567890abcdef0" && ((PASSED++))
((TOTAL++))

test_pattern "S3 Bucket" "my-production-bucket" && ((PASSED++))
((TOTAL++))

test_pattern "RDS Instance" "prod-mysql-db" && ((PASSED++))
((TOTAL++))

test_pattern "Security Group" "sg-0123456789abcdef0" && ((PASSED++))
((TOTAL++))

test_pattern "VPC ID" "vpc-12345678" && ((PASSED++))
((TOTAL++))

# Check Redis for mappings
echo ""
echo "Checking Redis for stored mappings..."
redis_keys=$(docker exec claude-redis redis-cli -a "${REDIS_PASSWORD}" --scan --pattern "mask:*" 2>/dev/null | head -5)
if [ -n "$redis_keys" ]; then
  echo -e "${GREEN}✅ Found masking mappings in Redis${NC}"
  echo "$redis_keys"
else
  echo -e "${YELLOW}⚠️ No masking mappings found in Redis${NC}"
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo "Total Tests: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $((TOTAL - PASSED))"
echo "Success Rate: $(( PASSED * 100 / TOTAL ))%"
echo ""
echo "Report saved to: $REPORT_FILE"

# Add summary to report
cat >> "$REPORT_FILE" << EOF

## Summary

- **Total Tests**: $TOTAL
- **Passed**: $PASSED
- **Failed**: $((TOTAL - PASSED))
- **Success Rate**: $(( PASSED * 100 / TOTAL ))%

**Test Completed**: $(date -Iseconds)
EOF