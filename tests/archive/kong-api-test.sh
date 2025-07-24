#!/bin/bash
# kong-api-test.sh
# Phase 4 - 1단계: 실제 Kong API를 통한 마스킹 테스트
# 보안 최우선: 모든 AWS 리소스가 안전하게 마스킹되는지 검증

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=========================================="
echo "🚀 Phase 4 - Kong API 통합 테스트"
echo "=========================================="
echo "시작 시간: $(date)"
echo ""

# 작업 디렉토리 설정
cd /Users/tw.kim/Documents/AGA/test/Kong

# Kong 상태 확인
echo -e "${BLUE}[1/5] Kong 상태 확인${NC}"
echo "=========================================="

# Kong이 실행 중인지 확인
if curl -s http://localhost:8001/status > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Kong Admin API 응답${NC}"
    KONG_VERSION=$(curl -s http://localhost:8001 | jq -r '.version')
    echo "Kong 버전: $KONG_VERSION"
else
    echo -e "${RED}✗ Kong Admin API 응답 없음${NC}"
    echo "Kong을 먼저 실행하세요: docker-compose up -d"
    exit 1
fi

# Backend API 확인
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Backend API 응답${NC}"
else
    echo -e "${YELLOW}⚠️  Backend API 응답 없음${NC}"
fi

# 테스트 데이터 준비
echo -e "\n${BLUE}[2/5] 테스트 데이터 준비${NC}"
echo "=========================================="

# 복합 AWS 리소스가 포함된 테스트 요청
cat > test-claude-request.json << EOF
{
  "model": "claude-3-sonnet-20240229",
  "max_tokens": 1024,
  "system": "You are analyzing AWS infrastructure for account 123456789012",
  "messages": [
    {
      "role": "user",
      "content": "Please analyze these AWS resources:\n\nEC2 Instances:\n- i-1234567890abcdef0 (10.0.1.50)\n- i-0987654321fedcba0 (10.0.2.100)\n\nVPC Configuration:\n- VPC: vpc-abcdef0123456789\n- Subnets: subnet-12345678, subnet-87654321\n- Security Groups: sg-11111111, sg-22222222\n\nRDS Database:\n- arn:aws:rds:us-east-1:123456789012:cluster:prod-mysql-cluster\n\nLambda Functions:\n- arn:aws:lambda:us-east-1:123456789012:function:dataProcessor\n- arn:aws:lambda:us-east-1:123456789012:function:apiHandler\n\nKMS Keys (CRITICAL):\n- arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012\n- arn:aws:kms:us-east-1:123456789012:alias/prod-encryption-key\n\nSecrets Manager (CRITICAL):\n- arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db/password-AbCdEf\n\nS3 Buckets:\n- s3://my-app-data-bucket-2024\n- s3://backup-bucket-prod\n\nDynamoDB Table:\n- arn:aws:dynamodb:us-east-1:123456789012:table/UserSessions\n\nAPI Gateway:\n- https://abc123def4.execute-api.us-east-1.amazonaws.com/prod\n\nECS Services:\n- arn:aws:ecs:us-east-1:123456789012:service/prod-cluster/web-service\n- arn:aws:ecs:us-east-1:123456789012:task/prod-cluster/1234567890abcdef\n\nIAM Credentials (CRITICAL - TEST ONLY):\n- Access Key: AKIAIOSFODNN7EXAMPLE\n- Secret: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    },
    {
      "role": "assistant",
      "content": "I'll analyze these AWS resources for account 123456789012. Let me examine each service category..."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Also check the EKS cluster arn:aws:eks:us-west-2:123456789012:cluster/prod-k8s-cluster"
        }
      ]
    }
  ],
  "tools": [
    {
      "name": "aws_analyzer",
      "description": "Analyzes AWS resources in account 123456789012 including S3 bucket my-logs-bucket"
    }
  ]
}
EOF

echo -e "${GREEN}✓ 테스트 데이터 생성 완료${NC}"
echo "  - 포함된 AWS 리소스 타입: 13개"
echo "  - Critical 패턴: 3개 (IAM, KMS, Secrets)"

