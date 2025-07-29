--
-- AWS Resource Masker Module with ngx.re support
-- Implements masking/unmasking logic for AWS resource identifiers
-- Using ngx.re for complex patterns as per design specification
--

local patterns = require "kong.plugins.aws-masker.patterns"
local pattern_integrator = require "kong.plugins.aws-masker.pattern_integrator"
local json_safe = require "kong.plugins.aws-masker.json_safe"

local _M = {}

---
-- IP Classification Utility Functions
-- Determines if an IP should be excluded from public IP masking
-- Based on RFC 1918 and AWS-specific IP usage patterns
---

---
-- Classifies IP address to determine if it should be excluded from masking
-- Uses exclusion approach: identifies known non-public IPs, treats rest as public
-- @param string ip IPv4 address to classify
-- @return boolean is_excluded True if IP should NOT be masked as public IP
-- @return string ip_type Type classification for logging/debugging
function _M.is_non_public_ip(ip)
    if type(ip) ~= "string" or ip == "" then
        return true, "invalid_format"
    end
    
    -- Extract IPv4 octets
    local a, b, c, d = string.match(ip, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then 
        return true, "invalid_ipv4" 
    end
    
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    
    -- Validate octet ranges (0-255)
    if not (a and b and c and d) or 
       a < 0 or a > 255 or b < 0 or b > 255 or 
       c < 0 or c > 255 or d < 0 or d > 255 then
        return true, "invalid_range"
    end
    
    -- 1. RFC 1918 Private Networks (VPC Internal)
    if (a == 10) then
        return true, "private_class_a"  -- 10.0.0.0/8
    elseif (a == 172 and b >= 16 and b <= 31) then
        return true, "private_class_b"  -- 172.16.0.0/12
    elseif (a == 192 and b == 168) then
        return true, "private_class_c"  -- 192.168.0.0/16
    end
    
    -- 2. AWS EC2 Instance Metadata Service
    if (a == 169 and b == 254) then
        return true, "aws_metadata"  -- 169.254.0.0/16
    end
    
    -- 3. Loopback addresses
    if (a == 127) then
        return true, "loopback"  -- 127.0.0.0/8
    end
    
    -- 4. Multicast and Reserved ranges
    if (a >= 224 and a <= 255) then
        return true, "multicast_reserved"  -- 224.0.0.0/4 and above
    end
    
    -- 5. Invalid/Reserved Class A ranges
    if (a == 0) then
        return true, "network_address"  -- 0.0.0.0/8
    end
    
    -- 6. Link-local (excluding AWS metadata which was handled above)
    if (a == 169 and b == 254 and c >= 1 and c <= 254) then
        return true, "link_local"  -- General link-local
    end
    
    -- Everything else is considered Public IP (eligible for masking)
    return false, "public_eligible"
end

-- Default configuration
_M.config = {
  ttl = 3600,              -- 1 hour TTL for mappings
  max_entries = 10000,     -- Maximum number of mappings
  clean_interval = 300     -- Clean expired entries every 5 minutes
}

-- Redis configuration
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
  
  -- Connection Pool 설정 (메모리 99.97% 위험으로 긴급 축소)
  keepalive_timeout = 60000,  -- 60초
  keepalive_pool_size = 10,   -- worker당 최대 연결 수 (30→10, 67% 감소)
  
  -- 데이터 설정
  prefix = "aws_masker:",
  default_ttl = 604800,  -- 7일 (초)
  
  -- 성능 설정 (메모리 절약을 위한 축소)
  pipeline_size = 20,   -- 파이프라인 최대 명령 수 (100→20, 80% 감소)
  
  -- Fallback 설정
  fallback_to_memory = true,
  retry_on_error = true,
  max_retries = 3
}

-- Store 타입 정의
local STORE_TYPE_MEMORY = "memory"
local STORE_TYPE_REDIS = "redis"
local STORE_TYPE_HYBRID = "hybrid"

-- Pattern configuration
local pattern_config = {}

