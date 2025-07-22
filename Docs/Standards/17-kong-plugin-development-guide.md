# 🔌 **Kong Plugin Development Guide - Lua Standards & Best Practices**

<!-- Tags: #kong #plugin #lua #standards #development #masking -->

> **PURPOSE**: Comprehensive guide for developing Kong plugins with Lua, focusing on AWS resource masking functionality  
> **SCOPE**: Plugin architecture, Lua coding standards, testing strategies, debugging techniques  
> **COMPLEXITY**: ⭐⭐⭐⭐ Advanced | **DURATION**: 3-4 hours for complete implementation  
> **PREREQUISITE**: Basic Lua knowledge, Kong Gateway concepts understanding

---

## ⚡ **QUICK START - Kong Plugin Essentials**

### 🎯 **Plugin Development Checklist**
```lua
-- Essential Kong plugin structure
return {
  name = "aws-masker",
  version = "1.0.0",
  priority = 1000,  -- Higher runs first
  handler = require("handler"),
  schema = require("schema")
}
```

### 🔍 **Quick Command Reference**
```bash
# Plugin development commands
kong start -c kong.yml              # Start Kong with config
kong reload                         # Reload after changes
kong stop                          # Stop Kong

# Testing plugins
curl -X POST http://localhost:8001/plugins \
  --data "name=aws-masker" \
  --data "config.mask_patterns=true"

# Debug mode
export KONG_LOG_LEVEL=debug
kong start
```

---

## 📋 **KONG PLUGIN ARCHITECTURE**

### **Plugin Lifecycle**
```lua
-- Handler lifecycle phases
function AwsMaskerHandler:init_worker()
  -- Called once per worker
end

function AwsMaskerHandler:access(conf)
  -- Pre-upstream processing
end

function AwsMaskerHandler:header_filter(conf)
  -- Modify response headers
end

function AwsMaskerHandler:body_filter(conf)
  -- Modify response body (our main logic)
end

function AwsMaskerHandler:log(conf)
  -- Logging phase
end
```

### **Plugin Structure**
```
aws-masker/
├── handler.lua       # Main plugin logic
├── schema.lua        # Configuration schema
├── masker.lua       # Masking utility module
└── spec/
    └── aws-masker_spec.lua  # Test specifications
```

---

## 🏗️ **LUA CODING STANDARDS**

### **Naming Conventions**
```lua
-- ✅ Correct naming patterns
local function mask_ec2_instance(data)  -- snake_case for functions
local MASK_PREFIX = "EC2_"             -- UPPER_CASE for constants
local masked_data = {}                 -- snake_case for variables

-- ❌ Avoid
local function maskEC2Instance(data)   -- camelCase
local maskPrefix = "EC2_"             -- camelCase for constants
```

### **Module Structure**
```lua
-- ✅ Proper module pattern
local _M = {}
local _MT = { __index = _M }

-- Private functions
local function validate_pattern(pattern)
  return pattern and type(pattern) == "string"
end

-- Public functions
function _M.new()
  return setmetatable({}, _MT)
end

function _M:mask_data(data, patterns)
  -- Implementation
end

return _M
```

### **Error Handling**
```lua
-- ✅ Proper error handling
function _M:process_request(data)
  if not data then
    return nil, "data is required"
  end
  
  local ok, result = pcall(function()
    return self:mask_sensitive_data(data)
  end)
  
  if not ok then
    kong.log.err("Masking failed: ", result)
    return nil, result
  end
  
  return result
end

-- ❌ Avoid bare errors
function process(data)
  return mask_data(data)  -- No error handling
end
```

---

## 🎯 **AWS MASKING IMPLEMENTATION**

### **Pattern Matching Strategy**
```lua
local patterns = {
  -- EC2 instances
  {
    pattern = "i%-[0-9a-f]+",
    replacement = function(match, counter)
      return "EC2_" .. string.format("%03d", counter.ec2)
    end,
    counter_key = "ec2"
  },
  
  -- S3 buckets
  {
    pattern = "[a-z0-9][a-z0-9%-]*[a-z0-9]%.s3",
    replacement = function(match, counter)
      return "BUCKET_" .. string.format("%03d", counter.s3)
    end,
    counter_key = "s3"
  },
  
  -- Private IPs
  {
    pattern = "10%.%d+%.%d+%.%d+",
    replacement = function(match, counter)
      return "PRIVATE_IP_" .. string.format("%03d", counter.ip)
    end,
    counter_key = "ip"
  }
}
```

### **Masking Logic**
```lua
function _M:mask_data(data)
  local masked = data
  local mapping = {}
  local counters = { ec2 = 1, s3 = 1, ip = 1 }
  
  for _, pattern_config in ipairs(patterns) do
    masked = string.gsub(masked, pattern_config.pattern, 
      function(match)
        -- Check if already masked
        if mapping[match] then
          return mapping[match]
        end
        
        -- Create new mask
        local masked_value = pattern_config.replacement(
          match, 
          counters
        )
        
        -- Store mapping
        mapping[match] = masked_value
        counters[pattern_config.counter_key] = 
          counters[pattern_config.counter_key] + 1
        
        return masked_value
      end
    )
  end
  
  return masked, mapping
end
```

---

## 🧪 **TESTING KONG PLUGINS**

### **Test Setup**
```lua
-- spec/aws-masker_spec.lua
local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("AWS Masker Plugin", function()
  local client
  
  setup(function()
    helpers.start_kong({
      plugins = "bundled,aws-masker",
      custom_plugins = "aws-masker"
    })
    
    client = helpers.proxy_client()
  end)
  
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)
end)
```

