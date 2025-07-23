# Redis 통합 상세 설계서

## 1. 설계 개요

### 1.1 목적
Kong AWS Masker의 매핑 데이터를 Redis에 저장하여 7일간 영속성을 보장하고, 멀티 워커 간 일관성을 확보한다.

### 1.2 설계 원칙
- **Backward Compatibility**: 기존 코드와 100% 호환
- **Graceful Degradation**: Redis 장애 시 메모리 모드로 자동 전환
- **Performance First**: Connection pooling과 파이프라인으로 성능 최적화
- **Zero Downtime**: 무중단 전환 가능

## 2. 아키텍처 설계

### 2.1 전체 구조
```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Backend    │────▶│  Kong        │────▶│  Claude API  │
│  (Node.js)  │     │  (Workers)   │     │              │
└─────────────┘     └──────────────┘     └──────────────┘
                           │
                    ┌──────────────┐
                    │    Redis     │
                    │  (Primary)   │
                    └──────────────┘
                           │
                    ┌──────────────┐
                    │ Memory Cache │ (Fallback)
                    │  (Worker)    │
                    └──────────────┘
```

### 2.2 데이터 플로우
```
1. 마스킹 요청
   ├─ Redis 연결 확인
   ├─ Redis 가용: Redis에서 조회/생성
   └─ Redis 불가: 메모리에서 조회/생성

2. 언마스킹 요청
   ├─ Redis 연결 확인
   ├─ Redis 가용: 일괄 조회
   └─ Redis 불가: 메모리에서 조회
```

## 3. Redis 데이터 구조 설계

### 3.1 Key 네이밍 규칙
```
Prefix: "aws_masker:"

매핑 데이터:
- aws_masker:map:{masked_id} → {original_value}
- aws_masker:rev:{base64_encoded_original} → {masked_id}

카운터:
- aws_masker:cnt:{resource_type} → {counter}

메타데이터:
- aws_masker:stats:{date} → {statistics}
- aws_masker:health → {timestamp}
```

### 3.2 데이터 타입 및 TTL
```
매핑 데이터: STRING with TTL (7일)
카운터: STRING (영구 보존)
통계: HASH with TTL (30일)
```

### 3.3 메모리 사용량 예측
```
항목당 크기:
- Key (평균): 40 bytes
- Value (평균): 60 bytes
- Redis overhead: 50 bytes
- 총: ~150 bytes/매핑

일일 예상 매핑: 10,000개
7일 누적: 70,000개
예상 메모리: 70,000 × 150 = 10.5MB
```

## 4. 모듈별 상세 설계

### 4.1 masker_ngx_re.lua 수정사항

#### 4.1.1 Redis 설정 관리
```lua
-- Redis 설정 구조체
_M.redis_config = {
  -- 연결 설정
  host = os.getenv("REDIS_HOST") or "redis",
  port = tonumber(os.getenv("REDIS_PORT")) or 6379,
  password = os.getenv("REDIS_PASSWORD"),
  database = tonumber(os.getenv("REDIS_DB")) or 0,
  
  -- 타임아웃 설정 (밀리초)
  connect_timeout = 1000,
  send_timeout = 1000,
  read_timeout = 1000,
  
  -- Connection Pool 설정
  keepalive_timeout = 60000,  -- 60초
  keepalive_pool_size = 30,   -- worker당 최대 연결 수
  
  -- 데이터 설정
  prefix = "aws_masker:",
  default_ttl = 604800,  -- 7일 (초)
  
  -- 성능 설정
  pipeline_size = 100,  -- 파이프라인 최대 명령 수
  
  -- Fallback 설정
  fallback_to_memory = true,
  retry_on_error = true,
  max_retries = 3
}
```

