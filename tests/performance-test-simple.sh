#!/bin/bash
# 간단한 성능 테스트

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "⚡ 성능 테스트 - Kong AWS Masking"
echo "================================================"

# 1. 간단한 요청
echo -e "\n[1] 간단한 요청 테스트"
# REMOVED - Wrong pattern: time curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "Test EC2 i-1234567890abcdef0"
    }],
    "max_tokens": 20
  }' | jq -r '.content[0].text' | head -1

# 2. 복잡한 요청
echo -e "\n[2] 복잡한 AWS 데이터 테스트"
# REMOVED - Wrong pattern: time curl -s -X POST http://localhost:3000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "List: EC2 i-1234567890abcdef0, i-0987654321fedcba0, i-abcdef1234567890 at 10.0.1.100, 10.0.2.200, 10.0.3.300. S3: my-production-bucket, backup-bucket-2023. RDS: prod-db-master"
    }],
    "max_tokens": 30
  }' | jq -r '.content[0].text' | head -1

# 3. 마스킹 로그 확인
echo -e "\n[3] 마스킹 통계"
docker-compose logs kong --tail=30 | grep -E "Masking completed|Masked [0-9]+" | tail -3

echo -e "\n✅ 성능 테스트 참고: 각 요청의 real time이 5초 미만이면 성공"
echo "================================================"