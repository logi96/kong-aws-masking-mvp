#!/bin/bash
# 마스킹 디버그 테스트

export ANTHROPIC_API_KEY="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"

# 간단한 테스트
echo "=== 간단한 마스킹 테스트 ==="
echo ""

# 1. 단순 텍스트로 테스트
SIMPLE_TEXT="Instance i-1234567890abcdef0 at 10.0.1.100"
echo "원본: $SIMPLE_TEXT"

REQUEST=$(jq -n --arg text "$SIMPLE_TEXT" '{
  model: "claude-3-5-sonnet-20241022",
  system: "You MUST return EXACTLY what the user sends. No modifications.",
  messages: [{
    role: "user",
    content: $text
  }],
  max_tokens: 100
}')

echo ""
echo "Kong으로 전송 중..."

# Kong 호출
# REMOVED - Wrong pattern: RESPONSE=$(curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST")

# 응답 텍스트 추출
CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

echo ""
echo "전체 응답:"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
echo ""
echo "Claude 응답 텍스트: $CLAUDE_TEXT"
echo ""

# 마스킹 확인
if echo "$CLAUDE_TEXT" | grep -q "i-1234567890abcdef0"; then
  echo "❌ 마스킹 실패: EC2 인스턴스 ID가 노출됨"
else
  echo "✅ 마스킹 성공: EC2 인스턴스 ID가 마스킹됨"
fi

if echo "$CLAUDE_TEXT" | grep -q "10.0.1.100"; then
  echo "❌ 마스킹 실패: IP 주소가 노출됨"
else
  echo "✅ 마스킹 성공: IP 주소가 마스킹됨"
fi

# Kong 로그 확인
echo ""
echo "=== Kong 로그 확인 ==="
docker-compose logs kong --tail=20 | grep -E "(Masker:|mask_data|_mask_string)" || echo "마스킹 관련 로그 없음"

# 2. 수동으로 마스킹된 텍스트 전송
echo ""
echo "=== 수동 마스킹 테스트 ==="
MASKED_TEXT="Instance EC2_001 at PRIVATE_IP_001"
echo "마스킹된 텍스트: $MASKED_TEXT"

MASKED_REQUEST=$(jq -n --arg text "$MASKED_TEXT" '{
  model: "claude-3-5-sonnet-20241022",
  system: "You MUST return EXACTLY what the user sends.",
  messages: [{
    role: "user",
    content: $text
  }],
  max_tokens: 100
}')

# REMOVED - Wrong pattern: MASKED_RESPONSE=$(curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$MASKED_REQUEST")

MASKED_CLAUDE_TEXT=$(echo "$MASKED_RESPONSE" | jq -r '.content[0].text' 2>/dev/null)
echo "Claude 응답: $MASKED_CLAUDE_TEXT"