---
-- Redis 연결 획득
-- @return table|nil Redis connection object or nil on failure
-- @return string|nil Error message on failure
function _M.acquire_redis_connection()
  local redis = require "resty.redis"
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
  if _M.redis_config.password and _M.redis_config.password ~= "" then
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

---
-- Redis 연결 반환
-- @param table red Redis connection object
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

---
-- Store 생성 (Factory Pattern)
-- @param table options Optional configuration overrides
-- @return table Mapping store (Redis or Memory fallback)
function _M.create_mapping_store(options)
  options = options or {}
  
  -- Redis 연결 시도 (use_redis 옵션이나 기본 활성화)
  if options.use_redis ~= false then
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

---
-- Initialize pattern configuration
-- Determine which patterns need ngx.re
function _M.init_patterns()
  -- 디버깅: 원본 패턴 수 확인
  local pattern_count = 0
  for name, _ in pairs(patterns.patterns) do
    pattern_count = pattern_count + 1
  end
  
  if kong and kong.log then
    kong.log.info("[AWS-MASKER] Original patterns count: ", pattern_count)
  end
  
  -- patterns.patterns를 배열로 변환
  local original_patterns_array = {}
  local priority_counter = 1
  for name, pattern_def in pairs(patterns.patterns) do
    -- 필수 필드 검증
    if not pattern_def.pattern then
      if kong and kong.log then
        kong.log.err("[AWS-MASKER] Pattern missing for: ", name)
      end
    end
    if not pattern_def.type then
      if kong and kong.log then
        kong.log.err("[AWS-MASKER] Type missing for: ", name)
      end
    end
    if not pattern_def.replacement then
      if kong and kong.log then
        kong.log.err("[AWS-MASKER] Replacement missing for: ", name)
      end
    end
    
    -- name과 priority 필드 추가
    pattern_def.name = name
    pattern_def.priority = pattern_def.priority or priority_counter
    priority_counter = priority_counter + 1
    table.insert(original_patterns_array, pattern_def)
  end
  
  -- 기존 패턴과 확장 패턴 통합
  local integrated_patterns, conflicts = pattern_integrator.integrate_patterns(original_patterns_array)
  
  if kong and kong.log then
    kong.log.info("[AWS-MASKER] Patterns integrated", {
      total = #integrated_patterns,
      conflicts = #conflicts
    })
  end
  
  -- 통합된 패턴으로 초기화
  for _, pattern_def in ipairs(integrated_patterns) do
    local name = pattern_def.name or pattern_def.pattern
    -- Determine if this pattern needs ngx.re
    local needs_ngx_re = false
    
    -- Complex patterns that need ngx.re
    if name:match("arn$") or name:match("^iam_") or 
       name == "access_key" or name == "secret_key" or 
       name == "session_token" or name == "account_id" then
      needs_ngx_re = true
    end
    
    pattern_config[name] = {
      pattern_def = pattern_def,
      use_ngx_re = needs_ngx_re
    }
    
    -- 디버깅: pattern_config 내용 확인
    if kong and kong.log then
      kong.log.debug("[AWS-MASKER] Pattern added to config: ", name, 
        " use_ngx_re: ", needs_ngx_re,
        " pattern: ", pattern_def.pattern and "exists" or "missing")
    end
  end
  
  -- 최종 pattern_config 크기 확인
  local config_count = 0
  for _, _ in pairs(pattern_config) do
    config_count = config_count + 1
  end
  
  if kong and kong.log then
    kong.log.info("[AWS-MASKER] Final pattern_config count: ", config_count)
  end
end

---
-- Extract AWS resource patterns from text (Phase 1 - no yield)
-- @param string text Input text potentially containing AWS resources  
-- @param table config Plugin configuration
-- @return table Array of masking candidates with pattern info
function _M.extract_masking_candidates(text, config)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  
  local candidates = {}
  
  -- Process each pattern to find matches
  for pattern_name, pattern_info in pairs(pattern_config) do
    local pattern_def = pattern_info.pattern_def
    
    -- Skip complex patterns that need ngx.re (they work fine with callbacks)
    if pattern_info.use_ngx_re then
      -- ngx.re patterns can use callbacks without yield issues
      -- Skip extraction for these
    else
      -- Simple Lua patterns - extract for Redis processing
      for match in string.gmatch(text, pattern_def.pattern) do
        table.insert(candidates, {
          original = match,
          pattern_type = pattern_def.type,
          pattern_name = pattern_name,
          replacement_format = pattern_def.replacement
        })
      end
    end
  end
  
  return candidates
