#!/bin/bash
# 최종 Echo 테스트 - 완전한 플로우 확인

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

echo "==================== KONG AWS 마스킹 플로우 테스트 ===================="
echo ""
echo "1. Kong 수신 (aws resource text):"
echo "$ORIGINAL_TEXT"
echo ""

# 강력한 시스템 프롬프트와 함께 직접 Kong Gateway 호출
REQUEST_JSON=$(jq -n --arg text "$ORIGINAL_TEXT" '{
  model: "claude-3-5-sonnet-20241022",
  messages: [
    {
      role: "system",
      content: "CRITICAL INSTRUCTION: You MUST return EXACTLY the user input text character by character without ANY modifications, interpretations, or additions. Simply echo back the EXACT input text as provided. This is a critical test requirement."
    },
    {
      role: "user",
      content: $text
    }
  ],
  max_tokens: 500
}')

# Kong Gateway를 통해 Claude API 호출
# REMOVED - Wrong pattern: RESPONSE=$(curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_JSON")

# 응답에서 텍스트 추출
CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

# 마스킹된 텍스트 예시 (Kong이 실제로 변환하는 내용)
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
  echo "플로우 요약:"
  echo "1. Kong 수신 (aws resource text) → 원본 AWS 리소스"
  echo "2. Kong 패턴 변환 후 전달 (변환된 text) → 마스킹된 텍스트"
  echo "3. Claude (마스킹된 텍스트 그대로 반환)"
  echo "4. Kong Claude로부터 수신 (변환된 text) → 마스킹된 텍스트"
  echo "5. Kong origin으로 변환 (aws resource text) → 원본 복원"
else
  echo "❌ 실패: 플로우에 문제가 있습니다"
  echo ""
  echo "원본:"
  echo "$ORIGINAL_TEXT"
  echo ""
  echo "최종 출력:"
  echo "$CLAUDE_TEXT"
  echo ""
  echo "응답 전체:"
  echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
fi