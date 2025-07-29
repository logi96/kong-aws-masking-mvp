#!/bin/bash
# 단일 언마스킹 테스트 - 디버깅용
# Kong 언마스킹이 클라이언트까지 전달되는지 확인

echo "=== 단일 EC2 언마스킹 테스트 ==="
echo ""

# 1. 요청 전송 및 응답 저장
echo "1. 요청 전송 중..."
RESPONSE=$(curl -s -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "contextText": "Analyze EC2 instance i-1234567890abcdef0 for security issues. Please reference this instance ID in your recommendations.",
    "options": {
      "analysisType": "security_only",
      "maxTokens": 200
    }
  }')

# 2. 응답을 파일로 저장
echo "$RESPONSE" > /tmp/unmask-test-response.json

# 3. Claude 텍스트 추출
CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.analysis.content[0].text // "ERROR"' 2>/dev/null)

# 4. 결과 분석
echo ""
echo "2. 응답 분석:"
echo "   - 원본 EC2 ID: i-1234567890abcdef0"
echo "   - 응답 길이: $(echo "$CLAUDE_TEXT" | wc -c) bytes"
echo ""

# 5. 마스킹된 ID 검색
echo "3. 마스킹된 ID 검색:"
echo "$CLAUDE_TEXT" | grep -o "AWS_EC2_[0-9]*" | head -5

# 6. 원본 ID 검색
echo ""
echo "4. 원본 ID 검색:"
echo "$CLAUDE_TEXT" | grep -o "i-[0-9a-f]\{16\}" | head -5

# 7. Kong 로그 확인
echo ""
echo "5. Kong 최근 언마스킹 로그:"
docker logs kong-gateway 2>&1 | grep -E "MEMORY_UNMASKING.*Replaced" | tail -3

# 8. 전체 응답 확인
echo ""
echo "6. 전체 응답 (처음 500자):"
echo "${CLAUDE_TEXT:0:500}"

# 9. Backend API 로그 확인
echo ""
echo "7. Backend API 최근 로그:"
docker logs backend-api 2>&1 | tail -10