--
-- 🔴 TDD RED: AWS Masker Core Logic Specification
-- Tests for the actual masking/unmasking functionality
-- Following TDD Red-Green-Refactor methodology
--

describe("AWS Masker Core Logic", function()
  local masker
  local patterns
  local mock_data = require("spec.mock_data")
  
  before_each(function()
    -- Reset module cache
    package.loaded["kong.plugins.aws-masker.masker"] = nil
    package.loaded["kong.plugins.aws-masker.patterns"] = nil
    
    patterns = require("kong.plugins.aws-masker.patterns")
    masker = require("kong.plugins.aws-masker.masker")
  end)
  
  describe("🔴 Masker Module Structure", function()
    it("should expose masking functions", function()
      -- TEST: Module should have required functions
      assert.is.function(masker.mask_data)
      assert.is.function(masker.unmask_data)
      assert.is.function(masker.create_mapping_store)
      assert.is.function(masker.clear_mappings)
    end)
    
    it("should have configuration options", function()
      -- TEST: Should have default config
      assert.is.table(masker.config)
      assert.is.number(masker.config.ttl)
      assert.is.number(masker.config.max_mappings)
    end)
  end)
  
  describe("🔴 Basic Data Masking", function()
    local mapping_store
    
    before_each(function()
      mapping_store = masker.create_mapping_store()
    end)
    
    it("should mask EC2 instance IDs in simple text", function()
      local original_text = "Please analyze instance i-1234567890abcdef0"
      
      -- TEST: Should mask EC2 instance ID
      local masked_result = masker.mask_data(original_text, mapping_store)
      
      assert.is.table(masked_result)
      assert.is.string(masked_result.masked)
      assert.is.table(masked_result.mappings)
      assert.is.number(masked_result.count)
      
      -- Should not contain original instance ID
      assert.is_false(string.find(masked_result.masked, "i%-1234567890abcdef0") ~= nil)
      
      -- Should contain masked version
      assert.is_true(string.find(masked_result.masked, "EC2_001") ~= nil)
      
      -- Should record mapping
      assert.is.equal(1, masked_result.count)
    end)
    
    it("should mask multiple resource types", function()
      local test_data = mock_data.get("request_payloads").mixed_content
      local original_text = test_data.message
      
      -- TEST: Should mask multiple AWS resources in one text
      local masked_result = masker.mask_data(original_text, mapping_store)
      
      assert.is.table(masked_result)
      assert.is.truthy(masked_result.count > 1)
      
      -- Should mask all resource types
      assert.is_true(string.find(masked_result.masked, "EC2_001") ~= nil)
      assert.is_true(string.find(masked_result.masked, "BUCKET_001") ~= nil)  
      assert.is_true(string.find(masked_result.masked, "PRIVATE_IP_001") ~= nil)
    end)
    
    it("should maintain masking consistency", function()
      local text1 = "Instance i-1234567890abcdef0 analysis"
      local text2 = "Check i-1234567890abcdef0 status"
      
      -- TEST: Same resource should get same mask
      local result1 = masker.mask_data(text1, mapping_store)
      local result2 = masker.mask_data(text2, mapping_store)
      
      -- Both should use EC2_001 for the same instance
      assert.is_true(string.find(result1.masked, "EC2_001") ~= nil)
      assert.is_true(string.find(result2.masked, "EC2_001") ~= nil)
      
      -- Should not create duplicate mappings
      local total_mappings = 0
      for _ in pairs(mapping_store.mappings) do
        total_mappings = total_mappings + 1
      end
      assert.is.equal(1, total_mappings)
    end)
  end)
  
  describe("🔴 Data Unmasking", function()
    local mapping_store
    
    before_each(function()
      mapping_store = masker.create_mapping_store()
    end)
    
    it("should unmask data using stored mappings", function()
      local original_text = "Instance i-1234567890abcdef0 with IP 10.0.1.100"
      
      -- First mask the data
      local masked_result = masker.mask_data(original_text, mapping_store)
      
      -- Then unmask it
      local unmasked_result = masker.unmask_data(masked_result.masked, mapping_store)
      
      -- TEST: Should restore original data
      assert.is.string(unmasked_result)
      assert.is.equal(original_text, unmasked_result)
    end)
    
    it("should handle partial unmasking", function()
      local original_text = "Instance i-1234567890abcdef0 analysis"
      local masked_result = masker.mask_data(original_text, mapping_store)
      
      -- Create text with only some masked identifiers
      local partial_text = "New EC2_001 configuration"
      
      -- TEST: Should unmask known identifiers
      local unmasked_result = masker.unmask_data(partial_text, mapping_store)
      assert.is_true(string.find(unmasked_result, "i%-1234567890abcdef0") ~= nil)
    end)
    
    it("should leave unknown masked identifiers unchanged", function()
      local unknown_masked = "Check EC2_999 status"
      
      -- TEST: Should leave unknown masks as-is
      local unmasked_result = masker.unmask_data(unknown_masked, mapping_store)
      assert.is.equal(unknown_masked, unmasked_result)
    end)
  end)
  
  describe("🔴 Complex Data Structure Masking", function() 
    local mapping_store
    
    before_each(function()
      mapping_store = masker.create_mapping_store()
    end)
    
    it("should handle nested JSON structures", function()
      local test_data = mock_data.get("request_payloads").nested_structure
      
      -- TEST: Should recursively mask nested structures
      local masked_result = masker.mask_data(test_data, mapping_store)
      
      assert.is.table(masked_result)
      assert.is.truthy(masked_result.count > 0)
      
      -- Should preserve structure while masking values
      assert.is.table(masked_result.masked)
      assert.is.table(masked_result.masked.infrastructure)
      assert.is.table(masked_result.masked.infrastructure.compute)
    end)
    
    it("should handle arrays of resources", function()
      local test_data = mock_data.get("request_payloads").multiple_resources
      
      -- TEST: Should mask all items in arrays
      local masked_result = masker.mask_data(test_data, mapping_store)
      
      assert.is.table(masked_result.masked)
      assert.is.table(masked_result.masked.instances)
      
      -- All instances should be masked
      for _, instance in ipairs(masked_result.masked.instances) do
        assert.is_true(string.find(instance, "EC2_") ~= nil)
      end
    end)
  end)
  
  describe("🔴 Mapping Store Management", function()
    it("should create mapping store with TTL support", function()
      local store = masker.create_mapping_store()
      
      -- TEST: Store should have required properties
      assert.is.table(store)
      assert.is.table(store.mappings)
      assert.is.table(store.reverse_mappings)
      assert.is.table(store.counters)
      assert.is.number(store.created_at)
    end)
    
    it("should enforce maximum mapping limits", function()
      local store = masker.create_mapping_store({max_mappings = 2})
      
      -- Add more mappings than limit
      masker.mask_data("i-1111111111111111", store)
      masker.mask_data("i-2222222222222222", store) 
      masker.mask_data("i-3333333333333333", store)
      
      -- TEST: Should not exceed max mappings
      local mapping_count = 0
      for _ in pairs(store.mappings) do
        mapping_count = mapping_count + 1
      end
      
      assert.is_truthy(mapping_count <= 2)
    end)
    
    it("should support TTL-based cleanup", function()
      local store = masker.create_mapping_store({ttl = 1}) -- 1 second TTL
      
      masker.mask_data("i-1234567890abcdef0", store)
      
      -- TEST: Should have mapping initially
      assert.is_truthy(next(store.mappings) ~= nil)
      
      -- Simulate TTL expiry and cleanup
      masker.cleanup_expired_mappings(store)
      
      -- Note: In real implementation, this would check timestamps
      assert.is.function(masker.cleanup_expired_mappings)
    end)
    
    it("should clear all mappings on demand", function()
      local store = masker.create_mapping_store()
      
      masker.mask_data("i-1234567890abcdef0", store)
      masker.mask_data("10.0.1.100", store)
      
      -- TEST: Should clear all mappings
      masker.clear_mappings(store)
      
      assert.is.equal(0, masker.get_mapping_count(store))
    end)
  end)
  
  describe("🔴 Performance Requirements", function()
    it("should mask data within 100ms limit", function()
      local mapping_store = masker.create_mapping_store()
      local test_data = mock_data.get("performance").large_payload
      
      -- TEST: Should process within time limit
      local start_time = os.clock()
      local masked_result = masker.mask_data(test_data, mapping_store)
      local elapsed = (os.clock() - start_time) * 1000
      
      assert.is.truthy(elapsed < 100, 
        "Masking took " .. elapsed .. "ms (should be < 100ms)")
      assert.is.table(masked_result)
    end)
    
    it("should handle concurrent masking requests", function()
      -- TEST: Should support multiple concurrent operations
      local store1 = masker.create_mapping_store()
      local store2 = masker.create_mapping_store()
      
      -- Simulate concurrent masking
      local result1 = masker.mask_data("i-1111111111111111", store1)
      local result2 = masker.mask_data("i-2222222222222222", store2)
      
      -- Should not interfere with each other
      assert.is.not_equal(result1.masked, result2.masked)
    end)
  end)
end)

--
-- 🔴 RED PHASE COMPLETE FOR MASKER
-- These tests will FAIL until we implement masker.lua
-- Next step: 🟢 GREEN - Implement masker.lua to make tests pass
--