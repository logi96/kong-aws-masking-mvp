--
-- Mock Kong Dependencies for Testing
-- Provides mock implementations of Kong modules for isolated testing
--

local mock_kong = {}

-- Mock Kong DB schema typedefs
mock_kong.typedefs = {
  no_consumer = {
    type = "foreign",
    reference = "consumers",
    default = ngx.null,
    eq = ngx.null
  },
  
  protocols = {
    type = "set",
    elements = {
      type = "string",
      one_of = { "grpc", "grpcs", "http", "https", "tcp", "tls", "udp" }
    },
    default = { "http", "https" }
  },
  
  protocols_http = {
    type = "set", 
    elements = {
      type = "string",
      one_of = { "http", "https" }
    },
    default = { "http", "https" }
  }
}

-- Mock Kong DB schema module
local mock_schema = {}
mock_schema.typedefs = mock_kong.typedefs

-- Set up package path mocking
if not package.loaded["kong.db.schema.typedefs"] then
  package.loaded["kong.db.schema.typedefs"] = mock_schema.typedefs
end

-- Mock Kong logging
mock_kong.log = {
  info = function(...) 
    if _G.test_config and _G.test_config.verbose then
      print("INFO:", ...) 
    end
  end,
  error = function(...) 
    if _G.test_config and _G.test_config.verbose then
      print("ERROR:", ...) 
    end
  end,
  warn = function(...) 
    if _G.test_config and _G.test_config.verbose then
      print("WARN:", ...) 
    end
  end,
  debug = function(...) 
    if _G.test_config and _G.test_config.verbose then
      print("DEBUG:", ...) 
    end
  end
}

-- Mock Kong request/response
mock_kong.request = {
  get_raw_body = function()
    return '{"test": "data"}'
  end,
  
  set_raw_body = function(body)
    -- Mock implementation
  end,
  
  get_headers = function()
    return {
      ["content-type"] = "application/json",
      ["user-agent"] = "test-client/1.0"
    }
  end
}

mock_kong.response = {
  get_raw_body = function()
    return '{"result": "success"}'
  end,
  
  set_raw_body = function(body)
    -- Mock implementation  
  end,
  
  get_headers = function()
    return {
      ["content-type"] = "application/json"
    }
  end
}

-- Mock Kong context
mock_kong.ctx = {
  shared = {}
}

-- Set global kong for tests
if not _G.kong then
  _G.kong = mock_kong
end

return mock_kong