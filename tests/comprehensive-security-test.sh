#!/bin/bash
# 🔒 포괄적 보안 테스트 - 50개 이상의 AWS 패턴

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "🔒 포괄적 AWS 패턴 보안 테스트 (50+ patterns)"
echo "================================================"

# 테스트 데이터 생성
TEST_DATA='{
  "model": "claude-3-5-sonnet-20241022",
  "messages": [{
    "role": "user",
    "content": "Analyze this AWS infrastructure:\n\n1. EC2 Instances: i-1234567890abcdef0, i-0987654321fedcba0, i-abcdef1234567890\n2. Security Groups: sg-12345678, sg-87654321, sg-abcdef12\n3. Subnets: subnet-12345678, subnet-87654321\n4. VPCs: vpc-12345678, vpc-87654321\n5. AMIs: ami-12345678, ami-87654321\n6. IPs: 10.0.1.100, 10.0.2.200, 172.16.0.50, 192.168.1.100, 54.123.45.67\n7. IPv6: 2001:0db8:85a3:0000:0000:8a2e:0370:7334\n8. Account: 123456789012\n9. Access Key: AKIAIOSFODNN7EXAMPLE\n10. Secret Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\n11. Session Token: FwoGZXIvYXdzEJr//////////wEaDFPtMiJk2XMPEXAMPLEiLwAf\n12. ARNs:\n    - arn:aws:iam::123456789012:role/MyTestRole\n    - arn:aws:iam::123456789012:user/test-user\n    - arn:aws:lambda:us-east-1:123456789012:function:myFunction\n    - arn:aws:s3:::my-bucket/*\n    - arn:aws:dynamodb:us-east-1:123456789012:table/MyTable\n    - arn:aws:sns:us-east-1:123456789012:MyTopic\n    - arn:aws:sqs:us-east-1:123456789012:MyQueue\n    - arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/50dc6c495c0c9188\n    - arn:aws:ecs:us-east-1:123456789012:task/c5cba4eb-5dad-405e-96db-71ef8eefe6a8\n    - arn:aws:eks:us-east-1:123456789012:cluster/my-cluster\n    - arn:aws:cloudformation:us-east-1:123456789012:stack/my-stack/c3a45670-2c84-11eb-9712-0a3c4a0e9b50\n13. KMS Key: 1234abcd-12ab-34cd-56ef-1234567890ab\n14. S3 Buckets: my-production-bucket, backup-bucket-2023, logs-bucket-prod\n15. RDS: prod-db-instance, dev-db-cluster, test-mysql-db\n16. EBS Volumes: vol-1234567890abcdef0, vol-0987654321fedcba0\n17. Snapshots: snap-1234567890abcdef0, snap-0987654321fedcba0\n18. EFS: fs-12345678, fs-87654321\n19. Internet Gateways: igw-12345678, igw-87654321\n20. NAT Gateways: nat-12345678901234567, nat-09876543210987654\n21. VPN: vpn-1234567890abcdef0\n22. Transit Gateway: tgw-1234567890abcdef0\n23. Route53 Zone: Z2FDTNDATAQYW2\n24. CloudFront: E2QWRUHAPOMQZL\n25. ElastiCache: my-redis-cluster-001-abc\n26. API Gateway: a1b2c3d4e5\n27. Log Groups: /aws/lambda/myFunction, /aws/ecs/my-cluster\n28. Certificate: arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012\n29. Secrets Manager: arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef\n30. Parameter Store: arn:aws:ssm:us-east-1:123456789012:parameter/my-parameter\n31. CodeCommit: arn:aws:codecommit:us-east-1:123456789012:my-repository\n32. ECR: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repository\n33. Glue: glue-job-my-etl-job\n34. SageMaker: arn:aws:sagemaker:us-east-1:123456789012:endpoint/my-endpoint\n35. Kinesis: arn:aws:kinesis:us-east-1:123456789012:stream/my-stream\n36. Redshift: my-redshift-cluster\n37. ElasticSearch: arn:aws:es:us-east-1:123456789012:domain/my-domain\n38. Step Functions: arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine\n39. Batch: arn:aws:batch:us-east-1:123456789012:job-queue/my-job-queue\n40. Athena: arn:aws:athena:us-east-1:123456789012:workgroup/primary\n41. SQS URL: https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue\n42. Additional IPs: 172.31.0.0, 192.168.0.0, 10.10.10.10\n43. Mixed: Instance i-abc123def456 in subnet-789012 with sg-345678\n44. Complex ARN: arn:aws:iam::123456789012:role/service-role/MyLambdaRole\n45. Long strings with embedded IDs: The EC2 instance i-1234567890abcdef0 is in vpc-12345678\n46. JSON embedding: {\"instance\":\"i-1234567890abcdef0\",\"ip\":\"10.0.1.100\"}\n47. URL with IDs: https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:instanceId=i-1234567890abcdef0\n48. Base64 encoded: aS0xMjM0NTY3ODkwYWJjZGVmMA==\n49. Mixed credentials: AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\n50. Special chars: i-1234567890abcdef0@aws, subnet-12345678#prod"
  }],
  "max_tokens": 100
}'

