-- Error codes and handling for AWS Masker ElastiCache Edition
-- Standardized error responses for Kong plugin

local _M = {}

-- Error code definitions
local ERROR_CODES = {
  ELASTICACHE_INIT_FAILED = {
    status = 503,
    message = "ElastiCache initialization failed",
    code = "ELASTICACHE_INIT_FAILED"
  },
  ELASTICACHE_UNAVAILABLE = {
    status = 503,
    message = "ElastiCache service unavailable",
    code = "ELASTICACHE_UNAVAILABLE"
  },
  MISSING_API_KEY = {
    status = 401,
    message = "API key required for authentication",
    code = "MISSING_API_KEY"
  },
  INVALID_CONFIGURATION = {
    status = 500,
    message = "Invalid plugin configuration",
    code = "INVALID_CONFIGURATION"
  },
  MASKING_FAILED = {
    status = 500,
    message = "AWS resource masking failed",
    code = "MASKING_FAILED"
  },
  UNMASKING_FAILED = {
    status = 500,
    message = "AWS resource unmasking failed",
    code = "UNMASKING_FAILED"
  }
}

-- Exit with standardized error response
function _M.exit_with_error(error_code, details)
  local error_def = ERROR_CODES[error_code]
  if not error_def then
    error_def = {
      status = 500,
      message = "Unknown error",
      code = "UNKNOWN_ERROR"
    }
  end
  
  local response_body = {
    error = {
      code = error_def.code,
      message = error_def.message,
      details = details or {},
      timestamp = ngx.now(),
      request_id = ngx.var.request_id
    }
  }
  
  kong.log.err("Plugin error: ", error_def.code, " - ", error_def.message)
  if details then
    kong.log.err("Error details: ", require("kong.plugins.aws-masker-elasticache.json_safe").encode(details))
  end
  
  return kong.response.exit(error_def.status, response_body)
end

-- Log warning without exiting
function _M.log_warning(warning_code, details)
  kong.log.warn("Plugin warning: ", warning_code)
  if details then
    kong.log.warn("Warning details: ", require("kong.plugins.aws-masker-elasticache.json_safe").encode(details))
  end
end

-- Check if error is retryable
function _M.is_retryable_error(error_code)
  local retryable_errors = {
    "ELASTICACHE_UNAVAILABLE",
    "CONNECTION_TIMEOUT",
    "NETWORK_ERROR"
  }
  
  for _, retryable in ipairs(retryable_errors) do
    if error_code == retryable then
      return true
    end
  end
  
  return false
end

return _M