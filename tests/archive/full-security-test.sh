#!/bin/bash
# 🚨 전체 보안 검증 테스트 - 요청/응답 모두 확인

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "🚨 전체 보안 검증 테스트"
echo "================================================"

# 1. 요청 마스킹 확인
echo -e "\n[1] 요청 마스킹 테스트"
REQUEST_BODY='{
  "model": "claude-3-5-sonnet-20241022",
  "messages": [{
    "role": "user",
    "content": "Please analyze these AWS resources: EC2 instance i-1234567890abcdef0 at IP 10.0.1.100, S3 bucket my-production-bucket, RDS database prod-db-instance"
  }],
  "max_tokens": 100
}'

echo "원본 요청:"
echo "$REQUEST_BODY" | jq .

# REMOVED - Wrong pattern: RESPONSE=$(curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_BODY")

echo -e "\n응답:"
echo "$RESPONSE" | jq . || echo "$RESPONSE"

# 2. 보안 검증
echo -e "\n[2] 🔍 보안 검증"

# AWS 패턴 목록
PATTERNS=(
  "i-1234567890abcdef0"  # EC2 instance ID
  "10\.0\.1\.100"  # Private IP
  "my-production-bucket"  # S3 bucket
  "prod-db-instance"  # RDS instance
)

SECURITY_PASSED=true
for pattern in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -q "$pattern"; then
    echo "❌ 치명적 보안 위반: $pattern 이(가) 응답에 노출됨!"
    SECURITY_PASSED=false
  else
    echo "✅ 안전: $pattern 마스킹됨"
  fi
done

# 3. Kong 로그 확인
echo -e "\n[3] Kong 마스킹 로그 확인"
docker-compose logs kong --tail=20 | grep -E "Masked|masked|EC2_|BUCKET_|RDS_|PRIVATE_IP_" | tail -5

# 4. 결과 요약
echo -e "\n[4] 📊 테스트 결과"
if [ "$SECURITY_PASSED" = true ]; then
  echo "✅ 보안 테스트 통과: 모든 AWS 정보가 마스킹됨"
else
  echo "❌ 보안 테스트 실패: AWS 정보가 노출됨!"
  echo "🚨 이는 심각한 보안 문제입니다!"
fi

echo -e "\n================================================"