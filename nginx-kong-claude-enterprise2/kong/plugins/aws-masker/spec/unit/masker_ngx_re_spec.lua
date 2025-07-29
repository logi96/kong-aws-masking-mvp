--
-- Unit tests for AWS Masker using ngx.re
--

describe("AWS Masker NGX RE", function()
  local masker
  local patterns
  
  setup(function()
    -- Mock ngx.re
    _G.ngx = {
      re = {
        match = function(str, pattern, flags)
          -- Simple mock implementation
          local lua_pattern = pattern:gsub("\\", "")
          return {str:match(lua_pattern)}
        end,
        gsub = function(str, pattern, replacement, flags)
          -- Simple mock implementation
          local lua_pattern = pattern:gsub("\\", "")
          local count = 0
          local result = str:gsub(lua_pattern, function(match)
            count = count + 1
            if type(replacement) == "function" then
              return replacement(match)
            else
              return replacement
            end
          end)
          return result, count
        end
      },
      shared = {
        kong = {
          get = function() return nil end,
          set = function() return true end
        }
      }
    }
    
    -- Load dependencies
    patterns = require("kong.plugins.aws-masker.patterns")
    masker = require("kong.plugins.aws-masker.masker_ngx_re")
  end)
  
  describe("mask_data", function()
    it("should mask EC2 instance IDs", function()
      local input = '{"instance_id": "i-1234567890abcdef0", "state": "running"}'
      local masked, count = masker.mask_data(input)
      
      assert.is_truthy(masked:find("EC2_001"))
      assert.is_falsy(masked:find("i%-1234567890abcdef0"))
      assert.equals(1, count)
    end)
    
    it("should mask multiple resources", function()
      local input = [[{
        "ec2": "i-1234567890abcdef0",
        "s3": "my-bucket-name",
        "ip": "10.0.0.1"
      }]]
      
      local masked, count = masker.mask_data(input)
      
      assert.is_truthy(masked:find("EC2_001"))
      assert.is_truthy(masked:find("BUCKET_001"))
      assert.is_truthy(masked:find("PRIVATE_IP_001"))
      assert.is_truthy(count >= 3)
    end)
    
    it("should preserve structure", function()
      local input = '{"data": {"instance": "i-1234567890abcdef0"}, "meta": {}}'
      local masked, count = masker.mask_data(input)
      
      -- Structure should remain intact
      assert.is_truthy(masked:find('"data"'))
      assert.is_truthy(masked:find('"meta"'))
      assert.is_truthy(masked:find('"instance"'))
    end)
    
    it("should handle empty input", function()
      local masked, count = masker.mask_data("")
      assert.equals("", masked)
      assert.equals(0, count)
    end)
    
    it("should handle nil input", function()
      local masked, count = masker.mask_data(nil)
      assert.equals("", masked)
      assert.equals(0, count)
    end)
    
    it("should generate unique masks for different resources", function()
      local input = '{"ec2_1": "i-1234567890abcdef0", "ec2_2": "i-0987654321fedcba0"}'
      local masked, count = masker.mask_data(input)
      
      assert.is_truthy(masked:find("EC2_001"))
      assert.is_truthy(masked:find("EC2_002"))
      assert.equals(2, count)
    end)
  end)
  
  describe("unmask_data", function()
    it("should unmask single resource", function()
      local masked = '{"instance": "EC2_001"}'
      local mappings = {
        ["EC2_001"] = "i-1234567890abcdef0"
      }
      
      local unmasked = masker.unmask_data(masked, mappings)
      
      assert.is_truthy(unmasked:find("i%-1234567890abcdef0"))
      assert.is_falsy(unmasked:find("EC2_001"))
    end)
    
    it("should unmask multiple resources", function()
      local masked = '{"ec2": "EC2_001", "s3": "BUCKET_001", "ip": "PRIVATE_IP_001"}'
      local mappings = {
        ["EC2_001"] = "i-1234567890abcdef0",
        ["BUCKET_001"] = "my-bucket-name",
        ["PRIVATE_IP_001"] = "10.0.0.1"
      }
      
      local unmasked = masker.unmask_data(masked, mappings)
      
      assert.is_truthy(unmasked:find("i%-1234567890abcdef0"))
      assert.is_truthy(unmasked:find("my%-bucket%-name"))
      assert.is_truthy(unmasked:find("10%.0%.0%.1"))
    end)
    
    it("should handle missing mappings", function()
      local masked = '{"instance": "EC2_001"}'
      local mappings = {}  -- Empty mappings
      
      local unmasked = masker.unmask_data(masked, mappings)
      
      -- Should remain masked if mapping not found
      assert.is_truthy(unmasked:find("EC2_001"))
    end)
    
    it("should handle nil mappings", function()
      local masked = '{"instance": "EC2_001"}'
      
      local unmasked = masker.unmask_data(masked, nil)
      
      -- Should return original if no mappings
      assert.equals(masked, unmasked)
    end)
  end)
  
  describe("get_mapping_store", function()
    it("should return mapping store", function()
      -- Create some mappings
      masker.mask_data('{"instance": "i-1234567890abcdef0"}')
      
      local store = masker.get_mapping_store()
      
      assert.is_table(store)
      -- Should have at least one mapping
      local count = 0
      for _ in pairs(store) do
        count = count + 1
      end
      assert.is_truthy(count > 0)
    end)
  end)
  
  describe("clear_mapping_store", function()
    it("should clear all mappings", function()
      -- Create some mappings
      masker.mask_data('{"instance": "i-1234567890abcdef0"}')
      
      -- Clear store
      masker.clear_mapping_store()
      
      local store = masker.get_mapping_store()
      local count = 0
      for _ in pairs(store) do
        count = count + 1
      end
      assert.equals(0, count)
    end)
  end)
  
  describe("performance", function()
    it("should handle large payloads efficiently", function()
      -- Generate large payload with many resources
      local instances = {}
      for i = 1, 100 do
        table.insert(instances, string.format('"inst_%d": "i-%016x"', i, i))
      end
      local large_input = "{" .. table.concat(instances, ", ") .. "}"
      
      local start_time = os.clock()
      local masked, count = masker.mask_data(large_input)
      local end_time = os.clock()
      
      -- Should mask all 100 instances
      assert.equals(100, count)
      
      -- Should complete within reasonable time (< 100ms)
      assert.is_truthy((end_time - start_time) < 0.1)
    end)
  end)
  
  describe("edge cases", function()
    it("should handle special characters in data", function()
      local input = '{"data": "i-1234567890abcdef0\n\t\r"}'
      local masked, count = masker.mask_data(input)
      
      assert.is_truthy(masked:find("EC2_001"))
      assert.equals(1, count)
    end)
    
    it("should handle nested JSON structures", function()
      local input = [[{
        "level1": {
          "level2": {
            "instance": "i-1234567890abcdef0"
          }
        }
      }]]
      
      local masked, count = masker.mask_data(input)
      
      assert.is_truthy(masked:find("EC2_001"))
      assert.is_falsy(masked:find("i%-1234567890abcdef0"))
    end)
    
    it("should handle arrays", function()
      local input = '{"instances": ["i-1234567890abcdef0", "i-0987654321fedcba0"]}'
      local masked, count = masker.mask_data(input)
      
      assert.is_truthy(masked:find("EC2_001"))
      assert.is_truthy(masked:find("EC2_002"))
      assert.equals(2, count)
    end)
  end)
end)