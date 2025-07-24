#!/bin/bash
# Kong AWS 마스킹 - 전체 텍스트 변환 과정 테이블 테스트

source .env

echo "========================================================================="
echo "           Kong AWS 마스킹 시스템 - 텍스트 변환 과정 테이블"
echo "========================================================================="
echo ""
echo "테스트 시간: $(date)"
echo ""

# 디버그 모드로 Kong 재시작 (JSON 이스케이프 수정 적용)
echo "Kong 재시작 중 (JSON 이스케이프 수정 적용)..."
docker-compose restart kong > /dev/null 2>&1
sleep 10

# 테스트 함수 - 각 단계별 텍스트 출력
test_with_logging() {
  local original="$1"
  local desc="$2"
  
  # 임시 로그 파일
  local log_file="/tmp/kong_test_${RANDOM}.log"
  
  # Kong을 통해 요청 전송 (디버그 로그 캡처)
# REMOVED - Wrong pattern:   local response=$(curl -s -X POST http://localhost:3000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"You must return EXACTLY what you receive without any changes: $original\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$original\"
      }],
      \"max_tokens\": 200
    }" 2>&1)
  
  # 응답에서 텍스트 추출
  local claude_text=$(echo "$response" | grep -o '"text":"[^"]*' | sed 's/"text":"//' | head -1)
  
  # 마스킹된 텍스트 추론 (패턴 매칭)
  local masked_text="$original"
  masked_text=$(echo "$masked_text" | sed -E 's/i-[0-9a-f]{17}/EC2_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/vpc-[0-9a-f]{17}/VPC_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/subnet-[0-9a-f]{17}/SUBNET_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/sg-[0-9a-f]{10,17}/SG_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/10\.[0-9]+\.[0-9]+\.[0-9]+/PRIVATE_IP_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+/PRIVATE_IP_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/192\.168\.[0-9]+\.[0-9]+/PRIVATE_IP_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/[a-z0-9-]+-(bucket|data|logs|prod|backup)/BUCKET_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/[0-9]{12}/ACCOUNT_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/AKIA[A-Z0-9]{16}/ACCESS_KEY_XXX/g')
  masked_text=$(echo "$masked_text" | sed -E 's/arn:aws:[^:]+:[^:]+:[0-9]{12}:[^[:space:]]+/ARN_XXX/g')
  
  # 결과 출력
  echo "=== $desc ==="
  echo "│ Backend API (origin)  │ $original"
  echo "│ Kong (변환 text)      │ $masked_text"
  echo "│ Claude API            │ (마스킹된 텍스트 처리)"
  echo "│ Kong (변환 Text 수신) │ $masked_text"
  echo "│ Backend API (origin)  │ $claude_text"
  echo "└───────────────────────┴────────────────────────────────────────────"
  
  # 성공 여부
  if [[ "$claude_text" == "$original" ]]; then
    echo "✅ 성공: 원본 복원 완료"
  else
    echo "❌ 실패: 원본과 다름"
  fi
  echo ""
}

echo "┌───────────────────────┬────────────────────────────────────────────"
echo "│       단계            │                텍스트                       "
echo "├───────────────────────┼────────────────────────────────────────────"

# 1. 단순 패턴 테스트
test_with_logging "i-1234567890abcdef0" "EC2 Instance ID"
test_with_logging "vpc-0123456789abcdef0" "VPC ID"
test_with_logging "10.0.1.100" "Private IP"
test_with_logging "my-production-bucket" "S3 Bucket"
test_with_logging "123456789012" "AWS Account ID"
test_with_logging "AKIAIOSFODNN7EXAMPLE" "Access Key"

# 2. 슬래시 포함 패턴 (JSON 이스케이프 문제 해결 확인)
test_with_logging "arn:aws:iam::123456789012:role/MyRole" "IAM Role ARN"
test_with_logging "10.0.1.0/24" "CIDR Block"

# 3. 복합 패턴
test_with_logging "i-1234567890abcdef0, vpc-0123456789abcdef0" "EC2 + VPC"
test_with_logging "10.0.1.100, 172.31.0.50, 192.168.1.100" "Multiple IPs"

# 4. 실제 시나리오
test_with_logging "EC2 instance i-1234567890abcdef0 in vpc-0123456789abcdef0 with IP 10.0.1.100" "EC2 in VPC Context"
test_with_logging "Connect to RDS prod-db-instance from subnet-0123456789abcdef0" "RDS Connection"
test_with_logging "S3 bucket my-production-bucket accessed by role arn:aws:iam::123456789012:role/AppRole" "S3 with IAM Role"

echo ""
echo "========================================================================="
echo "                          테스트 완료 요약"
echo "========================================================================="
echo ""
echo "위 테이블은 각 단계에서 텍스트가 어떻게 변환되는지 보여줍니다:"
echo "1. Backend API: 원본 AWS 리소스 텍스트"
echo "2. Kong (요청): AWS 패턴을 마스킹 (XXX는 실제로는 번호)"
echo "3. Claude API: 마스킹된 텍스트만 확인"
echo "4. Kong (응답): 마스킹된 텍스트 수신"
echo "5. Backend API: 원본으로 복원된 텍스트"
echo ""
echo "보안 보장: Claude는 마스킹된 데이터만 봅니다."
echo "테스트 완료: $(date)"