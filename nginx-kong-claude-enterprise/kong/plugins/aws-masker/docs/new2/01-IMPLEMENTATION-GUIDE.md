# Kong AWS Masker 실시간 모니터링 - 구현 가이드

## 📋 목차
1. [사전 준비](#사전-준비)
2. [Kong 플러그인 확장](#kong-플러그인-확장)
3. [Backend 서비스 구현](#backend-서비스-구현)
4. [통합 및 설정](#통합-및-설정)
5. [검증](#검증)

---

## 🔧 사전 준비

### 필수 확인 사항
```bash
# Kong 플러그인 위치 확인
ls -la kong/plugins/aws-masker/

# Redis 연결 확인
docker exec -it redis-cache redis-cli ping
# 예상 출력: PONG

# Backend 환경 확인
cd backend && npm list express
# 예상 출력: express@4.18.2
```

### 작업 디렉토리 설정
```bash
# 프로젝트 루트로 이동
cd /Users/tw.kim/Documents/AGA/test/Kong

# 작업 브랜치 생성 (선택사항)
git checkout -b feature/real-time-monitoring
```

---

## 🔨 Kong 플러그인 확장

### Step 1: monitoring.lua 확장 (15분)

#### 1.1 파일 열기
```bash
vim kong/plugins/aws-masker/monitoring.lua
```

#### 1.2 상단에 필요한 모듈 import 추가
파일 상단 (line 5-6 근처)에 추가:
```lua
local masker = require "kong.plugins.aws-masker.masker_ngx_re"
local cjson = require "cjson"
```

#### 1.3 Redis Pub/Sub 설정 추가
`THRESHOLDS` 테이블 아래 (line 50 근처)에 추가:
```lua
-- Redis Pub/Sub 설정
local REDIS_CONFIG = {
    channel = "kong:masking:events",
    enabled = os.getenv("ENABLE_REDIS_EVENTS") == "true"
}
```

#### 1.4 이벤트 발행 함수 추가
파일 끝부분 (return monitoring 전)에 추가:
```lua
-- Redis Pub/Sub 이벤트 발행
function monitoring.publish_masking_event(event_type, context)
    -- 기능이 비활성화되면 즉시 반환
    if not REDIS_CONFIG.enabled then
        return
    end
    
    -- Redis 연결 획득
    local red, err = masker.acquire_redis_connection()
    if not red then
        kong.log.debug("[Monitoring] Redis unavailable for events: ", err)
        return  -- Fire-and-forget
    end
    
    -- 이벤트 데이터 구성
    local event = {
        timestamp = ngx.now(),
        event_type = event_type,
        request_id = kong.request.get_header("X-Kong-Request-Id") or 
                    kong.request.get_header("X-Request-Id") or 
                    ngx.var.request_id,
        service = kong.service and kong.service.name or "unknown",
        route = kong.route and kong.route.name or "unknown",
        details = {
            action = event_type == "data_masked" and "mask" or "unmask",
            processing_time_ms = context.elapsed_time or 0,
            pattern_count = context.pattern_count or 0,
            patterns_used = context.patterns_used or {},
            request_size = context.request_size or 0
        }
    }
    
    -- 이벤트 발행
    local ok, err = red:publish(REDIS_CONFIG.channel, cjson.encode(event))
    if not ok then
        kong.log.debug("[Monitoring] Failed to publish event: ", err)
    else
        kong.log.debug("[Monitoring] Event published: ", event_type)
    end
    
    -- Redis 연결 반환
    masker.release_redis_connection(red)
end
```

#### 1.5 기존 메트릭 수집 함수 확장
`collect_request_metric` 함수 끝부분 (line 96 근처)에 추가:
```lua
    -- 기존 메트릭 수집 후 이벤트 발행
    if context.success then
        monitoring.publish_masking_event("data_masked", context)
    end
```

### Step 2: handler.lua 수정 (10분)

#### 2.1 파일 열기
```bash
vim kong/plugins/aws-masker/handler.lua
```

#### 2.2 마스킹 컨텍스트 개선
`monitoring.collect_request_metric` 호출 부분 (line 254 근처) 수정:
```lua
monitoring.collect_request_metric({
    success = true,
    elapsed_time = elapsed_time,
    request_size = string.len(raw_body),
    pattern_count = mask_result.count,
    patterns_used = mask_result.patterns_used  -- 추가
})
```

#### 2.3 언마스킹 이벤트 추가
`body_filter` 함수 끝부분 (line 380 근처)에 추가:
```lua
-- 언마스킹 완료 이벤트
if mapping_store.type == "redis" and next(real_unmask_map) then
    local unmask_time = (ngx.now() - (kong.ctx.plugin.start_time or ngx.now())) * 1000
    monitoring.publish_masking_event("data_unmasked", {
        elapsed_time = unmask_time,
        pattern_count = 0,
        success = true
    })
    
    -- 언마스킹된 패턴 수 계산
    local unmask_count = 0
    for _ in pairs(real_unmask_map) do
        unmask_count = unmask_count + 1
    end
    
    monitoring.publish_masking_event("data_unmasked", {
        elapsed_time = unmask_time,
        pattern_count = unmask_count,
        success = true
    })
end
```

---

## 💻 Backend 서비스 구현

### Step 3: Redis 구독 서비스 생성 (20분)

#### 3.1 디렉토리 생성
```bash
mkdir -p backend/src/services/redis
```

#### 3.2 Redis 구독 서비스 파일 생성
```bash
vim backend/src/services/redis/redisSubscriber.js
```

파일 내용은 [02-CODE-CHANGES.md](./02-CODE-CHANGES.md)의 전체 코드 참조

#### 3.3 Redis 패키지 설치
```bash
cd backend
npm install redis@^4.6.7
```

### Step 4: Backend 앱 통합 (10분)

#### 4.1 app.js 수정
```bash
vim backend/src/app.js
```

#### 4.2 상단에 import 추가
```javascript
const RedisEventSubscriber = require('./services/redis/redisSubscriber');
```

#### 4.3 createApp 함수 내 Redis 구독 시작
`app.use(compression());` 아래에 추가:
```javascript
// Redis 이벤트 구독 (선택적)
if (process.env.ENABLE_REDIS_EVENTS === 'true') {
    const redisSubscriber = new RedisEventSubscriber();
    
    // 비동기 시작
    redisSubscriber.start().catch(err => {
        console.error('❌ Redis subscriber failed:', err);
        // 실패해도 서비스는 계속 실행
    });
    
    // Graceful shutdown 처리
    process.on('SIGTERM', async () => {
        console.log('📡 Shutting down Redis subscriber...');
        await redisSubscriber.stop();
    });
    
    process.on('SIGINT', async () => {
        console.log('📡 Shutting down Redis subscriber...');
        await redisSubscriber.stop();
    });
}
```

---

## ⚙️ 통합 및 설정

### Step 5: Docker 환경 설정 (5분)

#### 5.1 환경 변수 설정
`.env` 파일 수정:
```bash
echo "ENABLE_REDIS_EVENTS=true" >> .env
```

#### 5.2 docker-compose.yml 확인
Backend 서비스의 환경변수가 올바르게 전달되는지 확인:
```yaml
backend:
  environment:
    ENABLE_REDIS_EVENTS: ${ENABLE_REDIS_EVENTS:-false}
    REDIS_HOST: ${REDIS_HOST:-redis}
    REDIS_PORT: ${REDIS_PORT:-6379}
    REDIS_PASSWORD: ${REDIS_PASSWORD:-}
```

### Step 6: Kong 환경 변수 전달 (5분)

#### 6.1 Kong 컨테이너 환경변수 추가
`docker-compose.yml`의 Kong 서비스에 추가:
```yaml
kong:
  environment:
    ENABLE_REDIS_EVENTS: ${ENABLE_REDIS_EVENTS:-false}
```

---

## ✅ 검증

### Step 7: 시스템 재시작 및 테스트

#### 7.1 전체 시스템 재시작
```bash
# 프로젝트 루트에서
docker-compose down
docker-compose up -d
```

#### 7.2 로그 모니터링 시작
```bash
# 별도 터미널에서
docker-compose logs -f backend-api | grep "Kong 마스킹"
```

#### 7.3 테스트 요청 전송
```bash
# 다른 터미널에서
curl -X POST http://localhost:8000/analyze-claude \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{
      "role": "user",
      "content": "Analyze EC2 instance i-1234567890abcdef0"
    }]
  }'
```

#### 7.4 예상 로그 확인
Backend 로그에 다음과 같은 출력이 나타나야 함:
```
✅ Redis subscriber connected
📡 Subscribed to kong:masking:events

=== Kong 마스킹 이벤트 ===
시간: 2025-07-24T10:30:45.123Z
타입: data_masked
요청ID: f8a8660e-1843-4844
서비스: claude-api-service
✅ 마스킹 완료 (15ms)
패턴 수: 1
========================

=== Kong 마스킹 이벤트 ===
시간: 2025-07-24T10:30:47.456Z
타입: data_unmasked
요청ID: f8a8660e-1843-4844
서비스: claude-api-service
✅ 언마스킹 완료 (12ms)
========================
```

---

## 🔧 트러블슈팅

### Redis 연결 실패
```bash
# Redis 연결 테스트
docker exec -it backend-api sh -c "redis-cli -h redis ping"

# Redis 로그 확인
docker-compose logs redis-cache
```

### 이벤트가 표시되지 않음
```bash
# 환경변수 확인
docker exec -it kong-gateway sh -c "echo \$ENABLE_REDIS_EVENTS"
docker exec -it backend-api sh -c "echo \$ENABLE_REDIS_EVENTS"

# Kong 로그 확인
docker-compose logs kong-gateway | grep "Monitoring"
```

### 권한 문제
```bash
# 파일 권한 확인
ls -la kong/plugins/aws-masker/monitoring.lua
chmod 644 kong/plugins/aws-masker/monitoring.lua
```

---

## 📊 성능 모니터링

### 시스템 리소스 확인
```bash
# CPU 및 메모리 사용량
docker stats

# Redis 메모리 사용량
docker exec -it redis-cache redis-cli info memory | grep used_memory_human
```

### 이벤트 처리량 확인
```bash
# Redis 모니터링
docker exec -it redis-cache redis-cli monitor | grep PUBLISH
```

---

## 🎯 다음 단계

1. **[02-CODE-CHANGES.md](./02-CODE-CHANGES.md)** - 전체 코드 변경 내용 확인
2. **[03-TESTING-VALIDATION.md](./03-TESTING-VALIDATION.md)** - 상세 테스트 절차
3. **[04-DEPLOYMENT-CHECKLIST.md](./04-DEPLOYMENT-CHECKLIST.md)** - 프로덕션 배포 준비

---

*이 가이드를 따라 약 60분 내에 실시간 모니터링 시스템을 구현할 수 있습니다.*