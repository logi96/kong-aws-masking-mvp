-- ElastiCache Client Module for Kong AWS Masker
-- Production-ready AWS ElastiCache Redis integration
-- Supports SSL/TLS, AUTH tokens, cluster mode, and failover

local redis = require "resty.redis"
local cjson = require "cjson.safe"
local ngx = ngx

local _M = {}
local mt = { __index = _M }

-- ElastiCache connection configuration
local POOL_SIZE = 100
local KEEPALIVE_TIMEOUT = 60000  -- 60 seconds
local CONNECTION_TIMEOUT = 2000   -- 2 seconds
local SSL_HANDSHAKE_TIMEOUT = 5000 -- 5 seconds for SSL handshake

-- Namespaces for ElastiCache keys
local MASKING_PREFIX = "aws:mask:"
local UNMASK_PREFIX = "aws:unmask:"
local STATS_PREFIX = "aws:stats:"
local HEALTH_PREFIX = "aws:health:"

-- Initialize ElastiCache client
function _M.new(config)
  if not config or not config.endpoint then
    return nil, "ElastiCache endpoint required"
  end
  
  local instance = {
    config = config,
    connection_pool = {},
    stats = {
      connections = 0,
      successful_ops = 0,
      failed_ops = 0,
      last_health_check = 0
    }
  }
  
  return setmetatable(instance, mt)
end

-- Get Redis connection with ElastiCache optimizations
function _M:get_connection()
  local red = redis:new()
  
  -- Set timeouts
  red:set_timeouts(
    self.config.connection_timeout or CONNECTION_TIMEOUT,
    self.config.socket_timeout or 5000,
    self.config.socket_timeout or 5000
  )
  
  -- Connect to ElastiCache endpoint
  local ok, err = red:connect(self.config.endpoint, self.config.port or 6379)
  if not ok then
    self.stats.failed_ops = self.stats.failed_ops + 1
    return nil, "Failed to connect to ElastiCache: " .. (err or "unknown error")
  end
  
  self.stats.connections = self.stats.connections + 1
  
  -- SSL/TLS configuration for ElastiCache
  if self.config.ssl_enabled then
    local session, err = red:ssl_handshake(
      nil,  -- reused_session
      nil,  -- server_name
      self.config.ssl_verify ~= false,  -- verify certificate
      nil,  -- send_status_req
      SSL_HANDSHAKE_TIMEOUT
    )
    
    if not session then
      red:close()
      self.stats.failed_ops = self.stats.failed_ops + 1
      return nil, "SSL handshake failed: " .. (err or "unknown error")
    end
    
    kong.log.info("ElastiCache SSL connection established")
  end
  
  -- AUTH token authentication
  if self.config.auth_token and self.config.auth_token ~= "" then
    local res, err = red:auth(self.config.auth_token)
    if not res or res == ngx.null then
      red:close()
      self.stats.failed_ops = self.stats.failed_ops + 1
      return nil, "ElastiCache AUTH failed: " .. (err or "invalid token")
    end
    kong.log.info("ElastiCache AUTH successful")
  end
  
  -- Select database (if not cluster mode)
  if not self.config.cluster_mode and self.config.database and self.config.database > 0 then
    local res, err = red:select(self.config.database)
    if not res then
      red:close()
      self.stats.failed_ops = self.stats.failed_ops + 1
      return nil, "Failed to select database: " .. (err or "unknown error")
    end
  end
  
  self.stats.successful_ops = self.stats.successful_ops + 1
  return red
end

-- Close connection with keep-alive
function _M:close_connection(red)
  if not red then
    return
  end
  
  -- Put connection back to the pool
  local ok, err = red:set_keepalive(
    self.config.keepalive_timeout or KEEPALIVE_TIMEOUT,
    self.config.pool_size or POOL_SIZE
  )
  
  if not ok then
    kong.log.warn("Failed to set keepalive: ", err)
    red:close()
  end
end

-- Execute Redis command with retry logic
function _M:execute_command(command, ...)
  local max_retries = self.config.max_retry_attempts or 3
  local retry_delay = self.config.retry_delay or 100
  
  for attempt = 1, max_retries do
    local red, err = self:get_connection()
    if not red then
      kong.log.err("Connection attempt ", attempt, " failed: ", err)
      if attempt < max_retries then
        ngx.sleep(retry_delay / 1000)  -- Convert to seconds
      end
    else
      -- Execute command
      local res, cmd_err = red[command](red, ...)
      
      if res and res ~= ngx.null then
        self:close_connection(red)
        self.stats.successful_ops = self.stats.successful_ops + 1
        return res
      else
        self:close_connection(red)
        self.stats.failed_ops = self.stats.failed_ops + 1
        kong.log.warn("Command ", command, " failed on attempt ", attempt, ": ", cmd_err)
        if attempt < max_retries then
          ngx.sleep(retry_delay / 1000)
        end
      end
    end
  end
  
  return nil, "All retry attempts failed for command: " .. command
