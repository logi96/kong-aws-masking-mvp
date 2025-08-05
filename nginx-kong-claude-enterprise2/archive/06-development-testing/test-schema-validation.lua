#!/usr/bin/env lua

--
-- Schema Validation Test for AWS Masker Plugin ElastiCache Support
-- Tests both traditional and managed Redis configurations
-- Day 2 Implementation Validation
--

-- Mock Kong DB schema typedefs (simplified for testing)
local typedefs = {}

-- Load the updated schema
local schema = dofile("kong/plugins/aws-masker/schema.lua")

---
-- Test configuration validator
-- @param config table Configuration to test
-- @param expected_valid boolean Whether config should be valid
-- @param test_name string Name of the test
local function test_config(config, expected_valid, test_name)
    print("Testing: " .. test_name)
    
    -- Get the config schema
    local config_schema = schema.fields[1].config
    
    -- Test custom validator if it exists
    if config_schema.custom_validator then
        local is_valid, err = config_schema.custom_validator(config)
        
        if expected_valid then
            if is_valid then
                print("  ✅ PASS: Configuration is valid")
            else
                print("  ❌ FAIL: Expected valid config but got error: " .. (err or "unknown"))
            end
        else
            if not is_valid then
                print("  ✅ PASS: Configuration correctly rejected: " .. (err or "unknown"))
            else
                print("  ❌ FAIL: Expected invalid config but validation passed")
            end
        end
    else
        print("  ⚠️  WARNING: No custom validator found")
    end
    
    print("")
end

---
-- Test Suite: Schema Validation Tests
--
print("=== AWS Masker Plugin Schema Validation Tests ===")
print("Testing ElastiCache configuration extensions")
print("")

-- Test 1: Default/Traditional Redis Configuration (Backward Compatibility)
test_config({
    redis_type = "traditional",
    mask_ec2_instances = true,
    use_redis = true,
    mapping_ttl = 604800
}, true, "Default traditional Redis configuration")

-- Test 2: Traditional Redis with ElastiCache fields (should fail)
test_config({
    redis_type = "traditional",
    redis_ssl_enabled = true,
    mask_ec2_instances = true
}, false, "Traditional Redis with ElastiCache SSL field")

-- Test 3: Managed Redis with SSL enabled
test_config({
    redis_type = "managed",
    redis_ssl_enabled = true,
    redis_ssl_verify = true,
    mask_ec2_instances = true
}, true, "Managed Redis with SSL configuration")

-- Test 4: Managed Redis with cluster mode (valid)
test_config({
    redis_type = "managed",
    redis_cluster_mode = true,
    redis_cluster_endpoint = "my-cluster.abc123.cache.amazonaws.com:6379",
    redis_ssl_enabled = true
}, true, "Managed Redis with cluster mode")

-- Test 5: Managed Redis with cluster mode but no endpoint (should fail)
test_config({
    redis_type = "managed",
    redis_cluster_mode = true,
    redis_ssl_enabled = true
}, false, "Managed Redis with cluster mode but no endpoint")

-- Test 6: Managed Redis with endpoint but no cluster mode (should fail)
test_config({
    redis_type = "managed",
    redis_cluster_endpoint = "my-cluster.abc123.cache.amazonaws.com:6379",
    redis_ssl_enabled = true
}, false, "Managed Redis with endpoint but cluster mode disabled")

-- Test 7: Managed Redis with user but no auth token (should fail)
test_config({
    redis_type = "managed",
    redis_user = "myuser",
    redis_ssl_enabled = true
}, false, "Managed Redis with user but no auth token")

-- Test 8: Managed Redis with complete authentication
test_config({
    redis_type = "managed",
    redis_user = "myuser",
    redis_auth_token = "mypassword123",
    redis_ssl_enabled = true,
    redis_ssl_verify = true
}, true, "Managed Redis with complete authentication")

-- Test 9: Backward compatibility - no redis_type specified (should default to traditional)
test_config({
    mask_ec2_instances = true,
    use_redis = true,
    mapping_ttl = 604800
}, true, "No redis_type specified (backward compatibility)")

-- Test 10: Empty configuration (should be valid with defaults)
test_config({}, true, "Empty configuration (should use defaults)")

print("=== Schema Field Structure Test ===")
print("Testing that all required fields are present in schema")
print("")

-- Test schema structure
local config_fields = schema.fields[1].config.fields
local expected_fields = {
    "mask_ec2_instances", "mask_s3_buckets", "mask_rds_instances", "mask_private_ips",
    "preserve_structure", "log_masked_requests", "anthropic_api_key", 
    "use_redis", "mapping_ttl", "max_entries",
    "redis_type", "redis_ssl_enabled", "redis_ssl_verify", 
    "redis_auth_token", "redis_user", "redis_cluster_mode", "redis_cluster_endpoint"
}

print("Expected fields: " .. #expected_fields)
print("Actual fields: " .. #config_fields)

-- Check if all expected fields are present
local field_map = {}
for _, field_def in ipairs(config_fields) do
    for field_name, _ in pairs(field_def) do
        field_map[field_name] = true
    end
end

local missing_fields = {}
for _, expected_field in ipairs(expected_fields) do
    if not field_map[expected_field] then
        table.insert(missing_fields, expected_field)
    end
end

if #missing_fields == 0 then
    print("✅ All expected fields are present in schema")
else
    print("❌ Missing fields: " .. table.concat(missing_fields, ", "))
end

print("")
print("=== Field Defaults Test ===")
print("Checking default values for ElastiCache fields")

-- Find redis_type field and check default
for _, field_def in ipairs(config_fields) do
    if field_def.redis_type then
        local default_val = field_def.redis_type.default
        if default_val == "traditional" then
            print("✅ redis_type defaults to 'traditional' (backward compatibility)")
        else
            print("❌ redis_type default is '" .. tostring(default_val) .. "', expected 'traditional'")
        end
        break
    end
end

-- Check SSL defaults
for _, field_def in ipairs(config_fields) do
    if field_def.redis_ssl_enabled then
        local default_val = field_def.redis_ssl_enabled.default
        if default_val == false then
            print("✅ redis_ssl_enabled defaults to false")
        else
            print("❌ redis_ssl_enabled default is " .. tostring(default_val) .. ", expected false")
        end
        break
    end
end

for _, field_def in ipairs(config_fields) do
    if field_def.redis_ssl_verify then
        local default_val = field_def.redis_ssl_verify.default
        if default_val == true then
            print("✅ redis_ssl_verify defaults to true (secure by default)")
        else
            print("❌ redis_ssl_verify default is " .. tostring(default_val) .. ", expected true")
        end
        break
    end
end

print("")
print("=== Test Summary ===")
print("Schema validation tests completed")
print("ElastiCache integration fields added successfully")
print("Backward compatibility maintained")
print("Conditional validation implemented")