### **Unit Tests**
```lua
describe("Masking patterns", function()
  local masker = require "kong.plugins.aws-masker.masker"
  
  it("masks EC2 instance IDs", function()
    local data = '{"instance": "i-1234567890abcdef0"}'
    local masked = masker:mask_data(data)
    
    assert.matches('"instance": "EC2_001"', masked)
  end)
  
  it("maintains consistent mapping", function()
    local data = 'i-abc123 and i-abc123'
    local masked = masker:mask_data(data)
    
    assert.equals("EC2_001 and EC2_001", masked)
  end)
end)
```

### **Integration Tests**
```lua
it("masks response body", function()
  local res = client:get("/test", {
    headers = { ["Content-Type"] = "application/json" }
  })
  
  local body = assert.res_status(200, res)
  local json = cjson.decode(body)
  
  assert.not_matches("i%-", body)  -- No instance IDs
  assert.matches("EC2_%d+", body)  -- Masked format
end)
```

---

## 🔒 **SECURITY CONSIDERATIONS**

### **Sensitive Data Handling**
```lua
-- ✅ Secure practices
function _M:store_mapping(mapping)
  -- Store in memory only, never persist
  self.mappings = self.mappings or {}
  
  for original, masked in pairs(mapping) do
    self.mappings[masked] = {
      timestamp = ngx.now(),
      -- Don't store full original, just type
      resource_type = self:get_resource_type(original)
    }
  end
end

-- ❌ Avoid
function store_mapping(mapping)
  -- Never log sensitive data
  kong.log.debug("Mapping: ", cjson.encode(mapping))
end
```

### **Memory Management**
```lua
-- ✅ Proper cleanup
function _M:cleanup_old_mappings()
  local now = ngx.now()
  local ttl = 300  -- 5 minutes
  
  for key, data in pairs(self.mappings or {}) do
    if now - data.timestamp > ttl then
      self.mappings[key] = nil
    end
  end
end
```

---

## 🐛 **DEBUGGING TECHNIQUES**

### **Debug Logging**
```lua
-- Conditional debug logging
local DEBUG = os.getenv("KONG_LOG_LEVEL") == "debug"

function _M:debug_log(...)
  if DEBUG then
    kong.log.debug(...)
  end
end

-- Usage
self:debug_log("Processing data length: ", #data)
```

### **Performance Profiling**
```lua
-- Simple profiling wrapper
local function profile(name, func)
  local start = ngx.now()
  local result = func()
  local elapsed = (ngx.now() - start) * 1000
  
  kong.log.info(name, " took ", elapsed, "ms")
  return result
end

-- Usage
local masked = profile("masking", function()
  return self:mask_data(data)
end)
```

---

## 📊 **PERFORMANCE OPTIMIZATION**

### **Pattern Compilation**
```lua
-- ✅ Compile patterns once
local compiled_patterns = {}

function _M:init_patterns()
  for i, pattern in ipairs(patterns) do
    compiled_patterns[i] = {
      regex = ngx.re.compile(pattern.pattern, "jo"),
      config = pattern
    }
  end
end

-- ❌ Avoid compiling in hot path
function mask_data(data)
  local pattern = ngx.re.compile("i%-[0-9a-f]+", "jo")
  -- Compiles every time
end
```

### **String Building**
```lua
-- ✅ Efficient string building
local function build_response(parts)
  local buffer = {}
  for i, part in ipairs(parts) do
    buffer[i] = part
  end
  return table.concat(buffer)
end

-- ❌ Avoid concatenation in loops
local result = ""
for _, part in ipairs(parts) do
  result = result .. part  -- Creates new string each time
end
```

---

## 🚀 **DEPLOYMENT GUIDELINES**

### **Plugin Installation**
```bash
# Directory structure
mkdir -p /usr/local/share/lua/5.1/kong/plugins/aws-masker
cp *.lua /usr/local/share/lua/5.1/kong/plugins/aws-masker/

# Kong configuration
echo "plugins = bundled,aws-masker" >> kong.conf
```

### **Configuration Management**
```yaml
# kong.yml declarative config
plugins:
  - name: aws-masker
    config:
      mask_patterns: true
      preserve_structure: true
      ttl: 300
    protocols:
      - http
      - https
```

---

## 💡 **BEST PRACTICES SUMMARY**

### **Do's**
```lua
-- ✅ Best practices
- Use local variables for performance
- Handle errors gracefully
- Profile critical paths
- Clean up resources
- Use Kong's built-in utilities
- Test edge cases thoroughly
```

### **Don'ts**
```lua
-- ❌ Avoid these
- Don't use global variables
- Don't log sensitive data
- Don't block the event loop
- Don't ignore errors
- Don't store state in files
- Don't modify request body unnecessarily
```

---

## 🔧 **TROUBLESHOOTING GUIDE**

### **Common Issues**

| Issue | Cause | Solution |
|-------|-------|----------|
| Plugin not loading | Path issues | Check LUA_PATH includes plugin directory |
| Pattern not matching | Regex escaping | Use `ngx.re.match` for testing patterns |
| Memory growth | No cleanup | Implement TTL for stored mappings |
| Performance degradation | Inefficient patterns | Pre-compile and optimize regex |

### **Debug Commands**
```bash
# Check plugin loading
curl http://localhost:8001/plugins/enabled

# View plugin config
curl http://localhost:8001/plugins

# Check Kong error log
tail -f /usr/local/kong/logs/error.log

# Test pattern matching
kong migrations up && kong start -c kong.yml --vv
```

---

**🔑 Key Message**: Successful Kong plugin development requires understanding Lua patterns, Kong's request lifecycle, and performance implications. Focus on secure, efficient masking with proper testing and monitoring.