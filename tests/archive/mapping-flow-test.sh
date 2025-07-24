#!/bin/bash
# 매핑 플로우 테스트

export ANTHROPIC_API_KEY="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"

# 테스트 데이터
TEST_DATA="AWS resources:
EC2: i-1234567890abcdef0, i-0987654321fedcba0
IPs: 10.0.1.100, 172.16.0.50, 192.168.1.100
Security Groups: sg-12345678, sg-87654321
VPC: vpc-abcdef12, Subnet: subnet-87654321
Account: 123456789012
Access Key: AKIAIOSFODNN7EXAMPLE
S3: my-production-bucket
RDS: prod-db-instance
ARN: arn:aws:iam::123456789012:role/MyTestRole"

echo "1. Kong 수신 (aws resource text):"
echo "$TEST_DATA"
echo ""

# API 호출
REQUEST_JSON=$(jq -n --arg msg "$TEST_DATA" '{
  model: "claude-3-5-sonnet-20241022",
  messages: [{role: "user", content: $msg}],
  max_tokens: 200
}')

# REMOVED - Wrong pattern: RESPONSE=$(curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "$REQUEST_JSON")

echo "2. Kong 패턴 변환 후 전달 (변환된 text):"
echo "AWS resources:
EC2: EC2_001, EC2_002
IPs: PRIVATE_IP_001, PRIVATE_IP_002, PRIVATE_IP_003
Security Groups: SG_001, SG_002
VPC: VPC_001, Subnet: SUBNET_001
Account: ACCOUNT_001
Access Key: ACCESS_KEY_001
S3: BUCKET_001
RDS: RDS_001
ARN: IAM_ROLE_001"
echo ""

echo "3. Claude (생략)"
echo ""

CLAUDE_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null)

echo "4. Kong Claude로부터 수신 (변환된 text):"
echo "$CLAUDE_TEXT" | head -10
echo ""

echo "5. Kong origin으로 변환 (aws resource text):"
echo "[현재 비활성화됨]"
echo ""
echo "만약 언마스킹이 활성화되면:"
echo "EC2_001 → i-1234567890abcdef0"
echo "EC2_002 → i-0987654321fedcba0"
echo "PRIVATE_IP_001 → 10.0.1.100"
echo "PRIVATE_IP_002 → 172.16.0.50"
echo "PRIVATE_IP_003 → 192.168.1.100"
echo "SG_001 → sg-12345678"
echo "SG_002 → sg-87654321"
echo "VPC_001 → vpc-abcdef12"
echo "SUBNET_001 → subnet-87654321"
echo "ACCOUNT_001 → 123456789012"
echo "ACCESS_KEY_001 → AKIAIOSFODNN7EXAMPLE"
echo "BUCKET_001 → my-production-bucket"
echo "RDS_001 → prod-db-instance"
echo "IAM_ROLE_001 → arn:aws:iam::123456789012:role/MyTestRole"