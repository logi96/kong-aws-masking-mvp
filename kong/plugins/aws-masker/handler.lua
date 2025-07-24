--
-- Kong 3.7 Compatible AWS Masker Plugin Handler
-- Simplified for compatibility without base_plugin dependency
-- Following CLAUDE.md: < 5s total response time, security-first design
--

local masker = require "kong.plugins.aws-masker.masker_ngx_re"
local json_safe = require "kong.plugins.aws-masker.json_safe"
local monitoring = require "kong.plugins.aws-masker.monitoring"
local auth_handler = require "kong.plugins.aws-masker.auth_handler"
local error_codes = require "kong.plugins.aws-masker.error_codes"
local health_check = require "kong.plugins.aws-masker.health_check"

-- Plugin handler class
local AwsMaskerHandler = {}

---
-- Plugin metadata - Version and priority for Kong  
-- Priority 900 ensures execution before most plugins but after auth
-- @type string
AwsMaskerHandler.VERSION = "1.0.0"
AwsMaskerHandler.PRIORITY = 900

---
-- Creates new handler instance
-- Initializes mapping store and default configuration  
-- @return table Handler instance with mapping store and config
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
      redis_fallback = true,
      mapping_ttl = 604800  -- 7일
    }
  }
  
  return setmetatable(instance, { __index = self })
end

