#!/bin/bash
# 50개 AWS 리소스 패턴 전체 플로우 테스트
# 형식: Backend API → Kong Gateway → Claude API → 언마스킹 → 원본 복원
# 
# 🚨 MUST 규칙: 테스트 결과 리포트 생성 필수
#
# Backend API 사용으로 인해 직접적인 API 키 필요 없음
# Backend API가 Kong Gateway를 통해 Claude API에 접근

# 테스트 리포트 설정 (MUST 규칙 준수)
TEST_REPORT_DIR="./test-report"
mkdir -p "$TEST_REPORT_DIR"

# 리포트 파일명 생성 (순번 자동 증가)
REPORT_BASE="50-patterns-complete-flow"
REPORT_COUNTER=1
while [ -f "$TEST_REPORT_DIR/${REPORT_BASE}-$(printf "%03d" $REPORT_COUNTER).md" ]; do
  ((REPORT_COUNTER++))
done
REPORT_FILE="$TEST_REPORT_DIR/${REPORT_BASE}-$(printf "%03d" $REPORT_COUNTER).md"

echo "=== 50개 AWS 리소스 패턴 마스킹/언마스킹 플로우 테스트 ==="
echo "📋 테스트 리포트: $REPORT_FILE"
echo ""

# 테스트 시작 시간 기록
TEST_START_TIME=$(date +%s)
TEST_START_ISO=$(date -Iseconds)

# 리포트 헤더 작성
cat > "$REPORT_FILE" << EOF
# 50개 AWS 패턴 마스킹/언마스킹 플로우 테스트 리포트

**테스트 실행 시간**: $TEST_START_ISO  
**테스트 스크립트**: 50-patterns-complete-flow.sh  
**목적**: 전체 AWS 리소스 패턴의 마스킹/언마스킹 완전성 검증

## 테스트 개요
- **총 패턴 수**: 46개 (복합 패턴 포함)
- **테스트 방식**: Backend API → Kong Gateway → Claude API → 언마스킹
- **검증 기준**: 원본 AWS 리소스가 사용자 응답에 완전 복원되는지 확인

## 상세 테스트 결과

EOF

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
  echo "   Claude 응답: ${CLAUDE_TEXT:0:100}..."
  
  # 성공 여부 체크 및 리포트 작성
  if [[ "$CLAUDE_TEXT" == *"$original"* ]] && [[ "$CLAUDE_TEXT" != "ERROR" ]] && [[ "$CLAUDE_TEXT" != "PARSE_ERROR" ]]; then
    echo "   ✅ 성공: 원본 리소스 복원됨"
    ((PASSED_TESTS++))
    
    # 리포트에 성공 기록
    echo "### ✅ Test $num: $type" >> "$REPORT_FILE"
    echo "- **원본**: \`$original\`" >> "$REPORT_FILE"
    echo "- **결과**: 성공 (원본 리소스 복원 확인)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  else
    echo "   ❌ 실패: 원본 리소스 복원 실패"
    ((FAILED_TESTS++))
    
    # 리포트에 실패 기록
    echo "### ❌ Test $num: $type" >> "$REPORT_FILE"
    echo "- **원본**: \`$original\`" >> "$REPORT_FILE"
    echo "- **응답**: \`${CLAUDE_TEXT:0:200}...\`" >> "$REPORT_FILE"
    echo "- **결과**: 실패 (원본 리소스 복원되지 않음)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi
  echo ""
}

# 50개 패턴 테스트
echo "=== EC2 관련 리소스 ==="
test_pattern "1" "EC2 Instance" "i-1234567890abcdef0" "EC2_001"
test_pattern "2" "EC2 Instance" "i-0987654321fedcba0" "EC2_002"
test_pattern "3" "AMI" "ami-0abcdef1234567890" "AMI_001"
test_pattern "4" "EBS Volume" "vol-0123456789abcdef0" "EBS_VOL_001"
test_pattern "5" "Snapshot" "snap-0123456789abcdef0" "SNAPSHOT_001"

