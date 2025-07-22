#!/bin/bash
# 🚨 CRITICAL SECURITY TEST - AWS 마스킹 검증
# 보안이 최우선: AWS 정보가 외부로 노출되면 절대 안됨

echo "================================================"
echo "🚨 AWS 마스킹 보안 테스트 시작"
echo "================================================"

# 1. 시스템 상태 확인
echo -e "\n[1] 시스템 상태 확인"
curl -s http://localhost:8000/health | jq . || echo "Kong health check failed"

# 2. 실제 AWS 데이터로 마스킹 테스트
echo -e "\n[2] AWS 마스킹 테스트 - 민감한 데이터 포함"

# 테스트 데이터: 실제 AWS 패턴
TEST_DATA='{
  "resources": ["ec2"],
  "options": {
    "analysisType": "security_only",
    "region": "us-east-1"
  }
}'

# Kong Gateway를 통해 analyze 요청 (마스킹이 적용되어야 함)
echo -e "\n요청 데이터:"
echo "$TEST_DATA" | jq .

echo -e "\n응답 (Kong을 통해 마스킹됨):"
RESPONSE=$(curl -s -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d "$TEST_DATA")

echo "$RESPONSE" | jq . || echo "$RESPONSE"

# 3. 마스킹 검증
echo -e "\n[3] 🔍 보안 검증 - 민감한 패턴 검색"

# AWS 패턴 검색
PATTERNS=(
  "i-[0-9a-f]{17}"  # EC2 instance ID
  "10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"  # Private IP
  "arn:aws"  # AWS ARN
  "ami-[0-9a-f]{8}"  # AMI ID
  "sg-[0-9a-f]{8}"  # Security Group
  "subnet-[0-9a-f]{8}"  # Subnet ID
)

FOUND_SENSITIVE=0
for pattern in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -qE "$pattern"; then
    echo "❌ 위험: 민감한 패턴 발견: $pattern"
    FOUND_SENSITIVE=1
  else
    echo "✅ 안전: $pattern 마스킹됨"
  fi
done

if [ $FOUND_SENSITIVE -eq 1 ]; then
  echo -e "\n🚨 치명적 보안 문제: AWS 정보가 마스킹되지 않음!"
  exit 1
else
  echo -e "\n✅ 보안 검증 통과: 모든 AWS 정보가 마스킹됨"
fi

# 4. 직접 Backend 호출 테스트 (마스킹 없음 - 비교용)
echo -e "\n[4] 직접 Backend 호출 (마스킹 없음 - 위험)"
DIRECT_RESPONSE=$(curl -s -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d "$TEST_DATA" 2>&1 || echo "Direct backend call failed")

echo "응답 길이 비교:"
echo "- Kong 경유 (마스킹): $(echo "$RESPONSE" | wc -c) bytes"
echo "- 직접 호출 (노출): $(echo "$DIRECT_RESPONSE" | wc -c) bytes"

echo -e "\n================================================"
echo "보안 테스트 완료"
echo "================================================"