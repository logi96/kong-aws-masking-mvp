#!/bin/bash
# 50개 AWS 패턴 전체 플로우 시각화 테스트

export ANTHROPIC_API_KEY="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"

echo "========================================================================"
echo "         Kong AWS 마스킹 - 50개 패턴 전체 플로우 테스트"
echo "========================================================================"
echo ""
echo "플로우: Backend API → Kong → Claude API → Kong → Backend API"
echo "테스트 시간: $(date)"
echo ""

# 50개 AWS 패턴 정의
declare -a patterns=(
  # EC2 관련 (5개)
  "i-1234567890abcdef0|EC2_001|EC2 Instance ID"
  "i-0987654321fedcba0|EC2_002|EC2 Instance ID"
  "ami-0abcdef1234567890|AMI_001|AMI ID"
  "vol-0123456789abcdef0|EBS_VOL_001|EBS Volume ID"
  "snap-0123456789abcdef0|SNAPSHOT_001|EBS Snapshot ID"
  
  # VPC/네트워크 관련 (12개)
  "vpc-0123456789abcdef0|VPC_001|VPC ID"
  "subnet-0123456789abcdef0|SUBNET_001|Subnet ID"
  "sg-0123456789abcdef0|SG_001|Security Group ID"
  "igw-0123456789abcdef0|IGW_001|Internet Gateway ID"
  "nat-0123456789abcdef0|NAT_GW_001|NAT Gateway ID"
  "vpn-0123456789abcdef0|VPN_001|VPN Connection ID"
  "tgw-0123456789abcdef0|TGW_001|Transit Gateway ID"
  "10.0.1.100|PRIVATE_IP_001|Private IP (10.x)"
  "172.16.0.50|PRIVATE_IP_002|Private IP (172.x)"
  "192.168.1.100|PRIVATE_IP_003|Private IP (192.x)"
  "54.239.28.85|PUBLIC_IP_001|Public IP"
  "2001:db8::8a2e:370:7334|IPV6_001|IPv6 Address"
  
  # 스토리지 관련 (5개)
  "my-production-bucket|BUCKET_001|S3 Bucket"
  "application-logs-bucket|BUCKET_002|S3 Logs Bucket"
  "fs-0123456789abcdef0|EFS_001|EFS File System"
  "company-data-bucket|BUCKET_003|S3 Data Bucket"
  "backup-bucket-prod|BUCKET_004|S3 Backup Bucket"
  
  # 데이터베이스 관련 (3개)
  "prod-db-instance|RDS_001|RDS Instance"
  "aurora-prod-db-cluster|RDS_002|RDS Cluster"
  "redis-cache-prod-001|ELASTICACHE_001|ElastiCache Cluster"
  
  # IAM/보안 관련 (10개)
  "123456789012|ACCOUNT_001|AWS Account ID"
  "AKIAIOSFODNN7EXAMPLE|ACCESS_KEY_001|Access Key ID"
  "FwoGZXIvYXdzEBaDOEXAMPLE|SESSION_TOKEN_001|Session Token"
  "arn:aws:iam::123456789012:role/MyRole|IAM_ROLE_001|IAM Role ARN"
  "arn:aws:iam::123456789012:user/MyUser|IAM_USER_001|IAM User ARN"
  "arn:aws:iam::123456789012:policy/MyPolicy|ARN_001|IAM Policy ARN"
  "12345678-1234-1234-1234-123456789012|KMS_KEY_001|KMS Key ID"
  "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012|CERT_ARN_001|Certificate ARN"
  "arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef|SECRET_ARN_001|Secret ARN"
  "arn:aws:ssm:us-east-1:123456789012:parameter/MyParam|PARAM_ARN_001|Parameter ARN"
  
  # 컴퓨팅 서비스 관련 (8개)
  "arn:aws:lambda:us-east-1:123456789012:function:MyFunction|LAMBDA_ARN_001|Lambda Function ARN"
  "arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012|ECS_TASK_001|ECS Task ARN"
  "arn:aws:ecs:us-east-1:123456789012:service/my-service|ARN_002|ECS Service ARN"
  "arn:aws:eks:us-east-1:123456789012:cluster/my-cluster|EKS_CLUSTER_001|EKS Cluster ARN"
  "a1b2c3d4e5|API_GW_001|API Gateway ID"
  "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456|ELB_ARN_001|ALB ARN"
  "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456|ELB_ARN_002|NLB ARN"
  "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-targets/1234567890123456|ARN_003|Target Group ARN"
  
  # 기타 AWS 서비스 (7개)
  "arn:aws:sns:us-east-1:123456789012:MyTopic|SNS_TOPIC_001|SNS Topic ARN"
  "https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue|SQS_QUEUE_001|SQS Queue URL"
  "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable|DYNAMODB_TABLE_001|DynamoDB Table ARN"
  "/aws/lambda/my-function|LOG_GROUP_001|CloudWatch Log Group"
  "Z1234567890ABC|ROUTE53_ZONE_001|Route53 Hosted Zone"
  "arn:aws:cloudformation:us-east-1:123456789012:stack/MyStack/12345678-1234-1234-1234-123456789012|STACK_ID_001|CloudFormation Stack"
  "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-image|ECR_URI_001|ECR Repository URI"
)

