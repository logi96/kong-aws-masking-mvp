--
-- Kong AWS Masker ElastiCache Edition - Handler
-- Production-ready AWS resource masking with ElastiCache integration  
-- Phase 1 Success Version Enhanced for ElastiCache
--

local elasticache_client = require "kong.plugins.aws-masker-elasticache.elasticache_client"
local json_safe = require "kong.plugins.aws-masker-elasticache.json_safe"
local patterns = require "kong.plugins.aws-masker-elasticache.patterns"
local error_codes = require "kong.plugins.aws-masker-elasticache.error_codes"

-- Plugin handler class
local AwsMaskerElastiCacheHandler = {}

AwsMaskerElastiCacheHandler.VERSION = "2.0.0-elasticache"
AwsMaskerElastiCacheHandler.PRIORITY = 700

function AwsMaskerElastiCacheHandler:new()
  local instance = {
    elasticache_client = nil,  -- Lazy initialization
    config = {
      -- Default configuration
      mask_ec2_instances = true,
      mask_s3_buckets = true,
      mask_rds_instances = true,
      mask_private_ips = true,
      preserve_structure = true,
      log_masked_requests = false,
      fail_secure = true,
      mapping_ttl = 604800,  -- 7 days
      -- ElastiCache defaults
      elasticache_ssl_enabled = true,
      connection_timeout = 2000,
      max_retry_attempts = 3
    }
  }
  return setmetatable(instance, { __index = self })
end

-- Initialize ElastiCache client (lazy loading)
function AwsMaskerElastiCacheHandler:init_elasticache_client(conf)
  if not self.elasticache_client then
    kong.log.info("=== ELASTICACHE CLIENT INITIALIZATION ===")
    
    -- ElastiCache connection configuration
    local elasticache_config = {
      endpoint = conf.elasticache_endpoint,
      port = conf.elasticache_port or 6379,
      auth_token = conf.elasticache_auth_token,
      ssl_enabled = conf.elasticache_ssl_enabled,
      ssl_verify = conf.elasticache_ssl_verify,
      cluster_mode = conf.elasticache_cluster_mode,
      read_replicas = conf.elasticache_read_replicas,
      database = conf.elasticache_database or 0,
      
      -- Connection pool settings
      pool_size = conf.connection_pool_size or 100,
      connection_timeout = conf.connection_timeout or 2000,
      keepalive_timeout = conf.keepalive_timeout or 60000,
      socket_timeout = conf.socket_timeout or 5000,
      
      -- Reliability settings
      enable_failover = conf.enable_failover,
      max_retry_attempts = conf.max_retry_attempts or 3,
      retry_delay = conf.retry_delay or 100,
      
      -- Performance settings
      enable_compression = conf.enable_compression,
      mapping_ttl = conf.mapping_ttl or 604800,
      
      -- AWS integration
      aws_region = conf.aws_region,
      use_iam_auth = conf.use_iam_auth,
      iam_role_arn = conf.iam_role_arn,
      
      -- Development
      debug_mode = conf.debug_mode,
      test_mode = conf.test_mode
    }
    
    -- Initialize ElastiCache client
    local client, err = elasticache_client.new(elasticache_config)
    if not client then
      kong.log.err("ElastiCache client initialization failed: ", err)
      if conf.fail_secure then
        return error_codes.exit_with_error("ELASTICACHE_INIT_FAILED", {
          error = "ElastiCache client initialization failed",
          details = err
        })
      end
    else
      self.elasticache_client = client
      kong.log.info("ElastiCache client initialized successfully")
      kong.log.info("Endpoint: ", conf.elasticache_endpoint, ":", conf.elasticache_port)
      kong.log.info("SSL Enabled: ", conf.elasticache_ssl_enabled and "YES" or "NO")
    end
  end
  
  return self.elasticache_client
end