# Kong을 통해 요청 전송
echo -e "\n${BLUE}[3/5] Kong Gateway로 요청 전송${NC}"
echo "=========================================="

# Claude API 엔드포인트로 요청 (Kong을 통해)
# REMOVED - Wrong pattern: RESPONSE=$(curl -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY:-test-key}" \
  -H "anthropic-version: 2023-06-01" \
  -d @test-claude-request.json \
  -w "\n{\"http_code\": %{http_code}}" \
  -s -o response.json)

HTTP_CODE=$(echo "$RESPONSE" | tail -1 | jq -r '.http_code')

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ 요청 성공 (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${RED}✗ 요청 실패 (HTTP $HTTP_CODE)${NC}"
    echo "응답 내용:"
    cat response.json
    exit 1
fi

# 마스킹 검증
echo -e "\n${BLUE}[4/5] 마스킹 검증${NC}"
echo "=========================================="

# 민감한 데이터가 마스킹되었는지 확인
DETECTED_PATTERNS=()
UNMASKED_PATTERNS=()

# 각 패턴 검사
patterns=(
    "123456789012:AWS 계정 ID"
    "i-[0-9a-f]{8,17}:EC2 인스턴스 ID"
    "vpc-[0-9a-f]{8,17}:VPC ID"
    "subnet-[0-9a-f]{8,17}:서브넷 ID"
    "sg-[0-9a-f]{8,17}:보안 그룹 ID"
    "10\\.0\\.[0-9]+\\.[0-9]+:프라이빗 IP"
    "AKIA[A-Z0-9]{16}:IAM Access Key"
    "[A-Za-z0-9/+=]{40}:IAM Secret Key"
    "my-app-data-bucket:S3 버킷 이름"
    "prod-mysql-cluster:RDS 클러스터"
    "dataProcessor:Lambda 함수"
    "12345678-1234-1234-1234-123456789012:KMS 키 ID"
    "prod/db/password:Secrets Manager"
    "UserSessions:DynamoDB 테이블"
    "abc123def4:API Gateway ID"
    "prod-k8s-cluster:EKS 클러스터"
)

for pattern_info in "${patterns[@]}"; do
    pattern="${pattern_info%%:*}"
    description="${pattern_info#*:}"
    
    if grep -qE "$pattern" response.json; then
        UNMASKED_PATTERNS+=("$description")
        echo -e "${RED}✗ $description - 노출됨!${NC}"
    else
        echo -e "${GREEN}✓ $description - 마스킹됨${NC}"
    fi
done

# 마스킹된 패턴 확인
masked_patterns=(
    "ACCOUNT_[0-9]+:AWS 계정 마스킹"
    "EC2_[0-9]+:EC2 인스턴스 마스킹"
    "VPC_[0-9]+:VPC 마스킹"
    "SUBNET_[0-9]+:서브넷 마스킹"
    "SG_[0-9]+:보안 그룹 마스킹"
    "PRIVATE_IP_[0-9]+:IP 마스킹"
    "ACCESS_KEY_[0-9]+:Access Key 마스킹"
    "SECRET_KEY_[0-9]+:Secret Key 마스킹"
    "BUCKET_[0-9]+:S3 버킷 마스킹"
    "RDS_[0-9]+:RDS 마스킹"
    "LAMBDA_[0-9]+:Lambda 마스킹"
    "KMS_KEY_[0-9]+:KMS 키 마스킹"
    "SECRET_[0-9]+:Secrets 마스킹"
    "DYNAMODB_TABLE_[0-9]+:DynamoDB 마스킹"
    "APIGW_[0-9]+:API Gateway 마스킹"
    "EKS_CLUSTER_[0-9]+:EKS 마스킹"
)

echo -e "\n마스킹된 패턴 확인:"
for pattern_info in "${masked_patterns[@]}"; do
    pattern="${pattern_info%%:*}"
    description="${pattern_info#*:}"
    
    if grep -qE "$pattern" response.json; then
        DETECTED_PATTERNS+=("$description")
        echo -e "${GREEN}✓ $description${NC}"
    fi
done

# 결과 요약
echo -e "\n${BLUE}[5/5] 테스트 결과${NC}"
echo "=========================================="

echo "탐지된 마스킹 패턴: ${#DETECTED_PATTERNS[@]}개"
echo "노출된 패턴: ${#UNMASKED_PATTERNS[@]}개"

# Critical 패턴 특별 검사
CRITICAL_EXPOSED=0
for pattern in "${UNMASKED_PATTERNS[@]}"; do
    if [[ "$pattern" == *"IAM"* ]] || [[ "$pattern" == *"KMS"* ]] || [[ "$pattern" == *"Secrets"* ]]; then
        echo -e "${RED}⚠️  CRITICAL: $pattern 노출!${NC}"
        CRITICAL_EXPOSED=$((CRITICAL_EXPOSED + 1))
    fi
done

# 보고서 생성
echo -e "\n📝 테스트 보고서 생성"
cat > kong-api-test-report.md << EOF
# Kong API 통합 테스트 보고서

**테스트 시간**: $(date)
**Kong 버전**: ${KONG_VERSION:-unknown}
**HTTP 상태**: $HTTP_CODE

## 테스트 결과

### 마스킹 통계
- 탐지된 마스킹 패턴: ${#DETECTED_PATTERNS[@]}개
- 노출된 패턴: ${#UNMASKED_PATTERNS[@]}개
- Critical 패턴 노출: $CRITICAL_EXPOSED개

### 보안 상태
$(if [ $CRITICAL_EXPOSED -eq 0 ] && [ ${#UNMASKED_PATTERNS[@]} -eq 0 ]; then
    echo "✅ **안전**: 모든 패턴이 성공적으로 마스킹됨"
else
    echo "❌ **위험**: 민감한 데이터 노출 감지"
fi)

### 노출된 패턴 목록
$(if [ ${#UNMASKED_PATTERNS[@]} -gt 0 ]; then
    for pattern in "${UNMASKED_PATTERNS[@]}"; do
        echo "- $pattern"
    done
else
    echo "- 없음"
fi)

### 마스킹된 패턴 목록
$(if [ ${#DETECTED_PATTERNS[@]} -gt 0 ]; then
    for pattern in "${DETECTED_PATTERNS[@]}"; do
        echo "- $pattern"
    done
else
    echo "- 없음"
fi)

## 권장사항

$(if [ $CRITICAL_EXPOSED -gt 0 ]; then
    echo "1. **긴급**: Critical 패턴 노출 - 즉시 조치 필요"
    echo "2. 패턴 우선순위 재조정 필요"
    echo "3. 비상 프로토콜 발동 고려"
else
    echo "1. 정기적인 패턴 업데이트 권장"
    echo "2. 성능 모니터링 지속"
fi)

---
테스트 수행: Kong AWS Masking Security Team
EOF

echo -e "${GREEN}✓ 보고서 생성: kong-api-test-report.md${NC}"

# 최종 결과
echo ""
echo "=========================================="
if [ ${#UNMASKED_PATTERNS[@]} -eq 0 ] && [ $CRITICAL_EXPOSED -eq 0 ]; then
    echo -e "${GREEN}✅ Kong API 통합 테스트 성공!${NC}"
    echo -e "${GREEN}   모든 AWS 리소스가 안전하게 마스킹되었습니다.${NC}"
    echo -e "${GREEN}   탐지된 패턴: ${#DETECTED_PATTERNS[@]}개${NC}"
    exit 0
else
    echo -e "${RED}❌ Kong API 통합 테스트 실패${NC}"
    echo -e "${RED}   노출된 패턴: ${#UNMASKED_PATTERNS[@]}개${NC}"
    if [ $CRITICAL_EXPOSED -gt 0 ]; then
        echo -e "${RED}   ⚠️  CRITICAL 패턴 노출: $CRITICAL_EXPOSED개${NC}"
    fi
    exit 1
fi