---
-- Access phase - masks AWS resources in outbound requests
-- Handles request body masking before sending to external APIs
-- Performance optimized for < 100ms masking requirement
-- @param table conf Plugin configuration from Kong
function AwsMaskerHandler:access(conf)
  -- SECURITY: Fail-secure approach - no Redis, no service
  local redis_check_ok = false
  
  -- Verify Redis is available before any processing
  
  -- 보안 체크포인트: JSON 모듈 검증
  if not json_safe.is_available() then
    kong.log.err("AWS Masker: CRITICAL - No JSON library available")
    -- JSON 모듈 테스트
    local test_ok, test_msg = json_safe.test()
    if not test_ok then
      kong.log.err("AWS Masker: JSON module test failed: " .. test_msg)
    else
      kong.log.info("AWS Masker: " .. test_msg)
    end
  end
  
  -- API 키 헤더 전달 (Backend에서 설정한 x-api-key를 Claude API로 전달)
  local headers = kong.request.get_headers()
  if headers["x-api-key"] then
    kong.service.request.set_header("x-api-key", headers["x-api-key"])
    -- API 키 전달 성공
  else
    -- 헤더 없음
  end
  
  -- Lazy initialization with config
  if not self.mapping_store then
    local store_options = {
      ttl = conf and conf.mapping_ttl or 604800,  -- 7일
      max_entries = conf and conf.max_entries or 10000,
      use_redis = conf and conf.use_redis ~= false  -- 기본값 true
    }
    self.mapping_store = masker.create_mapping_store(store_options)
  end
  
  -- WARN: Redis is preferred but not mandatory - fallback to memory mode
  if not self.mapping_store then
    kong.log.err("[AWS-MASKER] No mapping store available")
    return error_codes.exit_with_error("MAPPING_STORE_UNAVAILABLE")
  end
  
  -- SECURITY: Fail-secure approach - no Redis, no service
  if self.mapping_store.type ~= "redis" then
    kong.log.err("[AWS-MASKER] SECURITY BLOCK: Redis unavailable - fail-secure mode activated")
    return error_codes.exit_with_error("REDIS_UNAVAILABLE", {
      security_reason = "fail_secure",
      details = "Service blocked to prevent AWS data exposure when Redis is unavailable"
    })
  end
  
  -- Check Circuit Breaker before proceeding
  local allow_request, cb_state = health_check.should_allow_request()
  if not allow_request then
    kong.log.err("[CIRCUIT BREAKER] Request blocked - circuit is OPEN")
    return error_codes.exit_with_error("REDIS_UNAVAILABLE", {
      circuit_breaker = cb_state,
      details = "Service temporarily unavailable due to repeated failures"
    })
  end
  
  -- Test Redis health periodically
  if self.mapping_store.redis then
    local current_time = ngx.now()
    local last_check = health_check.health_status.redis.last_check or 0
    
    -- Check every 5 seconds
    if current_time - last_check > 5 then
      local health_ok, health_err = health_check.check_redis_health(self.mapping_store.redis)
      if not health_ok then
        kong.log.err("[HEALTH CHECK] Redis unhealthy: ", health_err)
        health_check.record_operation_result(false)
      end
    end
  end
  
  redis_check_ok = true
  
  -- Apply configuration with safety check
  if conf then
    self.config = self.config or {}
    for key, value in pairs(conf) do
      self.config[key] = value
    end
  else
    -- Use default configuration
    self.config = {
      mask_ec2_instances = true,
      mask_s3_buckets = true, 
      mask_rds_instances = true,
      mask_private_ips = true,
      preserve_structure = true,
      log_masked_requests = true,
      use_redis = true,
      redis_fallback = true
    }
  end
  
  -- 보안 체크포인트: API 인증 처리
  local auth_success, auth_err = auth_handler.handle_authentication()
  if not auth_success then
    kong.log.err("AWS Masker: Authentication handling failed: " .. (auth_err or "unknown"))
    -- 인증 실패해도 계속 진행 (마스킹은 수행)
    monitoring.log_security_event({
      type = "AUTH_HANDLING_FAILED",
      severity = "MEDIUM",
      details = {
        error = auth_err
      },
      action_taken = "Continuing with masking"
    })
  end
  
  -- Enable request buffering to access body (Kong 3.7 compatible)
  kong.service.request.enable_buffering()
  
  -- Start timing for performance monitoring
  local start_time = ngx.now()
  
  -- Handle request masking (no pcall due to Redis yield restrictions)
  local raw_body = kong.request.get_raw_body()
  if raw_body then
    -- SECURITY: First check if AWS patterns are present
    local patterns_detected = self:_detect_aws_patterns(raw_body)
    
    -- 1단계: 기존 마스킹 수행 (항상 문자열로)
    local mask_result = masker.mask_data(raw_body, self.mapping_store, self.config)
    
    -- SECURITY CHECK: Verify masking occurred if AWS patterns are present
    -- This prevents unmasked data from reaching external APIs
    if not mask_result then
      error_codes.log_error("MASKING_PROCESSING_ERROR")
      health_check.update_masking_stats({
        success = false,
        latency_ms = (ngx.now() - start_time) * 1000
      })
      health_check.record_operation_result(false)
      return error_codes.exit_with_error("MASKING_PROCESSING_ERROR")
    end
    
    -- CRITICAL: If AWS patterns were detected but nothing was masked, BLOCK
    if patterns_detected and mask_result.count == 0 then
      kong.log.err("[SECURITY] AWS patterns detected but masking returned 0 count")
      monitoring.log_security_event({
        type = "MASKING_BYPASS_ATTEMPT",
        severity = "CRITICAL",
        details = {
          patterns_detected = patterns_detected,
          mask_count = 0
        },
        action_taken = "Request blocked"
      })
      health_check.update_masking_stats({
        success = false,
        latency_ms = (ngx.now() - start_time) * 1000
      })
      health_check.record_operation_result(false)
      return error_codes.exit_with_error("MASKING_PATTERN_MISMATCH", {
        patterns_detected = patterns_detected,
        mask_count = 0
      })
    end
    
    -- Use the masked string directly
    local masked_body = mask_result.masked
    
    -- Debug log masking results
    kong.log.debug("[MASKING] Original body length: ", string.len(raw_body))
    kong.log.debug("[MASKING] Masked body length: ", string.len(masked_body))
    kong.log.debug("[MASKING] Mask count: ", mask_result.count)
    if mask_result.patterns_used then
      for pattern, count in pairs(mask_result.patterns_used) do
        kong.log.debug("[MASKING] Pattern ", pattern, " matched ", count, " times")
      end
    end
    
    if masked_body then
      kong.service.request.set_raw_body(masked_body)
      
      -- 2단계: Redis 모드인 경우 언마스킹 Pre-fetch 수행
      if self.mapping_store.type == "redis" then
        local unmask_map = masker.prepare_unmask_data(raw_body, self.mapping_store)
        -- Kong context에 언마스킹 데이터 저장 (BODY_FILTER에서 사용)
        kong.ctx.shared.aws_unmask_map = unmask_map
        -- 언마스킹 맵 크기 계산
        local unmask_count = 0
        if unmask_map then
          for _ in pairs(unmask_map) do unmask_count = unmask_count + 1 end
        end
        -- Pre-fetch completed
      end
      
      -- Store mapping context for response unmasking
      kong.ctx.shared.aws_mapping_store = self.mapping_store
      
      -- Log if requested
      self:_log_masking_result(mask_result)
      
      -- Collect monitoring metrics
      local elapsed_time = (ngx.now() - start_time) * 1000 -- Convert to milliseconds
      monitoring.collect_request_metric({
        success = true,
        elapsed_time = elapsed_time,
        request_size = string.len(raw_body),
        pattern_count = mask_result.count
      })
      
      -- Update health metrics
      health_check.update_masking_stats({
        success = true,
        latency_ms = elapsed_time
      })
      health_check.record_operation_result(true)
      
      -- Track pattern usage
      if mask_result.patterns_used then
        for pattern_name, count in pairs(mask_result.patterns_used) do
          monitoring.track_pattern_usage(pattern_name, count)
        end
      end
    else
      -- SECURITY: Block request if masking failed
      kong.log.err("[SECURITY] Failed to prepare masked body")
      local failure_time = (ngx.now() - start_time) * 1000
      monitoring.collect_request_metric({
        success = false,
        elapsed_time = failure_time
      })
      health_check.update_masking_stats({
        success = false,
        latency_ms = failure_time
      })
      health_check.record_operation_result(false)
      return error_codes.exit_with_error("MASKING_BODY_PREPARATION_ERROR")
    end
  else
    -- No body is acceptable for some requests (GET, DELETE, etc.)
    -- Continue processing without masking
  end
  
  -- Store 정리 (중요: Redis Connection 반환)
  if self.mapping_store and self.mapping_store.type == "redis" and self.mapping_store.redis then
    masker.release_redis_connection(self.mapping_store.redis)
    self.mapping_store.redis = nil
  end
