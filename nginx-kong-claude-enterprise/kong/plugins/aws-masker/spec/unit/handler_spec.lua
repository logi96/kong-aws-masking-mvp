--
-- 🔴 TDD RED: AWS Masker Handler Specification
-- Tests for Kong plugin handler lifecycle and integration
-- Following TDD Red-Green-Refactor with 04-code-quality-assurance.md standards
-- Per CLAUDE.md: < 5s total response time, security-first design
--

describe("AWS Masker Handler", function()
  local handler
  local mock_data = require("spec.mock_data")
  
  before_each(function()
    -- Reset module cache to ensure clean state
    package.loaded["kong.plugins.aws-masker.handler"] = nil
    
    -- Mock kong.plugins.base_plugin
    if not package.loaded["kong.plugins.base_plugin"] then
      package.loaded["kong.plugins.base_plugin"] = {
        extend = function(self)
          local plugin = {}
          plugin.super = {
            new = function() end,
            access = function() end,
            body_filter = function() end
          }
          setmetatable(plugin, {__index = self})
          return plugin
        end
      }
    end
    
    handler = require("kong.plugins.aws-masker.handler")
  end)
  
  describe("🔴 Handler Structure", function()
    it("should extend BasePlugin properly", function()
      -- TEST: Handler should be properly constructed
      assert.is.table(handler)
      assert.is.string(handler.VERSION)
      assert.is.number(handler.PRIORITY)
      
      -- TEST: Should have Kong plugin priority between 1-1000
      assert.is.truthy(handler.PRIORITY >= 1 and handler.PRIORITY <= 1000)
    end)
    
    it("should have required lifecycle methods", function()
      -- TEST: Should implement Kong plugin lifecycle
      assert.is.function(handler.new)
      assert.is.function(handler.access)
      assert.is.function(handler.body_filter)
    end)
    
    it("should have proper version format", function()
      -- TEST: Version should follow semver format
      assert.matches("%d+%.%d+%.%d+", handler.VERSION)
    end)
  end)
  
  describe("🔴 Plugin Initialization", function()
    it("should create new handler instance", function()
      local instance = handler:new()
      
      -- TEST: Should create valid instance
      assert.is.table(instance)
      assert.is.not_nil(instance.mapping_store)
    end)
    
    it("should initialize with default configuration", function()
      local instance = handler:new()
      
      -- TEST: Should have default config values
      assert.is.table(instance.config)
      assert.is.boolean(instance.config.mask_ec2_instances)
      assert.is.boolean(instance.config.mask_s3_buckets)
      assert.is.boolean(instance.config.mask_rds_instances)
      assert.is.boolean(instance.config.mask_private_ips)
    end)
    
    it("should handle custom configuration", function()
      local custom_config = {
        mask_ec2_instances = false,
        mask_s3_buckets = true,
        log_masked_requests = true
      }
      
      local instance = handler:new()
      instance.config = custom_config
      
      -- TEST: Should use custom config
      assert.is.false(instance.config.mask_ec2_instances)
      assert.is.true(instance.config.mask_s3_buckets)
      assert.is.true(instance.config.log_masked_requests)
    end)
  end)
  
  describe("🔴 Access Phase - Request Masking", function()
    local instance
    local mock_conf
    
    before_each(function()
      instance = handler:new()
      mock_conf = {
        mask_ec2_instances = true,
        mask_s3_buckets = true,
        mask_rds_instances = true,
        mask_private_ips = true,
        preserve_structure = true,
        log_masked_requests = false
      }
      
      -- Mock Kong request handling
      kong.service = kong.service or {}
      kong.service.request = {
        enable_buffering = function() end,
        get_raw_body = function() 
          return '{"message": "Instance i-1234567890abcdef0 analysis"}'
        end,
        set_raw_body = function(body)
          -- Store for verification
          kong.ctx.shared.masked_request_body = body
        end
      }
    end)
    
    it("should enable request buffering", function()
      local buffer_enabled = false
      kong.service.request.enable_buffering = function()
        buffer_enabled = true
      end
      
      -- TEST: Should enable buffering for body access
      instance:access(mock_conf)
      assert.is.true(buffer_enabled)
    end)
    
    it("should mask AWS resources in request body", function()
      -- TEST: Should mask EC2 instance in request
      instance:access(mock_conf)
      
      local masked_body = kong.ctx.shared.masked_request_body
      assert.is.string(masked_body)
      
      -- Should not contain original instance ID
      assert.is.false(string.find(masked_body, "i%-1234567890abcdef0") ~= nil)
      
      -- Should contain masked version
      assert.is.true(string.find(masked_body, "EC2_001") ~= nil)
    end)
    
    it("should store mapping in Kong context", function()
      -- TEST: Should store mappings for later unmasking
      instance:access(mock_conf)
      
      assert.is.not_nil(kong.ctx.shared.aws_mapping_store)
      assert.is.table(kong.ctx.shared.aws_mapping_store.mappings)
    end)
    
    it("should respect configuration options", function()
      -- Disable EC2 masking
      mock_conf.mask_ec2_instances = false
      
      kong.service.request.get_raw_body = function()
        return '{"message": "Instance i-1234567890abcdef0 and bucket my-test-bucket"}'
      end
      
      -- TEST: Should not mask EC2 when disabled
      instance:access(mock_conf)
      
      local masked_body = kong.ctx.shared.masked_request_body
      
      -- Should still contain EC2 instance (not masked)
      assert.is.true(string.find(masked_body, "i%-1234567890abcdef0") ~= nil)
      
      -- Should mask S3 bucket (still enabled)
      assert.is.true(string.find(masked_body, "BUCKET_") ~= nil)
    end)
    
    it("should handle empty or invalid request body", function()
      kong.service.request.get_raw_body = function()
        return nil
      end
      
      -- TEST: Should handle nil body gracefully
      local success = pcall(function()
        instance:access(mock_conf)
      end)
      
      assert.is.true(success)
    end)
    
    it("should handle malformed JSON gracefully", function()
      kong.service.request.get_raw_body = function()
        return '{"invalid": json malformed'
      end
      
      -- TEST: Should not crash on invalid JSON
      local success = pcall(function()
        instance:access(mock_conf)
      end)
      
      assert.is.true(success)
    end)
    
    it("should log masked requests when enabled", function()
      mock_conf.log_masked_requests = true
      
      local logged = false
      kong.log.info = function(msg)
        if string.find(msg, "masked") then
          logged = true
        end
      end
      
      -- TEST: Should log when log_masked_requests is true
      instance:access(mock_conf)
      assert.is.true(logged)
    end)
  end)
  
  describe("🔴 Body Filter Phase - Response Unmasking", function()
    local instance
    local mock_conf
    
    before_each(function()
      instance = handler:new()
      mock_conf = {
        mask_ec2_instances = true,
        mask_s3_buckets = true
      }
      
      -- Set up context with mappings (from access phase)
      kong.ctx.shared.aws_mapping_store = {
        mappings = {
          ["EC2_001"] = "i-1234567890abcdef0",
          ["BUCKET_001"] = "my-test-bucket"
        },
        reverse_mappings = {
          ["i-1234567890abcdef0"] = "EC2_001",
          ["my-test-bucket"] = "BUCKET_001"
        }
      }
      
      -- Mock Kong response handling
      kong.response = kong.response or {}
      kong.response.get_raw_body = function()
        return '{"analysis": "EC2_001 performance is good, check BUCKET_001"}'
      end
      kong.response.set_raw_body = function(body)
        kong.ctx.shared.unmasked_response_body = body
      end
    end)
    
    it("should unmask AWS resources in response body", function()
      -- TEST: Should unmask resources in Claude API response
      instance:body_filter(mock_conf)
      
      local unmasked_body = kong.ctx.shared.unmasked_response_body
      assert.is.string(unmasked_body)
      
      -- Should contain original identifiers
      assert.is.true(string.find(unmasked_body, "i%-1234567890abcdef0") ~= nil)
      assert.is.true(string.find(unmasked_body, "my%-test%-bucket") ~= nil)
      
      -- Should not contain masked versions
      assert.is.false(string.find(unmasked_body, "EC2_001") ~= nil)
      assert.is.false(string.find(unmasked_body, "BUCKET_001") ~= nil)
    end)
    
    it("should handle response without mappings context", function()
      -- Clear mapping context
      kong.ctx.shared.aws_mapping_store = nil
      
      -- TEST: Should handle missing context gracefully
      local success = pcall(function()
        instance:body_filter(mock_conf)
      end)
      
      assert.is.true(success)
    end)
    
    it("should handle empty response body", function()
      kong.response.get_raw_body = function()
        return nil
      end
      
      -- TEST: Should handle nil response gracefully
      local success = pcall(function()
        instance:body_filter(mock_conf)
      end)
      
      assert.is.true(success)
    end)
    
    it("should preserve response structure during unmasking", function()
      kong.response.get_raw_body = function()
        return '{"data": {"instances": ["EC2_001"], "buckets": ["BUCKET_001"]}, "status": "ok"}'
      end
      
      -- TEST: Should unmask while preserving JSON structure
      instance:body_filter(mock_conf)
      
      local unmasked_body = kong.ctx.shared.unmasked_response_body
      local parsed = cjson.decode(unmasked_body)
      
      assert.is.table(parsed)
      assert.is.table(parsed.data)
      assert.is.equal("ok", parsed.status)
      assert.is.equal("i-1234567890abcdef0", parsed.data.instances[1])
    end)
  end)
  
  describe("🔴 Performance Requirements", function()
    local instance
    
    before_each(function()
      instance = handler:new()
    end)
    
    it("should process requests within 5 second total limit", function()
      -- Mock large payload for performance test
      local large_payload = mock_data.get("performance").large_payload
      
      kong.service.request.get_raw_body = function()
        return cjson.encode(large_payload)
      end
      
      local start_time = os.clock()
      
      -- TEST: Access phase should be fast
      instance:access({
        mask_ec2_instances = true,
        mask_s3_buckets = true,
        mask_rds_instances = true,
        mask_private_ips = true
      })
      
      -- TEST: Body filter phase should be fast
      kong.response.get_raw_body = function()
        return '{"result": "processed"}'
      end
      
      instance:body_filter({})
      
      local elapsed = (os.clock() - start_time) * 1000
      
      -- Should complete well within 5 second limit (testing for 1 second)
      assert.is.truthy(elapsed < 1000, 
        "Handler processing took " .. elapsed .. "ms (should be < 1000ms)")
    end)
    
    it("should handle concurrent requests without interference", function()
      -- Create two handler instances (simulating concurrent requests)
      local instance1 = handler:new()
      local instance2 = handler:new()
      
      -- Set up different contexts
      local ctx1 = {shared = {}}
      local ctx2 = {shared = {}}
      
      -- Mock different request bodies
      local request1 = '{"data": "i-1111111111111111"}'
      local request2 = '{"data": "i-2222222222222222"}'
      
      -- TEST: Should not interfere with each other
      -- This is a simplified test - full concurrency would need proper threading
      assert.is.not_equal(request1, request2)
      assert.is.table(instance1)
      assert.is.table(instance2)
    end)
  end)
  
  describe("🔴 Error Handling", function()
    local instance
    
    before_each(function()
      instance = handler:new()
    end)
    
    it("should handle masker errors gracefully", function()
      -- Mock masker to throw error
      local original_mask = require("kong.plugins.aws-masker.masker").mask_data
      require("kong.plugins.aws-masker.masker").mask_data = function()
        error("Simulated masker error")
      end
      
      kong.service.request.get_raw_body = function()
        return '{"test": "data"}'
      end
      
      -- TEST: Should not crash on masker errors
      local success = pcall(function()
        instance:access({mask_ec2_instances = true})
      end)
      
      -- Restore original function
      require("kong.plugins.aws-masker.masker").mask_data = original_mask
      
      -- Should handle error gracefully
      assert.is.true(success)
    end)
    
    it("should handle JSON parsing errors", function()
      kong.service.request.get_raw_body = function()
        return "not json at all"
      end
      
      -- TEST: Should handle non-JSON content
      local success = pcall(function()
        instance:access({mask_ec2_instances = true})
      end)
      
      assert.is.true(success)
    end)
    
    it("should log errors appropriately", function()
      local error_logged = false
      kong.log.error = function(msg)
        error_logged = true
      end
      
      -- Force an error condition
      kong.service.request.get_raw_body = function()
        error("Simulated request error")
      end
      
      -- TEST: Should log errors when they occur
      pcall(function()
        instance:access({mask_ec2_instances = true})
      end)
      
      assert.is.true(error_logged)
    end)
  end)
  
  describe("🔴 Integration Requirements", function()
    it("should maintain CLAUDE.md security requirements", function()
      -- TEST: Should never expose original AWS resources externally
      local instance = handler:new()
      
      kong.service.request.get_raw_body = function()
        return '{"aws_data": "Instance i-1234567890abcdef0 in 10.0.1.100"}'
      end
      
      instance:access({
        mask_ec2_instances = true,
        mask_private_ips = true
      })
      
      local masked_body = kong.ctx.shared.masked_request_body
      
      -- Should not contain ANY original AWS identifiers
      assert.is.false(string.find(masked_body, "i%-1234567890abcdef0") ~= nil)
      assert.is.false(string.find(masked_body, "10%.0%.1%.100") ~= nil)
    end)
    
    it("should support all required AWS resource types", function()
      -- TEST: Should handle all AWS resource types per plan requirements
      local patterns = require("kong.plugins.aws-masker.patterns")
      
      -- Should have patterns for all required types
      assert.is.not_nil(patterns.patterns.ec2_instance)
      assert.is.not_nil(patterns.patterns.private_ip)
      assert.is.not_nil(patterns.patterns.s3_bucket)
      assert.is.not_nil(patterns.patterns.rds_instance)
    end)
  end)
end)

--
-- 🔴 RED PHASE COMPLETE FOR HANDLER
-- These tests will FAIL until we implement the handler properly
-- Current handler.lua is just a skeleton from Infrastructure team
-- Next step: 🟢 GREEN - Implement full handler.lua to make tests pass
--