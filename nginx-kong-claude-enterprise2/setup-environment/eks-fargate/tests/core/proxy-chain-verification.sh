#!/bin/bash
# Quick Proxy Chain Verification
# Tests: Claude Code SDK → Nginx → Kong → Claude API

echo "=== Proxy Chain Verification ==="
echo "Testing the complete proxy chain step by step..."
echo ""

# Check if services are running
echo "1. Checking Docker services..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "claude-nginx|claude-kong|claude-redis|claude-code-sdk"
echo ""

# Test Nginx proxy endpoint (using port from .env)
echo "2. Testing Nginx proxy (port ${NGINX_PROXY_PORT:-8085})..."
curl -s -o /dev/null -w "Nginx Health Check: %{http_code}\n" http://localhost:${NGINX_PROXY_PORT:-8085}/health
echo ""

# Test Kong admin (using port from .env)
echo "3. Testing Kong admin (port ${KONG_ADMIN_PORT:-8011})..."
curl -s http://localhost:${KONG_ADMIN_PORT:-8011}/status | jq -r '"Kong Status: " + .database.reachable' 2>/dev/null || echo "Kong Status: Unable to check"
echo ""

# Test Redis
echo "4. Testing Redis connection..."
docker exec claude-redis redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null && echo "Redis: Connected" || echo "Redis: Failed"
echo ""

# Test simple Claude API call through proxy
echo "5. Testing Claude API through proxy chain..."
echo "   Sending test request through Nginx proxy..."

response=$(curl -s -X POST http://localhost:${NGINX_PROXY_PORT:-8085}/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [
      {
        "role": "user", 
        "content": "Say hello and confirm you received this message. Include the AWS resource: i-1234567890abcdef0"
      }
    ],
    "max_tokens": 100
  }' 2>&1)

# Check response
if echo "$response" | jq . >/dev/null 2>&1; then
  echo "   ✅ Valid JSON response received"
  content=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
  if [ -n "$content" ]; then
    echo "   ✅ Claude responded successfully"
    echo "   Response preview: ${content:0:100}..."
    
    # Check if AWS resource was unmasked
    if [[ "$content" == *"i-1234567890abcdef0"* ]]; then
      echo "   ✅ AWS resource unmasking working!"
    else
      echo "   ⚠️  AWS resource not found in response (masking may be active)"
    fi
  else
    echo "   ❌ No content in response"
  fi
else
  echo "   ❌ Invalid response received"
  echo "   Response: ${response:0:200}..."
fi

echo ""
echo "6. Checking Kong logs for masking activity..."
if [ -f "./logs/kong/access.log" ]; then
  echo "Recent Kong access log entries:"
  tail -3 ./logs/kong/access.log | grep -E "(AWS_|mask:|unmask:)" || echo "No masking entries found in recent logs"
fi

echo ""
echo "7. Checking Redis for stored mappings..."
mask_count=$(docker exec claude-redis redis-cli -a "${REDIS_PASSWORD}" --scan --pattern "mask:*" 2>/dev/null | wc -l)
echo "Masking entries in Redis: $mask_count"

echo ""
echo "=== Verification Complete ==="
echo ""
echo "Summary:"
echo "- Nginx Proxy: http://localhost:${NGINX_PROXY_PORT:-8085}"
echo "- Kong Gateway: http://localhost:${KONG_PROXY_PORT:-8010} (internal)"
echo "- Kong Admin: http://localhost:${KONG_ADMIN_PORT:-8011}"
echo "- Redis: localhost:${REDIS_PORT:-6385}"
echo ""
echo "Run ./proxy-integration-test.sh for full 50-pattern test"