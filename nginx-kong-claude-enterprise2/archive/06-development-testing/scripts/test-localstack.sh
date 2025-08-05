#!/bin/bash

# LocalStack 연결 테스트 스크립트
# Kong AWS Masking Enterprise 2 - LocalStack 통합 테스트

set -euo pipefail

# LocalStack 엔드포인트 설정
export AWS_ENDPOINT_URL="http://localstack:4566"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="us-east-1"

echo "🚀 LocalStack AWS 서비스 연결 테스트 시작..."

# 1. LocalStack 헬스 체크
echo "1. LocalStack 헬스 체크..."
curl -s http://localstack:4566/_localstack/health | jq '.'

# 2. EC2 서비스 테스트
echo "2. EC2 서비스 테스트..."
echo "  - VPC 생성..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
echo "  - VPC 생성됨: $VPC_ID"

echo "  - 서브넷 생성..."
SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text)
echo "  - 서브넷 생성됨: $SUBNET_ID"

# 3. ECS 서비스 테스트
echo "3. ECS 서비스 테스트..."
echo "  - ECS 클러스터 생성..."
CLUSTER_NAME="kong-test-cluster"
aws ecs create-cluster --cluster-name $CLUSTER_NAME
echo "  - ECS 클러스터 '$CLUSTER_NAME' 생성됨"

echo "  - ECS 클러스터 목록..."
aws ecs list-clusters

# 4. EKS 서비스 테스트
echo "4. EKS 서비스 테스트..."
echo "  - EKS 클러스터 목록..."
aws eks list-clusters

# 5. CloudFormation 서비스 테스트
echo "5. CloudFormation 서비스 테스트..."
echo "  - CloudFormation 스택 목록..."
aws cloudformation list-stacks

# 6. IAM 서비스 테스트
echo "6. IAM 서비스 테스트..."
echo "  - IAM 역할 목록..."
aws iam list-roles --query 'Roles[0:3].RoleName'

echo "✅ LocalStack AWS 서비스 연결 테스트 완료!"
echo "   - VPC: $VPC_ID"
echo "   - 서브넷: $SUBNET_ID" 
echo "   - ECS 클러스터: $CLUSTER_NAME"
echo "   - 모든 AWS 서비스 정상 작동 확인"