#### 4.1.2 Connection Pool 관리
```lua
-- Redis 연결 획득
function _M.acquire_redis_connection()
  local red = redis:new()
  
  -- 타임아웃 설정
  red:set_timeouts(
    _M.redis_config.connect_timeout,
    _M.redis_config.send_timeout,
    _M.redis_config.read_timeout
  )
  
  -- 연결
  local ok, err = red:connect(_M.redis_config.host, _M.redis_config.port)
  if not ok then
    return nil, "Failed to connect: " .. err
  end
  
  -- 인증
  if _M.redis_config.password then
    local ok, err = red:auth(_M.redis_config.password)
    if not ok then
      red:close()
      return nil, "Failed to authenticate: " .. err
    end
  end
  
  -- 데이터베이스 선택
  if _M.redis_config.database > 0 then
    local ok, err = red:select(_M.redis_config.database)
    if not ok then
      red:close()
      return nil, "Failed to select database: " .. err
    end
  end
  
  -- Connection ID 로깅 (디버깅용)
  if kong and kong.log then
    local conn_id = red:get_reused_times()
    if conn_id == 0 then
      kong.log.debug("New Redis connection created")
    else
      kong.log.debug("Reused Redis connection #", conn_id)
    end
  end
  
  return red
end

-- Redis 연결 반환
function _M.release_redis_connection(red)
  if not red then return end
  
  -- Connection Pool에 반환
  local ok, err = red:set_keepalive(
    _M.redis_config.keepalive_timeout,
    _M.redis_config.keepalive_pool_size
  )
  
  if not ok then
    -- Pool이 가득 찬 경우 연결 종료
    red:close()
    if kong and kong.log then
      kong.log.warn("Failed to set keepalive: ", err)
    end
  end
end
```

#### 4.1.3 Mapping Store 인터페이스
```lua
-- Store 타입 정의
local STORE_TYPE_MEMORY = "memory"
local STORE_TYPE_REDIS = "redis"
local STORE_TYPE_HYBRID = "hybrid"

-- Store 생성 (Factory Pattern)
function _M.create_mapping_store(options)
  options = options or {}
  
  -- Redis 연결 시도
  if _M.redis_config.fallback_to_memory then
    local red, err = _M.acquire_redis_connection()
    if red then
      -- Redis Store 생성
      local store = {
        type = STORE_TYPE_REDIS,
        redis = red,
        prefix = _M.redis_config.prefix,
        ttl = options.ttl or _M.redis_config.default_ttl,
        
        -- Redis 전용 메서드
        acquire_connection = _M.acquire_redis_connection,
        release_connection = _M.release_redis_connection,
        
        -- 통계
        stats = {
          hits = 0,
          misses = 0,
          errors = 0
        }
      }
      
      -- 연결 테스트
      local ok, err = red:ping()
      if ok then
        return store
      else
        _M.release_redis_connection(red)
        kong.log.warn("Redis ping failed: ", err)
      end
    else
      kong.log.warn("Redis connection failed: ", err)
    end
  end
  
  -- Fallback: Memory Store
  kong.log.info("Using memory store (Redis unavailable)")
  return {
    type = STORE_TYPE_MEMORY,
    mappings = {},
    reverse_mappings = {},  -- O(1) 조회를 위해 추가
    counters = {},
    ttl = options.ttl or 3600,  -- 메모리는 1시간
    created_at = ngx.now(),
    
    -- 통계
    stats = {
      size = 0,
      max_size = options.max_entries or 10000
    }
  }
end
```

