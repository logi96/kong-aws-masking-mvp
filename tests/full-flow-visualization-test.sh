#!/bin/bash
# 전체 플로우 시각화 테스트 - 요청 → 패턴 변환 → 응답 → origin으로 변환 → 수신

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "🔄 AWS 패턴 전체 변환 플로우 시각화"
echo "================================================"

# 컬러 설정
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 테스트 데이터 - 다양한 AWS 리소스 포함
TEST_MESSAGE="AWS 인프라 분석:
1. EC2: i-1234567890abcdef0 (10.0.1.100)
2. Security Group: sg-12345678
3. VPC: vpc-abcdef12, Subnet: subnet-87654321
4. Account: 123456789012
5. Access Key: AKIAIOSFODNN7EXAMPLE
6. RDS: prod-db-instance
7. S3: my-production-bucket
8. Lambda: arn:aws:lambda:us-east-1:123456789012:function:myFunction
9. IAM Role: arn:aws:iam::123456789012:role/MyTestRole
10. Private IPs: 172.16.0.50, 192.168.1.100"

# 테스트 케이스
declare -a TEST_CASES=(
  "EC2 Instance|i-1234567890abcdef0|EC2_XXX"
  "Private IP 10.x|10.0.1.100|PRIVATE_IP_XXX"
  "Security Group|sg-12345678|SG_XXX"
  "VPC|vpc-abcdef12|VPC_XXX"
  "Subnet|subnet-87654321|SUBNET_XXX"
  "Account ID|123456789012|ACCOUNT_XXX"
  "Access Key|AKIAIOSFODNN7EXAMPLE|ACCESS_KEY_XXX"
  "RDS Instance|prod-db-instance|RDS_XXX"
  "S3 Bucket|my-production-bucket|BUCKET_XXX"
  "Lambda ARN|arn:aws:lambda:us-east-1:123456789012:function:myFunction|LAMBDA_ARN_XXX"
  "IAM Role ARN|arn:aws:iam::123456789012:role/MyTestRole|IAM_ROLE_XXX"
  "Private IP 172.x|172.16.0.50|PRIVATE_IP_XXX"
  "Private IP 192.x|192.168.1.100|PRIVATE_IP_XXX"
)

echo -e "\n${CYAN}=== 1. 원본 요청 (Original Request) ===${NC}"
echo "$TEST_MESSAGE"

# API 요청 데이터
REQUEST_DATA="{
  \"model\": \"claude-3-5-sonnet-20241022\",
  \"messages\": [{
    \"role\": \"user\",
    \"content\": \"$TEST_MESSAGE\"
  }],
  \"max_tokens\": 500
}"

echo -e "\n${YELLOW}=== 2. Kong으로 전송되는 요청 ===${NC}"
echo "$REQUEST_DATA" | jq -r '.messages[0].content' | head -5
echo "..."

# 임시 파일로 요청 저장
echo "$REQUEST_DATA" > /tmp/request.json

echo -e "\n${PURPLE}=== 3. Kong에서 마스킹 처리 ===${NC}"
echo "다음 패턴들이 마스킹됩니다:"
for test_case in "${TEST_CASES[@]}"; do
  IFS='|' read -r description original expected <<< "$test_case"
  echo -e "  ${original} → ${expected/XXX/???}"
done

# 실제 API 호출
echo -e "\n${BLUE}=== 4. Claude API 호출 중... ===${NC}"
RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "@/tmp/request.json")

# 응답 상태 확인
if [ $? -eq 0 ]; then
  echo "✅ API 호출 성공"
else
  echo "❌ API 호출 실패"
fi

echo -e "\n${GREEN}=== 5. Claude API 응답 (마스킹된 상태) ===${NC}"
echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null | head -10 || echo "$RESPONSE" | head -c 500
echo "..."

echo -e "\n${CYAN}=== 6. 마스킹 검증 ===${NC}"
echo "각 패턴의 마스킹 상태:"

SUCCESS_COUNT=0
FAIL_COUNT=0

for test_case in "${TEST_CASES[@]}"; do
  IFS='|' read -r description original expected <<< "$test_case"
  
  if echo "$RESPONSE" | grep -q "$original"; then
    echo -e "  ${RED}❌ $description: $original (노출됨!)${NC}"
    ((FAIL_COUNT++))
  else
    echo -e "  ${GREEN}✅ $description: $original → 마스킹됨${NC}"
    ((SUCCESS_COUNT++))
  fi
done

echo -e "\n${YELLOW}=== 7. 변환 매핑 예시 ===${NC}"
echo "Kong 내부 매핑 테이블 (예시):"
echo "┌─────────────────────────┬──────────────┐"
echo "│ Original                │ Masked       │"
echo "├─────────────────────────┼──────────────┤"
echo "│ i-1234567890abcdef0     │ EC2_001      │"
echo "│ 10.0.1.100              │ PRIVATE_IP_001│"
echo "│ sg-12345678             │ SG_001       │"
echo "│ 123456789012            │ ACCOUNT_001  │"
echo "│ ...                     │ ...          │"
echo "└─────────────────────────┴──────────────┘"

echo -e "\n${PURPLE}=== 8. 역변환 프로세스 (현재 비활성화) ===${NC}"
echo "보안을 위해 body_filter에서 언마스킹이 비활성화되어 있습니다."
echo "클라이언트는 마스킹된 응답을 받습니다."

echo -e "\n${CYAN}=== 9. 최종 수신 데이터 ===${NC}"
echo "클라이언트가 받는 최종 응답:"
echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null | head -5 || echo "$RESPONSE" | head -c 200
echo "..."

echo -e "\n${GREEN}=== 10. 테스트 결과 요약 ===${NC}"
echo "┌──────────────────────────────────────┐"
echo "│ 전체 플로우 테스트 결과              │"
echo "├──────────────────────────────────────┤"
echo "│ 총 패턴: ${#TEST_CASES[@]}개                        │"
echo "│ 마스킹 성공: $SUCCESS_COUNT개                     │"
echo "│ 마스킹 실패: $FAIL_COUNT개                      │"
echo "│ 성공률: $((SUCCESS_COUNT * 100 / ${#TEST_CASES[@]}))%                          │"
echo "└──────────────────────────────────────┘"

# 임시 파일 삭제
rm -f /tmp/request.json

echo -e "\n================================================"
echo "✅ 전체 플로우 시각화 테스트 완료"
echo "================================================"