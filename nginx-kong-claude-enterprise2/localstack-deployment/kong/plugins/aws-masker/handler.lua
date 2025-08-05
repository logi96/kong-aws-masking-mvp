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
local event_publisher = require "kong.plugins.aws-masker.event_publisher"

-- Plugin handler class
local AwsMaskerHandler = {}

---
-- Plugin metadata - Version and priority for Kong  
-- Priority 700 ensures execution after request-transformer (801) but before response processing
-- @type string
AwsMaskerHandler.VERSION = "1.0.0"
AwsMaskerHandler.PRIORITY = 700

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
  
  -- Phase 1: 강화된 API Key 접근 (Plugin Config 우선, 환경변수 Fallback)
  kong.log.info("=== API KEY ACCESS DEBUG ===")
  
  -- 1순위: Kong Plugin Config에서 API 키 가져오기
  local api_key_from_config = conf and conf.anthropic_api_key
  kong.log.info("Plugin config API key: ", api_key_from_config and "VALUE_FOUND" or "NIL")
  if api_key_from_config then
    kong.log.info("Config API Key length: ", string.len(api_key_from_config))
    kong.log.info("Config API Key first 10 chars: ", string.sub(api_key_from_config, 1, 10))
  end
  
  -- 2순위: 환경변수에서 API 키 가져오기 (Fallback)
  local api_key_from_env = os.getenv("ANTHROPIC_API_KEY")
  kong.log.info("Environment API key: ", api_key_from_env and "VALUE_FOUND" or "NIL")
  
  -- 3순위: ngx.var 시도 (추가 Fallback)
  local api_key_from_ngx = ngx.var.ANTHROPIC_API_KEY
  kong.log.info("ngx.var API key: ", api_key_from_ngx and "FOUND" or "NOT_FOUND")
  
  -- 최종 API 키 결정 (우선순위: Config > Environment > ngx.var)
  local final_api_key = api_key_from_config or api_key_from_env or api_key_from_ngx
  kong.log.info("Final API Key Selected: ", final_api_key and "YES" or "NO")
  if final_api_key then
    kong.log.info("Final API Key Source: ", 
      api_key_from_config and "PLUGIN_CONFIG" or 
      api_key_from_env and "ENVIRONMENT" or 
      "NGX_VAR")
  end
  
  -- API 키 헤더 자동 추가 (환경변수에서 읽어서 추가)
  if final_api_key and final_api_key ~= "" and final_api_key ~= "${ANTHROPIC_API_KEY}" then
    kong.service.request.set_header("x-api-key", final_api_key)
    kong.service.request.set_header("anthropic-version", "2023-06-01")
    
    -- Phase 1: 강화된 API Key 검증 로깅
    kong.log.info("=== STEP 1: API KEY VERIFICATION ===")
    kong.log.info("Environment API Key Available: YES")
    kong.log.info("API Key Length: ", string.len(final_api_key))
    kong.log.info("API Key Header Set: SUCCESS")
    kong.log.info("Header x-api-key: ", kong.request.get_header("x-api-key") and "CONFIRMED" or "FAILED")
    kong.log.info("Header anthropic-version: ", kong.request.get_header("anthropic-version") or "NOT_SET")
    kong.log.debug("API Key prefix: ", string.sub(final_api_key, 1, 10) .. "...")
  else
    kong.log.err("=== STEP 1: API KEY VERIFICATION FAILED ===")
    kong.log.err("Environment API Key Available: NO")
    kong.log.err("CRITICAL: ANTHROPIC_API_KEY environment variable not set")
    return error_codes.exit_with_error("MISSING_API_KEY", {
      error = "ANTHROPIC_API_KEY environment variable required for Claude API authentication"
    })
  end
  
  -- Claude API 요청 디버그 정보
  local upstream_uri = kong.request.get_path()
  local method = kong.request.get_method()
  kong.log.debug("Claude API Request - Method: ", method)
  kong.log.debug("Claude API Request - URI: ", upstream_uri)
  kong.log.debug("Claude API Request - Service: ", kong.router.get_service() and kong.router.get_service().name or "unknown")
  
  -- Lazy initialization with config (Enhanced with ElastiCache support)
  if not self.mapping_store then
    local store_options = {
      ttl = conf and conf.mapping_ttl or 604800,  -- 7일
      max_entries = conf and conf.max_entries or 10000,
      use_redis = conf and conf.use_redis ~= false,  -- 기본값 true
      
      -- ElastiCache configuration
      redis_type = conf and conf.redis_type or "traditional",
      redis_host = conf and conf.redis_host or "redis",
      redis_port = conf and conf.redis_port or 6379,
      redis_database = conf and conf.redis_database or 0,
      
      -- ElastiCache SSL/TLS configuration (only for managed Redis)
      redis_ssl_enabled = (conf and conf.redis_type == "managed") and (conf.redis_ssl_enabled or false) or false,
      redis_ssl_verify = (conf and conf.redis_type == "managed") and (conf.redis_ssl_verify ~= false) or nil,
      
      -- ElastiCache authentication (only for managed Redis)
      redis_auth_token = (conf and conf.redis_type == "managed") and conf.redis_auth_token or nil,
      redis_user = (conf and conf.redis_type == "managed") and conf.redis_user or nil,
      
      -- ElastiCache cluster configuration (only for managed Redis)
      redis_cluster_mode = (conf and conf.redis_type == "managed") and (conf.redis_cluster_mode or false) or false,
      redis_cluster_endpoint = (conf and conf.redis_type == "managed") and conf.redis_cluster_endpoint or nil
    }
    
    -- Log configuration for debugging
    kong.log.info("[AWS-MASKER] Creating mapping store with configuration:", {
      redis_type = store_options.redis_type,
      ssl_enabled = store_options.redis_ssl_enabled,
      cluster_mode = store_options.redis_cluster_mode
    })
    
    self.mapping_store = masker.create_mapping_store(store_options)
  end
  
  -- WARN: Redis is preferred but not mandatory - fallback to memory mode
  if not self.mapping_store then
    kong.log.err("[AWS-MASKER] No mapping store available")
    return error_codes.exit_with_error("MAPPING_STORE_UNAVAILABLE")
  end
  
  -- Phase 1: Smart fail-secure - AWS 패턴 있을 때만 Redis 필수
  local raw_body = kong.request.get_raw_body()
  local has_aws_patterns = false
  
  if raw_body and raw_body ~= "" then
    has_aws_patterns = self:_detect_aws_patterns(raw_body)
    kong.log.info("=== STEP 2: PATTERN DETECTION ===")
    kong.log.info("Request Body Size: ", string.len(raw_body))
    kong.log.info("AWS Patterns Detected: ", has_aws_patterns and "YES" or "NO")
  else
    kong.log.info("=== STEP 2: PATTERN DETECTION ===")
    kong.log.info("Request Body: EMPTY")
    kong.log.info("AWS Patterns Detected: NO")
  end
  
  -- SECURITY: Smart fail-secure - Redis 필수는 AWS 패턴 있을 때만
  if has_aws_patterns and self.mapping_store.type ~= "redis" then
    kong.log.err("[AWS-MASKER] SECURITY BLOCK: AWS patterns detected but Redis unavailable")
    return error_codes.exit_with_error("REDIS_UNAVAILABLE", {
      security_reason = "fail_secure_aws_patterns",
      aws_patterns_detected = true,
      details = "Service blocked to prevent AWS data exposure when Redis is unavailable"
    })
  elseif not has_aws_patterns and self.mapping_store.type ~= "redis" then
    kong.log.info("[AWS-MASKER] PASS-THROUGH: No AWS patterns, allowing request without Redis")
    kong.log.info("=== STEP 3: MASKING PROCESS ===")
    kong.log.info("Masking Required: NO")
    kong.log.info("Pass-through Mode: ENABLED")
    -- AWS 패턴이 없으면 Redis 없어도 통과 허용
  else
    kong.log.info("[AWS-MASKER] REDIS AVAILABLE: Normal masking mode")
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
  
  -- Generate or retrieve request ID for tracking
  local request_id = kong.request.get_header("x-request-id")
  if not request_id then
    request_id = string.format("%s-%s-%s", ngx.now(), ngx.var.connection, ngx.var.connection_requests)
    kong.service.request.set_header("X-Request-ID", request_id)
  end
  
  -- Log request start
  kong.log.info(string.format("[REQUEST-START] request_id=%s method=%s uri=%s body_size=%d", 
    request_id, 
    kong.request.get_method(), 
    kong.request.get_path(),
    raw_body and #raw_body or 0
  ))
  
  -- Handle request masking (no pcall due to Redis yield restrictions)
  local raw_body = kong.request.get_raw_body()
  if raw_body then
    -- SECURITY: First check if AWS patterns are present
    local patterns_detected = self:_detect_aws_patterns(raw_body)
    
    -- 1단계: 기존 마스킹 수행 (항상 문자열로)
    local mask_result = masker.mask_data(raw_body, self.mapping_store, self.config)
    
    -- CRITICAL: Extract memory mappings from masking result for body_filter
    if mask_result and mask_result.memory_mappings then
      kong.ctx.shared.aws_memory_mappings = mask_result.memory_mappings
    end
    
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
    
    -- WARNING: If AWS patterns were detected but nothing was masked, log it
    -- This can happen for legitimate reasons (e.g., private IPs, already masked values)
    if patterns_detected and mask_result.count == 0 then
      kong.log.warn("[SECURITY] AWS patterns detected but masking returned 0 count - allowing request")
      monitoring.log_security_event({
        type = "MASKING_PATTERN_MISMATCH",
        severity = "MEDIUM",
        details = {
          patterns_detected = patterns_detected,
          mask_count = 0,
          reason = "Possible private IP or pre-masked value"
        },
        action_taken = "Request allowed with warning"
      })
      -- Still record as success since we're allowing it
      health_check.update_masking_stats({
        success = true,
        latency_ms = (ngx.now() - start_time) * 1000
      })
    end
    
    -- Use the masked string directly
    local masked_body = mask_result.masked
    
    -- Claude API Request Body Debug
    kong.log.debug("=== CLAUDE API REQUEST BODY DEBUG ===")
    kong.log.debug("Request ID: ", request_id)
    kong.log.debug("Original body size: ", string.len(raw_body))
    kong.log.debug("Masked body size: ", string.len(masked_body))
    kong.log.debug("Mask count: ", mask_result.count)
    
    -- Log first 500 characters of masked body for debugging (safe since it's masked)
    if string.len(masked_body) > 500 then
      kong.log.debug("Masked body preview: ", string.sub(masked_body, 1, 500) .. "... (truncated)")
    else
      kong.log.debug("Masked body full: ", masked_body)
    end
    
    -- Comprehensive masking event logging
    local masking_log = {
      request_id = request_id,
      stage = "masking",
      original_size = string.len(raw_body),
      masked_size = string.len(masked_body),
      mask_count = mask_result.count,
      patterns_used = mask_result.patterns_used or {},
      processing_time_ms = (ngx.now() - start_time) * 1000
    }
    
    -- Log masking event in JSON format
    kong.log.info(string.format("[MASKING-EVENT] %s", json_safe.encode(masking_log)))
    
    -- Debug log individual patterns
    if mask_result.patterns_used then
      for pattern, count in pairs(mask_result.patterns_used) do
        kong.log.debug(string.format("[MASKING-PATTERN] request_id=%s pattern=%s count=%d", 
          request_id, pattern, count))
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
      
      -- CRITICAL: Create memory mappings for body_filter unmasking
      if not kong.ctx.shared.aws_memory_mappings then
        kong.ctx.shared.aws_memory_mappings = {}
      end
      
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
      
      -- 실시간 모니터링: 마스킹 이벤트 발행 (내부 데모용 - before/after 포함)
      if event_publisher.is_event_publishing_enabled() then
        local success = event_publisher.publish_masking_event({
          success = true,
          patterns_used = mask_result.patterns_used,
          count = mask_result.count,
          processing_time_ms = elapsed_time,
          request_size = string.len(raw_body),
          -- 내부 데모용: before/after 텍스트 추가
          original_text = raw_body,
          masked_text = masked_body
        }, self.mapping_store.redis) -- 기존 Redis 연결 재사용
        -- 이벤트 발행 실패해도 기존 로직에 영향 없음 (fire-and-forget)
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
  
  -- Store 정리 (중요: Redis/ElastiCache Connection 반환)
  if self.mapping_store and self.mapping_store.type == "redis" then
    if self.mapping_store.redis_type == "managed" then
      -- ElastiCache connection cleanup
      if self.mapping_store.redis_client then
        -- ElastiCache uses integrated connection management
        kong.log.debug("[AWS-MASKER] ElastiCache connections managed by redis_client")
      end
    else
      -- Traditional Redis connection cleanup
      if self.mapping_store.redis then
        masker.release_redis_connection(self.mapping_store.redis)
        self.mapping_store.redis = nil
      end
    end
  end
end

---
-- Header filter phase - captures Claude API response status and headers
-- Critical for debugging Claude API communication failures
-- @param table conf Plugin configuration from Kong
function AwsMaskerHandler:header_filter(conf)
  local status = kong.response.get_status()
  local headers = kong.response.get_headers()
  
  -- Get request ID for correlation
  local request_id = kong.request.get_header("x-request-id") or "unknown"
  
  -- Claude API Response Analysis
  kong.log.debug("=== CLAUDE API RESPONSE DEBUG ===")
  kong.log.debug("Request ID: ", request_id)
  kong.log.debug("Response Status: ", status)
  kong.log.debug("Content-Type: ", headers["content-type"] or "none")
  kong.log.debug("Content-Length: ", headers["content-length"] or "none")
  
  -- Detect Claude API errors
  if status >= 400 then
    kong.log.err("=== CLAUDE API ERROR DETECTED ===")
    kong.log.err("Request ID: ", request_id)
    kong.log.err("Error Status: ", status)
    kong.log.err("Error Headers: ", json_safe.encode(headers))
    
    -- Specific Claude API error analysis
    if status == 401 then
      kong.log.err("CLAUDE API 401: Authentication failed - Invalid API key")
    elseif status == 403 then
      kong.log.err("CLAUDE API 403: Forbidden - API key permissions issue")
    elseif status == 429 then
      kong.log.err("CLAUDE API 429: Rate limit exceeded")
      kong.log.err("Rate limit headers: ", headers["retry-after"] or "none")
    elseif status == 400 then
      kong.log.err("CLAUDE API 400: Bad request - Check request format")
    elseif status >= 500 then
      kong.log.err("CLAUDE API 5xx: Server error - Claude API internal issue")
    end
    
    -- Store error info for body_filter analysis
    kong.ctx.shared.claude_api_error = {
      status = status,
      headers = headers,
      timestamp = ngx.now()
    }
  else
    kong.log.info("Claude API Success - Status: ", status, " Request ID: ", request_id)
  end
end

---
-- Body filter phase - unmasks AWS resources in inbound responses
-- Restores original AWS identifiers in responses from external APIs
-- @param table conf Plugin configuration from Kong
function AwsMaskerHandler:body_filter(conf)
  local chunk = ngx.arg[1]
  local is_last_chunk = ngx.arg[2]
  
  -- Get request ID for correlation
  local request_id = kong.request.get_header("x-request-id") or "unknown"
  
  -- If there was a Claude API error, capture the error response body
  if kong.ctx.shared.claude_api_error and chunk and chunk ~= "" then
    if not kong.ctx.shared.claude_error_body then
      kong.ctx.shared.claude_error_body = ""
    end
    kong.ctx.shared.claude_error_body = kong.ctx.shared.claude_error_body .. chunk
    
    -- On last chunk, log the complete error response
    if is_last_chunk then
      kong.log.err("=== CLAUDE API ERROR BODY ===")
      kong.log.err("Request ID: ", request_id)
      kong.log.err("Error Body: ", kong.ctx.shared.claude_error_body)
      
      -- Try to parse JSON error response
      local decoded_error = json_safe.decode(kong.ctx.shared.claude_error_body)
      if decoded_error and decoded_error.error then
        kong.log.err("Claude API Error Details:")
        kong.log.err("  Type: ", decoded_error.error.type or "unknown")
        kong.log.err("  Message: ", decoded_error.error.message or "no message")
      end
    end
  end
  
  -- Skip unmasking if no mappings
  if not kong.ctx.shared.aws_memory_mappings or not next(kong.ctx.shared.aws_memory_mappings) then
    return
  end
  
  -- Get request ID for correlation
  local request_id = kong.request.get_header("x-request-id") or "unknown"
  
  -- Track unmasking stats
  if not kong.ctx.shared.unmask_stats then
    kong.ctx.shared.unmask_stats = {
      start_time = ngx.now(),
      unmask_count = 0,
      chunks_processed = 0
    }
  end
  
  -- Only process non-empty chunks
  if chunk and chunk ~= "" then
    local original_chunk_size = #chunk
    local unmask_count = 0
    
    -- Apply all unmaskings to this chunk
    for masked_id, original_value in pairs(kong.ctx.shared.aws_memory_mappings) do
      local new_chunk, n = string.gsub(chunk, masked_id, original_value)
      if n > 0 then
        chunk = new_chunk
        unmask_count = unmask_count + n
        kong.ctx.shared.unmask_stats.unmask_count = kong.ctx.shared.unmask_stats.unmask_count + n
      end
    end
    
    kong.ctx.shared.unmask_stats.chunks_processed = kong.ctx.shared.unmask_stats.chunks_processed + 1
    
    -- Log chunk processing
    if unmask_count > 0 then
      kong.log.debug(string.format("[UNMASK-CHUNK] request_id=%s chunk_size=%d unmask_count=%d", 
        request_id, original_chunk_size, unmask_count))
    end
    
    -- Update the chunk
    ngx.arg[1] = chunk
  end
  
  -- Log final unmasking stats on last chunk
  if is_last_chunk and kong.ctx.shared.unmask_stats.unmask_count > 0 then
    local unmask_log = {
      request_id = request_id,
      stage = "unmasking",
      unmask_count = kong.ctx.shared.unmask_stats.unmask_count,
      chunks_processed = kong.ctx.shared.unmask_stats.chunks_processed,
      processing_time_ms = (ngx.now() - kong.ctx.shared.unmask_stats.start_time) * 1000
    }
    kong.log.info(string.format("[UNMASK-EVENT] %s", json_safe.encode(unmask_log)))
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
    -- EC2 instances (17-character hex ID)
    "i%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]",
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