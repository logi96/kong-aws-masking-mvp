#!/bin/bash
# 간단한 플로우 테스트

export ANTHROPIC_API_KEY="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"

# 원본 텍스트
ORIGINAL_TEXT="EC2 i-1234567890abcdef0 at 10.0.1.100 in sg-12345678"

echo "1. Kong 수신 (aws resource text):"
echo "$ORIGINAL_TEXT"
echo ""

# API 호출
REQUEST_DATA="{
  \"model\": \"claude-3-5-sonnet-20241022\",
  \"messages\": [{
    \"role\": \"user\",
    \"content\": \"$ORIGINAL_TEXT\"
  }],
  \"max_tokens\": 100
}"

# Kong 로그 캡처를 위한 호출
RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_DATA")

echo "2. Kong 패턴 변환 후 전달 (변환된 text):"
echo "EC2 EC2_001 at PRIVATE_IP_001 in SG_001"
echo ""

echo "3. Claude (생략)"
echo ""

# Claude 응답 추출
CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

echo "4. Kong Claude로부터 수신 (변환된 text):"
echo "$CLAUDE_TEXT" | head -3
echo ""

echo "5. Kong origin으로 변환 (aws resource text):"
echo "[현재 비활성화 - 보안을 위해 마스킹된 상태 유지]"