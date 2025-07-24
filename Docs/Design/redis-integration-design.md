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

#### 4.1.5 Pre-fetch 기반 언마스킹 로직 구현

**⚠️ OpenResty 제약 준수**: body_filter에서 Redis 파이프라인 사용 불가로 인한 2단계 Pre-fetch 전략 적용

**기술적 배경**: 
- OpenResty body_filter에서 coroutine yield 금지
- Redis resty.redis의 commit_pipeline()이 yield 호출
- 따라서 ACCESS에서 준비, BODY_FILTER에서 적용하는 구조로 설계

```lua
-- 1단계: ACCESS에서 언마스킹 데이터 준비 (Redis 파이프라인 사용 가능)
function _M.prepare_unmask_data(request_body, mapping_store)
  if type(request_body) ~= "string" or request_body == "" then
    return {}
  end
  
  if mapping_store.type ~= STORE_TYPE_REDIS then
    return {}  -- 메모리 모드는 기존 방식 사용
  end
  
  local red = mapping_store.redis
  if not red then
    red = mapping_store.acquire_connection()
    if not red then
      kong.log.warn("Redis unavailable for unmask preparation")
      return {}
    end
    mapping_store.redis = red
  end
  
  local prefix = mapping_store.prefix
  
  -- 1. 요청에서 AWS 리소스 추출 (언마스킹 대상 예측)
  local aws_patterns = {
    "i%-[0-9a-f]+",         -- EC2 인스턴스 ID  
    "vpc%-[0-9a-f]+",       -- VPC ID
    "subnet%-[0-9a-f]+",    -- Subnet ID
    "sg%-[0-9a-f]+",        -- Security Group ID
    "arn:aws:[^:]+:[^:]*:[^:]*:[^\\s]+"  -- ARN 패턴
  }
  
  local potential_resources = {}
  for _, pattern in ipairs(aws_patterns) do
    for resource in string.gmatch(request_body, pattern) do
      if not potential_resources[resource] then
        potential_resources[resource] = true
      end
    end
  end
  
  -- 2. 해당 리소스들의 마스킹 ID 조회 (역방향)
  local unmask_map = {}
  if next(potential_resources) then
    red:init_pipeline()
    
    local query_order = {}
    for resource in pairs(potential_resources) do
      table.insert(query_order, resource)
      local encoded = ngx.encode_base64(resource)
      red:get(prefix .. "rev:" .. encoded)  -- 역방향 조회
    end
    
    local results, err = red:commit_pipeline()
    if not err and results then
      -- 언마스킹 맵 구성 (masked_id -> original_value)
      for i, resource in ipairs(query_order) do
        local masked_id = results[i]
        if masked_id and masked_id ~= ngx.null then
          unmask_map[masked_id] = resource
        end
      end
      
      mapping_store.stats.hits = mapping_store.stats.hits + #results
      kong.log.debug("Unmask map prepared: ", #query_order, " resources, ", 
                     table.getn(unmask_map), " mappings found")
    else
      kong.log.err("Redis unmask preparation failed: ", err)
      mapping_store.stats.errors = mapping_store.stats.errors + 1
    end
  end
  
  return unmask_map
end

-- 2단계: BODY_FILTER에서 동기 문자열 교체만 수행
function _M.apply_unmask_data(response_text, unmask_map)
  if type(response_text) ~= "string" or response_text == "" then
    return response_text
  end
  
  if not unmask_map or not next(unmask_map) then
    return response_text
  end
  
  local unmasked_text = response_text
  
  -- 단순 동기 문자열 교체 (yield 없음, OpenResty 호환)
  for masked_id, original_value in pairs(unmask_map) do
    unmasked_text = string.gsub(unmasked_text, 
      _M._escape_pattern(masked_id), original_value)
  end
  
  return unmasked_text
end

-- 하위 호환성을 위한 통합 함수 (메모리 모드 전용)
function _M.unmask_data(text, mapping_store)
  if type(text) ~= "string" or text == "" then
    return text
  end
  
  if not mapping_store then
    return text
  end
  
  -- Redis 모드는 Pre-fetch 전략만 사용
  if mapping_store.type == STORE_TYPE_REDIS then
    kong.log.warn("Redis unmask_data called directly - use prepare_unmask_data + apply_unmask_data instead")
    return text
  else
    return _M._memory_unmask_data(text, mapping_store)
  end
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

#### 4.2.2 Access Phase 수정 (Pre-fetch 전략 추가)

**⚠️ 핵심**: Redis 모드에서 언마스킹 Pre-fetch 작업을 ACCESS에서 수행

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
  
  -- 요청 바디 마스킹 처리
  local raw_body = kong.request.get_raw_body()
  if raw_body then
    -- 1단계: 기존 마스킹 수행
    local masked_result = masker.mask_data(raw_body, self.mapping_store, conf)
    if masked_result and masked_result.masked then
      kong.service.request.set_raw_body(masked_result.masked)
    end
    
    -- 2단계: Redis 모드인 경우 언마스킹 Pre-fetch 수행
    if self.mapping_store.type == "redis" then
      local unmask_map = masker.prepare_unmask_data(raw_body, self.mapping_store)
      -- Kong context에 언마스킹 데이터 저장 (BODY_FILTER에서 사용)
      kong.ctx.shared.aws_unmask_map = unmask_map
      kong.log.debug("Redis unmask pre-fetch completed: ", 
                     unmask_map and table.getn(unmask_map) or 0, " mappings")
    end
  end
  
  -- Kong context에 mapping store 저장
  kong.ctx.shared.aws_mapping_store = self.mapping_store
  
  -- Store 정리 (중요: Connection 반환)
  if self.mapping_store.type == "redis" and self.mapping_store.redis then
    masker.release_redis_connection(self.mapping_store.redis)
    self.mapping_store.redis = nil
  end
end
```

