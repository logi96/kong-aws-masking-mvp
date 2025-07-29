#!/bin/bash
# 올바른 마스킹/언마스킹 플로우 테스트
# Claude가 마스킹된 ID를 자연스럽게 사용하도록 유도하여 언마스킹 검증
#
# 테스트 시나리오:
# 1. AWS 리소스를 포함한 컨텍스트 전송
# 2. Kong이 마스킹 (i-1234... → AWS_EC2_001)
# 3. Claude가 마스킹된 ID를 응답에 사용
# 4. Kong이 언마스킹 (AWS_EC2_001 → i-1234...)

echo "=== 올바른 마스킹/언마스킹 플로우 테스트 ==="
echo ""

# 전역 카운터 초기화
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 테스트 함수
test_pattern() {
  local num="$1"
  local type="$2"
  local original="$3"
  local masked="$4"
  
  # 자연스러운 컨텍스트로 요청 전송
  # Claude가 리소스 ID를 응답에 포함하도록 유도
  RESPONSE=$(curl -s -X POST http://localhost:3000/analyze \
    -H "Content-Type: application/json" \
    -d "{
      \"contextText\": \"I have an AWS $type with ID $original that needs security analysis. Please analyze this specific resource and mention its ID in your response when providing recommendations.\",
      \"options\": {
        \"analysisType\": \"security_only\",
        \"maxTokens\": 300
      }
    }")
  
  # 응답에서 텍스트 추출
  CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.analysis.content[0].text // "ERROR"' 2>/dev/null || echo "PARSE_ERROR")
  
  # 전역 카운터 업데이트
  ((TOTAL_TESTS++))
  
  echo "$num. $type 테스트:"
  echo "   원본 리소스: $original"
  echo "   Kong 마스킹: $original → $masked"
  echo "   응답 (처음 150자): ${CLAUDE_TEXT:0:150}..."
  
  # 언마스킹 성공 여부 체크
  # 원본 리소스 ID가 응답에 있으면 언마스킹 성공
  if [[ "$CLAUDE_TEXT" == *"$original"* ]] && [[ "$CLAUDE_TEXT" != "ERROR" ]] && [[ "$CLAUDE_TEXT" != "PARSE_ERROR" ]]; then
    echo "   ✅ 언마스킹 성공: 원본 리소스 ID가 복원됨"
    ((PASSED_TESTS++))
    # 성공 시 해당 부분 하이라이트
    echo "   복원된 부분:"
    echo "$CLAUDE_TEXT" | grep -o ".\{0,50\}$original.\{0,50\}" | head -3 | sed 's/^/      /'
  else
    echo "   ❌ 언마스킹 실패: 원본 리소스 ID를 찾을 수 없음"
    ((FAILED_TESTS++))
    # 실패 시 마스킹된 ID 확인
    if [[ "$CLAUDE_TEXT" == *"$masked"* ]] || [[ "$CLAUDE_TEXT" == *"AWS_"* ]]; then
      echo "   마스킹된 ID는 있음 (언마스킹 안됨):"
      echo "$CLAUDE_TEXT" | grep -o ".\{0,50\}AWS_[A-Z0-9_]*.\{0,50\}" | head -3 | sed 's/^/      /'
    fi
  fi
  echo ""
  
  # Circuit breaker 방지를 위한 대기
  sleep 2
}

# 서비스 준비 대기
echo "서비스 준비 대기 중..."
sleep 3

# 디버그: Kong 로그 모니터링 시작
echo "Kong 로그 모니터링 시작..."
docker logs -f kong-gateway 2>&1 | grep -E "(MASKING|UNMASKING|aws_memory_mappings)" &
KONG_LOG_PID=$!

# 5개 패턴 테스트
echo ""
echo "=== 테스트 시작 ==="
test_pattern "1" "EC2 instance" "i-1234567890abcdef0" "AWS_EC2_XXX"
test_pattern "2" "VPC" "vpc-0123456789abcdef0" "AWS_VPC_XXX"
test_pattern "3" "S3 bucket" "my-production-bucket" "AWS_S3_BUCKET_XXX"
test_pattern "4" "security group" "sg-0123456789abcdef0" "AWS_SECURITY_GROUP_XXX"
test_pattern "5" "RDS instance" "prod-mysql-db" "AWS_RDS_XXX"

# Kong 로그 모니터링 중지
kill $KONG_LOG_PID 2>/dev/null

# 테스트 완료
echo "=== 테스트 완료 ==="
echo "📊 총 테스트: $TOTAL_TESTS개"
echo "✅ 성공: $PASSED_TESTS개"
echo "❌ 실패: $FAILED_TESTS개"
echo "📈 성공률: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"

if [ $PASSED_TESTS -gt 0 ]; then
  echo ""
  echo "🎉 언마스킹이 작동합니다! ($PASSED_TESTS/$TOTAL_TESTS 성공)"
else
  echo ""
  echo "⚠️ 언마스킹이 작동하지 않습니다. Kong 설정 확인이 필요합니다."
fi