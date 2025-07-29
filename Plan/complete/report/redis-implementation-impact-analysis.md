# Redis 도입 영향도 분석 보고서

## 요약
- **영향도**: 낮음 ~ 중간 (★★☆☆☆)
- **예상 작업량**: 3-5일
- **권장사항**: PostgreSQL DB 모드보다 **Redis가 훨씬 간단하고 효율적**

## 1. Redis vs PostgreSQL DB 모드 비교

### 구현 복잡도 비교
| 항목 | Redis | PostgreSQL DB 모드 |
|------|-------|-------------------|
| **코드 수정량** | 약 170줄 | 1,000줄 이상 |
| **작업 기간** | 3-5일 | 2-3주 |
| **아키텍처 변경** | 최소 | 전면 재설계 |
| **위험도** | 낮음 | 매우 높음 |

### 성능 비교
```
현재 (메모리)    : ~0.01ms
Redis 도입      : 1-2ms (100배 느림, 그러나 여전히 빠름)
PostgreSQL DB   : 5-10ms (500-1000배 느림)
```

## 2. Redis 구현 방안

### 2.1 Docker Compose 추가 (20줄)
```yaml
services:
  redis:
    image: redis:7-alpine
    container_name: redis-cache
    command: redis-server --save 60 1 --loglevel warning
    volumes:
      - redis-data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M

volumes:
  redis-data:
    driver: local
```

### 2.2 주요 코드 수정 (약 150줄)

#### masker_ngx_re.lua 수정 예시
```lua
local redis = require "resty.redis"

-- Redis 연결 함수
function _M.get_redis_connection()
  local red = redis:new()
  red:set_timeouts(1000, 1000, 1000) -- 1초 타임아웃
  
  local ok, err = red:connect("redis", 6379)
  if not ok then
    return nil, err
  end
  
  return red
end

-- 매핑 저장 (현재 메모리 → Redis)
function _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
  local red = mapping_store.redis
  if not red then
    -- Fallback to memory
    return _M._get_or_create_masked_id_memory(original_value, pattern_def, mapping_store)
  end
  
  -- Redis key 생성
  local reverse_key = "aws:reverse:" .. ngx.encode_base64(original_value)
  
  -- 기존 매핑 확인
  local masked_id = red:get(reverse_key)
  if masked_id and masked_id ~= ngx.null then
    return masked_id
  end
  
  -- 새 매핑 생성 (원자적 카운터)
  local counter_key = "aws:counter:" .. pattern_def.type
  local counter = red:incr(counter_key)
  masked_id = string.format(pattern_def.replacement, counter)
  
  -- 양방향 매핑 저장 (TTL 적용)
  local ttl = mapping_store.ttl or 604800 -- 7일
  red:setex("aws:mapping:" .. masked_id, ttl, original_value)
  red:setex(reverse_key, ttl, masked_id)
  
  return masked_id
end
```

### 2.3 Hybrid 접근법 (Fallback 지원)
```lua
function _M.create_mapping_store(options)
  -- Redis 연결 시도
  local red, err = _M.get_redis_connection()
  if red then
    return {
      type = "redis",
      redis = red,
      ttl = options.ttl or 604800
    }
  end
  
  -- Redis 실패 시 메모리 사용
  kong.log.warn("Redis unavailable, using in-memory store: " .. err)
  return {
    type = "memory",
    mappings = {},
    counters = {},
    ttl = options.ttl or 3600
  }
end
```

## 3. 운영 측면 비교

### 3.1 Redis 운영
**장점**:
- 단순한 Key-Value 구조
- 자동 TTL 관리 (EXPIRE 명령)
- RDB/AOF 백업 지원
- Redis Commander로 쉬운 모니터링
- Kong과 독립적 운영

**필요 작업**:
- Redis 메모리 모니터링
- 주기적 백업 설정
- maxmemory-policy 설정

### 3.2 PostgreSQL DB 모드 운영
**단점**:
- 복잡한 스키마 관리
- Kong 버전 업그레이드 시 마이그레이션
- Kong Admin API 필수
- 백업/복구 복잡
- 성능 튜닝 어려움

## 4. 성능 영향 분석

### 4.1 응답 시간 영향
```
현재 전체 응답 시간: ~100ms
├─ 마스킹 처리: 0.01ms (0.01%)
└─ 기타 처리: 99.99ms

Redis 도입 후: ~102ms (+2%)
├─ 마스킹 처리: 2ms (2%)
└─ 기타 처리: 100ms

PostgreSQL DB 모드: ~110ms (+10%)
├─ 마스킹 처리: 10ms (9%)
└─ 기타 처리: 100ms
```

### 4.2 확장성
- **Redis**: 모든 Kong worker가 동일 데이터 공유
- **현재**: Worker별 독립 데이터 (불일치 가능)
- **DB 모드**: 무겁고 복잡한 동기화

## 5. 구현 로드맵

### Phase 1: MVP 유지 (현재)
- In-Memory 방식 유지
- TTL 24시간으로 증가
- 모니터링으로 실사용 패턴 파악

### Phase 2: Redis 도입 (권장)
**작업 기간**: 3-5일
1. Docker Compose에 Redis 추가 (0.5일)
2. masker_ngx_re.lua 수정 (2일)
3. Fallback 로직 구현 (0.5일)
4. 테스트 및 검증 (1-2일)

### Phase 3: Redis 최적화 (선택)
- Pipeline으로 배치 처리
- Lua 스크립트로 원자적 연산
- Read replica 추가

## 6. 결론

### Redis가 PostgreSQL DB 모드보다 우수한 이유

1. **10배 간단한 구현**
   - Redis: 170줄 수정
   - DB 모드: 1,000줄 이상 + 아키텍처 변경

2. **5배 빠른 성능**
   - Redis: 1-2ms
   - DB 모드: 5-10ms

3. **독립적 운영**
   - Redis: Kong과 분리
   - DB 모드: Kong 라이프사이클에 종속

4. **낮은 위험도**
   - Redis: Fallback 가능
   - DB 모드: 전체 시스템 영향

### 최종 권장사항

**현재 MVP 단계**: In-Memory 유지
**프로덕션 전환 시**: Redis 도입 (3-5일이면 충분)
**피해야 할 선택**: PostgreSQL DB 모드 (과도한 복잡도)

Redis는 최소한의 코드 변경으로 데이터 영속성과 확장성을 제공하는 최적의 선택입니다.

---

**보고서 작성일**: 2025년 7월 23일  
**작성자**: Claude Assistant  
**결론**: Redis 도입은 간단하고 효율적인 해결책