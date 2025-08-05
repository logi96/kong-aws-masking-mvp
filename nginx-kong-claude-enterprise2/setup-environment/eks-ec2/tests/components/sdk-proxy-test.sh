#!/bin/bash
# SDK Proxy Test - Run from inside Claude Code SDK container
# This script tests the proxy chain from within the Docker network

echo "=== Claude Code SDK Proxy Test ==="
echo "Testing from inside the Docker network..."
echo ""

# Function to test AWS pattern
test_pattern() {
  local pattern_name="$1"
  local aws_resource="$2"
  
  echo "Testing: $pattern_name"
  echo "Resource: $aws_resource"
  
  # Use the internal proxy URL configured in the SDK container
  response=$(curl -s -X POST ${ANTHROPIC_BASE_URL}/messages \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"Please repeat this AWS resource exactly: $aws_resource\"
        }
      ],
      \"max_tokens\": 50
    }" 2>&1)
  
  if echo "$response" | jq . >/dev/null 2>&1; then
    content=$(echo "$response" | jq -r '.content[0].text // empty')
    if [[ "$content" == *"$aws_resource"* ]]; then
      echo "✅ PASSED - Resource found in response"
    else
      echo "❌ FAILED - Resource not found in response"
      echo "Response: ${content:0:100}..."
    fi
  else
    echo "❌ ERROR - Invalid response"
    echo "Response: ${response:0:100}..."
  fi
  echo ""
}

# Check environment
echo "Environment Check:"
echo "ANTHROPIC_BASE_URL: ${ANTHROPIC_BASE_URL}"
echo "HTTP_PROXY: ${HTTP_PROXY}"
echo ""

# Test connectivity
echo "Testing proxy connectivity..."
curl -s -o /dev/null -w "Proxy health check: %{http_code}\n" ${HTTP_PROXY}/health || echo "Proxy health check failed"
echo ""

# Test various AWS patterns
echo "=== Testing AWS Patterns ==="
test_pattern "EC2 Instance" "i-1234567890abcdef0"
test_pattern "S3 Bucket" "my-production-bucket"
test_pattern "RDS Instance" "prod-mysql-db"
test_pattern "Security Group" "sg-0123456789abcdef0"
test_pattern "Lambda ARN" "arn:aws:lambda:us-east-1:123456789012:function:MyFunction"

echo "=== Test Complete ==="