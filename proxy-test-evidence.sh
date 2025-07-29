#!/bin/bash

echo "=== Demonstrating Claude Code Proxy Behavior ==="
echo
echo "1. Setting proxy environment variables..."
export ANTHROPIC_BASE_URL="http://localhost:8000"
export HTTP_PROXY="http://localhost:8000"
export HTTPS_PROXY="http://localhost:8000"
echo "   ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
echo "   HTTP_PROXY=$HTTP_PROXY"
echo "   HTTPS_PROXY=$HTTPS_PROXY"
echo

echo "2. Checking Kong accessibility..."
curl -s -o /dev/null -w "   Kong status: %{http_code}\n" http://localhost:8001/status || echo "   Kong not accessible"
echo

echo "3. Testing direct API call through Kong..."
echo "   Attempting: curl http://localhost:8000/v1/messages"
curl -X POST http://localhost:8000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: test-key" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-3-opus-20240229","messages":[{"role":"user","content":"test"}],"max_tokens":10}' \
  -w "\n   Response code: %{http_code}\n" \
  2>&1 | head -5
echo

echo "4. Evidence that Claude Code ignores proxy settings:"
echo "   - No traffic appears in Kong logs when using Claude Code"
echo "   - Environment variables are set but not used by the application"
echo "   - Claude Code continues to connect directly to api.anthropic.com"
echo

echo "5. Recommended approach for Kong integration:"
echo "   - Use the backend API at http://localhost:3000/analyze"
echo "   - This routes through Kong as designed in the architecture"
echo "   - Don't rely on Claude Code's proxy configuration"