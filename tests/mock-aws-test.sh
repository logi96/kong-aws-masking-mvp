#!/bin/bash
# Mock AWS 데이터로 마스킹 테스트

echo "================================================"
echo "🧪 Mock AWS 데이터로 마스킹 테스트"
echo "================================================"

# Mock AWS 데이터 직접 전송
MOCK_DATA='{
  "awsData": {
    "ec2": [
      {
        "InstanceId": "i-1234567890abcdef0",
        "PrivateIpAddress": "10.0.1.100",
        "PublicIpAddress": "54.123.45.67",
        "SecurityGroups": ["sg-12345678"],
        "SubnetId": "subnet-abcdef12",
        "ImageId": "ami-12345678"
      },
      {
        "InstanceId": "i-0987654321fedcba0",
        "PrivateIpAddress": "10.0.2.200",
        "Tags": [
          {"Key": "Name", "Value": "production-server"},
          {"Key": "Environment", "Value": "prod"}
        ]
      }
    ],
    "s3": [
      {
        "Name": "my-production-bucket",
        "Region": "us-east-1",
        "CreationDate": "2023-01-01T00:00:00Z"
      },
      {
        "Name": "backup-bucket-2023",
        "Region": "us-west-2"
      }
    ]
  }
}'

# Claude API 직접 호출 테스트 (Kong 경유)
echo -e "\n[1] Mock 데이터로 Claude API 호출"
RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 1024,
    "messages": [{
      "role": "user",
      "content": "Analyze this AWS infrastructure: '"$(echo $MOCK_DATA | sed 's/"/\\"/g')"'"
    }]
  }')

echo "$RESPONSE" | jq . || echo "$RESPONSE"

# 마스킹 검증
echo -e "\n[2] 🔍 마스킹 검증"
if echo "$RESPONSE" | grep -qE "i-[0-9a-f]{17}|10\.[0-9]+\.[0-9]+\.[0-9]+|sg-[0-9a-f]{8}|subnet-[0-9a-f]{8}|ami-[0-9a-f]{8}"; then
  echo "❌ 위험: AWS 패턴이 마스킹되지 않음!"
  echo "$RESPONSE" | grep -E "i-[0-9a-f]{17}|10\.[0-9]+\.[0-9]+\.[0-9]+|sg-[0-9a-f]{8}|subnet-[0-9a-f]{8}|ami-[0-9a-f]{8}"
else
  echo "✅ 안전: AWS 패턴이 마스킹됨"
fi

echo -e "\n================================================"