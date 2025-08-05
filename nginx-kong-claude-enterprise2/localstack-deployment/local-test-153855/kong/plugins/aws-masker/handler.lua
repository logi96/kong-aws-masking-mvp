local AwsMaskerHandler = {}
AwsMaskerHandler.VERSION = "1.0.0" 
AwsMaskerHandler.PRIORITY = 700

function AwsMaskerHandler:access(conf)
  -- Phase 1 핵심: API 키 Plugin Config 우선 접근
  local api_key_from_config = conf and conf.anthropic_api_key
  kong.log.info("Plugin config API key available: ", api_key_from_config and "YES" or "NO")
  
  if api_key_from_config and api_key_from_config ~= "" then
    kong.service.request.set_header("x-api-key", api_key_from_config)
    kong.service.request.set_header("anthropic-version", "2023-06-01")
    kong.log.info("API key set from plugin config")
  end
end

return AwsMaskerHandler
