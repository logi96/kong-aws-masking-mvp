-- Safe JSON encoding/decoding module
-- Handles errors gracefully for Kong plugin environment

local cjson = require "cjson.safe"

local _M = {}

-- Safe JSON encoding
function _M.encode(data)
  if not data then
    return nil
  end
  
  local encoded, err = cjson.encode(data)
  if not encoded then
    kong.log.warn("JSON encode error: ", err)
    return nil
  end
  
  return encoded
end

-- Safe JSON decoding
function _M.decode(json_str)
  if not json_str or json_str == "" then
    return nil
  end
  
  local decoded, err = cjson.decode(json_str)
  if not decoded then
    kong.log.warn("JSON decode error: ", err)
    return nil
  end
  
  return decoded
end

return _M