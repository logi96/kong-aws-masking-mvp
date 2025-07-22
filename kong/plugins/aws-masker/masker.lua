--
-- AWS Masker Core Logic Module
-- Handles masking/unmasking of AWS resources with performance optimization
-- Following TDD Green phase with 04-code-quality-assurance.md standards
-- JSDoc annotations for type safety per CLAUDE.md requirements
--

local patterns = require("kong.plugins.aws-masker.patterns")
local cjson = require("cjson.safe")

local _M = {}

---
-- Default configuration for masker
-- TTL and limits follow CLAUDE.md performance requirements (< 5s total, < 100ms masking)
-- @type table
_M.config = {
  ttl = 300,              -- 5 minutes TTL for mappings
  max_mappings = 10000,   -- Memory limit per CLAUDE.md
  cleanup_interval = 60   -- Cleanup every minute
}

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
-- Masks AWS resources in provided data
-- Handles both string and table inputs recursively
-- Performance optimized for < 100ms requirement
-- @param string|table data Data to mask AWS resources in
-- @param table mapping_store Mapping store for consistency
-- @param table config Optional masking configuration
-- @return table Result with masked data, mappings, and metadata
function _M.mask_data(data, mapping_store, config)
  local start_time = os.clock()
  local result = {
    masked = nil,
    mappings = {},
    count = 0,
    duration = 0,
    timestamp = os.time()
  }
  
  kong.log.info("Masker: mask_data called with data type: " .. type(data))
  kong.log.info("Masker: mapping_store present: " .. (mapping_store and "yes" or "no"))
  kong.log.info("Masker: config present: " .. (config and "yes" or "no"))
  
  if not data then
    kong.log.info("Masker: No data provided, returning unchanged")
    result.masked = data
    result.duration = (os.clock() - start_time) * 1000
    return result
  end
  
  -- Handle different data types
  if type(data) == "string" then
    kong.log.info("Masker: Processing string data, length: " .. string.len(data))
    result.masked, result.count = _M._mask_string(data, mapping_store, config)
  elseif type(data) == "table" then
    kong.log.info("Masker: Processing table data")
    result.masked, result.count = _M._mask_table(data, mapping_store, config)
  else
    kong.log.info("Masker: Data type not supported for masking: " .. type(data))
    result.masked = data
  end
  
  -- Copy current mappings to result
  for masked_id, original in pairs(mapping_store.mappings) do
    result.mappings[masked_id] = original
  end
  
  result.duration = (os.clock() - start_time) * 1000
  
  -- Performance check per CLAUDE.md requirements
  if result.duration > 100 then
    kong.log.warn("Masking took " .. result.duration .. "ms (>100ms limit)")
  end
  
  return result
end

---
-- Unmasks AWS resources using stored mappings
-- @param string|table masked_data Data containing masked AWS resources
-- @param table mapping_store Mapping store with original values
-- @return string|table Data with original AWS resource identifiers restored
function _M.unmask_data(masked_data, mapping_store)
  if not masked_data or not mapping_store then
    return masked_data
  end
  
  if type(masked_data) == "string" then
    return _M._unmask_string(masked_data, mapping_store)
  elseif type(masked_data) == "table" then
    return _M._unmask_table(masked_data, mapping_store)
  else
    return masked_data
  end
end

