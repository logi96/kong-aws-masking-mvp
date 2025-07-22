--
-- Kong 3.7 Compatible AWS Masker Plugin Handler
-- Simplified for compatibility without base_plugin dependency
-- Following CLAUDE.md: < 5s total response time, security-first design
--

local masker = require "kong.plugins.aws-masker.masker"
local cjson = require "cjson.safe"

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
  -- Initialize mapping store if not exists
  if not self.mapping_store then
    self.mapping_store = masker.create_mapping_store()
    kong.log.info("AWS Masker: Created new mapping store")
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
  
  -- Enable request buffering to access body (Kong 3.7 compatible)
  kong.service.request.enable_buffering()
  
  -- Handle request masking with error protection
  local success, err = pcall(function()
    local raw_body = kong.request.get_raw_body()
    
    kong.log.info("AWS Masker: Raw body retrieved, length: " .. (raw_body and string.len(raw_body) or "nil"))
    
    if raw_body then
      -- Attempt to parse as JSON, fallback to string masking
      local request_data = cjson.decode(raw_body)
      if not request_data then
        kong.log.info("AWS Masker: JSON decode failed, treating as string")
        request_data = raw_body
      else
        kong.log.info("AWS Masker: JSON decoded successfully")
      end
      
      kong.log.info("AWS Masker: Starting masking process with config: " .. (self.config and "present" or "nil"))
      
      -- Mask AWS resources using masker module
      local mask_result = masker.mask_data(request_data, self.mapping_store, self.config)
      
      kong.log.info("AWS Masker: Masking completed, count: " .. (mask_result and mask_result.count or "nil"))
      kong.log.info("AWS Masker: Original data sample: " .. tostring(raw_body):sub(1, 100))
      
      -- Convert masked result back to JSON if it was originally JSON
      local masked_body = self:_prepare_masked_body(mask_result)
      
      if masked_body then
        kong.log.info("AWS Masker: Masked body prepared, length: " .. string.len(masked_body))
        kong.log.info("AWS Masker: Masked data sample: " .. tostring(masked_body):sub(1, 100))
        
        kong.service.request.set_raw_body(masked_body)
        
        -- Store mapping context for response unmasking
        kong.ctx.shared.aws_mapping_store = self.mapping_store
        
        -- Log if requested
        self:_log_masking_result(mask_result)
      else
        kong.log.warn("AWS Masker: Failed to prepare masked body")
      end
    else
      kong.log.warn("AWS Masker: No raw body found in request")
    end
  end)
  
  -- Log errors but don't fail the request
  if not success then
    kong.log.err("AWS masking error in access phase: " .. tostring(err))
  end
end

---
-- Body filter phase - unmasks AWS resources in inbound responses
-- Restores original AWS identifiers in responses from external APIs
-- @param table conf Plugin configuration from Kong
function AwsMaskerHandler:body_filter(conf)
  -- Handle response unmasking with error protection
  local success, err = pcall(function()
    -- Get mapping store from request context
    local mapping_store = kong.ctx.shared.aws_mapping_store
    
    if not mapping_store then
      -- No mappings available, skip unmasking
      return
    end
    
    local raw_body = kong.response.get_raw_body()
    
    if raw_body then
      -- Attempt to parse as JSON, fallback to string unmasking
      local response_data = cjson.decode(raw_body)
      if not response_data then
        response_data = raw_body
      end
      
      -- Unmask AWS resources
      local unmasked_data = masker.unmask_data(response_data, mapping_store)
      
      -- Convert unmasked result back to JSON if it was originally JSON
      local unmasked_body = self:_prepare_unmasked_body(unmasked_data)
      
      -- Set unmasked body for client response (Kong 3.7 compatible)
      if unmasked_body then
        kong.response.set_raw_body(unmasked_body)
      end
    end
  end)
  
  -- Log errors but don't fail the response
  if not success then
    kong.log.err("AWS unmasking error in body_filter phase: " .. tostring(err))
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
    return cjson.encode(mask_result.masked)
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
    return cjson.encode(unmasked_data)
  else
    return unmasked_data
  end
end

---
-- Logs masking results if logging is enabled
-- @param table mask_result Result from masker.mask_data
function AwsMaskerHandler:_log_masking_result(mask_result)
  if self.config.log_masked_requests and mask_result.count > 0 then
    kong.log.info("Masked " .. mask_result.count .. " AWS resources in request")
  end
end

-- Return the handler class
return AwsMaskerHandler

--
-- Kong 3.7 Compatible Handler Complete
-- Simplified architecture without BasePlugin dependency for better compatibility
-- All core functionality maintained: masking, unmasking, performance, security
--