# Kong AWS Masker 실시간 모니터링 - 중요 문제점 분석

## 🚨 개요

작성된 구현 가이드를 냉철하게 검토한 결과, 실제 구현 시 발생할 수 있는 여러 기술적 문제점들을 발견했습니다. 이 문서는 발견된 문제점들을 심각도별로 분류하고 해결방안을 제시합니다.

---

## 🔴 심각도: 높음 (Critical)

### 1. Redis 연결 획득/해제 경쟁 조건 (Race Condition)

#### 문제점
```lua
-- monitoring.lua의 제안된 코드
local red, err = masker.acquire_redis_connection()
if not red then
    return  -- Fire-and-forget
end

-- 이벤트 발행
red:publish(REDIS_CONFIG.channel, cjson.encode(event))

-- 연결 반환
masker.release_redis_connection(red)
```

**문제**: `handler.lua`의 ACCESS 단계에서도 Redis 연결을 사용하고 있는데, 같은 요청 내에서 monitoring.lua가 또 다른 Redis 연결을 획득하려 하면 연결 풀 고갈이나 데드락이 발생할 수 있습니다.

#### 영향도
- 높은 동시성 상황에서 Redis 연결 풀 고갈
- 요청 처리 지연 또는 실패
- 최악의 경우 Kong 프로세스 행업

#### 해결방안
```lua
-- 기존 연결 재사용 방식으로 수정
function monitoring.publish_masking_event(event_type, context, existing_redis)
    if not REDIS_CONFIG.enabled then
        return
    end
    
    -- 기존 연결이 있으면 재사용
    local red = existing_redis
    local need_release = false
    
    if not red then
        red, err = masker.acquire_redis_connection()
        if not red then
            kong.log.debug("[Monitoring] Redis unavailable: ", err)
            return
        end
        need_release = true
    end
    
    -- 이벤트 발행
    local ok, err = red:publish(REDIS_CONFIG.channel, cjson.encode(event))
    
    -- 새로 획득한 경우에만 해제
    if need_release then
        masker.release_redis_connection(red)
    end
end
```

### 2. body_filter의 get_raw_body() 성능 문제

#### 문제점
현재 `handler.lua`는 `kong.response.get_raw_body()`를 사용하는데, 이는 전체 응답을 메모리에 버퍼링합니다.

```lua
function AwsMaskerHandler:body_filter(conf)
  local chunk = kong.response.get_raw_body()  -- 전체 응답 버퍼링
```

**문제**: 
- 대용량 응답 시 메모리 사용량 급증
- Kong의 기본 body 크기 제한(8MB)을 초과하면 실패
- 스트리밍 응답 불가능

#### 영향도
- 대용량 응답 처리 불가
- 메모리 부족으로 인한 서비스 중단
- 응답 지연 증가

#### 해결방안
```lua
function AwsMaskerHandler:body_filter(conf)
  -- 청크 단위 처리 방식으로 변경
  local chunk = kong.arg[1]  -- 현재 청크
  local eof = kong.arg[2]    -- 마지막 청크 여부
  
  if not eof then
    -- 청크 누적
    kong.ctx.plugin.body_buffer = (kong.ctx.plugin.body_buffer or "") .. chunk
    return
  end
  
  -- 마지막 청크에서만 처리
  local full_body = kong.ctx.plugin.body_buffer .. chunk
  -- 언마스킹 처리...
  
  -- 언마스킹 이벤트는 한 번만 발행
  if kong.ctx.plugin.unmask_event_sent then
    return
  end
  kong.ctx.plugin.unmask_event_sent = true
  
  -- 이벤트 발행...
end
```

---

## 🟠 심각도: 중간 (Major)

### 3. 성능 영향 과소평가

#### 문제점
문서에서는 "성능 영향 < 1%"라고 주장하지만, 실제로는:

1. **매 요청마다 Redis publish**: 네트워크 RTT 추가 (최소 1-5ms)
2. **JSON 인코딩 오버헤드**: 패턴 정보가 많을 경우 상당한 CPU 사용
3. **Redis 연결 획득/해제**: 연결 풀 관리 오버헤드

#### 실제 성능 영향 예측
```
기본 요청 처리: 10ms
+ Redis 연결 획득: 0.5ms
+ JSON 인코딩: 0.5ms
+ Redis publish: 2ms (네트워크 RTT)
+ 연결 해제: 0.5ms
= 총 13.5ms (35% 증가)
```

#### 해결방안
```lua
-- 1. 배치 처리 방식
local event_buffer = {}
local last_flush = ngx.now()

function monitoring.buffer_event(event)
    table.insert(event_buffer, event)
    
    -- 100개 또는 1초마다 플러시
    if #event_buffer >= 100 or (ngx.now() - last_flush) > 1 then
        monitoring.flush_events()
    end
end

-- 2. 샘플링 적용
function monitoring.should_publish_event()
    -- 10% 샘플링
    return math.random() < 0.1
end
```

### 4. 환경변수 의존성 문제

#### 문제점
`os.getenv("ENABLE_REDIS_EVENTS")`는 Kong이 시작될 때의 환경변수만 읽을 수 있고, 런타임 변경이 불가능합니다.

#### 영향도
- 기능 활성화/비활성화를 위해 Kong 재시작 필요
- 동적 설정 변경 불가능

