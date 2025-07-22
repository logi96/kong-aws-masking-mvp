#!/bin/bash
# 상세 변환 테스트 - 요청 → 패턴 변환 → 응답 과정 시각화

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "🔄 AWS 패턴 변환 과정 상세 테스트"
echo "================================================"

# 컬러 설정
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 테스트 케이스 배열
declare -a TEST_CASES=(
  "EC2 Instance|i-1234567890abcdef0"
  "Security Group|sg-12345678"
  "Subnet|subnet-87654321"
  "VPC|vpc-abcdef12"
  "AMI|ami-0987654321"
  "Private IP 10.x|10.0.1.100"
  "Private IP 172.x|172.16.0.50"
  "Private IP 192.x|192.168.1.100"
  "Account ID|123456789012"
  "Access Key|AKIAIOSFODNN7EXAMPLE"
  "Secret Key|wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  "Session Token|FwoGZXIvYXdzEJr//////////wEaDFPtMiJk2XMPEXAMPLEiLwAf"
  "S3 Bucket|my-production-bucket"
  "RDS Instance|prod-db-instance"
  "EBS Volume|vol-1234567890abcdef0"
  "Snapshot|snap-0987654321fedcba0"
  "EFS|fs-12345678"
  "IGW|igw-87654321"
  "NAT Gateway|nat-12345678901234567"
  "VPN|vpn-1234567890abcdef0"
  "Transit Gateway|tgw-1234567890abcdef0"
  "Route53 Zone|Z2FDTNDATAQYW2"
  "CloudFront|E2QWRUHAPOMQZL"
  "API Gateway|a1b2c3d4e5"
  "KMS Key|1234abcd-12ab-34cd-56ef-1234567890ab"
  "Lambda ARN|arn:aws:lambda:us-east-1:123456789012:function:myFunction"
  "IAM Role ARN|arn:aws:iam::123456789012:role/MyTestRole"
  "S3 ARN|arn:aws:s3:::my-bucket/*"
  "DynamoDB ARN|arn:aws:dynamodb:us-east-1:123456789012:table/MyTable"
  "ELB ARN|arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/50dc6c495c0c9188"
  "ECS Task ARN|arn:aws:ecs:us-east-1:123456789012:task/c5cba4eb-5dad-405e-96db-71ef8eefe6a8"
  "CloudFormation Stack|arn:aws:cloudformation:us-east-1:123456789012:stack/my-stack/c3a45670-2c84-11eb-9712-0a3c4a0e9b50"
  "Certificate ARN|arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  "Secrets Manager ARN|arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef"
  "Parameter Store ARN|arn:aws:ssm:us-east-1:123456789012:parameter/my-parameter"
  "CodeCommit ARN|arn:aws:codecommit:us-east-1:123456789012:my-repository"
  "ECR URI|123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repository"
  "Glue Job|glue-job-my-etl-job"
  "Redshift Cluster|my-redshift-cluster"
  "SageMaker Endpoint|arn:aws:sagemaker:us-east-1:123456789012:endpoint/my-endpoint"
  "Kinesis Stream|arn:aws:kinesis:us-east-1:123456789012:stream/my-stream"
  "ElasticSearch Domain|arn:aws:es:us-east-1:123456789012:domain/my-domain"
  "Step Functions|arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine"
  "Batch Job Queue|arn:aws:batch:us-east-1:123456789012:job-queue/my-job-queue"
  "Athena Workgroup|arn:aws:athena:us-east-1:123456789012:workgroup/primary"
  "SQS URL|https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue"
  "Log Group|/aws/lambda/myFunction"
  "ElastiCache Cluster|my-redis-cluster-001-abc"
  "SNS Topic ARN|arn:aws:sns:us-east-1:123456789012:MyTopic"
  "EKS Cluster ARN|arn:aws:eks:us-east-1:123456789012:cluster/my-cluster"
)

# 각 패턴 테스트
for i in "${!TEST_CASES[@]}"; do
  IFS='|' read -r description pattern <<< "${TEST_CASES[$i]}"
  
  echo -e "\n${BLUE}[테스트 $((i+1))/50] ${description}${NC}"
  echo -e "${YELLOW}원본:${NC} $pattern"
  
  # 간단한 테스트 데이터 생성
  TEST_DATA="{
    \"model\": \"claude-3-5-sonnet-20241022\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": \"Test with AWS resource: $pattern\"
    }],
    \"max_tokens\": 50
  }"
  
  # 요청 전송 및 응답 저장
  RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "$TEST_DATA" 2>&1)
  
  # 응답에서 패턴 검색
  if echo "$RESPONSE" | grep -q "$pattern"; then
    echo -e "${RED}❌ 마스킹 실패${NC} - 원본 패턴이 응답에 노출됨"
  else
    echo -e "${GREEN}✅ 마스킹 성공${NC} - 패턴이 적절히 마스킹됨"
    
    # 마스킹된 형태 추출 시도
    if [[ "$description" == *"EC2"* ]]; then
      MASKED=$(echo "$RESPONSE" | grep -oE "EC2_[0-9]{3}" | head -1)
    elif [[ "$description" == *"Security Group"* ]]; then
      MASKED=$(echo "$RESPONSE" | grep -oE "SG_[0-9]{3}" | head -1)
    elif [[ "$description" == *"Account ID"* ]]; then
      MASKED=$(echo "$RESPONSE" | grep -oE "ACCOUNT_[0-9]{3}" | head -1)
    elif [[ "$description" == *"Private IP"* ]]; then
      MASKED=$(echo "$RESPONSE" | grep -oE "PRIVATE_IP_[0-9]{3}" | head -1)
    fi
    
    if [ ! -z "$MASKED" ]; then
      echo -e "${GREEN}변환:${NC} $pattern → $MASKED"
    fi
  fi
  
  # 짧은 대기 시간
  sleep 0.2
done

echo -e "\n================================================"
echo "✅ 상세 변환 테스트 완료"
echo "================================================"