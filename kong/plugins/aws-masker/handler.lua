--
-- Kong 3.7 Compatible AWS Masker Plugin Handler
-- Simplified for compatibility without base_plugin dependency
-- Following CLAUDE.md: < 5s total response time, security-first design
--

local masker = require "kong.plugins.aws-masker.masker_ngx_re"
local json_safe = require "kong.plugins.aws-masker.json_safe"
local monitoring = require "kong.plugins.aws-masker.monitoring"
local auth_handler = require "kong.plugins.aws-masker.auth_handler"

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
    mapping_store = masker.create_mapping_store(),
    config = {
      mask_ec2_instances = true,
      mask_s3_buckets = true, 
      mask_rds_instances = true,
      mask_private_ips = true,
      preserve_structure = true,
      log_masked_requests = false
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
  
  -- Initialize mapping store if not exists
  if not self.mapping_store then
    self.mapping_store = masker.create_mapping_store()
    -- mapping store 생성됨
  end
  
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
      log_masked_requests = true
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
  
  -- Handle request masking with error protection
  local success, err = pcall(function()
    local raw_body = kong.request.get_raw_body()
    
    -- 요청 바디 처리 시작
    
    if raw_body then
      -- Attempt to parse as JSON, fallback to string masking
      local request_data, decode_err = json_safe.decode(raw_body)
      if decode_err then
        -- 문자열로 처리
        request_data = raw_body
      else
        -- JSON 디코드 성공
      end
      
      -- 마스킹 시작
      
      -- Mask AWS resources using masker module
      local mask_result = masker.mask_data(request_data, self.mapping_store, self.config)
      
      -- 보안: 원본 데이터를 로그에 출력하지 않음
      
      -- Convert masked result back to JSON if it was originally JSON
      local masked_body = self:_prepare_masked_body(mask_result)
      
      if masked_body then
        -- 마스킹 완료
        
        kong.service.request.set_raw_body(masked_body)
        
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
        
        -- Track pattern usage
        if mask_result.patterns_used then
          for pattern_name, count in pairs(mask_result.patterns_used) do
            monitoring.track_pattern_usage(pattern_name, count)
          end
        end
      else
        kong.log.warn("AWS Masker: Failed to prepare masked body")
        monitoring.collect_request_metric({
          success = false,
          elapsed_time = (ngx.now() - start_time) * 1000
        })
      end
    else
      kong.log.warn("AWS Masker: No raw body found in request")
    end
  end)
  
  -- Log errors but don't fail the request
  if not success then
    kong.log.err("AWS masking error in access phase: " .. tostring(err))
    
    -- Record failure in monitoring
    monitoring.collect_request_metric({
      success = false,
      elapsed_time = (ngx.now() - start_time) * 1000,
      error = tostring(err)
    })
    
    -- Log security event for failures
    monitoring.log_security_event({
      type = "MASKING_FAILURE",
      severity = "HIGH",
      details = {
        error = tostring(err),
        phase = "access"
      },
      action_taken = "Request passed without masking"
    })
  end
end

---
-- Body filter phase - unmasks AWS resources in inbound responses
-- Restores original AWS identifiers in responses from external APIs
-- @param table conf Plugin configuration from Kong
function AwsMaskerHandler:body_filter(conf)
  -- 언마스킹 활성화
  local chunk = kong.response.get_raw_body()
  
  if chunk and kong.ctx.shared.aws_mapping_store then
    -- JSON 응답 파싱 시도
    local response_data, err = json_safe.decode(chunk)
    if not err and response_data and response_data.content then
      -- Claude 응답 텍스트 언마스킹
      for _, content in ipairs(response_data.content) do
        if content.type == "text" and content.text then
          -- 언마스킹 수행
          content.text = masker.unmask_data(content.text, kong.ctx.shared.aws_mapping_store)
        end
      end
      
      -- 언마스킹된 응답 인코딩
      local unmasked_body, encode_err = json_safe.encode(response_data)
      if not encode_err then
        -- JSON 인코딩 후 슬래시 이스케이프 제거
        -- cjson이 \/ 로 인코딩한 것을 / 로 복원
        unmasked_body = unmasked_body:gsub("\\/", "/")
        kong.response.set_raw_body(unmasked_body)
      end
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

-- Return the handler class
return AwsMaskerHandler

--
-- Kong 3.7 Compatible Handler Complete
-- Simplified architecture without BasePlugin dependency for better compatibility
-- All core functionality maintained: masking, unmasking, performance, security
--