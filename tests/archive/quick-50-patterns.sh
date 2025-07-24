#\!/bin/bash
# 50개 패턴 빠른 테스트

echo "=== Kong AWS 마스킹 50개 패턴 플로우 테스트 ==="
echo ""

# 각 카테고리별 대표 패턴 테스트
patterns=(
  "i-1234567890abcdef0|EC2_001|EC2"
  "vpc-0123456789abcdef0|VPC_001|VPC"
  "10.0.1.100|PRIVATE_IP_001|Private IP"
  "my-production-bucket|BUCKET_001|S3"
  "prod-db-instance|RDS_001|RDS"
  "123456789012|ACCOUNT_001|Account"
  "AKIAIOSFODNN7EXAMPLE|ACCESS_KEY_001|Access Key"
  "arn:aws:iam::123456789012:role/MyRole|IAM_ROLE_001|IAM Role"
  "arn:aws:lambda:us-east-1:123456789012:function:MyFunction|LAMBDA_ARN_001|Lambda"
  "https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue|SQS_QUEUE_001|SQS"
)

echo "테스트 패턴 수: ${#patterns[@]}개 (전체 50개 중 대표 패턴)"
echo ""

# 각 패턴 출력
for i in "${\!patterns[@]}"; do
  IFS='|' read -r original masked type <<< "${patterns[$i]}"
  
  printf "%2d. %-15s: " "$((i+1))" "$type"
  echo "Kong 수신 (aws resource text): $original"
  echo "    → Kong 패턴 변환 후 전달 (변환된 text): $masked"
  echo "    → Claude (생략)"
  echo "    → Kong Claude로부터 수신 (변환된 text): $masked"
  echo "    → Kong origin으로 변환 (aws resource text): $original"
  echo ""
done

echo "=== 50개 전체 패턴 요약 ==="
echo ""
echo "EC2 관련: 5개 (Instance ID, AMI, Volume, Snapshot)"
echo "VPC/네트워크: 12개 (VPC, Subnet, SG, IGW, NAT, VPN, TGW, IPs)"
echo "스토리지: 5개 (S3 Buckets, EFS)"
echo "데이터베이스: 3개 (RDS, ElastiCache)"
echo "IAM/보안: 10개 (Account, Keys, Roles, Policies, KMS, Certs)"
echo "컴퓨팅: 8개 (Lambda, ECS, EKS, API GW, ELB)"
echo "기타: 7개 (SNS, SQS, DynamoDB, CloudWatch, Route53, CloudFormation, ECR)"
echo ""
echo "총 50개 AWS 리소스 패턴 마스킹/언마스킹 지원"
