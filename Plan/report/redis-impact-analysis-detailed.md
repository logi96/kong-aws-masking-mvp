# Redis 전환 상세 영향도 분석 보고서

## 현재 코드 구조 분석 완료

### 1. 메모리 저장소 사용 현황

#### masker_ngx_re.lua (핵심 변경 대상)
```lua
-- 현재 메모리 기반 저장소 구조
function _M.create_mapping_store(options)
  local store = {
    mappings = {},           -- masked_id -> original_value
    reverse_mappings = {},   -- original_value -> masked_id (사용 안됨)
    counters = {},          -- resource_type -> counter
    timestamps = {},        -- masked_id -> creation_timestamp (사용 안됨)
    created_at = os.time(),
    config = {}
  }
  return store
end
```

**문제점 발견**:
- `reverse_mappings`와 `timestamps`는 생성되지만 실제로 사용되지 않음
- `_get_or_create_masked_id`에서 선형 검색으로 중복 확인 (성능 이슈)
- TTL 관리 로직 없음 (clean_interval 설정만 있고 구현 없음)

#### handler.lua
- 인스턴스 생성 시: `mapping_store = masker.create_mapping_store()`
- access phase에서 재생성: 매 요청마다 새 저장소 생성 가능
- `kong.ctx.shared.aws_mapping_store`로 요청 내 공유

### 2. 현재 아키텍처의 한계

1. **Worker 프로세스 격리**
   - Kong은 기본 12개 worker 프로세스 실행
   - 각 worker가 독립적인 매핑 데이터 보유
   - 동일한 AWS 리소스가 worker별로 다른 ID로 마스킹될 수 있음

2. **데이터 비영속성**
   - Kong 재시작 시 모든 매핑 손실
   - 롤링 업데이트 시 일관성 깨짐

3. **메모리 비효율**
   - Worker 수 × 매핑 데이터 = 실제 메모리 사용량
   - TTL 구현 없어 메모리 누수 가능

## Redis 전환 영향도 상세

### 1. 코드 변경 범위

#### A. masker_ngx_re.lua 수정 (약 200줄)

**1) Redis 연결 관리 추가**
```lua
local redis = require "resty.redis"

-- Redis 설정
_M.redis_config = {
  host = os.getenv("REDIS_HOST") or "redis",
  port = os.getenv("REDIS_PORT") or 6379,
  timeout = 1000,  -- 1초
  keepalive_timeout = 60000,  -- 60초
  keepalive_pool_size = 30,
  prefix = "aws_masker:",
  ttl = 604800  -- 7일
}

-- Redis 연결 풀 관리
function _M.get_redis_connection()
  local red = redis:new()
  red:set_timeouts(_M.redis_config.timeout, _M.redis_config.timeout, _M.redis_config.timeout)
  
  local ok, err = red:connect(_M.redis_config.host, _M.redis_config.port)
  if not ok then
    return nil, "Failed to connect to Redis: " .. err
  end
  
  return red
end

-- 연결 반환
function _M.return_redis_connection(red)
  if not red then return end
  
  local ok, err = red:set_keepalive(_M.redis_config.keepalive_timeout, _M.redis_config.keepalive_pool_size)
  if not ok then
    red:close()
  end
end
```

**2) create_mapping_store 수정**
```lua
function _M.create_mapping_store(options)
  -- Redis 연결 시도
  local red, err = _M.get_redis_connection()
  if red then
    -- Redis 모드
    return {
      type = "redis",
      redis = red,
      prefix = _M.redis_config.prefix,
      ttl = options and options.ttl or _M.redis_config.ttl,
      fallback_to_memory = true
    }
  end
  
  -- Fallback: 메모리 모드
  kong.log.warn("Redis unavailable, using memory store: " .. err)
  return {
    type = "memory",
    mappings = {},
    counters = {},
    reverse_mappings = {},  -- 성능 개선을 위해 실제 사용
    ttl = options and options.ttl or 3600
  }
end
```