#### 4.1.4 마스킹 로직 구현
```lua
-- 통합 마스킹 함수
function _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
  -- Store 타입별 분기
  if mapping_store.type == STORE_TYPE_REDIS then
    return _M._redis_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  else
    return _M._memory_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  end
end

-- Redis 마스킹 구현
function _M._redis_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  local red = mapping_store.redis
  if not red then
    -- 연결 재시도
    red = mapping_store.acquire_connection()
    if not red then
      -- Fallback to memory
      return _M._generate_masked_id(pattern_def.type, pattern_def.replacement, 0)
    end
    mapping_store.redis = red
  end
  
  local prefix = mapping_store.prefix
  
  -- 원본 값 인코딩 (특수문자 처리)
  local encoded = ngx.encode_base64(original_value)
  local reverse_key = prefix .. "rev:" .. encoded
  
  -- 1. 기존 매핑 확인
  local masked_id, err = red:get(reverse_key)
  if err then
    mapping_store.stats.errors = mapping_store.stats.errors + 1
    kong.log.err("Redis GET error: ", err)
    -- Continue with generation
  elseif masked_id and masked_id ~= ngx.null then
    mapping_store.stats.hits = mapping_store.stats.hits + 1
    return masked_id
  end
  
  mapping_store.stats.misses = mapping_store.stats.misses + 1
  
  -- 2. 새 마스킹 ID 생성
  local resource_type = pattern_def.type or "unknown"
  local counter_key = prefix .. "cnt:" .. resource_type
  
  -- 원자적 카운터 증가
  local counter, err = red:incr(counter_key)
  if err then
    kong.log.err("Redis INCR error: ", err)
    -- Fallback counter
    counter = ngx.now() * 1000 % 999999
  end
  
  -- 마스킹 ID 생성
  masked_id = string.format(pattern_def.replacement, counter)
  
  -- 3. 양방향 매핑 저장 (파이프라인)
  red:init_pipeline()
  
  -- Forward mapping
  local map_key = prefix .. "map:" .. masked_id
  red:setex(map_key, mapping_store.ttl, original_value)
  
  -- Reverse mapping
  red:setex(reverse_key, mapping_store.ttl, masked_id)
  
  -- 통계 업데이트 (선택적)
  local stats_key = prefix .. "stats:" .. os.date("%Y%m%d")
  red:hincrby(stats_key, "total", 1)
  red:hincrby(stats_key, resource_type, 1)
  red:expire(stats_key, 2592000)  -- 30일
  
  -- 파이프라인 실행
  local results, err = red:commit_pipeline()
  if err then
    kong.log.err("Redis pipeline error: ", err)
    -- 매핑은 메모리에 임시 저장
  end
  
  return masked_id
end

-- 메모리 마스킹 구현 (개선)
function _M._memory_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  -- O(1) reverse lookup
  local masked_id = mapping_store.reverse_mappings[original_value]
  if masked_id then
    return masked_id
  end
  
  -- 크기 제한 확인
  if mapping_store.stats.size >= mapping_store.stats.max_size then
    -- LRU 제거 또는 오래된 항목 제거
    _M._memory_evict_old_entries(mapping_store)
  end
  
  -- 새 마스킹 ID 생성
  local resource_type = pattern_def.type or "unknown"
  local counter = (mapping_store.counters[resource_type] or 0) + 1
  mapping_store.counters[resource_type] = counter
  
  masked_id = string.format(pattern_def.replacement, counter)
  
  -- 양방향 저장
  mapping_store.mappings[masked_id] = original_value
  mapping_store.reverse_mappings[original_value] = masked_id
  mapping_store.stats.size = mapping_store.stats.size + 1
  
  return masked_id
end
```

#### 4.1.5 언마스킹 로직 구현
```lua
-- 통합 언마스킹 함수
function _M.unmask_data(text, mapping_store)
  if type(text) ~= "string" or text == "" then
    return text
  end
  
  if not mapping_store then
    return text
  end
  
  if mapping_store.type == STORE_TYPE_REDIS then
    return _M._redis_unmask_data(text, mapping_store)
  else
    return _M._memory_unmask_data(text, mapping_store)
  end
end

-- Redis 언마스킹 구현 (최적화)
function _M._redis_unmask_data(text, mapping_store)
  local red = mapping_store.redis
  if not red then
    red = mapping_store.acquire_connection()
    if not red then
      return text  -- Redis 불가 시 원본 반환
    end
    mapping_store.redis = red
  end
  
  local prefix = mapping_store.prefix
  
  -- 1. 마스킹된 ID 추출
  local masked_patterns = {
    "[A-Z][A-Z0-9_]+_%d+",  -- 일반 패턴 (EC2_001)
    "i%-[0-9a-f]+",         -- EC2 인스턴스 ID
    "vpc%-[0-9a-f]+",       -- VPC ID
    -- 필요시 추가
  }
  
  local masked_ids = {}
  local id_positions = {}  -- 위치 저장
  
  for _, pattern in ipairs(masked_patterns) do
    for masked_id, pos in string.gmatch(text, "((" .. pattern .. "))()") do
      if not masked_ids[masked_id] then
        masked_ids[masked_id] = true
        table.insert(id_positions, {id = masked_id, pos = pos})
      end
    end
  end
  
  -- 2. 일괄 조회 (파이프라인)
  if next(masked_ids) then
    red:init_pipeline()
    
    local query_order = {}
    for masked_id in pairs(masked_ids) do
      table.insert(query_order, masked_id)
      red:get(prefix .. "map:" .. masked_id)
    end
    
    local results, err = red:commit_pipeline()
    if err then
      kong.log.err("Redis pipeline error in unmask: ", err)
      return text
    end
    
    -- 3. 치환 수행
    local replacements = {}
    for i, masked_id in ipairs(query_order) do
      local original_value = results[i]
      if original_value and original_value ~= ngx.null then
        replacements[masked_id] = original_value
      end
    end
    
    -- 효율적인 치환
    local unmasked_text = text
    for masked_id, original_value in pairs(replacements) do
      unmasked_text = string.gsub(unmasked_text, 
        _M._escape_pattern(masked_id), 
        original_value)
    end
    
    return unmasked_text
  end
  
  return text
end

-- 메모리 언마스킹 (기존 유지)
function _M._memory_unmask_data(text, mapping_store)
  if not mapping_store.mappings then
    return text
  end
  
  local unmasked_text = text
  for masked_id, original_value in pairs(mapping_store.mappings) do
    unmasked_text = string.gsub(unmasked_text, 
      _M._escape_pattern(masked_id), 
      original_value)
  end
  
  return unmasked_text
end
```