end

---
-- Body filter phase - unmasks AWS resources in inbound responses
-- Restores original AWS identifiers in responses from external APIs
-- @param table conf Plugin configuration from Kong
function AwsMaskerHandler:body_filter(conf)
  local chunk = kong.response.get_raw_body()
  
  if chunk and kong.ctx.shared.aws_mapping_store then
    local mapping_store = kong.ctx.shared.aws_mapping_store
    
    -- Pre-fetch된 언마스킹 데이터 사용 (ACCESS에서 준비됨)
    local unmask_map = kong.ctx.shared.aws_unmask_map
    
    if mapping_store.type == "redis" then
      -- Redis 모드: Claude 응답에서 마스킹된 ID 직접 추출하여 언마스킹
      local response_data, err = json_safe.decode(chunk)
      if not err and response_data and response_data.content then
        -- Claude 응답 텍스트에서 마스킹된 ID 패턴 추출
        for _, content in ipairs(response_data.content) do
          if content.type == "text" and content.text then
            local original_text = content.text
            
            -- 마스킹된 ID 패턴 추출 ([A-Z_]+_\d+)
            local masked_ids = {}
            for masked_id in string.gmatch(original_text, "([A-Z_]+_%d+)") do
              if not masked_ids[masked_id] then
                masked_ids[masked_id] = true
              end
            end
            
            -- Redis에서 마스킹된 ID들의 원본 값 조회
            if next(masked_ids) then
              local red = masker.acquire_redis_connection()
              if red then
                local real_unmask_map = {}
                for masked_id in pairs(masked_ids) do
                  local map_key = "aws_masker:map:" .. masked_id
                  local original_value, redis_err = red:get(map_key)
                  if not redis_err and original_value and original_value ~= ngx.null then
                    real_unmask_map[masked_id] = original_value
                  end
                end
                masker.release_redis_connection(red)
                
                -- 실제 언마스킹 적용
                if next(real_unmask_map) then
                  content.text = masker.apply_unmask_data(content.text, real_unmask_map)
                  
                  -- Debug 로그
                  local unmask_keys = {}
                  for k, v in pairs(real_unmask_map) do
                    table.insert(unmask_keys, k .. "=>" .. v)
                  end
                  kong.log.debug("[REAL_UNMASK] Applied: ", table.concat(unmask_keys, ", "))
                end
              end
            end
          end
        end
        
        -- 언마스킹된 응답 인코딩
        local unmasked_body, encode_err = json_safe.encode(response_data)
        if not encode_err then
          -- JSON 인코딩 후 슬래시 이스케이프 제거
          unmasked_body = unmasked_body:gsub("\\/", "/")
          kong.response.set_raw_body(unmasked_body)
        end
      end
    else
      -- Memory 모드는 기존 방식 사용
      local unmasked_text = masker.unmask_data(chunk, mapping_store)
      kong.response.set_raw_body(unmasked_text)
      kong.log.debug("Memory unmask applied")
    end
    
    -- 언마스킹 통계 업데이트
    if mapping_store.stats then
      mapping_store.stats.unmask_requests = (mapping_store.stats.unmask_requests or 0) + 1
    end
  end