end

-- Store masking context in ElastiCache
function _M:store_masking_context(session_id, masking_stats, ttl)
  if not session_id or not masking_stats then
    return nil, "Invalid parameters"
  end
  
  local key = MASKING_PREFIX .. session_id
  local data = cjson.encode(masking_stats)
  
  if not data then
    return nil, "Failed to encode masking context"
  end
  
  -- Store with TTL
  local res, err = self:execute_command("setex", key, ttl or 3600, data)
  if not res then
    return nil, "Failed to store masking context: " .. (err or "unknown error")
  end
  
  kong.log.info("Masking context stored: ", key, " (", string.len(data), " bytes)")
  return true
end

-- Retrieve masking context from ElastiCache
function _M:get_masking_context(session_id)
  if not session_id then
    return nil, "Session ID required"
  end
  
  local key = MASKING_PREFIX .. session_id
  local data, err = self:execute_command("get", key)
  
  if not data or data == ngx.null then
    return nil, "Masking context not found: " .. (err or "key not exists")
  end
  
  local context = cjson.decode(data)
  if not context then
    return nil, "Failed to decode masking context"
  end
  
  kong.log.info("Masking context retrieved: ", key)
  return context
end

-- Delete masking context from ElastiCache
function _M:delete_masking_context(session_id)
  if not session_id then
    return nil, "Session ID required"
  end
  
  local key = MASKING_PREFIX .. session_id
  local res, err = self:execute_command("del", key)
  
  if not res then
    kong.log.warn("Failed to delete masking context: ", err)
    return nil, err
  end
  
  kong.log.info("Masking context deleted: ", key)
  return true
end

-- Health check for ElastiCache
function _M:health_check()
  local current_time = ngx.now()
  
  -- Throttle health checks (max once per 10 seconds)
  if current_time - self.stats.last_health_check < 10 then
    return true  -- Assume healthy if recently checked
  end
  
  local res, err = self:execute_command("ping")
  
  if res == "PONG" then
    self.stats.last_health_check = current_time
    kong.log.info("ElastiCache health check: HEALTHY")
    return true
  else
    kong.log.err("ElastiCache health check failed: ", err)
    return false, err
  end
end

-- Get connection statistics
function _M:get_stats()
  return {
    connections = self.stats.connections,
    successful_ops = self.stats.successful_ops,
    failed_ops = self.stats.failed_ops,
    success_rate = self.stats.successful_ops / (self.stats.successful_ops + self.stats.failed_ops) * 100,
    last_health_check = self.stats.last_health_check,
    endpoint = self.config.endpoint .. ":" .. (self.config.port or 6379),
    ssl_enabled = self.config.ssl_enabled,
    auth_enabled = self.config.auth_token and true or false
  }
end

-- Batch operations for performance
function _M:batch_store(mappings, ttl)
  if not mappings or type(mappings) ~= "table" then
    return nil, "Invalid mappings"
  end
  
  local red, err = self:get_connection()
  if not red then
    return nil, err
  end
  
  -- Start pipeline
  red:init_pipeline()
  
  local count = 0
  for session_id, data in pairs(mappings) do
    local key = MASKING_PREFIX .. session_id
    local encoded_data = cjson.encode(data)
    if encoded_data then
      red:setex(key, ttl or 3600, encoded_data)
      count = count + 1
    end
  end
  
  -- Execute pipeline
  local results, pipeline_err = red:commit_pipeline()
  self:close_connection(red)
  
  if not results then
    self.stats.failed_ops = self.stats.failed_ops + 1
    return nil, "Batch store failed: " .. (pipeline_err or "unknown error")
  end
  
  self.stats.successful_ops = self.stats.successful_ops + count
  kong.log.info("Batch stored ", count, " masking contexts")
  return count
end

-- Cleanup expired keys (maintenance operation)
function _M:cleanup_expired_keys()
  -- This would typically be handled by Redis TTL automatically
  -- But we can implement custom cleanup logic if needed
  kong.log.info("ElastiCache cleanup completed (TTL-based)")
  return true
end

return _M