--
-- AWS Masker Error Codes and Handling Module
-- Standardized error definitions for production-grade fail-secure operation
-- Following 100% security requirements with financial penalty implications
--

local _M = {}

---
-- Error Code Definitions
-- Each error has a unique code, HTTP status, and standardized response format
-- @type table
_M.errors = {
  -- Redis Connection Errors (1xxx)
  REDIS_UNAVAILABLE = {
    code = "AWS_MASKER_1001",
    status = 503,
    message = "Service Unavailable",
    details = "AWS resource masking requires Redis for secure operation"
  },
  
  REDIS_AUTH_FAILED = {
    code = "AWS_MASKER_1002",
    status = 503,
    message = "Service Unavailable",
    details = "Redis authentication failed"
  },
  
  REDIS_OPERATION_FAILED = {
    code = "AWS_MASKER_1003",
    status = 503,
    message = "Service Temporarily Unavailable",
    details = "Redis operation failed during masking process"
  },
  
  -- Masking Operation Errors (2xxx)
  MASKING_PROCESSING_ERROR = {
    code = "AWS_MASKER_2001",
    status = 503,
    message = "Service Unavailable",
    details = "Failed to process AWS resource masking"
  },
  
  MASKING_PATTERN_MISMATCH = {
    code = "AWS_MASKER_2002",
    status = 503,
    message = "Service Unavailable",
    details = "Security validation failed - pattern detection mismatch"
  },
  
  MASKING_BODY_PREPARATION_ERROR = {
    code = "AWS_MASKER_2003",
    status = 503,
    message = "Service Unavailable",
    details = "Failed to prepare masked request body"
  },
  
  -- Unmasking Operation Errors (3xxx)
  UNMASKING_FAILED = {
    code = "AWS_MASKER_3001",
    status = 500,
    message = "Internal Server Error",
    details = "Failed to unmask response data"
  },
  
  UNMASKING_INCOMPLETE = {
    code = "AWS_MASKER_3002",
    status = 500,
    message = "Internal Server Error",
    details = "Response unmasking incomplete - security risk detected"
  },
  
  -- Configuration Errors (4xxx)
  INVALID_CONFIGURATION = {
    code = "AWS_MASKER_4001",
    status = 500,
    message = "Internal Server Error",
    details = "Invalid plugin configuration"
  },
  
  MISSING_REQUIRED_CONFIG = {
    code = "AWS_MASKER_4002",
    status = 500,
    message = "Internal Server Error",
    details = "Required configuration parameter missing"
  },
  
  -- Security Validation Errors (5xxx)
  SECURITY_BYPASS_ATTEMPT = {
    code = "AWS_MASKER_5001",
    status = 403,
    message = "Forbidden",
    details = "Security validation failed - potential bypass attempt detected"
  },
  
  UNMASKED_DATA_LEAK = {
    code = "AWS_MASKER_5002",
    status = 503,
    message = "Service Unavailable",
    details = "Unmasked AWS data detected in outbound request"
  },
  
  -- Module/Dependency Errors (6xxx)
  MODULE_LOAD_FAILED = {
    code = "AWS_MASKER_6001",
    status = 500,
    message = "Internal Server Error",
    details = "Failed to load required module"
  },
  
  JSON_PROCESSING_ERROR = {
    code = "AWS_MASKER_6002",
    status = 500,
    message = "Internal Server Error",
    details = "JSON encoding/decoding failed"
  }
}

---
-- Get standardized error response
-- @param string error_name Error identifier from errors table
-- @param table extra_details Optional additional details
-- @return table Error response structure
function _M.get_error(error_name, extra_details)
  local error_def = _M.errors[error_name]
  if not error_def then
    -- Fallback for unknown errors
    return {
      error = "AWS_MASKER_9999",
      message = "Unknown Error",
      details = error_name or "An unexpected error occurred"
    }
  end
  
  local response = {
    error = error_def.code,
    message = error_def.message,
    details = error_def.details
  }
  
  -- Add extra details if provided
  if extra_details then
    response.extra = extra_details
  end
  
  return response, error_def.status
end

---
-- Log error with security context
-- @param string error_name Error identifier
-- @param table context Additional context for logging
function _M.log_error(error_name, context)
  local error_def = _M.errors[error_name]
  if not error_def then
    kong.log.err("[AWS_MASKER] Unknown error: ", error_name)
    return
  end
  
  -- Build log message
  local log_parts = {
    "[AWS_MASKER]",
    error_def.code,
    "-",
    error_def.details
  }
  
  -- Add context if provided
  if context then
    table.insert(log_parts, " | Context: ")
    if type(context) == "table" then
      table.insert(log_parts, require("kong.plugins.aws-masker.json_safe").encode(context) or "")
    else
      table.insert(log_parts, tostring(context))
    end
  end
  
  kong.log.err(table.concat(log_parts, " "))
end

---
-- Create error response and exit
-- @param string error_name Error identifier
-- @param table extra_details Optional additional details
function _M.exit_with_error(error_name, extra_details)
  local response, status = _M.get_error(error_name, extra_details)
  return kong.response.exit(status, response)
end

return _M