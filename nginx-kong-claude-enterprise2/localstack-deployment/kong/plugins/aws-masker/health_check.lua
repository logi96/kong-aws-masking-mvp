--
-- AWS Masker Health Check and Circuit Breaker Module
-- Monitors Redis connectivity and plugin health for production stability
-- Implements Circuit Breaker pattern for automatic recovery
--

local error_codes = require "kong.plugins.aws-masker.error_codes"

local _M = {}

-- Circuit Breaker states
local CB_CLOSED = "CLOSED"  -- Normal operation
local CB_OPEN = "OPEN"      -- Failing, reject requests
local CB_HALF_OPEN = "HALF_OPEN"  -- Testing recovery

-- Circuit Breaker configuration
_M.circuit_breaker = {
  -- Failure tracking
  failure_threshold = 5,      -- Failures before opening
  success_threshold = 3,      -- Successes to close from half-open
  timeout = 30,              -- Seconds before trying half-open
  
  -- Current state
  state = CB_CLOSED,
  failure_count = 0,
  success_count = 0,
  last_failure_time = 0,
  last_state_change = ngx.now()
}

-- Health status storage
_M.health_status = {
  redis = {
    healthy = false,
    last_check = 0,
    error_message = nil,
    latency_ms = 0
  },
  masking = {
    healthy = true,
    requests_processed = 0,
    requests_failed = 0,
    avg_latency_ms = 0
  },
  overall = {
    healthy = false,
    ready = false,
    last_update = 0
  }
}

---
-- Check Redis connectivity and performance
-- @param table redis_connection Active Redis connection
-- @return boolean Success status
-- @return string Error message if failed
function _M.check_redis_health(redis_connection)
  local start_time = ngx.now()
  
  if not redis_connection then
    return false, "No Redis connection provided"
  end
  
  -- Try PING command
  local ok, err = redis_connection:ping()
  if not ok then
    _M.health_status.redis.healthy = false
    _M.health_status.redis.error_message = err
    return false, err
  end
  
  -- Check response time
  local latency_ms = (ngx.now() - start_time) * 1000
  _M.health_status.redis.latency_ms = latency_ms
  
  -- Consider unhealthy if latency > 100ms
  if latency_ms > 100 then
    _M.health_status.redis.healthy = false
    _M.health_status.redis.error_message = "High latency: " .. latency_ms .. "ms"
    return false, "Redis latency too high"
  end
  
  -- Test basic operations
  local test_key = "aws_masker:health:test"
  ok, err = redis_connection:setex(test_key, 10, "healthy")
  if not ok then
    _M.health_status.redis.healthy = false
    _M.health_status.redis.error_message = "Write test failed: " .. err
    return false, err
  end
  
  -- All checks passed
  _M.health_status.redis.healthy = true
  _M.health_status.redis.error_message = nil
  _M.health_status.redis.last_check = ngx.now()
  
  return true
end

---
-- Update Circuit Breaker state based on operation result
-- @param boolean success Whether the operation succeeded
function _M.record_operation_result(success)
  local cb = _M.circuit_breaker
  local now = ngx.now()
  
  if cb.state == CB_CLOSED then
    if success then
      cb.failure_count = 0  -- Reset on success
    else
      cb.failure_count = cb.failure_count + 1
      cb.last_failure_time = now
      
      -- Open circuit if threshold reached
      if cb.failure_count >= cb.failure_threshold then
        cb.state = CB_OPEN
        cb.last_state_change = now
        kong.log.err("[CIRCUIT BREAKER] Opening circuit after ", cb.failure_count, " failures")
      end
    end
    
  elseif cb.state == CB_OPEN then
    -- Check if timeout has passed
    if now - cb.last_state_change >= cb.timeout then
      cb.state = CB_HALF_OPEN
      cb.last_state_change = now
      cb.success_count = 0
      kong.log.info("[CIRCUIT BREAKER] Moving to half-open state")
    end
    
  elseif cb.state == CB_HALF_OPEN then
    if success then
      cb.success_count = cb.success_count + 1
      
      -- Close circuit if success threshold reached
      if cb.success_count >= cb.success_threshold then
        cb.state = CB_CLOSED
        cb.last_state_change = now
        cb.failure_count = 0
        kong.log.info("[CIRCUIT BREAKER] Closing circuit after recovery")
      end
    else
      -- Single failure in half-open reopens circuit
      cb.state = CB_OPEN
      cb.last_state_change = now
      cb.failure_count = cb.failure_count + 1
      kong.log.err("[CIRCUIT BREAKER] Reopening circuit after half-open failure")
    end
  end
end

---
-- Check if requests should be allowed through Circuit Breaker
-- @return boolean Whether to allow the request
-- @return string Circuit breaker state
function _M.should_allow_request()
  local cb = _M.circuit_breaker
  
  if cb.state == CB_CLOSED then
    return true, CB_CLOSED
  elseif cb.state == CB_OPEN then
    -- Check if we should try half-open
    if ngx.now() - cb.last_state_change >= cb.timeout then
      cb.state = CB_HALF_OPEN
      cb.last_state_change = ngx.now()
      cb.success_count = 0
      return true, CB_HALF_OPEN  -- Allow test request
    end
    return false, CB_OPEN
  else  -- CB_HALF_OPEN
    return true, CB_HALF_OPEN
  end
end

---
-- Update masking operation statistics
-- @param table stats Operation statistics
function _M.update_masking_stats(stats)
  local masking = _M.health_status.masking
  
  if stats.success then
    masking.requests_processed = masking.requests_processed + 1
  else
    masking.requests_failed = masking.requests_failed + 1
  end
  
  -- Update average latency (simple moving average)
  if stats.latency_ms then
    local total_requests = masking.requests_processed + masking.requests_failed
    masking.avg_latency_ms = ((masking.avg_latency_ms * (total_requests - 1)) + stats.latency_ms) / total_requests
  end
  
  -- Consider unhealthy if failure rate > 10%
  local failure_rate = masking.requests_failed / math.max(1, masking.requests_processed + masking.requests_failed)
  masking.healthy = failure_rate < 0.1
end

---
-- Get comprehensive health status
-- @return table Health status report
function _M.get_health_status()
  local status = _M.health_status
  local cb = _M.circuit_breaker
  
  -- Update overall health
  status.overall.healthy = status.redis.healthy and status.masking.healthy
  status.overall.ready = status.overall.healthy and cb.state ~= CB_OPEN
  status.overall.last_update = ngx.now()
  
  return {
    status = status.overall.ready and "healthy" or "unhealthy",
    timestamp = ngx.time(),
    components = {
      redis = {
        status = status.redis.healthy and "UP" or "DOWN",
        latency_ms = status.redis.latency_ms,
        error = status.redis.error_message,
        last_check = status.redis.last_check
      },
      masking = {
        status = status.masking.healthy and "UP" or "DOWN",
        requests = {
          total = status.masking.requests_processed + status.masking.requests_failed,
          successful = status.masking.requests_processed,
          failed = status.masking.requests_failed
        },
        avg_latency_ms = status.masking.avg_latency_ms
      },
      circuit_breaker = {
        state = cb.state,
        failure_count = cb.failure_count,
        last_state_change = cb.last_state_change
      }
    }
  }
end

---
-- Reset Circuit Breaker (admin operation)
function _M.reset_circuit_breaker()
  local cb = _M.circuit_breaker
  cb.state = CB_CLOSED
  cb.failure_count = 0
  cb.success_count = 0
  cb.last_state_change = ngx.now()
  kong.log.info("[CIRCUIT BREAKER] Manually reset to closed state")
end

return _M