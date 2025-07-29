# Kong AWS Masker 실시간 모니터링 - 테스트 및 검증

## 📋 목차
1. [단위 테스트](#단위-테스트)
2. [통합 테스트](#통합-테스트)
3. [성능 테스트](#성능-테스트)
4. [보안 테스트](#보안-테스트)
5. [시나리오 테스트](#시나리오-테스트)
6. [트러블슈팅](#트러블슈팅)

---

## 🧪 단위 테스트

### 1. Redis 연결 테스트

#### 1.1 Kong 플러그인에서 Redis 연결 확인
```bash
# Kong 컨테이너 접속
docker exec -it kong-gateway sh

# Lua 인터프리터로 테스트
kong eval '
local masker = require "kong.plugins.aws-masker.masker_ngx_re"
local red, err = masker.acquire_redis_connection()
if red then
  print("✅ Redis connection successful")
  masker.release_redis_connection(red)
else
  print("❌ Redis connection failed: " .. err)
end
'
```

#### 1.2 Backend에서 Redis 연결 확인
```bash
# 테스트 스크립트 생성
cat > backend/test-redis.js << 'EOF'
const redis = require('redis');

async function testRedis() {
    const client = redis.createClient({
        socket: {
            host: process.env.REDIS_HOST || 'redis',
            port: process.env.REDIS_PORT || 6379
        }
    });
    
    try {
        await client.connect();
        console.log('✅ Redis connection successful');
        
        // Pub/Sub 테스트
        await client.publish('test:channel', 'Hello Redis');
        console.log('✅ Publish test successful');
        
        await client.disconnect();
    } catch (error) {
        console.error('❌ Redis test failed:', error);
    }
}

testRedis();
EOF

# 테스트 실행
docker exec -it backend-api node test-redis.js
```

### 2. 이벤트 발행 테스트

#### 2.1 monitoring.lua 함수 테스트
```lua
-- Kong 컨테이너에서 실행
kong eval '
local monitoring = require "kong.plugins.aws-masker.monitoring"
local context = {
    success = true,
    elapsed_time = 15.5,
    pattern_count = 2,
    request_size = 1024
}

-- 환경변수 설정 시뮬레이션
os.setenv("ENABLE_REDIS_EVENTS", "true")

-- 이벤트 발행
monitoring.publish_masking_event("data_masked", context)
print("✅ Event published")
'
```

---

## 🔗 통합 테스트

### 1. 전체 시스템 통합 테스트

#### 1.1 환경 준비
```bash
# 환경변수 설정
export ENABLE_REDIS_EVENTS=true
export ANTHROPIC_API_KEY=your-api-key

# 시스템 재시작
docker-compose down
docker-compose up -d

# 로그 모니터링 시작
docker-compose logs -f backend-api | grep -E "(Kong 마스킹|Redis subscriber)"
```

#### 1.2 간단한 마스킹 테스트
```bash
# 테스트 요청 전송
curl -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "Test with EC2 instance i-1234567890abcdef0"
    }],
    "max_tokens": 100
  }'
```

#### 1.3 복합 패턴 테스트
```bash
# 여러 AWS 리소스가 포함된 요청
curl -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "Analyze infrastructure: EC2 i-1234567890abcdef0, S3 bucket my-secure-bucket, RDS database-prod-001, Private IP 10.0.1.100"
    }],
    "max_tokens": 200
  }'
```

### 2. 이벤트 흐름 검증

#### 2.1 Redis 모니터링
```bash
# Redis 이벤트 모니터링
docker exec -it redis-cache redis-cli monitor | grep -E "(PUBLISH|kong:masking)"
```

#### 2.2 Kong 로그 확인
```bash
# Kong 디버그 로그
docker-compose logs kong-gateway | grep -E "(Monitoring|Event published)"
```

---

## ⚡ 성능 테스트

### 1. 부하 테스트

#### 1.1 연속 요청 테스트
```bash
# 부하 테스트 스크립트
cat > test-load.sh << 'EOF'
#!/bin/bash

echo "🔥 Starting load test..."
echo "Sending 100 requests..."

for i in {1..100}; do
  echo -n "Request $i: "
  
  time curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"Test $i: EC2 i-test${i}abcdef0\"
      }],
      \"max_tokens\": 50
    }" > /dev/null
  
  if [ $? -eq 0 ]; then
    echo "✅"
  else
    echo "❌"
  fi
  
  # 짧은 대기
  sleep 0.1
done

echo "✅ Load test completed"
EOF

chmod +x test-load.sh
./test-load.sh
```

#### 1.2 동시 요청 테스트
```bash
# Apache Bench 사용 (설치 필요)
ab -n 100 -c 10 -p request.json -T "application/json" \
   -H "x-api-key: ${ANTHROPIC_API_KEY}" \
   http://localhost:8000/analyze-claude
```

### 2. 성능 메트릭 수집

#### 2.1 시스템 리소스 모니터링
```bash
# 실시간 리소스 모니터링
watch -n 1 'docker stats --no-stream | grep -E "(NAME|kong|backend|redis)"'
```

#### 2.2 Redis 성능 확인
```bash
# Redis 메모리 사용량
docker exec -it redis-cache redis-cli info memory | grep -E "(used_memory_human|used_memory_peak_human)"

# Redis 명령 통계
docker exec -it redis-cache redis-cli info commandstats | grep -E "(publish|get|set)"
```

---

## 🔒 보안 테스트

### 1. Redis 인증 테스트

#### 1.1 비밀번호 설정 확인
```bash
# Redis 비밀번호 설정
export REDIS_PASSWORD=secure_password_123

# docker-compose.yml 업데이트 후 재시작
docker-compose down
docker-compose up -d

# 인증 테스트
docker exec -it redis-cache redis-cli -a ${REDIS_PASSWORD} ping
```

### 2. 실패 시나리오 테스트

#### 2.1 Redis 중단 테스트
```bash
# Redis 중단
docker stop redis-cache

# Kong 요청 테스트 (정상 동작해야 함)
curl -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d '{"model": "claude-3-5-sonnet-20241022", "messages": [{"role": "user", "content": "Test"}]}'

# Redis 재시작
docker start redis-cache
```

#### 2.2 네트워크 장애 시뮬레이션
```bash
# 네트워크 지연 추가
docker exec -it kong-gateway tc qdisc add dev eth0 root netem delay 1000ms

# 테스트 후 제거
docker exec -it kong-gateway tc qdisc del dev eth0 root
```

---

## 🎬 시나리오 테스트

### 1. 실제 사용 시나리오

#### 1.1 AWS 인프라 분석 요청
```bash
# 실제 AWS 리소스 패턴 테스트
cat > real-test.json << 'EOF'
{
  "model": "claude-3-5-sonnet-20241022",
  "messages": [{
    "role": "user",
    "content": "Please analyze this AWS infrastructure:\n\nEC2 Instances:\n- Production: i-0123456789abcdef0 (10.0.1.100)\n- Staging: i-0987654321fedcba0 (10.0.2.100)\n\nRDS Databases:\n- Primary: database-prod-master\n- Replica: database-prod-replica\n\nS3 Buckets:\n- my-app-static-assets\n- my-app-backups-2024\n\nVPC: vpc-12345678\nSubnet: subnet-87654321\n\nPlease provide security recommendations."
  }],
  "max_tokens": 500
}
EOF

# 요청 전송 및 응답 저장
curl -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d @real-test.json | jq . > response.json

# 마스킹 확인
echo "🔍 Checking masking..."
grep -E "(i-[0-9a-f]+|10\.[0-9]+\.[0-9]+\.[0-9]+|database-|my-app-)" response.json || echo "✅ All patterns masked"
```

#### 1.2 연속 대화 시나리오
```bash
# 대화 컨텍스트 유지 테스트
for i in {1..3}; do
  echo "=== Conversation turn $i ==="
  
  curl -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"messages\": [
        {\"role\": \"user\", \"content\": \"Remember EC2 instance i-prod${i}1234567890\"},
        {\"role\": \"assistant\", \"content\": \"I'll remember that instance.\"},
        {\"role\": \"user\", \"content\": \"What was the instance ID?\"}
      ],
      \"max_tokens\": 100
    }"
  
  echo -e "\n"
  sleep 2
done
```

### 2. 검증 체크리스트

#### 2.1 기능 검증
- [ ] 마스킹 이벤트가 Backend 콘솔에 표시됨
- [ ] 언마스킹 이벤트가 Backend 콘솔에 표시됨
- [ ] 요청 ID가 올바르게 추적됨
- [ ] 패턴 사용 통계가 정확함
- [ ] 처리 시간이 올바르게 측정됨

#### 2.2 성능 검증
- [ ] 평균 응답 시간 < 10초
- [ ] Redis 이벤트 지연 < 10ms
- [ ] CPU 사용률 증가 < 5%
- [ ] 메모리 사용 증가 < 50MB

#### 2.3 안정성 검증
- [ ] Redis 중단 시 서비스 정상 동작
- [ ] 100개 연속 요청 성공
- [ ] 메모리 누수 없음
- [ ] 로그 에러 없음

---

## 🔧 트러블슈팅

### 1. 일반적인 문제 해결

#### 1.1 이벤트가 표시되지 않음
```bash
# 1. 환경변수 확인
docker exec -it kong-gateway sh -c 'echo $ENABLE_REDIS_EVENTS'
docker exec -it backend-api sh -c 'echo $ENABLE_REDIS_EVENTS'

# 2. Redis 구독 상태 확인
docker exec -it redis-cache redis-cli pubsub channels

# 3. Kong 로그 레벨 상향
docker exec -it kong-gateway kong log debug
```

#### 1.2 Redis 연결 실패
```bash
# 1. Redis 상태 확인
docker-compose ps redis-cache

# 2. 네트워크 연결 테스트
docker exec -it kong-gateway ping -c 3 redis

# 3. Redis 로그 확인
docker-compose logs redis-cache --tail=50
```

### 2. 디버깅 도구

#### 2.1 실시간 이벤트 모니터링
```bash
# Redis 이벤트 스트림 모니터링
docker exec -it redis-cache redis-cli subscribe "kong:masking:events"
```

#### 2.2 Kong 디버그 모드
```bash
# Kong 상세 로그 활성화
docker exec -it kong-gateway kong log debug
docker-compose logs -f kong-gateway | grep -E "(AWS-MASKER|Monitoring)"
```

### 3. 성능 프로파일링

#### 3.1 Kong 플러그인 성능
```bash
# Kong Admin API로 플러그인 메트릭 조회
curl -s http://localhost:8001/plugins | jq '.data[] | select(.name=="aws-masker")'
```

#### 3.2 Redis 레이턴시 측정
```bash
# Redis 레이턴시 모니터링
docker exec -it redis-cache redis-cli --latency

# Redis 슬로우 로그
docker exec -it redis-cache redis-cli slowlog get 10
```

---

## 📊 테스트 보고서 템플릿

### 테스트 실행 결과
```markdown
## 테스트 실행 보고서

**일시**: 2025-07-24
**환경**: Docker Compose Local
**버전**: Kong 3.7, Redis 7-alpine

### 기능 테스트
- [x] Redis 연결: ✅ 성공
- [x] 이벤트 발행: ✅ 성공  
- [x] 이벤트 구독: ✅ 성공
- [x] 콘솔 출력: ✅ 성공

### 성능 테스트
- 평균 응답 시간: 8.5초
- Redis 이벤트 지연: 3ms
- CPU 사용률 증가: 2%
- 메모리 사용 증가: 25MB

### 안정성 테스트
- 100회 연속 요청: ✅ 100% 성공
- Redis 장애 복구: ✅ 정상
- 24시간 연속 실행: ✅ 안정

### 이슈 및 개선사항
- 없음
```

---

*이 문서는 실시간 모니터링 시스템의 완전한 테스트 및 검증 절차를 제공합니다.*