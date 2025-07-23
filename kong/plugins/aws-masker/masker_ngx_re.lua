--
-- AWS Resource Masker Module with ngx.re support
-- Implements masking/unmasking logic for AWS resource identifiers
-- Using ngx.re for complex patterns as per design specification
--

local patterns = require "kong.plugins.aws-masker.patterns"
local json_safe = require "kong.plugins.aws-masker.json_safe"

local _M = {}

-- Default configuration
_M.config = {
  ttl = 3600,              -- 1 hour TTL for mappings
  max_entries = 10000,     -- Maximum number of mappings
  clean_interval = 300     -- Clean expired entries every 5 minutes
}

-- Pattern configuration
local pattern_config = {}

---
-- Creates a new mapping store for AWS resource mappings
-- @param table options Optional configuration overrides
-- @return table Mapping store with TTL and counter support
function _M.create_mapping_store(options)
  local store = {
    mappings = {},           -- masked_id -> original_value
    reverse_mappings = {},   -- original_value -> masked_id  
    counters = {},          -- resource_type -> counter
    timestamps = {},        -- masked_id -> creation_timestamp
    created_at = os.time(),
    config = {}
  }
  
  -- Apply options
  if options then
    for k, v in pairs(options) do
      store.config[k] = v
    end
  end
  
  -- Set defaults
  for k, v in pairs(_M.config) do
    if store.config[k] == nil then
      store.config[k] = v
    end
  end
  
  return store
end

---
-- Initialize pattern configuration
-- Determine which patterns need ngx.re
function _M.init_patterns()
  for name, pattern_def in pairs(patterns.patterns) do
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
  end
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
  
  -- Initialize mapping store if needed
  if not mapping_store.mappings then
    mapping_store.mappings = {}
    mapping_store.counters = {}
  end
  
  -- Process each pattern
  for pattern_name, pattern_info in pairs(pattern_config) do
    local pattern_def = pattern_info.pattern_def
    
    if pattern_info.use_ngx_re and ngx and ngx.re then
      -- Use ngx.re for complex patterns
      -- Convert Lua pattern to PCRE pattern
      local pcre_pattern = pattern_def.pattern
      -- Fix dash escaping: %-  → - (dash at end doesn't need escaping)
      pcre_pattern = pcre_pattern:gsub("%%%-", "-")
      -- Fix other Lua escapes if needed
      pcre_pattern = pcre_pattern:gsub("%%%+", "+")
      
      -- Use global replace with callback for better performance
      local replace_count = 0
      masked_text, _, err = ngx.re.gsub(masked_text, pcre_pattern, function(m)
        local masked_id = _M._get_or_create_masked_id(m[0], pattern_def, mapping_store)
        replace_count = replace_count + 1
        return masked_id
      end, "jo")
      
      if err then
        -- Fallback to Lua pattern if ngx.re fails
        masked_text = text
        replace_count = 0
        masked_text = masked_text:gsub(pattern_def.pattern, function(match)
          local masked_id = _M._get_or_create_masked_id(match, pattern_def, mapping_store)
          replace_count = replace_count + 1
          return masked_id
        end)
      end
      
      if replace_count > 0 then
        mask_count = mask_count + replace_count
        patterns_used[pattern_name] = replace_count
      end
    else
      -- Use Lua pattern for simple cases
      local replace_count = 0
      masked_text = masked_text:gsub(pattern_def.pattern, function(match)
        local masked_id = _M._get_or_create_masked_id(match, pattern_def, mapping_store)
        replace_count = replace_count + 1
        return masked_id
      end)
      
      if replace_count > 0 then
        mask_count = mask_count + replace_count
        patterns_used[pattern_name] = replace_count
      end
    end
  end
  
  return {
    masked = masked_text,
    count = mask_count,
    patterns_used = patterns_used
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
  
  if not mapping_store or not mapping_store.mappings then
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
  -- Check if already masked
  for masked_id, stored_value in pairs(mapping_store.mappings) do
    if stored_value == original_value then
      return masked_id
    end
  end
  
  -- Create new masked ID
  local resource_type = pattern_def.type or "unknown"
  mapping_store.counters[resource_type] = (mapping_store.counters[resource_type] or 0) + 1
  
  local masked_id = string.format(pattern_def.replacement, mapping_store.counters[resource_type])
  
  -- Store bidirectional mapping
  mapping_store.mappings[masked_id] = original_value
  
  return masked_id
end

---
-- Escape special pattern characters for string replacement
-- @param string str String to escape
-- @return string Escaped string
function _M._escape_pattern(str)
  if type(str) ~= "string" then return "" end
  return string.gsub(str, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- Initialize patterns on module load
_M.init_patterns()

return _M