#### 해결방안
```lua
-- Kong 플러그인 설정으로 이동
-- schema.lua에 추가
{
  enable_redis_events = {
    type = "boolean",
    default = false,
    description = "Enable Redis event publishing for real-time monitoring"
  }
},
{
  redis_event_channel = {
    type = "string",
    default = "kong:masking:events",
    description = "Redis channel for publishing events"
  }
}

-- monitoring.lua 수정
function monitoring.publish_masking_event(event_type, context, config)
    if not config.enable_redis_events then
        return
    end
    -- ...
end
```

### 5. 보안 및 프라이버시 우려

#### 문제점
1. **마스킹된 데이터 노출**: 콘솔 로그에 마스킹된 ID가 출력됨
2. **패턴 정보 노출**: 사용된 패턴 정보가 로그에 기록됨
3. **요청 ID 추적**: 요청을 추적할 수 있는 정보 노출

#### 영향도
- 보안 감사 실패 가능성
- GDPR/개인정보보호법 위반 위험
- 내부 시스템 구조 노출

#### 해결방안
```javascript
// redisSubscriber.js 수정
logMaskingEvent(event) {
    // 프로덕션에서는 최소 정보만 로깅
    if (process.env.NODE_ENV === 'production') {
        console.log(`[${event.event_type}] ${event.request_id} - ${event.details.processing_time_ms}ms`);
        return;
    }
    
    // 개발 환경에서만 상세 로깅
    // ... 기존 상세 로깅 코드 ...
}
```

---

## 🟡 심각도: 낮음 (Minor)

### 6. Redis Pub/Sub 메시지 손실 가능성

#### 문제점
Redis Pub/Sub은 "fire-and-forget" 모델로, 구독자가 없거나 일시적으로 연결이 끊어지면 메시지가 손실됩니다.

#### 해결방안
```lua
-- Redis Streams 사용 고려
local ok, err = red:xadd("masking:events:stream", "*", 
    "event_type", event_type,
    "data", cjson.encode(event)
)
```

### 7. 로그 폭증 위험

#### 문제점
고트래픽 상황에서 콘솔 로그가 과도하게 생성되어 디스크 공간을 소진할 수 있습니다.

#### 해결방안
```javascript
// 로그 제한 적용
const LOG_RATE_LIMIT = 100; // 초당 최대 로그 수
let logCount = 0;
let lastReset = Date.now();

function rateLimitedLog(message) {
    const now = Date.now();
    if (now - lastReset > 1000) {
        logCount = 0;
        lastReset = now;
    }
    
    if (logCount < LOG_RATE_LIMIT) {
        console.log(message);
        logCount++;
    }
}
```

### 8. 모듈 의존성 복잡도 증가

#### 문제점
monitoring.lua가 masker_ngx_re.lua를 require하면서 의존성이 복잡해집니다.

#### 해결방안
- 의존성 주입 패턴 사용
- 인터페이스 분리 원칙 적용

---

## 📊 위험도 매트릭스

| 문제점 | 발생 가능성 | 영향도 | 위험도 | 우선순위 |
|--------|------------|--------|--------|----------|
| Redis 연결 경쟁 조건 | 높음 | 심각 | 🔴 매우 높음 | 1 |
| body_filter 성능 | 중간 | 높음 | 🔴 높음 | 2 |
| 성능 영향 과소평가 | 높음 | 중간 | 🟠 중간 | 3 |
| 환경변수 의존성 | 낮음 | 중간 | 🟡 낮음 | 4 |
| 보안/프라이버시 | 중간 | 중간 | 🟠 중간 | 5 |

---

## 🛠️ 권장 구현 순서

### Phase 1: 핵심 문제 해결 (필수)
1. Redis 연결 관리 개선
2. body_filter 청크 처리 구현
3. 플러그인 설정 기반으로 변경

### Phase 2: 성능 최적화 (권장)
1. 이벤트 샘플링 구현
2. 배치 처리 방식 도입
3. 로그 레이트 제한

### Phase 3: 운영 안정성 (선택)
1. Redis Streams 마이그레이션
2. 모니터링 대시보드 구축
3. 상세 메트릭 수집

---

## 🔍 테스트 시나리오 추가

### 부하 테스트
```bash
# 1000 TPS 부하 테스트
ab -n 10000 -c 100 -p request.json -T application/json \
   http://localhost:8000/analyze-claude

# Redis 연결 풀 모니터링
watch -n 1 'redis-cli client list | wc -l'
```

### 대용량 응답 테스트
```bash
# 10MB 응답 생성 테스트
curl -X POST http://localhost:8000/test/large-response
```

### 장애 시나리오
```bash
# Redis 연결 수 제한
redis-cli config set maxclients 10

# 네트워크 지연 시뮬레이션
tc qdisc add dev eth0 root netem delay 100ms
```

---

## 💡 결론

제안된 구현은 기능적으로는 작동하지만, 프로덕션 환경에서는 여러 기술적 문제가 발생할 수 있습니다. 특히:

1. **Redis 연결 관리**는 반드시 개선 필요
2. **성능 영향**은 재평가 필요 (실제 10-30% 증가 예상)
3. **보안 고려사항**은 환경별로 다르게 적용 필요

이러한 문제들을 해결하지 않고 배포할 경우, 서비스 안정성에 심각한 영향을 미칠 수 있습니다.

---

*이 분석은 실제 프로덕션 환경에서의 경험을 바탕으로 작성되었습니다.*