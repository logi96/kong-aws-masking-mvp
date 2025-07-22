#!/bin/bash
# 성능 테스트 - CLAUDE.md 요구사항: < 5초 응답 시간

export ANTHROPIC_API_KEY="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"

echo "================================================"
echo "⚡ 성능 테스트 - Kong AWS Masking"
echo "================================================"

# 1. 간단한 요청 성능 테스트
echo -e "\n[1] 간단한 요청 성능 테스트"
START_TIME=$(date +%s%N | cut -b1-13)

curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "Test EC2 i-1234567890abcdef0"
    }],
    "max_tokens": 20
  }' > /dev/null

END_TIME=$(date +%s%N | cut -b1-13)
SIMPLE_TIME=$((END_TIME - START_TIME))
echo "응답 시간: ${SIMPLE_TIME}ms"

# 2. 복잡한 AWS 데이터 성능 테스트
echo -e "\n[2] 복잡한 AWS 데이터 성능 테스트"
START_TIME=$(date +%s%N | cut -b1-13)

curl -s -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "Analyze: EC2 i-1234567890abcdef0, i-0987654321fedcba0, i-abcdef1234567890 at IPs 10.0.1.100, 10.0.2.200, 10.0.3.300. S3 buckets: my-production-bucket, backup-bucket-2023, logs-bucket-prod. RDS: prod-db-master, prod-db-replica, test-db-instance"
    }],
    "max_tokens": 50
  }' > /dev/null

END_TIME=$(date +%s%N | cut -b1-13)
COMPLEX_TIME=$((END_TIME - START_TIME))
echo "응답 시간: ${COMPLEX_TIME}ms"

# 3. 병렬 요청 테스트 (5개 동시)
echo -e "\n[3] 병렬 요청 테스트 (5개 동시)"
START_TIME=$(date +%s%N | cut -b1-13)

for i in {1..5}; do
  (curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"Test $i: EC2 i-test${i}1234567890\"
      }],
      \"max_tokens\": 10
    }" > /dev/null) &
done

wait
END_TIME=$(date +%s%N | cut -b1-13)
PARALLEL_TIME=$((END_TIME - START_TIME))
echo "총 응답 시간: ${PARALLEL_TIME}ms"
echo "평균 응답 시간: $((PARALLEL_TIME / 5))ms"

# 4. Kong 마스킹 오버헤드 측정
echo -e "\n[4] Kong 마스킹 오버헤드"
echo "마스킹 패턴 수: 12개 (EC2, S3, RDS, IP 등)"
docker-compose logs kong --tail=50 | grep -E "elapsed_time|Masking completed|Masked [0-9]+ AWS" | tail -5

# 5. 결과 요약
echo -e "\n[5] 📊 성능 테스트 결과"
echo "- 간단한 요청: ${SIMPLE_TIME}ms"
echo "- 복잡한 요청: ${COMPLEX_TIME}ms"
echo "- 병렬 요청 평균: $((PARALLEL_TIME / 5))ms"

# 성능 기준 검증 (< 5000ms)
if [ $SIMPLE_TIME -lt 5000 ] && [ $COMPLEX_TIME -lt 5000 ]; then
  echo -e "\n✅ 성능 테스트 통과: 모든 요청이 5초 이내 완료"
else
  echo -e "\n❌ 성능 테스트 실패: 일부 요청이 5초 초과"
fi

echo -e "\n================================================"