-- Access phase: Request body masking
function AwsMaskerElastiCacheHandler:access(conf)
  kong.log.info("=== AWS MASKER ELASTICACHE: ACCESS PHASE ===")
  
  -- Phase 1 Success Integration: API Key handling (highest priority)
  kong.log.info("=== API KEY ACCESS DEBUG ===")
  
  -- 1순위: Kong Plugin Config에서 API 키 가져오기 (Phase 1 성공 핵심!)
  local api_key_from_config = conf and conf.anthropic_api_key
  kong.log.info("Plugin config API key: ", api_key_from_config and "VALUE_FOUND" or "NIL")
  
  -- 2순위: 환경변수에서 API 키 가져오기 (Fallback)
  local api_key_from_env = os.getenv("ANTHROPIC_API_KEY")
  kong.log.info("Environment API key: ", api_key_from_env and "VALUE_FOUND" or "NIL")
  
  -- 최종 API 키 결정 (우선순위: Config > Environment)
  local final_api_key = api_key_from_config or api_key_from_env
  kong.log.info("Final API Key Selected: ", final_api_key and "YES" or "NO")
  
  if final_api_key and final_api_key ~= "" then
    kong.service.request.set_header("x-api-key", final_api_key)
    kong.service.request.set_header("anthropic-version", "2023-06-01")
    kong.log.info("API Key Source: ", api_key_from_config and "PLUGIN_CONFIG" or "ENVIRONMENT")
    kong.log.info("API Key Headers Set: SUCCESS")
  else
    kong.log.err("=== API KEY VERIFICATION FAILED ===")
    kong.log.err("CRITICAL: API KEY not available")
    return error_codes.exit_with_error("MISSING_API_KEY", {
      error = "API KEY required for Claude API authentication"
    })
  end
  
  -- ElastiCache client initialization
  local client = self:init_elasticache_client(conf)
  if not client and conf.fail_secure then
    kong.log.err("ElastiCache unavailable and fail_secure enabled")
    return error_codes.exit_with_error("ELASTICACHE_UNAVAILABLE", {
      error = "ElastiCache required but unavailable"
    })
  end
  
  -- Request body processing
  local raw_body = kong.request.get_raw_body()
  if not raw_body or raw_body == "" then
    kong.log.info("No request body to mask")
    return
  end
  
  kong.log.info("Processing request body (", string.len(raw_body), " bytes)")
  
  -- AWS pattern detection and masking
  local masked_body, masking_stats = self:mask_aws_patterns(raw_body, client, conf)
  
  if masked_body ~= raw_body then
    -- Store masking mappings in ElastiCache for response unmasking
    if client then
      local session_id = ngx.var.request_id or "session_" .. ngx.now()
      local stored, err = client:store_masking_context(session_id, masking_stats, conf.mapping_ttl)
      if stored then
        kong.log.info("Masking context stored in ElastiCache: ", session_id)
        kong.service.request.set_header("X-Masking-Session", session_id)
      else
        kong.log.warn("Failed to store masking context: ", err)
      end
    end
    
    -- Apply masked body
    kong.service.request.set_raw_body(masked_body)
    kong.log.info("Request body masked successfully")
    
    -- Statistics logging
    if masking_stats and masking_stats.patterns_found > 0 then
      kong.log.info("AWS patterns masked: ", masking_stats.patterns_found)
      kong.log.info("Masking types: ", json_safe.encode(masking_stats.types))
    end
  else
    kong.log.info("No AWS patterns found in request body")
  end
end

-- Header filter phase: Capture response headers
function AwsMaskerElastiCacheHandler:header_filter(conf)
  kong.log.info("=== AWS MASKER ELASTICACHE: HEADER FILTER PHASE ===")
  
  -- Add response headers for monitoring
  kong.response.set_header("X-AWS-Masker-Version", self.VERSION)
  kong.response.set_header("X-ElastiCache-Enabled", "true")
  
  local status = kong.response.get_status()
  kong.log.info("Claude API response status: ", status)
  
  if status >= 400 then
    kong.log.err("Claude API error response: ", status)
    -- Log additional error details for debugging
    local headers = kong.response.get_headers()
    if headers["content-type"] and string.find(headers["content-type"], "application/json") then
      kong.log.err("Error response headers: ", json_safe.encode(headers))
    end
  end
end