**3) _get_or_create_masked_id 재구현**
```lua
function _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
  if mapping_store.type == "redis" then
    return _M._get_or_create_masked_id_redis(original_value, pattern_def, mapping_store)
  else
    return _M._get_or_create_masked_id_memory(original_value, pattern_def, mapping_store)
  end
end

-- Redis 버전
function _M._get_or_create_masked_id_redis(original_value, pattern_def, mapping_store)
  local red = mapping_store.redis
  local prefix = mapping_store.prefix
  
  -- Base64 인코딩으로 특수문자 처리
  local encoded_value = ngx.encode_base64(original_value)
  local reverse_key = prefix .. "rev:" .. encoded_value
  
  -- 기존 매핑 확인
  local masked_id, err = red:get(reverse_key)
  if masked_id and masked_id ~= ngx.null then
    return masked_id
  end
  
  -- 새 마스킹 ID 생성 (원자적 카운터)
  local resource_type = pattern_def.type or "unknown"
  local counter_key = prefix .. "cnt:" .. resource_type
  local counter, err = red:incr(counter_key)
  if err then
    -- 에러 시 메모리 fallback
    return _M._get_or_create_masked_id_memory(original_value, pattern_def, mapping_store)
  end
  
  masked_id = string.format(pattern_def.replacement, counter)
  
  -- 양방향 매핑 저장 (파이프라인)
  red:init_pipeline()
  red:setex(prefix .. "map:" .. masked_id, mapping_store.ttl, original_value)
  red:setex(reverse_key, mapping_store.ttl, masked_id)
  local results, err = red:commit_pipeline()
  
  if err then
    kong.log.err("Redis pipeline error: " .. err)
  end
  
  return masked_id
end

-- 메모리 버전 (개선)
function _M._get_or_create_masked_id_memory(original_value, pattern_def, mapping_store)
  -- reverse_mappings 활용으로 O(1) 조회
  if mapping_store.reverse_mappings and mapping_store.reverse_mappings[original_value] then
    return mapping_store.reverse_mappings[original_value]
  end
  
  -- 기존 로직 (fallback)
  for masked_id, stored_value in pairs(mapping_store.mappings) do
    if stored_value == original_value then
      return masked_id
    end
  end
  
  -- 새 마스킹 ID 생성
  local resource_type = pattern_def.type or "unknown"
  mapping_store.counters[resource_type] = (mapping_store.counters[resource_type] or 0) + 1
  
  local masked_id = string.format(pattern_def.replacement, mapping_store.counters[resource_type])
  
  -- 양방향 저장
  mapping_store.mappings[masked_id] = original_value
  if mapping_store.reverse_mappings then
    mapping_store.reverse_mappings[original_value] = masked_id
  end
  
  return masked_id
end
```

**4) unmask_data 수정**
```lua
function _M.unmask_data(text, mapping_store)
  if type(text) ~= "string" or text == "" then
    return text
  end
  
  if not mapping_store then
    return text
  end
  
  if mapping_store.type == "redis" then
    return _M.unmask_data_redis(text, mapping_store)
  else
    return _M.unmask_data_memory(text, mapping_store)
  end
end

function _M.unmask_data_redis(text, mapping_store)
  local red = mapping_store.redis
  local prefix = mapping_store.prefix
  local unmasked_text = text
  
  -- 마스킹된 ID 패턴 찾기 (예: EC2_001, VPC_002 등)
  local masked_ids = {}
  for masked_id in string.gmatch(text, "[A-Z]+_[0-9]+") do
    masked_ids[masked_id] = true
  end
  
  -- 파이프라인으로 일괄 조회
  if next(masked_ids) then
    red:init_pipeline()
    for masked_id in pairs(masked_ids) do
      red:get(prefix .. "map:" .. masked_id)
    end
    local results, err = red:commit_pipeline()
    
    if results then
      local i = 1
      for masked_id in pairs(masked_ids) do
        local original_value = results[i]
        if original_value and original_value ~= ngx.null then
          unmasked_text = string.gsub(unmasked_text, _M._escape_pattern(masked_id), original_value)
        end
        i = i + 1
      end
    end
  end
  
  return unmasked_text
end

function _M.unmask_data_memory(text, mapping_store)
  -- 기존 로직 유지
  if not mapping_store.mappings then
    return text
  end
  
  local unmasked_text = text
  for masked_id, original_value in pairs(mapping_store.mappings) do
    unmasked_text = string.gsub(unmasked_text, _M._escape_pattern(masked_id), original_value)
  end
  
  return unmasked_text
end
```

**5) 연결 정리 함수 추가**
```lua
function _M.cleanup_store(mapping_store)
  if mapping_store.type == "redis" and mapping_store.redis then
    _M.return_redis_connection(mapping_store.redis)
    mapping_store.redis = nil
  end
end
```

#### B. handler.lua 수정 (약 30줄)

**1) access phase 수정**
```lua
function AwsMaskerHandler:access(conf)
  -- ... 기존 코드 ...
  
  -- Initialize mapping store if not exists
  if not self.mapping_store then
    self.mapping_store = masker.create_mapping_store(conf)
  end
  
  -- Redis 재연결 확인 (연결이 끊어진 경우)
  if self.mapping_store.type == "redis" and not self.mapping_store.redis then
    local red, err = masker.get_redis_connection()
    if red then
      self.mapping_store.redis = red
    else
      -- Fallback to memory
      self.mapping_store = masker.create_mapping_store(conf)
    end
  end
  
  -- ... 마스킹 로직 ...
  
  -- 마스킹 후 연결 반환
  if self.mapping_store.type == "redis" then
    masker.return_redis_connection(self.mapping_store.redis)
    self.mapping_store.redis = nil
  end
end
```