### 4.2 handler.lua 수정사항

#### 4.2.1 생성자 수정
```lua
function AwsMaskerHandler:new()
  local instance = {
    mapping_store = nil,  -- Lazy initialization
    config = {
      mask_ec2_instances = true,
      mask_s3_buckets = true, 
      mask_rds_instances = true,
      mask_private_ips = true,
      preserve_structure = true,
      log_masked_requests = false,
      -- Redis 설정 추가
      use_redis = true,
      redis_fallback = true
    }
  }
  
  return setmetatable(instance, { __index = self })
end
```

#### 4.2.2 Access Phase 수정
```lua
function AwsMaskerHandler:access(conf)
  -- ... 기존 초기화 코드 ...
  
  -- Lazy initialization with config
  if not self.mapping_store then
    local store_options = {
      ttl = conf.mapping_ttl or 604800,  -- 7일
      max_entries = conf.max_entries or 10000,
      use_redis = conf.use_redis ~= false  -- 기본값 true
    }
    self.mapping_store = masker.create_mapping_store(store_options)
  end
  
  -- ... 마스킹 처리 ...
  
  -- Store 정리 (중요: Connection 반환)
  if self.mapping_store.type == "redis" and self.mapping_store.redis then
    masker.release_redis_connection(self.mapping_store.redis)
    self.mapping_store.redis = nil
  end
end
```

#### 4.2.3 Body Filter 수정
```lua
function AwsMaskerHandler:body_filter(conf)
  local chunk = kong.response.get_raw_body()
  
  if chunk and kong.ctx.shared.aws_mapping_store then
    local mapping_store = kong.ctx.shared.aws_mapping_store
    
    -- Redis 연결 재획득 (다른 phase)
    if mapping_store.type == "redis" and not mapping_store.redis then
      mapping_store.redis = masker.acquire_redis_connection()
      if not mapping_store.redis then
        -- Redis 불가 시 언마스킹 스킵
        kong.log.warn("Redis unavailable for unmasking")
        return
      end
    end
    
    -- ... 언마스킹 처리 ...
    
    -- 연결 반환
    if mapping_store.type == "redis" and mapping_store.redis then
      masker.release_redis_connection(mapping_store.redis)
      mapping_store.redis = nil
    end
  end
end
```

### 4.3 Docker 설정

#### 4.3.1 docker-compose.yml
```yaml
services:
  # Redis 서비스 추가
  redis:
    image: redis:7-alpine
    container_name: redis-cache
    hostname: redis
    command: >
      redis-server
      --save 60 1 300 10
      --loglevel warning
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfilename "aws-masker.aof"
      --dir /data
      --bind 0.0.0.0
      --protected-mode no
      --tcp-backlog 511
      --timeout 0
      --tcp-keepalive 300
    environment:
      <<: *common-variables
    volumes:
      - redis-data:/data
      - ./config/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - backend
    healthcheck:
      <<: *healthcheck-defaults
      test: ["CMD-SHELL", "redis-cli ping || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 5
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
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Kong 서비스 수정
  kong:
    # ... 기존 설정 ...
    environment:
      # ... 기존 환경 변수 ...
      # Redis 설정 추가
      REDIS_HOST: ${REDIS_HOST:-redis}
      REDIS_PORT: ${REDIS_PORT:-6379}
      REDIS_PASSWORD: ${REDIS_PASSWORD:-}
      REDIS_DB: ${REDIS_DB:-0}
    depends_on:
      redis:
        condition: service_healthy
    # ... 나머지 설정 ...

volumes:
  redis-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${PWD}/data/redis
```

