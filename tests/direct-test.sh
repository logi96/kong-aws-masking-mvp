#!/bin/bash
# 직접 테스트 스크립트 - Kong을 우회하여 테스트

echo "=== 직접 Anthropic API 테스트 ==="
echo "API 키가 올바른지 확인..."

# API 키 확인
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY not set"
    exit 1
fi

echo "API Key length: ${#ANTHROPIC_API_KEY}"

# 직접 Anthropic API 호출
echo -e "\n=== Anthropic API 직접 호출 ==="
curl -s -w "\nHTTP_CODE: %{http_code}\n" https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{
        "model": "claude-3-sonnet-20240229",
        "messages": [{
            "role": "user",
            "content": "Say hello in 5 words"
        }],
        "max_tokens": 20
    }'