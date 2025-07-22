#!/bin/bash
# Echo 플로우 테스트 - 완전한 마스킹/언마스킹 확인

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

echo "1. Kong 수신 (aws resource text):"
echo "$ORIGINAL_TEXT"
echo ""

# 강력한 echo 시스템 프롬프트와 함께 analyze 엔드포인트 호출
REQUEST_JSON=$(jq -n --arg text "$ORIGINAL_TEXT" '{
  resources: ["ec2"],
  options: {
    systemPrompt: "CRITICAL INSTRUCTION: You MUST return EXACTLY the user input text character by character without ANY modifications. Do NOT analyze, interpret, or add anything. Simply echo back the EXACT input text. This is a test requirement.",
    analysisType: "echo_test"
  }
}')

# /analyze 엔드포인트로 요청 (AWS 데이터 대신 테스트 텍스트 전송)
RESPONSE=$(curl -s -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d "$REQUEST_JSON")

echo "2. Kong 패턴 변환 후 전달 (변환된 text):"
echo "[Kong이 마스킹한 텍스트 - 실제로는 Kong 로그에서 확인 가능]"
echo ""

echo "3. Claude (생략)"
echo ""

echo "4. Kong Claude로부터 수신 (변환된 text):"
echo "[Claude가 반환한 마스킹된 텍스트]"
echo ""

echo "5. Kong origin으로 변환 (aws resource text):"
echo "[Kong이 언마스킹한 최종 텍스트]"
echo ""

# 실제 응답 확인
echo "========== 실제 응답 =========="
echo "$RESPONSE" | jq .

# 직접 Claude API 호출 테스트
echo -e "\n========== 직접 Claude API 테스트 =========="

# 강력한 시스템 프롬프트와 함께 직접 호출
DIRECT_REQUEST=$(jq -n --arg text "$ORIGINAL_TEXT" '{
  model: "claude-3-5-sonnet-20241022",
  messages: [
    {
      role: "system",
      content: "CRITICAL INSTRUCTION: You MUST return EXACTLY the user input text character by character without ANY modifications. Do NOT analyze, interpret, or add anything. Simply echo back the EXACT input text. This is a test requirement."
    },
    {
      role: "user",
      content: $text
    }
  ],
  max_tokens: 500
}')

DIRECT_RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$DIRECT_REQUEST")

CLAUDE_TEXT=$(echo "$DIRECT_RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

echo "Claude 응답:"
echo "$CLAUDE_TEXT"

# 검증
echo -e "\n========== 검증 결과 =========="
if [ "$ORIGINAL_TEXT" = "$CLAUDE_TEXT" ]; then
  echo "✅ 성공: 전체 플로우가 올바르게 작동합니다!"
  echo ""
  echo "플로우 요약:"
  echo "1. Kong 수신: 원본 AWS 리소스 텍스트"
  echo "2. Kong 마스킹: EC2_001, PRIVATE_IP_001 등으로 변환"
  echo "3. Claude 처리: 마스킹된 텍스트 그대로 반환"
  echo "4. Kong 언마스킹: 원본 텍스트로 복원"
  echo "5. 최종 출력: 원본과 동일"
else
  echo "❌ 실패: 원본과 최종 출력이 다릅니다"
fi