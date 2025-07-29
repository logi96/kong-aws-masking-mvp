--
-- Unit tests for AWS Masker Handler
--

describe("AWS Masker Handler", function()
  local handler
  local masker_ngx_re
  local json_safe
  local monitoring
  local event_publisher
  
  setup(function()
    -- Mock dependencies
    _G.kong = {
      log = {
        err = function() end,
        warn = function() end,
        info = function() end,
        debug = function() end
      },
      response = {
        set_header = function() end,
        get_header = function() end
      },
      service = {
        request = {
          set_header = function() end,
          get_header = function() end,
          get_body = function() return nil end,
          set_body = function() end
        },
        response = {
          get_header = function() end,
          get_body = function() return nil end,
          set_body = function() end
        }
      }
    }
    
    -- Mock ngx
    _G.ngx = {
      ctx = {},
      timer = {
        at = function() return true end
      },
      var = {},
      shared = {
        kong = {
          get = function() return nil end,
          set = function() return true end
        }
      }
    }
    
    -- Mock required modules
    masker_ngx_re = {
      mask_data = function(data) 
        return data:gsub("i%-[%w]+", "EC2_001"), 1
      end,
      unmask_data = function(data, mappings)
        if mappings and mappings["EC2_001"] then
          return data:gsub("EC2_001", mappings["EC2_001"])
        end
        return data
      end,
      get_mapping_store = function()
        return { ["EC2_001"] = "i-1234567890abcdef0" }
      end
    }
    
    json_safe = {
      decode = function(str) 
        if str == '{"id":"i-1234567890abcdef0"}' then
          return {id = "i-1234567890abcdef0"}
        end
        return {}
      end,
      encode = function(tbl)
        if tbl.id then
          return '{"id":"' .. tbl.id .. '"}'
        end
        return '{}'
      end
    }
    
    monitoring = {
      record_masking = function() end,
      record_unmasking = function() end
    }
    
    event_publisher = {
      publish_masking_event = function() end
    }
    
    -- Override require
    local old_require = require
    _G.require = function(module)
      if module == "kong.plugins.aws-masker.masker_ngx_re" then
        return masker_ngx_re
      elseif module == "kong.plugins.aws-masker.json_safe" then
        return json_safe
      elseif module == "kong.plugins.aws-masker.monitoring" then
        return monitoring
      elseif module == "kong.plugins.aws-masker.event_publisher" then
        return event_publisher
      else
        return old_require(module)
      end
    end
    
    -- Load handler
    handler = require("kong.plugins.aws-masker.handler")
  end)
  
  describe("access phase", function()
    it("should mask request body with AWS resources", function()
      local conf = {
        mask_ec2_instances = true,
        log_masked_requests = false
      }
      
      -- Mock request body
      kong.service.request.get_body = function()
        return '{"id":"i-1234567890abcdef0"}'
      end
      
      local body_set
      kong.service.request.set_body = function(body)
        body_set = body
      end
      
      handler:access(conf)
      
      assert.equals('{"id":"EC2_001"}', body_set)
    end)
    
    it("should handle empty request body", function()
      local conf = {}
      
      kong.service.request.get_body = function()
        return nil
      end
      
      -- Should not throw error
      assert.has_no.errors(function()
        handler:access(conf)
      end)
    end)
    
    it("should handle JSON decode errors", function()
      local conf = {}
      
      kong.service.request.get_body = function()
        return "invalid json"
      end
      
      json_safe.decode = function()
        error("Invalid JSON")
      end
      
      -- Should handle error gracefully
      assert.has_no.errors(function()
        handler:access(conf)
      end)
    end)
  end)
  
  describe("response phase", function()
    it("should unmask response body", function()
      local conf = {
        preserve_structure = true
      }
      
      -- Set mapping in context
      ngx.ctx.masked_mappings = {
        ["EC2_001"] = "i-1234567890abcdef0"
      }
      
      kong.service.response.get_body = function()
        return '{"resource":"EC2_001"}'
      end
      
      local body_set
      kong.service.response.set_body = function(body)
        body_set = body
      end
      
      handler:response(conf)
      
      assert.equals('{"resource":"i-1234567890abcdef0"}', body_set)
    end)
    
    it("should handle missing mappings", function()
      local conf = {}
      
      ngx.ctx.masked_mappings = nil
      
      kong.service.response.get_body = function()
        return '{"resource":"EC2_001"}'
      end
      
      local body_set
      kong.service.response.set_body = function(body)
        body_set = body
      end
      
      handler:response(conf)
      
      -- Should not modify if no mappings
      assert.equals('{"resource":"EC2_001"}', body_set)
    end)
    
    it("should handle response errors gracefully", function()
      local conf = {}
      
      kong.service.response.get_body = function()
        error("Failed to get body")
      end
      
      -- Should not throw error
      assert.has_no.errors(function()
        handler:response(conf)
      end)
    end)
  end)
  
  describe("health check", function()
    it("should return healthy status", function()
      local health = handler:health_check()
      
      assert.equals("healthy", health.status)
      assert.equals("1.0.0", health.version)
      assert.is_true(health.features.masking)
      assert.is_true(health.features.unmasking)
    end)
  end)
end)