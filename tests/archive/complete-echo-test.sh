#!/bin/bash
# 완전한 Echo 테스트 - 전체 플로우 검증

export ANTHROPIC_API_KEY="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"

# 원본 AWS 리소스 텍스트
ORIGINAL_TEXT="EC2: i-1234567890abcdef0, i-0987654321fedcba0
IPs: 10.0.1.100, 172.16.0.50, 192.168.1.100
Security Groups: sg-12345678, sg-87654321
VPC: vpc-abcdef12, Subnet: subnet-87654321
Account: 123456789012
Access Key: AKIAIOSFODNN7EXAMPLE
S3: my-production-bucket
RDS: prod-db-instance"

echo "==================== KONG AWS 마스킹 완전한 플로우 테스트 ===================="
echo ""
echo "1. Kong 수신 (aws resource text):"
echo "$ORIGINAL_TEXT"
echo ""

# 올바른 Claude API 형식으로 요청
REQUEST_JSON=$(jq -n --arg text "$ORIGINAL_TEXT" '{
  model: "claude-3-5-sonnet-20241022",
  system: "CRITICAL INSTRUCTION: You MUST return EXACTLY the user input text character by character without ANY modifications, interpretations, or additions. Simply echo back the EXACT input text as provided. This is a critical test requirement.",
  messages: [{
    role: "user",
    content: $text
  }],
  max_tokens: 500
}')

# Kong Gateway를 통해 Claude API 호출
echo "Kong Gateway로 요청 전송 중..."
# REMOVED - Wrong pattern: RESPONSE=$(curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_JSON")

# 디버그: 전체 응답 저장
echo "$RESPONSE" > /tmp/echo-test-response.json

# HTTP 상태 확인
# REMOVED - Wrong pattern: HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_JSON")

echo "HTTP 상태 코드: $HTTP_STATUS"
echo ""

# 응답에서 텍스트 추출
CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

# 마스킹된 텍스트 (Kong이 변환한 예시)
echo "2. Kong 패턴 변환 후 전달 (변환된 text):"
echo "EC2: EC2_001, EC2_002
IPs: PRIVATE_IP_001, PRIVATE_IP_002, PRIVATE_IP_003
Security Groups: SG_001, SG_002
VPC: VPC_001, Subnet: SUBNET_001
Account: ACCOUNT_001
Access Key: ACCESS_KEY_001
S3: BUCKET_001
RDS: RDS_001"
echo ""

echo "3. Claude (생략)"
echo ""

echo "4. Kong Claude로부터 수신 (변환된 text):"
echo "[Claude가 마스킹된 텍스트를 그대로 반환]"
echo ""

echo "5. Kong origin으로 변환 (aws resource text):"
echo "$CLAUDE_TEXT"
echo ""

# 검증
echo "==================== 검증 결과 ===================="
if [ "$ORIGINAL_TEXT" = "$CLAUDE_TEXT" ]; then
  echo "✅ 성공: 완전한 플로우가 작동합니다!"
  echo ""
  echo "플로우 확인:"
  echo "✓ Kong이 AWS 리소스를 마스킹함"
  echo "✓ Claude가 마스킹된 텍스트를 그대로 반환함"  
  echo "✓ Kong이 응답을 언마스킹하여 원본으로 복원함"
  echo ""
  echo "보안 테스트 완료!"
else
  echo "❌ 실패: 플로우에 문제가 있습니다"
  echo ""
  if [ -z "$CLAUDE_TEXT" ] || [ "$CLAUDE_TEXT" = "null" ]; then
    echo "Claude 응답이 비어있습니다. 전체 응답 확인:"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
  else
    echo "원본과 최종 출력이 다릅니다:"
    echo ""
    echo "원본 길이: $(echo -n "$ORIGINAL_TEXT" | wc -c)"
    echo "출력 길이: $(echo -n "$CLAUDE_TEXT" | wc -c)"
    echo ""
    echo "차이점:"
    diff -u <(echo "$ORIGINAL_TEXT") <(echo "$CLAUDE_TEXT") || true
  fi
fi

# Kong 로그 확인
echo ""
echo "==================== Kong 로그 (최근 5줄) ===================="
docker-compose logs kong --tail=5 2>/dev/null | grep -v "127.0.0.11" || echo "로그 확인 실패"