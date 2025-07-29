#!/bin/bash
# Simplified Kong Test - Direct approach

echo "===================================="
echo "🧪 Simplified Kong Test"
echo "===================================="
echo ""

# Direct test to Kong's analyze-claude endpoint
echo "1. Testing Kong analyze-claude endpoint directly..."
echo ""

TEST_RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: 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" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "List these AWS resources: EC2 i-1234567890abcdef0, VPC vpc-12345678, IP 10.0.1.100"
    }],
    "max_tokens": 100
  }' 2>&1)

echo "Response:"
echo "$TEST_RESPONSE" | jq '.' 2>/dev/null || echo "$TEST_RESPONSE"
echo ""

# Check if masking is working
if echo "$TEST_RESPONSE" | grep -E "i-[0-9a-f]{17}|vpc-[0-9a-f]{8}|10\.[0-9]+\.[0-9]+\.[0-9]+" > /dev/null; then
  echo "❌ WARNING: AWS patterns found in response - masking may not be working!"
else
  echo "✅ No AWS patterns found - masking appears to be working"
fi

echo ""
echo "2. Checking Kong logs for masking activity..."
docker-compose logs kong --tail=20 | grep -E "Masked|aws-masker" || echo "No masking logs found"