-- Body filter phase: Response unmasking
function AwsMaskerElastiCacheHandler:body_filter(conf)
  kong.log.info("=== AWS MASKER ELASTICACHE: BODY FILTER PHASE ===")
  
  -- Get response body chunk
  local chunk = kong.response.get_raw_body()
  local eof = kong.response.get_source().eof
  
  if not chunk or chunk == "" then
    if eof then
      kong.log.info("Empty response body - no unmasking needed")
    end
    return
  end
  
  kong.log.info("Processing response chunk (", string.len(chunk), " bytes)")
  
  -- Get masking session for unmasking
  local session_id = kong.request.get_header("X-Masking-Session")
  if not session_id then
    kong.log.info("No masking session found - passing response as-is")
    return
  end
  
  -- ElastiCache client for unmasking
  local client = self:init_elasticache_client(conf)
  if not client then
    kong.log.warn("ElastiCache unavailable for unmasking - passing response as-is")
    return
  end
  
  -- Retrieve masking context from ElastiCache
  local masking_context, err = client:get_masking_context(session_id)
  if not masking_context then
    kong.log.warn("Masking context not found in ElastiCache: ", err)
    return
  end
  
  -- Unmask AWS identifiers in response
  local unmasked_chunk = self:unmask_aws_patterns(chunk, masking_context, conf)
  
  if unmasked_chunk ~= chunk then
    kong.response.set_raw_body(unmasked_chunk)
    kong.log.info("Response unmasked successfully")
  end
  
  -- Cleanup masking context on final chunk
  if eof then
    client:delete_masking_context(session_id)
    kong.log.info("Masking session cleaned up: ", session_id)
  end
end

-- AWS patterns masking logic
function AwsMaskerElastiCacheHandler:mask_aws_patterns(body, client, conf)
  local stats = {
    patterns_found = 0,
    types = {},
    mappings = {}
  }
  
  local masked_body = body
  
  -- EC2 Instance IDs
  if conf.mask_ec2_instances then
    local ec2_pattern = "i%-[0-9a-f]{8,17}"
    local count = 0
    masked_body = string.gsub(masked_body, ec2_pattern, function(match)
      count = count + 1
      local masked = "EC2_INSTANCE_" .. string.format("%03d", count)
      stats.mappings[masked] = match
      return masked
    end)
    if count > 0 then
      stats.patterns_found = stats.patterns_found + count
      stats.types["ec2_instances"] = count
      kong.log.info("Masked ", count, " EC2 instance IDs")
    end
  end
  
  -- S3 Bucket Names
  if conf.mask_s3_buckets then
    local s3_pattern = "s3://[a-z0-9][a-z0-9%-%.]*[a-z0-9]"
    local count = 0
    masked_body = string.gsub(masked_body, s3_pattern, function(match)
      count = count + 1
      local masked = "S3_BUCKET_" .. string.format("%03d", count)
      stats.mappings[masked] = match
      return masked
    end)
    if count > 0 then
      stats.patterns_found = stats.patterns_found + count
      stats.types["s3_buckets"] = count
      kong.log.info("Masked ", count, " S3 bucket names")
    end
  end
  
  -- Private IP Addresses
  if conf.mask_private_ips then
    local private_ip_pattern = "10%.%d+%.%d+%.%d+"
    local count = 0
    masked_body = string.gsub(masked_body, private_ip_pattern, function(match)
      count = count + 1
      local masked = "PRIVATE_IP_" .. string.format("%03d", count)
      stats.mappings[masked] = match
      return masked
    end)
    if count > 0 then
      stats.patterns_found = stats.patterns_found + count
      stats.types["private_ips"] = count
      kong.log.info("Masked ", count, " private IP addresses")
    end
  end
  
  -- VPC IDs
  if conf.mask_vpc_ids then
    local vpc_pattern = "vpc%-[0-9a-f]{8,17}"
    local count = 0
    masked_body = string.gsub(masked_body, vpc_pattern, function(match)
      count = count + 1
      local masked = "VPC_" .. string.format("%03d", count)
      stats.mappings[masked] = match
      return masked
    end)
    if count > 0 then
      stats.patterns_found = stats.patterns_found + count
      stats.types["vpc_ids"] = count
      kong.log.info("Masked ", count, " VPC IDs")
    end
  end
  
  return masked_body, stats
end

-- AWS patterns unmasking logic
function AwsMaskerElastiCacheHandler:unmask_aws_patterns(body, masking_context, conf)
  if not masking_context or not masking_context.mappings then
    return body
  end
  
  local unmasked_body = body
  local unmask_count = 0
  
  -- Reverse the masking mappings
  for masked_value, original_value in pairs(masking_context.mappings) do
    local found = string.find(unmasked_body, masked_value, 1, true)
    if found then
      unmasked_body = string.gsub(unmasked_body, masked_value, original_value)
      unmask_count = unmask_count + 1
    end
  end
  
  if unmask_count > 0 then
    kong.log.info("Unmasked ", unmask_count, " AWS identifiers")
  end
  
  return unmasked_body
end

return AwsMaskerElastiCacheHandler