echo "=== VPC/네트워크 관련 리소스 ==="
test_pattern "6" "VPC" "vpc-0123456789abcdef0" "VPC_001"
test_pattern "7" "Subnet" "subnet-0123456789abcdef0" "SUBNET_001"
test_pattern "8" "Security Group" "sg-0123456789abcdef0" "SG_001"
test_pattern "9" "Internet Gateway" "igw-0123456789abcdef0" "IGW_001"
test_pattern "10" "NAT Gateway" "nat-0123456789abcdef0" "NAT_GW_001"
test_pattern "11" "VPN Connection" "vpn-0123456789abcdef0" "VPN_001"
test_pattern "12" "Transit Gateway" "tgw-0123456789abcdef0" "TGW_001"

echo "=== IP 주소 관련 ==="
test_pattern "13" "Private IP (10.x)" "10.0.1.100" "PRIVATE_IP_001"
test_pattern "14" "Private IP (172.x)" "172.16.0.50" "PRIVATE_IP_002"
test_pattern "15" "Private IP (192.x)" "192.168.1.100" "PRIVATE_IP_003"
test_pattern "16" "Public IP" "54.239.28.85" "PUBLIC_IP_001"
test_pattern "17" "IPv6" "2001:db8::8a2e:370:7334" "IPV6_001"

echo "=== 스토리지 관련 ==="
test_pattern "18" "S3 Bucket" "my-production-bucket" "BUCKET_001"
test_pattern "19" "S3 Logs" "application-logs-bucket" "BUCKET_002"
test_pattern "20" "EFS" "fs-0123456789abcdef0" "EFS_001"

echo "=== 데이터베이스 관련 ==="
test_pattern "21" "RDS Instance" "prod-db-instance" "RDS_001"
test_pattern "22" "ElastiCache" "redis-cluster-prod-001" "ELASTICACHE_001"

echo "=== IAM/보안 관련 ==="
test_pattern "23" "AWS Account" "123456789012" "ACCOUNT_001"
test_pattern "24" "Access Key" "AKIAIOSFODNN7EXAMPLE" "ACCESS_KEY_001"
test_pattern "25" "Session Token" "FwoGZXIvYXdzEBaDOEXAMPLETOKEN123" "SESSION_TOKEN_001"
test_pattern "26" "IAM Role ARN" "arn:aws:iam::123456789012:role/MyRole" "IAM_ROLE_001"
test_pattern "27" "IAM User ARN" "arn:aws:iam::123456789012:user/MyUser" "IAM_USER_001"
test_pattern "28" "KMS Key" "12345678-1234-1234-1234-123456789012" "KMS_KEY_001"
test_pattern "29" "Certificate ARN" "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012" "CERT_ARN_001"
test_pattern "30" "Secret ARN" "arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef" "SECRET_ARN_001"

echo "=== 컴퓨팅 서비스 관련 ==="
test_pattern "31" "Lambda ARN" "arn:aws:lambda:us-east-1:123456789012:function:MyFunction" "LAMBDA_ARN_001"
test_pattern "32" "ECS Task" "arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012" "ECS_TASK_001"
test_pattern "33" "EKS Cluster" "arn:aws:eks:us-east-1:123456789012:cluster/my-cluster" "EKS_CLUSTER_001"
test_pattern "34" "API Gateway" "a1b2c3d4e5" "API_GW_001"
test_pattern "35" "ELB ARN" "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456" "ELB_ARN_001"

echo "=== 메시징/큐 서비스 ==="
test_pattern "36" "SNS Topic" "arn:aws:sns:us-east-1:123456789012:MyTopic" "SNS_TOPIC_001"
test_pattern "37" "SQS Queue" "https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue" "SQS_QUEUE_001"