#### 4.3.2 Redis 설정 파일 (config/redis.conf)
```conf
# Redis configuration for AWS Masker

# Network
bind 0.0.0.0
protected-mode no
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel warning
logfile ""
databases 16

# Snapshotting
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename aws-masker.rdb
dir /data

# Replication
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5

# Memory Management
maxmemory 256mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Append Only Mode
appendonly yes
appendfilename "aws-masker.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Lua scripting
lua-time-limit 5000

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Advanced config
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100

# Active rehashing
activerehashing yes

# Client output buffer limits
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Frequency
hz 10

# AOF rewrite
aof-rewrite-incremental-fsync yes

# RDB
rdb-save-incremental-fsync yes
```

## 5. 에러 처리 및 Fallback

### 5.1 에러 시나리오
1. **Redis 연결 실패**
   - 자동으로 메모리 모드 전환
   - 경고 로그 기록
   - 모니터링 알림

2. **Redis 타임아웃**
   - 재시도 로직 (최대 3회)
   - 타임아웃 후 메모리 모드

3. **메모리 부족**
   - LRU 정책으로 자동 제거
   - 모니터링 알림

### 5.2 Fallback 전략
```lua
-- Fallback wrapper
function _M.with_fallback(redis_func, memory_func, ...)
  local success, result = pcall(redis_func, ...)
  if success then
    return result
  else
    kong.log.warn("Redis operation failed, using memory: ", result)
    return memory_func(...)
  end
end
```

## 6. 모니터링 및 운영

### 6.1 메트릭 수집
```lua
-- 통계 수집
function _M.collect_metrics(mapping_store)
  local metrics = {
    type = mapping_store.type,
    timestamp = ngx.now()
  }
  
  if mapping_store.type == "redis" then
    metrics.hits = mapping_store.stats.hits
    metrics.misses = mapping_store.stats.misses
    metrics.errors = mapping_store.stats.errors
  else
    metrics.size = mapping_store.stats.size
    metrics.max_size = mapping_store.stats.max_size
  end
  
  -- Prometheus 형식으로 노출
  return metrics
end
```

### 6.2 Health Check
```lua
-- Redis health check
function _M.check_redis_health()
  local red = _M.acquire_redis_connection()
  if not red then
    return false, "Connection failed"
  end
  
  local ok, err = red:ping()
  _M.release_redis_connection(red)
  
  return ok, err
end
```

## 7. 마이그레이션 계획

### 7.1 단계별 전환
1. **Phase 1**: Redis 추가, 메모리 우선
2. **Phase 2**: Redis 우선, 메모리 Fallback
3. **Phase 3**: Redis 전용 (선택적)

### 7.2 롤백 계획
- 환경 변수로 즉시 전환 가능
- `REDIS_HOST=none` 설정 시 메모리 모드

## 8. 테스트 계획

### 8.1 단위 테스트
- Redis 연결/해제
- 마스킹/언마스킹 정확성
- Fallback 동작
- 성능 벤치마크

### 8.2 통합 테스트
- 기존 테스트 100% 통과
- Redis 재시작 시나리오
- 멀티 워커 일관성
- 7일 TTL 검증

### 8.3 부하 테스트
- 동시 요청 처리
- Connection pool 효율성
- 메모리 사용량 추이

## 9. 보안 고려사항

### 9.1 Redis 보안
- Protected mode 비활성화 (내부 네트워크)
- 비밀번호 설정 (선택적)
- 네트워크 격리 (backend network)

### 9.2 데이터 보안
- 민감 정보 마스킹 유지
- Redis persistence 암호화 (선택적)
- 접근 로그 모니터링

## 10. 구현 체크리스트

- [ ] Redis 서비스 추가 (docker-compose.yml)
- [ ] Redis 설정 파일 생성
- [ ] masker_ngx_re.lua 수정
  - [ ] Redis 연결 관리
  - [ ] 마스킹 로직
  - [ ] 언마스킹 로직
  - [ ] Fallback 처리
- [ ] handler.lua 수정
  - [ ] Store 초기화
  - [ ] 연결 관리
- [ ] 테스트 작성
  - [ ] 단위 테스트
  - [ ] 통합 테스트
  - [ ] 성능 테스트
- [ ] 문서 업데이트
- [ ] 모니터링 설정

---

**설계 완료일**: 2025년 7월 23일
**설계자**: Claude Assistant
**검토 상태**: 구현 준비 완료