echo -e "\n[1] 테스트 데이터 전송 중..."
RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$TEST_DATA")

echo -e "\n[2] 응답 받음 (처음 500자):"
echo "$RESPONSE" | head -c 500
echo "..."

# 패턴 검증
echo -e "\n\n[3] 🔍 보안 검증 시작"

# 테스트할 패턴들
PATTERNS=(
  # EC2 & VPC
  "i-[0-9a-f]{17}"
  "sg-[0-9a-f]{8}"
  "subnet-[0-9a-f]{8}"
  "vpc-[0-9a-f]{8}"
  "ami-[0-9a-f]{8}"
  
  # IPs
  "10\.[0-9]+\.[0-9]+\.[0-9]+"
  "172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+"
  "192\.168\.[0-9]+\.[0-9]+"
  "54\.[0-9]+\.[0-9]+\.[0-9]+"
  "2001:0db8"
  
  # Credentials
  "123456789012"
  "AKIA[0-9A-Z]{16}"
  "wJalrXUtnFEMI"
  "FwoGZXIvYXdzE"
  
  # Storage
  "vol-[0-9a-f]+"
  "snap-[0-9a-f]+"
  "fs-[0-9a-f]+"
  
  # Network
  "igw-[0-9a-f]+"
  "nat-[0-9a-f]+"
  "vpn-[0-9a-f]+"
  "tgw-[0-9a-f]+"
  
  # Services
  "E[0-9A-Z]{13}"
  "Z[0-9A-Z]{13}"
  "[0-9]{12}\.dkr\.ecr"
  "a1b2c3d4e5"
  "glue-job-"
  "my-redshift-cluster"
  
  # ARNs
  "arn:aws:iam"
  "arn:aws:lambda"
  "arn:aws:s3"
  "arn:aws:dynamodb"
  "arn:aws:sns"
  "arn:aws:sqs"
  "arn:aws:elasticloadbalancing"
  "arn:aws:ecs"
  "arn:aws:eks"
  "arn:aws:cloudformation"
  "arn:aws:acm"
  "arn:aws:secretsmanager"
  "arn:aws:ssm"
  "arn:aws:codecommit"
  "arn:aws:sagemaker"
  "arn:aws:kinesis"
  "arn:aws:es"
  "arn:aws:states"
  "arn:aws:batch"
  "arn:aws:athena"
  
  # Others
  "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
  "https://sqs\."
  "/aws/lambda"
  "my-bucket"
  "MyTable"
  "MyQueue"
)

FOUND=0
NOT_FOUND=0

for pattern in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -qE "$pattern"; then
    echo "❌ 발견: $pattern"
    ((FOUND++))
  else
    echo "✅ 마스킹됨: $pattern"
    ((NOT_FOUND++))
  fi
done

echo -e "\n[4] 📊 테스트 결과"
echo "총 패턴: ${#PATTERNS[@]}개"
echo "마스킹됨: $NOT_FOUND개"
echo "노출됨: $FOUND개"
echo "마스킹 비율: $(( NOT_FOUND * 100 / ${#PATTERNS[@]} ))%"

if [ $FOUND -eq 0 ]; then
  echo -e "\n✅ 모든 AWS 패턴이 성공적으로 마스킹되었습니다!"
else
  echo -e "\n❌ 경고: $FOUND개의 패턴이 마스킹되지 않았습니다!"
fi

# Kong 로그 확인
echo -e "\n[5] Kong 처리 로그"
docker-compose logs kong --tail=10 | grep -v "127.0.0.11"

echo -e "\n================================================"