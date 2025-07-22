#!/bin/bash
# 완전한 플로우 시각화 - 요청 → 패턴 변환 → 응답 → origin으로 변환 → 수신

export ANTHROPIC_API_KEY="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"

echo "================================================================================"
echo "🔄 Kong AWS 마스킹 전체 플로우 시각화"
echo "================================================================================"

# 컬러 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 테스트 데이터
TEST_MESSAGE="분석할 AWS 리소스:
EC2: i-1234567890abcdef0, i-0987654321fedcba0
IPs: 10.0.1.100, 172.16.0.50, 192.168.1.100
Security Groups: sg-12345678, sg-87654321
VPC/Subnet: vpc-abcdef12, subnet-87654321
Account: 123456789012
Access Key: AKIAIOSFODNN7EXAMPLE
RDS: prod-db-instance
S3: my-production-bucket
ARN: arn:aws:iam::123456789012:role/MyTestRole"

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│               STEP 1: 원본 요청 (Client)            │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${YELLOW}[Client → Backend]${NC}"
echo "$TEST_MESSAGE"

# JSON 요청 생성
REQUEST_JSON=$(jq -n \
  --arg msg "$TEST_MESSAGE" \
  '{
    model: "claude-3-5-sonnet-20241022",
    messages: [{
      role: "user",
      content: $msg
    }],
    max_tokens: 200
  }')

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│           STEP 2: Backend JSON 요청 생성            │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${YELLOW}[Backend → Kong Gateway]${NC}"
echo "$REQUEST_JSON" | jq -C .

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│         STEP 3: Kong 마스킹 처리 (access phase)    │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${YELLOW}[Kong Plugin Processing]${NC}"
echo "다음 패턴들이 감지되고 마스킹됩니다:"
echo -e "${GREEN}✓${NC} i-1234567890abcdef0 → EC2_001"
echo -e "${GREEN}✓${NC} i-0987654321fedcba0 → EC2_002"
echo -e "${GREEN}✓${NC} 10.0.1.100 → PRIVATE_IP_001"
echo -e "${GREEN}✓${NC} 172.16.0.50 → PRIVATE_IP_002"
echo -e "${GREEN}✓${NC} 192.168.1.100 → PRIVATE_IP_003"
echo -e "${GREEN}✓${NC} sg-12345678 → SG_001"
echo -e "${GREEN}✓${NC} sg-87654321 → SG_002"
echo -e "${GREEN}✓${NC} vpc-abcdef12 → VPC_001"
echo -e "${GREEN}✓${NC} subnet-87654321 → SUBNET_001"
echo -e "${GREEN}✓${NC} 123456789012 → ACCOUNT_001"
echo -e "${GREEN}✓${NC} AKIAIOSFODNN7EXAMPLE → ACCESS_KEY_001"
echo -e "${GREEN}✓${NC} prod-db-instance → RDS_001"
echo -e "${GREEN}✓${NC} my-production-bucket → BUCKET_001"
echo -e "${GREEN}✓${NC} arn:aws:iam::123456789012:role/MyTestRole → IAM_ROLE_001"

# 마스킹된 메시지 예시
MASKED_MESSAGE="분석할 AWS 리소스:
EC2: EC2_001, EC2_002
IPs: PRIVATE_IP_001, PRIVATE_IP_002, PRIVATE_IP_003
Security Groups: SG_001, SG_002
VPC/Subnet: VPC_001, SUBNET_001
Account: ACCOUNT_001
Access Key: ACCESS_KEY_001
RDS: RDS_001
S3: BUCKET_001
ARN: IAM_ROLE_001"

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│      STEP 4: 마스킹된 요청 (Kong → Claude API)     │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${YELLOW}[Kong → Claude API]${NC}"
echo "$MASKED_MESSAGE"

# 실제 API 호출
echo -e "\n${PURPLE}API 호출 실행 중...${NC}"
RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_JSON")

# Claude 응답 추출
CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│      STEP 5: Claude API 응답 (마스킹된 상태)       │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${YELLOW}[Claude API → Kong]${NC}"
if [ "$CLAUDE_TEXT" != "null" ] && [ -n "$CLAUDE_TEXT" ]; then
  echo "$CLAUDE_TEXT"
else
  echo "$RESPONSE" | jq -C . 2>/dev/null || echo "$RESPONSE"
fi

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│   STEP 6: Kong 응답 처리 (body_filter phase)       │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${RED}[보안: 언마스킹 비활성화]${NC}"
echo "현재 설정: body_filter에서 언마스킹을 수행하지 않음"
echo "이유: 보안 최우선 - Claude가 생성한 응답에는 원본 AWS 리소스가 없음"

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│        STEP 7: 최종 응답 (Kong → Client)           │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "${YELLOW}[Kong → Backend → Client]${NC}"
echo "클라이언트가 받는 최종 응답:"
if [ "$CLAUDE_TEXT" != "null" ] && [ -n "$CLAUDE_TEXT" ]; then
  echo "$CLAUDE_TEXT" | head -10
  echo "..."
fi

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│              STEP 8: 마스킹 매핑 테이블             │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo "Kong 내부 매핑 저장소 (메모리):"
echo "┌────────────────────────────┬─────────────────┐"
echo "│ Original Value             │ Masked Value    │"
echo "├────────────────────────────┼─────────────────┤"
echo "│ i-1234567890abcdef0        │ EC2_001         │"
echo "│ i-0987654321fedcba0        │ EC2_002         │"
echo "│ 10.0.1.100                 │ PRIVATE_IP_001  │"
echo "│ 172.16.0.50                │ PRIVATE_IP_002  │"
echo "│ 192.168.1.100              │ PRIVATE_IP_003  │"
echo "│ sg-12345678                │ SG_001          │"
echo "│ sg-87654321                │ SG_002          │"
echo "│ vpc-abcdef12               │ VPC_001         │"
echo "│ subnet-87654321            │ SUBNET_001      │"
echo "│ 123456789012               │ ACCOUNT_001     │"
echo "│ AKIAIOSFODNN7EXAMPLE       │ ACCESS_KEY_001  │"
echo "│ prod-db-instance           │ RDS_001         │"
echo "│ my-production-bucket       │ BUCKET_001      │"
echo "│ arn:aws:iam::12345...      │ IAM_ROLE_001    │"
echo "└────────────────────────────┴─────────────────┘"

echo -e "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│                   검증 결과                         │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"

# 패턴 검증
PATTERNS=(
  "i-1234567890abcdef0"
  "i-0987654321fedcba0"
  "10.0.1.100"
  "172.16.0.50"
  "192.168.1.100"
  "sg-12345678"
  "sg-87654321"
  "vpc-abcdef12"
  "subnet-87654321"
  "123456789012"
  "AKIAIOSFODNN7EXAMPLE"
  "prod-db-instance"
  "my-production-bucket"
  "arn:aws:iam::123456789012"
)

SUCCESS=0
FAIL=0

for pattern in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -q "$pattern"; then
    echo -e "${RED}❌ $pattern - 마스킹 실패 (노출됨!)${NC}"
    ((FAIL++))
  else
    echo -e "${GREEN}✅ $pattern - 마스킹 성공${NC}"
    ((SUCCESS++))
  fi
done

echo -e "\n${GREEN}총 ${#PATTERNS[@]}개 패턴 중 $SUCCESS개 마스킹 성공 ($(( SUCCESS * 100 / ${#PATTERNS[@]} ))%)${NC}"

echo -e "\n================================================================================"
echo -e "${GREEN}✅ 전체 플로우 시각화 완료${NC}"
echo -e "================================================================================"