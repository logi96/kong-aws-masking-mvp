#!/bin/bash
# 헤더 전달 디버깅 테스트

echo "================================================"
echo "🔍 헤더 전달 디버깅"
echo "================================================"

# 1. 직접 Claude API 호출 (작동 확인)
echo -e "\n[1] 직접 Claude API 호출 (Kong 없이)"
curl -s -w "\nHTTP_CODE: %{http_code}\n" https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 10
  }' | jq . || echo "Direct API call failed"

# 2. Kong을 통한 호출 (헤더 포함)
echo -e "\n[2] Kong을 통한 호출 (x-api-key 헤더 포함)"
curl -v -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{"role": "user", "content": "Test with EC2 instance i-1234567890abcdef0"}],
    "max_tokens": 10
  }' 2>&1 | grep -E "< HTTP|< x-api-key|\"type\"|\"error\""

echo -e "\n================================================"