---
-- Internal function to mask AWS resources in string
-- @param string text Text to mask
-- @param table mapping_store Mapping store
-- @param table config Configuration options
-- @return string,number Masked text and count of masked resources
function _M._mask_string(text, mapping_store, config)
  if not text or type(text) ~= "string" then
    kong.log.info("Masker: _mask_string called with invalid input")
    return text, 0
  end
  
  kong.log.info("Masker: _mask_string processing text of length: " .. string.len(text))
  
  local masked_text = text
  local mask_count = 0
  
  -- Apply each pattern type
  for pattern_name, pattern_def in pairs(patterns.patterns) do
    kong.log.info("Masker: Checking pattern: " .. pattern_name .. " for type: " .. pattern_def.type)
    
    -- Skip if pattern disabled in config
    if config and config["mask_" .. pattern_def.type] == false then
      kong.log.info("Masker: Pattern " .. pattern_name .. " disabled in config")
      goto continue
    end
    
    -- Find all matches for this pattern
    local matches = {}
    
    -- Debug the pattern and input text
    kong.log.info("Masker: Testing pattern '" .. pattern_def.pattern .. "' against text sample: '" .. text:sub(1, 100) .. "'")
    
    for match in string.gmatch(text, pattern_def.pattern) do
      kong.log.info("Masker: Found match for " .. pattern_name .. ": " .. match)
      table.insert(matches, match)
    end
    
    kong.log.info("Masker: Found " .. #matches .. " matches for pattern " .. pattern_name)
    
    -- Test single match for debugging
    if #matches == 0 and pattern_name == "ec2_instance" then
      local test_match = string.match(text, pattern_def.pattern)
      kong.log.info("Masker: Direct string.match test for EC2: " .. tostring(test_match))
    end
    
    -- Replace each match with masked version
    for _, original_value in ipairs(matches) do
      local masked_id = _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
      if masked_id then
        kong.log.info("Masker: Masking " .. original_value .. " -> " .. masked_id)
        -- Replace all occurrences of this original value
        masked_text = string.gsub(masked_text, _M._escape_pattern(original_value), masked_id)
        mask_count = mask_count + 1
      end
    end
    
    ::continue::
  end
  
  kong.log.info("Masker: _mask_string completed, total masked: " .. mask_count)
  return masked_text, mask_count
end

---
-- Internal function to mask AWS resources in table structures
-- @param table data Table data to mask recursively
-- @param table mapping_store Mapping store
-- @param table config Configuration options
-- @return table,number Masked table and count of masked resources
function _M._mask_table(data, mapping_store, config)
  if not data or type(data) ~= "table" then
    return data, 0
  end
  
  local masked_table = {}
  local total_count = 0
  
  for key, value in pairs(data) do
    if type(value) == "string" then
      local masked_value, count = _M._mask_string(value, mapping_store, config)
      masked_table[key] = masked_value
      total_count = total_count + count
    elseif type(value) == "table" then
      local masked_subtable, count = _M._mask_table(value, mapping_store, config)
      masked_table[key] = masked_subtable
      total_count = total_count + count
    else
      masked_table[key] = value
    end
  end
  
  return masked_table, total_count
end

---
-- Internal function to unmask string data
-- @param string text Masked text
-- @param table mapping_store Mapping store with original values
-- @return string Unmasked text
function _M._unmask_string(text, mapping_store)
  if not text or type(text) ~= "string" then
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
-- Internal function to unmask table data recursively
-- @param table data Masked table data
-- @param table mapping_store Mapping store
-- @return table Unmasked table data
function _M._unmask_table(data, mapping_store)
  if not data or type(data) ~= "table" then
    return data
  end
  
  local unmasked_table = {}
  
  for key, value in pairs(data) do
    if type(value) == "string" then
      unmasked_table[key] = _M._unmask_string(value, mapping_store)
    elseif type(value) == "table" then
      unmasked_table[key] = _M._unmask_table(value, mapping_store)
    else
      unmasked_table[key] = value
    end
  end
  
  return unmasked_table
end

---
-- Gets existing masked ID or creates new one for AWS resource
-- Ensures consistency - same resource gets same masked ID
-- @param string original_value Original AWS resource identifier
-- @param table pattern_def Pattern definition with replacement format
-- @param table mapping_store Mapping store
-- @return string|nil Masked identifier or nil on error
function _M._get_or_create_masked_id(original_value, pattern_def, mapping_store)
  if not original_value or not pattern_def or not mapping_store then
    return nil
  end
  
  -- Check if already masked
  local existing_masked = mapping_store.reverse_mappings[original_value]
  if existing_masked then
    return existing_masked
  end
  
  -- Check mapping limit per CLAUDE.md requirements
  local current_count = 0
  for _ in pairs(mapping_store.mappings) do
    current_count = current_count + 1
  end
  
  if current_count >= mapping_store.config.max_mappings then
    kong.log.warn("Mapping store limit reached: " .. mapping_store.config.max_mappings)
    _M._cleanup_old_mappings(mapping_store)
  end
  
  -- Create new masked ID
  local resource_type = pattern_def.type
  mapping_store.counters[resource_type] = (mapping_store.counters[resource_type] or 0) + 1
  
  local masked_id = string.format(pattern_def.replacement, mapping_store.counters[resource_type])
  
  -- Store bidirectional mapping
  mapping_store.mappings[masked_id] = original_value
  mapping_store.reverse_mappings[original_value] = masked_id
  mapping_store.timestamps[masked_id] = os.time()
  
  return masked_id
end

---
-- Escapes special pattern characters for string replacement
-- @param string str String to escape
-- @return string Escaped string safe for pattern matching
function _M._escape_pattern(str)
  if not str then return str end
  
  -- Escape Lua pattern special characters
  return string.gsub(str, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

---
-- Cleans up old mappings based on TTL
-- Called automatically when mapping limit is reached
-- @param table mapping_store Mapping store to cleanup
-- @return number Number of mappings removed
function _M._cleanup_old_mappings(mapping_store)
  if not mapping_store or not mapping_store.timestamps then
    return 0
  end
  
  local current_time = os.time()
  local ttl = mapping_store.config.ttl or _M.config.ttl
  local removed_count = 0
  
  for masked_id, timestamp in pairs(mapping_store.timestamps) do
    if current_time - timestamp > ttl then
      local original_value = mapping_store.mappings[masked_id]
      
      -- Remove from all mapping tables
      mapping_store.mappings[masked_id] = nil
      mapping_store.timestamps[masked_id] = nil
      if original_value then
        mapping_store.reverse_mappings[original_value] = nil
      end
      
      removed_count = removed_count + 1
    end
  end
  
  if removed_count > 0 then
    kong.log.info("Cleaned up " .. removed_count .. " expired mappings")
  end
  
  return removed_count
end

---
-- Clears all mappings from store
-- @param table mapping_store Mapping store to clear
function _M.clear_mappings(mapping_store)
  if not mapping_store then return end
  
  mapping_store.mappings = {}
  mapping_store.reverse_mappings = {}
  mapping_store.counters = {}
  mapping_store.timestamps = {}
  
  kong.log.info("Cleared all mappings from store")
end

---
-- Gets count of current mappings in store
-- @param table mapping_store Mapping store
-- @return number Number of current mappings
function _M.get_mapping_count(mapping_store)
  if not mapping_store or not mapping_store.mappings then
    return 0
  end
  
  local count = 0
  for _ in pairs(mapping_store.mappings) do
    count = count + 1
  end
  
  return count
end

---
-- Cleanup expired mappings (public interface)
-- @param table mapping_store Mapping store
-- @return number Number of mappings cleaned up
function _M.cleanup_expired_mappings(mapping_store)
  return _M._cleanup_old_mappings(mapping_store)
end

return _M