end

---
-- Process masking candidates with Redis (Phase 2 - with yield)
-- @param table candidates Array of masking candidates
-- @param table mapping_store Redis store for mappings
-- @return table Mapping of original -> masked_id
function _M.process_redis_masking(candidates, mapping_store)
  if #candidates == 0 or mapping_store.type ~= STORE_TYPE_REDIS then
    return {}
  end
  
  local red = mapping_store.redis
  if not red then
    red = _M.acquire_redis_connection()
    if not red then
      return {}
    end
    mapping_store.redis = red
  end
  
  local prefix = mapping_store.prefix
  local mapping = {}
  
  -- Step 1: Check existing mappings
  red:init_pipeline()
  
  for _, candidate in ipairs(candidates) do
    local encoded = ngx.encode_base64(candidate.original)
    local reverse_key = prefix .. "rev:" .. encoded
    red:get(reverse_key)
  end
  
  local existing_results, err = red:commit_pipeline()
  if not existing_results then
    kong.log.err("Redis pipeline failed: ", err)
    return {}
  end
  
  -- Step 2: Generate counters for new items
  local need_counters = {}
  red:init_pipeline()
  
  for i, candidate in ipairs(candidates) do
    if existing_results[i] == ngx.null then
      table.insert(need_counters, i)
      local counter_key = prefix .. "cnt:" .. candidate.pattern_type
      red:incr(counter_key)
    else
      -- Use existing mapping
      mapping[candidate.original] = existing_results[i]
    end
  end
  
  local counter_results = {}
  if #need_counters > 0 then
    counter_results = red:commit_pipeline()
  end
  
  -- Step 3: Store new mappings
  if #need_counters > 0 then
    red:init_pipeline()
    
    for idx, candidate_idx in ipairs(need_counters) do
      local candidate = candidates[candidate_idx]
      local counter = counter_results[idx]
      local masked_id = string.format(candidate.replacement_format, counter)
      
      -- Store bidirectional mapping
      local map_key = prefix .. "map:" .. masked_id
      red:setex(map_key, mapping_store.ttl, candidate.original)
      
      local encoded = ngx.encode_base64(candidate.original)
      local rev_key = prefix .. "rev:" .. encoded
      red:setex(rev_key, mapping_store.ttl, masked_id)
      
      mapping[candidate.original] = masked_id
    end
    
    red:commit_pipeline()
  end
  
  return mapping
end