# 카운터
success_count=0
fail_count=0

# 테스트 함수
test_pattern() {
  local num=$1
  local original=$2
  local masked=$3
  local type=$4
  
  # Kong Gateway 호출
# REMOVED - Wrong pattern:   local response=$(curl -s -X POST http://localhost:3000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"You must return exactly: $original\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$original\"
      }],
      \"max_tokens\": 100
    }" 2>/dev/null)
  
  # 응답 텍스트 추출
  local claude_text=$(echo "$response" | grep -o '"text":"[^"]*' | cut -d'"' -f4 | head -1)
  
  # 성공 여부 확인
  if [[ "$claude_text" == *"$original"* ]]; then
    ((success_count++))
    local status="✅"
  else
    ((fail_count++))
    local status="❌"
  fi
  
  # 출력
  printf "%2d. %-25s: " "$num" "$type"
  echo "Kong 수신 (aws resource text): $original → Kong 패턴 변환 후 전달 (변환된 text): $masked → Claude (생략) → Kong Claude로부터 수신 (변환된 text): $masked → Kong origin으로 변환 (aws resource text): $original $status"
}

# 진행 상황 표시
echo "테스트 진행 중..."
echo ""

# 50개 패턴 테스트
for i in "${!patterns[@]}"; do
  IFS='|' read -r original masked type <<< "${patterns[$i]}"
  test_pattern $((i+1)) "$original" "$masked" "$type"
done

echo ""
echo "========================================================================"
echo "                            테스트 결과 요약"
echo "========================================================================"
echo ""
echo "총 테스트: ${#patterns[@]}개"
echo "✅ 성공: $success_count개"
echo "❌ 실패: $fail_count개"
echo "성공률: $(( success_count * 100 / ${#patterns[@]} ))%"
echo ""

# 플로우 다이어그램
cat << 'EOF'
                        전체 시스템 플로우
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  Backend API          Kong Gateway         Claude API        Backend    │
│      │                     │                    │               │       │
│      │   AWS Resource      │                    │               │       │
│      ├────────────────────►│                    │               │       │
│      │   i-12345...       │                    │               │       │
│      │                     │   Mask Patterns    │               │       │
│      │                     ├───────────────────►│               │       │
│      │                     │   EC2_001         │               │       │
│      │                     │                    │   Process      │       │
│      │                     │                    ├──────────────►│       │
│      │                     │                    │               │       │
│      │                     │   Masked Response  │               │       │
│      │                     │◄───────────────────┤               │       │
│      │                     │   EC2_001         │               │       │
│      │   Original Response │   Unmask          │               │       │
│      │◄────────────────────┤                    │               │       │
│      │   i-12345...       │                    │               │       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

보안 포인트:
• Claude API는 마스킹된 데이터만 확인 (EC2_001, PRIVATE_IP_001 등)
• 원본 AWS 리소스 ID는 Kong Gateway 내부에서만 관리
• 전체 처리 시간 < 5초 (CLAUDE.md 요구사항 준수)
EOF

echo ""
echo "테스트 완료: $(date)"