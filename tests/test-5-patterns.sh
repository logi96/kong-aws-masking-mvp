#!/bin/bash
# 5개 AWS 리소스 패턴 테스트 - Circuit Breaker 방지를 위한 제한된 테스트
# 개선된 프롬프트로 Claude가 리소스 ID를 명시적으로 반복하는지 검증
#
# Backend API 사용으로 인해 직접적인 API 키 필요 없음
# Backend API가 Kong Gateway를 통해 Claude API에 접근

echo "=== 5개 AWS 리소스 패턴 테스트 (개선된 프롬프트) ==="
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
  
  # Backend API로 요청 전송 (Kong Gateway가 outbound traffic을 intercept하여 마스킹됨)
  RESPONSE=$(curl -s -X POST http://localhost:3000/analyze \
    -H "Content-Type: application/json" \
    -d "{
      \"contextText\": \"IMPORTANT: First, please repeat this exact AWS resource ID: $original\\n\\nAfter repeating the ID above, provide a brief security analysis of this AWS $type resource.\",
      \"options\": {
        \"analysisType\": \"security_only\",
        \"maxTokens\": 200
      }
    }")
  
  # 응답에서 텍스트 추출 (Backend API → Claude API 응답 형식)
  CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.analysis.content[0].text // "ERROR"' 2>/dev/null || echo "PARSE_ERROR")
  
  # 전역 카운터 업데이트
  ((TOTAL_TESTS++))
  
  echo "$num. $type:"
  echo "   원본 AWS 리소스: $original"
  echo "   기대 마스킹: $masked"
  echo "   Claude 응답 (처음 100자): ${CLAUDE_TEXT:0:100}..."
  
  # 성공 여부 체크
  if [[ "$CLAUDE_TEXT" == *"$original"* ]] && [[ "$CLAUDE_TEXT" != "ERROR" ]] && [[ "$CLAUDE_TEXT" != "PARSE_ERROR" ]]; then
    echo "   ✅ 성공: 원본 리소스가 응답에 포함됨"
    ((PASSED_TESTS++))
  else
    echo "   ❌ 실패: 원본 리소스가 응답에 없음"
    ((FAILED_TESTS++))
    # 실패 시 전체 응답 확인
    echo "   전체 응답:"
    echo "$CLAUDE_TEXT" | sed 's/^/      /'
  fi
  echo ""
  
  # Circuit breaker 방지를 위한 대기 시간
  sleep 2
}

# 서비스 준비 대기
echo "서비스 준비 대기 중..."
sleep 5

# 5개 패턴만 테스트
echo "=== 제한된 패턴 테스트 시작 ==="
test_pattern "1" "EC2 Instance" "i-1234567890abcdef0" "EC2_001"
test_pattern "2" "VPC" "vpc-0123456789abcdef0" "VPC_001"
test_pattern "3" "S3 Bucket" "my-production-bucket" "BUCKET_001"
test_pattern "4" "Private IP" "10.0.1.100" "PRIVATE_IP_001"
test_pattern "5" "IAM Role ARN" "arn:aws:iam::123456789012:role/MyRole" "IAM_ROLE_001"

# 테스트 완료
echo "=== 테스트 완료 ==="
echo "📊 총 테스트: $TOTAL_TESTS개"
echo "✅ 성공: $PASSED_TESTS개"
echo "❌ 실패: $FAILED_TESTS개"
echo "📈 성공률: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
  echo ""
  echo "🎉 모든 테스트 성공! 개선된 프롬프트가 작동합니다."
  echo "전체 50개 패턴 테스트를 실행할 준비가 되었습니다."
else
  echo ""
  echo "⚠️ 일부 테스트 실패. 프롬프트 개선이 더 필요할 수 있습니다."
fi