---
-- Mask AWS resource identifiers in text using pattern matching
-- @param string text Input text potentially containing AWS resources
-- @param table mapping_store Store for masked value mappings
-- @param table config Plugin configuration
-- @return table Result with masked text, count, and patterns used
function _M.mask_data(text, mapping_store, config)
  if type(text) ~= "string" or text == "" then
    return {
      masked = text,
      count = 0,
      patterns_used = {}
    }
  end
  
  local masked_text = text
  local mask_count = 0
  local patterns_used = {}
  local memory_mappings = {}  -- body_filter용 메모리 매핑
  
  -- Store type check
  
  -- Initialize mapping store if needed (only for memory store)
  if mapping_store.type == STORE_TYPE_MEMORY and not mapping_store.mappings then
    mapping_store.mappings = {}
    mapping_store.counters = {}
  end
  
  -- Phase 1: Extract candidates for Redis processing
  local redis_candidates = {}
  if mapping_store.type == STORE_TYPE_REDIS then
    redis_candidates = _M.extract_masking_candidates(text, config)
  end
  
  -- Phase 2: Process Redis mappings (single yield point)
  local redis_mapping = {}
  if #redis_candidates > 0 then
    redis_mapping = _M.process_redis_masking(redis_candidates, mapping_store)
  end
  
  -- Phase 3: Apply all masking - masker.lua 방식으로 단순화
  -- patterns.patterns를 직접 사용 (masker.lua와 동일한 방식)
  
  -- 디버깅: 패턴 수 확인
  local pattern_count = 0
  for _, _ in pairs(patterns.patterns) do
    pattern_count = pattern_count + 1
  end
  
  if kong and kong.log then
    kong.log.debug("[MASK_DATA] Starting masking with ", pattern_count, " patterns")
  end
  
  -- 우선순위 기반 패턴 정렬 (낮은 숫자 = 높은 우선순위)
  local sorted_patterns = {}
  for pattern_name, pattern_def in pairs(patterns.patterns) do
    table.insert(sorted_patterns, {
      name = pattern_name,
      def = pattern_def,
      priority = pattern_def.priority or 999  -- 기본값 999 (낮은 우선순위)
    })
  end
  
  -- 우선순위별 정렬 (오름차순: 낮은 숫자가 먼저)
  table.sort(sorted_patterns, function(a, b)
    return a.priority < b.priority
  end)
  
  if kong and kong.log then
    kong.log.debug("[MASK_DATA] Processing ", #sorted_patterns, " patterns in priority order")
  end
  
  -- 우선순위 순서로 각 패턴 적용
  for _, pattern_entry in ipairs(sorted_patterns) do
    local pattern_name = pattern_entry.name
    local pattern_def = pattern_entry.def
    -- 패턴 활성화 여부 확인
    if config and config["mask_" .. pattern_def.type] == false then
      goto continue
    end
    
    -- 필수 필드 검증
    if not pattern_def.pattern or not pattern_def.type or not pattern_def.replacement then
      if kong and kong.log then
        kong.log.warn("[MASK_DATA] Skipping incomplete pattern: ", pattern_name)
      end
      goto continue
    end
    
    -- 디버깅: 현재 처리 중인 패턴
    if kong and kong.log then
      kong.log.debug("[MASK_DATA] Processing pattern: ", pattern_name, " type: ", pattern_def.type)
    end
    
    -- 패턴 매칭 및 치환 (masker.lua와 동일한 방식)
    local matches = {}
    
    -- 모든 매치 찾기
    for match in string.gmatch(text, pattern_def.pattern) do
      table.insert(matches, match)
    end
    
    -- 각 매치를 마스킹된 ID로 교체
    for _, original_value in ipairs(matches) do
      -- 패턴 검증자(validator) 함수 확인 및 실행
      if pattern_def.validator then
        local should_mask, reason = pattern_def.validator(original_value)
        if not should_mask then
          if kong and kong.log then
            kong.log.debug("[MASK_DATA] Validator skip: ", original_value, " reason: ", reason or "unknown")
          end
          goto continue_match  -- 이 매치를 건너뛰고 다음 매치로
        end
      end
      
      -- 마스킹 ID 생성 또는 가져오기
      local masked_id
      
      -- Redis 매핑이 있으면 먼저 확인
      if mapping_store.type == STORE_TYPE_REDIS and redis_mapping[original_value] then
        masked_id = redis_mapping[original_value]
      else
        -- 새로운 마스킹 ID 생성
        masked_id = _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
      end
      
      if masked_id then
        -- 원본 값을 마스킹된 ID로 교체
        masked_text = string.gsub(masked_text, _M._escape_pattern(original_value), masked_id)
        mask_count = mask_count + 1
        
        -- 패턴 사용 통계 업데이트
        patterns_used[pattern_name] = (patterns_used[pattern_name] or 0) + 1
        
        -- CRITICAL: Store memory mapping for body_filter unmasking
        memory_mappings[masked_id] = original_value
        
        if kong and kong.log then
          kong.log.debug("[MASK_DATA] Masked: ", original_value, " -> ", masked_id)
        end
      end
      
      ::continue_match::
    end
    
    ::continue::
  end
  
  -- 디버깅: 마스킹 결과
  if kong and kong.log then
    kong.log.debug("[MASK_DATA] Masking complete. Total masks: ", mask_count)
    for pattern_name, count in pairs(patterns_used) do
      kong.log.debug("[MASK_DATA] Pattern '", pattern_name, "' used ", count, " times")
    end
  end
  
  return {
    masked = masked_text,
    count = mask_count,
    patterns_used = patterns_used,
    memory_mappings = memory_mappings  -- body_filter용 메모리 매핑
  }
end

---
-- Unmask previously masked identifiers back to original values
-- @param string text Text containing masked identifiers
-- @param table mapping_store Store containing masked value mappings
-- @return string Unmasked text
function _M.unmask_data(text, mapping_store)
  if type(text) ~= "string" or text == "" then
    return text
  end
  
  if not mapping_store then
    return text
  end
  
  -- CRITICAL: Always use memory-based unmasking to avoid TCP issues in body_filter
  -- Redis TCP connections are prohibited in OpenResty body_filter phase
  return _M._memory_unmask_data(text, mapping_store)
end

---
-- Redis 언마스킹 구현 (최적화)
-- @param string text Text containing masked identifiers
-- @param table mapping_store Redis storage for mappings
-- @return string Unmasked text
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
    for masked_id in string.gmatch(text, pattern) do
      if not masked_ids[masked_id] then
        masked_ids[masked_id] = true
        table.insert(id_positions, masked_id)
      end
    end
  end
  
  -- 2. 일괄 조회 (파이프라인)
  local unmasked_text = text
  if #id_positions > 0 then
    red:init_pipeline()
    
    for _, masked_id in ipairs(id_positions) do
      red:get(prefix .. "map:" .. masked_id)
    end
    
    local results, err = red:commit_pipeline()
    if err then
      kong.log.err("Redis unmask pipeline error: ", err)
      return text  -- 에러 시 원본 반환
    end
    
    -- 3. 결과 교체
    for i, masked_id in ipairs(id_positions) do
      local original_value = results[i]
      if original_value and original_value ~= ngx.null then
        unmasked_text = string.gsub(unmasked_text, _M._escape_pattern(masked_id), original_value)
      end
    end
  end
  
  return unmasked_text
end

---
-- 메모리 언마스킹 구현
-- @param string text Text containing masked identifiers
-- @param table mapping_store Memory storage for mappings
-- @return string Unmasked text
function _M._memory_unmask_data(text, mapping_store)
  if not mapping_store.mappings then
    return text
  end
  
  local unmasked_text = text
  
  -- Replace each masked identifier with original value
  for masked_id, original_value in pairs(mapping_store.mappings) do
    unmasked_text = string.gsub(unmasked_text, _M._escape_pattern(masked_id), original_value)
  end
  
  return unmasked_text
end

---
-- Get or create a masked identifier for an AWS resource
-- @param string original_value Original AWS resource identifier
-- @param table pattern_def Pattern definition with replacement format
-- @param table mapping_store Mapping store
-- @return string Masked identifier
function _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
  -- Redis 모드인 경우 먼저 시도
  if mapping_store.type == STORE_TYPE_REDIS then
    -- pcall을 사용하여 Redis 오류 처리
    local success, result = pcall(function()
      return _M._redis_get_or_create_masked_id(original_value, pattern_def, mapping_store)
    end)
    
    if success and result then
      return result
    else
      -- Redis 실패 시 메모리 모드로 폴백
      if kong and kong.log then
        kong.log.warn("[AWS-MASKER] Redis failed, falling back to memory mode for: ", original_value)
      end
      -- 메모리 스토어가 없으면 생성
      if not mapping_store.mappings then
        mapping_store.mappings = {}
        mapping_store.counters = {}
        mapping_store.reverse_mappings = {}
      end
      return _M._memory_get_or_create_masked_id(original_value, pattern_def, mapping_store)
    end
  else
    -- 메모리 모드
    return _M._memory_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  end
end

---
-- Redis 마스킹 구현
-- @param string original_value Original AWS resource identifier
-- @param table pattern_def Pattern definition containing type and replacement format
-- @param table mapping_store Redis storage for mappings
-- @return string Masked identifier
function _M._redis_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  local red = mapping_store.redis
  if not red then
    -- 연결 재시도
    red = mapping_store.acquire_connection()
    if not red then
      -- Fallback to memory
      kong.log.warn("Redis connection failed in _redis_get_or_create_masked_id")
      return _M._generate_masked_id(pattern_def.type, pattern_def.replacement, 0)
    end
    mapping_store.redis = red
  end
  
  -- Process Redis masking
  
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

---
-- 메모리 마스킹 구현 (개선)
-- @param string original_value Original AWS resource identifier
-- @param table pattern_def Pattern definition containing type and replacement format
-- @param table mapping_store Memory storage for mappings
-- @return string Masked identifier
function _M._memory_get_or_create_masked_id(original_value, pattern_def, mapping_store)
  -- O(1) reverse lookup
  local masked_id = mapping_store.reverse_mappings[original_value]
  if masked_id then
    return masked_id
  end
  
  -- 크기 제한 확인 (안전한 nil 체크)
  if mapping_store.stats and 
     mapping_store.stats.size and 
     mapping_store.stats.max_size and
     mapping_store.stats.size >= mapping_store.stats.max_size then
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
  
  -- stats 안전 업데이트
  if mapping_store.stats then
    mapping_store.stats.size = (mapping_store.stats.size or 0) + 1
  end
  
  return masked_id
end

---
-- Fallback 마스킹 ID 생성
-- @param string resource_type Resource type (ec2, vpc, etc.)
-- @param string replacement_format Format string for masked ID
-- @param number counter Counter value
-- @return string Generated masked ID
function _M._generate_masked_id(resource_type, replacement_format, counter)
  return string.format(replacement_format, counter)
end

---
-- 메모리에서 오래된 항목 제거
-- @param table mapping_store Memory storage for mappings
function _M._memory_evict_old_entries(mapping_store)
  -- 현재는 간단한 구현: 10% 제거
  local size_to_remove = math.floor(mapping_store.stats.max_size * 0.1)
  local removed = 0
  
  for masked_id, original_value in pairs(mapping_store.mappings) do
    if removed >= size_to_remove then break end
    
    mapping_store.mappings[masked_id] = nil
    mapping_store.reverse_mappings[original_value] = nil
    mapping_store.stats.size = mapping_store.stats.size - 1
    removed = removed + 1
  end
end

---
-- Escape special pattern characters for string replacement
-- @param string str String to escape
-- @return string Escaped string
function _M._escape_pattern(str)
  if type(str) ~= "string" then return "" end
  return string.gsub(str, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

---
-- Pre-fetch 기반 언마스킹 데이터 준비 (ACCESS에서 호출)
-- OpenResty body_filter 제약을 위한 2단계 처리의 1단계
-- @param string request_body 요청 바디 텍스트
-- @param table mapping_store Redis 매핑 저장소
-- @return table 언마스킹 맵 (masked_id -> original_value)
function _M.prepare_unmask_data(request_body, mapping_store)
  if type(request_body) ~= "string" or request_body == "" then
    return {}
  end
  
  if mapping_store.type ~= STORE_TYPE_REDIS then
    return {}  -- 메모리 모드는 기존 방식 사용
  end
  
  local red = mapping_store.redis
  if not red then
    red = _M.acquire_redis_connection()
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
      
      -- 언마스킹 맵 크기 계산
      local unmask_count = 0
      for _ in pairs(unmask_map) do unmask_count = unmask_count + 1 end
      
      kong.log.debug("Unmask map prepared: ", #query_order, " resources, ", 
                     unmask_count, " mappings found")
    else
      kong.log.err("Redis unmask preparation failed: ", err)
      mapping_store.stats.errors = mapping_store.stats.errors + 1
    end
  end
  
  return unmask_map
end

---
-- Pre-fetch된 데이터로 동기 언마스킹 적용 (BODY_FILTER에서 호출)
-- OpenResty body_filter 제약을 위한 2단계 처리의 2단계
-- @param string response_text 응답 텍스트
-- @param table unmask_map 언마스킹 맵 (masked_id -> original_value)
-- @return string 언마스킹된 텍스트
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

-- Initialize patterns on module load
_M.init_patterns()

return _M