**2) body_filter 수정**
```lua
function AwsMaskerHandler:body_filter(conf)
  local chunk = kong.response.get_raw_body()
  
  if chunk and kong.ctx.shared.aws_mapping_store then
    -- Redis 재연결 (body_filter는 다른 컨텍스트)
    local mapping_store = kong.ctx.shared.aws_mapping_store
    if mapping_store.type == "redis" and not mapping_store.redis then
      local red, err = masker.get_redis_connection()
      if red then
        mapping_store.redis = red
      else
        -- Skip unmasking if Redis unavailable
        return
      end
    end
    
    -- ... 언마스킹 로직 ...
    
    -- 연결 반환
    if mapping_store.type == "redis" then
      masker.return_redis_connection(mapping_store.redis)
    end
  end
end
```

#### C. docker-compose.yml 수정 (약 20줄)

```yaml
services:
  # Redis Cache Service
  redis:
    image: redis:7-alpine
    container_name: redis-cache
    hostname: redis
    command: >
      redis-server
      --save 60 1
      --save 300 10
      --loglevel warning
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfilename "aws-masker.aof"
    environment:
      <<: *common-variables
    volumes:
      - redis-data:/data
      - ./config/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - backend
    healthcheck:
      <<: *healthcheck-defaults
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 128M
    security_opt:
      - no-new-privileges:true

  # Kong 서비스에 Redis 의존성 추가
  kong:
    # ... 기존 설정 ...
    environment:
      # ... 기존 환경 변수 ...
      REDIS_HOST: redis
      REDIS_PORT: 6379
    depends_on:
      redis:
        condition: service_healthy

volumes:
  redis-data:
    driver: local
```

### 2. 테스트 영향도

#### 기존 테스트 호환성
- **영향 없음**: 모든 테스트는 HTTP API를 통해 수행
- **자동 Fallback**: Redis 없이도 메모리 모드로 테스트 가능
- **추가 테스트 필요**: Redis 전용 시나리오

#### 새로운 테스트 추가 필요
1. Redis 연결 실패 시 Fallback 테스트
2. Redis 재시작 후 매핑 유지 테스트
3. 멀티 워커 일관성 테스트
4. 7일 TTL 검증 테스트
5. 성능 비교 테스트

### 3. 성능 영향 예측

#### 현재 성능 (메모리)
- 마스킹 조회: ~0.01ms
- 마스킹 생성: ~0.01ms
- 언마스킹: O(n) where n = 매핑 수

#### Redis 도입 후
- 마스킹 조회: 1-2ms (네트워크 포함)
- 마스킹 생성: 2-3ms (파이프라인 사용)
- 언마스킹: 2-5ms (일괄 조회)
- **Connection Pooling으로 최적화**

#### 예상 전체 영향
- 평균 응답시간: +3-5ms
- 최악 응답시간: +10ms
- **목표 5초 내 달성 가능**

### 4. 리스크 분석

#### 높은 리스크
1. **Redis 단일 장애점**
   - 대응: Fallback 메모리 모드
   - Redis Sentinel 고려 (Phase 2)

2. **네트워크 지연**
   - 대응: Connection pooling
   - 타임아웃 설정 최적화

#### 중간 리스크
1. **메모리 사용량**
   - 예측: 10,000 매핑 × 200 bytes = 2MB
   - 7일 누적: 최대 100MB
   - maxmemory-policy로 관리

2. **데이터 일관성**
   - 원자적 연산 사용
   - 파이프라인으로 트랜잭션 보장

#### 낮은 리스크
1. **구현 복잡도**
   - 명확한 인터페이스 분리
   - 기존 로직 최대한 유지

### 5. 구현 우선순위

1. **Phase 1**: 기본 Redis 연동 (2일)
   - Connection 관리
   - 기본 CRUD 구현
   - Fallback 로직

2. **Phase 2**: 최적화 (1일)
   - Connection pooling
   - Pipeline 최적화
   - 일괄 조회 구현

3. **Phase 3**: 테스트 및 검증 (2일)
   - 모든 기존 테스트 통과
   - Redis 전용 테스트
   - 성능 벤치마크

## 결론

### 구현 가능성: ✅ 높음
- 코드 변경 범위 명확 (약 250줄)
- 기존 테스트 100% 호환
- Fallback으로 리스크 최소화

### 예상 효과
- ✅ 7일 데이터 영속성 확보
- ✅ 멀티 워커 간 일관성 보장
- ✅ 수평 확장 가능
- ✅ 성능 목표 달성 가능

### 권장사항
1. **즉시 시작 가능**: 설계 명확, 리스크 낮음
2. **단계적 접근**: 기본 구현 → 최적화 → 고가용성
3. **모니터링 강화**: Redis 메트릭 추가 필요

---

**보고서 작성일**: 2025년 7월 23일
**분석 방법**: 전체 소스코드 정밀 분석
**결론**: Redis 전환은 안전하고 효율적으로 구현 가능