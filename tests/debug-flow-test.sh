#!/bin/bash
# 디버그 플로우 테스트 - 전체 변환 과정 상세 출력

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "🔍 AWS 패턴 변환 플로우 디버그 테스트"
echo "================================================"

# 간단한 테스트 메시지
TEST_MESSAGE="EC2 instance i-1234567890abcdef0 at IP 10.0.1.100 in security group sg-12345678"

echo -e "\n[1] 원본 요청 데이터:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TEST_MESSAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# JSON 요청 생성
REQUEST_JSON=$(cat <<EOF
{
  "model": "claude-3-5-sonnet-20241022",
  "messages": [{
    "role": "user",
    "content": "$TEST_MESSAGE"
  }],
  "max_tokens": 100
}
EOF
)

echo -e "\n[2] Kong으로 전송할 JSON:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$REQUEST_JSON" | jq .
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n[3] API 호출 실행..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_JSON")

# HTTP 상태 코드 추출
HTTP_STATUS=$(echo "$RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')

echo -e "\n[4] HTTP 응답 상태: $HTTP_STATUS"

echo -e "\n[5] 원시 응답 (처음 1000자):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$RESPONSE_BODY" | head -c 1000
echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n[6] 응답 파싱 시도:"
if [ -n "$RESPONSE_BODY" ]; then
  # JSON 응답인지 확인
  if echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    echo "✅ 유효한 JSON 응답"
    
    # Claude 응답 내용 추출
    CLAUDE_RESPONSE=$(echo "$RESPONSE_BODY" | jq -r '.content[0].text' 2>/dev/null)
    if [ "$CLAUDE_RESPONSE" != "null" ] && [ -n "$CLAUDE_RESPONSE" ]; then
      echo -e "\n[7] Claude 응답 내용:"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "$CLAUDE_RESPONSE"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "⚠️  Claude 응답 내용을 추출할 수 없습니다"
    fi
  else
    echo "❌ JSON 파싱 실패"
  fi
fi

echo -e "\n[8] 마스킹 검증:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 원본 패턴 검색
declare -a PATTERNS=(
  "i-1234567890abcdef0"
  "10.0.1.100"
  "sg-12345678"
)

for pattern in "${PATTERNS[@]}"; do
  if echo "$RESPONSE_BODY" | grep -q "$pattern"; then
    echo "❌ $pattern - 마스킹되지 않음 (노출됨!)"
  else
    echo "✅ $pattern - 성공적으로 마스킹됨"
  fi
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n[9] Kong 로그 확인:"
docker-compose logs kong --tail=5 | grep -v "127.0.0.11"

echo -e "\n================================================"