end

---
-- Prepares masked body for outbound request
-- Handles JSON encoding and type conversion
-- @param table mask_result Result from masker.mask_data
-- @return string|nil Prepared masked body
function AwsMaskerHandler:_prepare_masked_body(mask_result)
  if not mask_result or not mask_result.masked then
    return nil
  end
  
  if type(mask_result.masked) == "table" then
    local encoded, err = json_safe.encode(mask_result.masked)
    if err then
      kong.log.err("AWS Masker: Failed to encode masked data: " .. err)
      -- 보안 최우선: 인코딩 실패 시 요청 차단
      return nil
    end
    return encoded
  else
    return mask_result.masked
  end
end

---
-- Prepares unmasked body for client response
-- Handles JSON encoding and type conversion
-- @param any unmasked_data Unmasked data from masker.unmask_data
-- @return string|nil Prepared unmasked body
function AwsMaskerHandler:_prepare_unmasked_body(unmasked_data)
  if not unmasked_data then
    return nil
  end
  
  if type(unmasked_data) == "table" then
    local encoded, err = json_safe.encode(unmasked_data)
    if err then
      kong.log.err("AWS Masker: Failed to encode unmasked data: " .. err)
      -- 보안 최우선: 언마스킹 실패 시 원본 데이터 노출 방지
      return nil
    end
    return encoded
  else
    return unmasked_data
  end
end

---
-- Logs masking results if logging is enabled
-- @param table mask_result Result from masker.mask_data
function AwsMaskerHandler:_log_masking_result(mask_result)
  -- 로깅 비활성화 (보안)
end

---
-- Detect AWS patterns in request body for fail-secure validation
-- @param string body Request body to scan
-- @return boolean True if AWS patterns detected
function AwsMaskerHandler:_detect_aws_patterns(body)
  if type(body) ~= "string" or body == "" then
    return false
  end
  
  -- Quick pattern checks for common AWS resources
  local aws_patterns = {
    -- EC2 instances
    "i%-[0-9a-f]+",
    -- VPC resources
    "vpc%-[0-9a-f]+",
    "subnet%-[0-9a-f]+", 
    "sg%-[0-9a-f]+",
    -- S3 buckets (common patterns)
    "s3://[%w%-%.]+",
    "%.s3%.amazonaws%.com",
    "%.s3%-[%w%-]+%.amazonaws%.com",
    -- Private IPs
    "10%.%d+%.%d+%.%d+",
    "172%.1[6-9]%.%d+%.%d+",
    "172%.2%d%.%d+%.%d+",
    "172%.3[01]%.%d+%.%d+",
    "192%.168%.%d+%.%d+",
    -- RDS instances
    "[%w%-]+%.rds%.amazonaws%.com",
    -- ARNs
    "arn:aws:[%w%-]+:[%w%-]*:[%w%-]*:",
    -- IAM
    "AKIA[0-9A-Z]+",
    "aws_access_key_id",
    "aws_secret_access_key"
  }
  
  -- Scan for any AWS pattern
  for _, pattern in ipairs(aws_patterns) do
    if string.find(body, pattern) then
      return true
    end
  end
  
  return false
end

-- Return the handler class
return AwsMaskerHandler

--
-- Kong 3.7 Compatible Handler Complete
-- Simplified architecture without BasePlugin dependency for better compatibility
-- All core functionality maintained: masking, unmasking, performance, security
--