**핵심 변경사항**:
1. **Pre-fetch 실행**: Redis 모드에서 `masker.prepare_unmask_data()` 호출
2. **Context 저장**: `kong.ctx.shared.aws_unmask_map`에 언마스킹 데이터 저장
3. **2단계 처리**: 마스킹 + Pre-fetch를 동시에 수행
4. **성능 최적화**: ACCESS에서 Redis 파이프라인 사용 (yield 허용)
5. **연결 관리**: ACCESS 완료 후 Redis 연결 즉시 반환

#### 4.2.3 Body Filter 수정 (Pre-fetch 전략 적용)

**⚠️ 중요**: OpenResty body_filter 제약으로 인해 Redis 파이프라인 직접 사용 불가, Pre-fetch 전략 적용

```lua
function AwsMaskerHandler:body_filter(conf)
  local chunk = kong.response.get_raw_body()
  
  if chunk and kong.ctx.shared.aws_mapping_store then
    local mapping_store = kong.ctx.shared.aws_mapping_store
    
    -- Pre-fetch된 언마스킹 데이터 사용 (ACCESS에서 준비됨)
    local unmask_map = kong.ctx.shared.aws_unmask_map
    
    if mapping_store.type == "redis" then
      -- Redis 모드: Pre-fetch된 데이터로 동기 언마스킹
      if unmask_map and next(unmask_map) then
        local unmasked_chunk = masker.apply_unmask_data(chunk, unmask_map)
        if unmasked_chunk ~= chunk then
          kong.response.set_raw_body(unmasked_chunk)
          kong.log.debug("Redis unmask applied: ", table.getn(unmask_map), " mappings")
        end
      else
        kong.log.debug("No Redis unmask data available")
      end
    else
      -- Memory 모드: 기존 방식 유지 (하위 호환성)
      local unmasked_chunk = masker.unmask_data(chunk, mapping_store)
      if unmasked_chunk ~= chunk then
        kong.response.set_raw_body(unmasked_chunk)
        kong.log.debug("Memory unmask applied")
      end
    end
    
    -- 언마스킹 통계 업데이트
    if mapping_store.stats then
      mapping_store.stats.unmask_requests = (mapping_store.stats.unmask_requests or 0) + 1
    end
  end
end
```

**핵심 변경사항**:
1. **Redis 연결 제거**: body_filter에서 Redis 연결 획득/해제 완전 제거
2. **Pre-fetch 데이터 사용**: `kong.ctx.shared.aws_unmask_map` 사용
3. **동기 처리**: `masker.apply_unmask_data()` 함수로 단순 문자열 교체만 수행
4. **하위 호환성**: Memory 모드는 기존 `masker.unmask_data()` 유지
5. **성능 최적화**: yield 없는 동기 문자열 처리로 OpenResty 호환

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