echo "=== 기타 AWS 서비스 ==="
test_pattern "38" "DynamoDB Table" "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" "DYNAMODB_TABLE_001"
test_pattern "39" "CloudWatch Log" "/aws/lambda/my-function" "LOG_GROUP_001"
test_pattern "40" "Route53 Zone" "Z1234567890ABC" "ROUTE53_ZONE_001"
test_pattern "41" "CloudFormation Stack" "arn:aws:cloudformation:us-east-1:123456789012:stack/MyStack/12345678-1234-1234-1234-123456789012" "STACK_ID_001"
test_pattern "42" "CodeCommit Repo" "arn:aws:codecommit:us-east-1:123456789012:MyRepo" "CODECOMMIT_001"
test_pattern "43" "ECR URI" "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-image" "ECR_URI_001"
test_pattern "44" "Parameter Store" "arn:aws:ssm:us-east-1:123456789012:parameter/MyParam" "PARAM_ARN_001"
test_pattern "45" "Glue Job" "glue-job-data-processor" "GLUE_JOB_001"

echo "=== 복합 패턴 테스트 ==="
# 실제 복합 패턴 테스트 수행
test_pattern "46" "복합 패턴 (EC2+Subnet+IP)" "EC2 instance i-1234567890abcdef0 in subnet subnet-0987654321 with IP 10.0.1.100" "EC2_001, SUBNET_002, PRIVATE_IP_004"

# 테스트 완료 및 리포트 마무리
TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))
SUCCESS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)

# 콘솔 요약 출력
echo "=== 테스트 완료 ==="
echo "📊 총 테스트: $TOTAL_TESTS개"
echo "✅ 성공: $PASSED_TESTS개"
echo "❌ 실패: $FAILED_TESTS개"
echo "📈 성공률: ${SUCCESS_RATE}%"
echo "⏱️  실행 시간: ${TEST_DURATION}초"
echo "📋 상세 리포트: $REPORT_FILE"

# 리포트 요약 섹션 추가
cat >> "$REPORT_FILE" << EOF

## 테스트 결과 요약

### 📊 통계
- **총 테스트**: $TOTAL_TESTS개
- **성공**: $PASSED_TESTS개
- **실패**: $FAILED_TESTS개  
- **성공률**: ${SUCCESS_RATE}%
- **실행 시간**: ${TEST_DURATION}초

### 🎯 분석
EOF

if (( $(echo "$SUCCESS_RATE >= 90" | bc -l) )); then
  echo "- **결과**: ✅ 우수 (90% 이상 성공률)" >> "$REPORT_FILE"
  echo "- **권고**: 프로덕션 배포 적합" >> "$REPORT_FILE"
  echo ""
  echo "🎉 테스트 성공: 90% 이상 성공률 달성!"
elif (( $(echo "$SUCCESS_RATE >= 70" | bc -l) )); then
  echo "- **결과**: ⚠️ 양호 (70-90% 성공률)" >> "$REPORT_FILE"
  echo "- **권고**: 실패 패턴 개선 후 재테스트 필요" >> "$REPORT_FILE"
  echo ""
  echo "⚠️  주의: 일부 패턴 개선 필요 (70-90% 성공률)"
else
  echo "- **결과**: ❌ 부족 (70% 미만 성공률)" >> "$REPORT_FILE"
  echo "- **권고**: 대폭적인 패턴 개선 필수, 프로덕션 배포 부적합" >> "$REPORT_FILE"
  echo ""
  echo "❌ 경고: 대부분 패턴 실패 (70% 미만 성공률)"
fi

echo "" >> "$REPORT_FILE"
echo "**테스트 완료 시간**: $(date -Iseconds)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "*이 리포트는 Kong AWS Masker 50개 패턴 검증의 공식 결과입니다.*" >> "$REPORT_FILE"

echo ""
echo "📋 MUST 규칙 준수: 테스트 리포트가 성공적으로 생성되었습니다."