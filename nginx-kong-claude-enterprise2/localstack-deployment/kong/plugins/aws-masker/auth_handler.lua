-- auth_handler.lua
-- Phase 4-1 Fix: API 인증 문제 해결
-- 보안 최우선: API 키 안전한 전달 보장

local auth_handler = {}

-- API 키 헤더 이름들
local API_KEY_HEADERS = {
    "X-API-Key",
    "Authorization",
    "Anthropic-Api-Key",
    "x-api-key",
    "authorization"
}

-- 민감한 헤더 목록 (로깅 시 마스킹)
local SENSITIVE_HEADERS = {
    ["x-api-key"] = true,
    ["authorization"] = true,
    ["anthropic-api-key"] = true,
    ["x-auth-token"] = true,
    ["api-key"] = true
}

-- API 키 추출 함수
function auth_handler.extract_api_key(headers)
    if not headers then
        return nil, "No headers provided"
    end
    
    -- Kong은 헤더를 소문자로 변환하고 테이블 배열로 저장할 수 있음
    -- 헤더 검색을 더 유연하게 처리
    local function get_header_value(headers, name)
        -- 직접 접근 시도
        local value = headers[name] or headers[name:lower()]
        if value then
            -- 배열인 경우 첫 번째 값 사용
            if type(value) == "table" then
                value = value[1]
            end
            return value
        end
        
        -- 대소문자 무시하고 검색
        for k, v in pairs(headers) do
            if k:lower() == name:lower() then
                if type(v) == "table" then
                    return v[1]
                end
                return v
            end
        end
        
        return nil
    end
    
    -- 다양한 헤더에서 API 키 찾기
    for _, header_name in ipairs(API_KEY_HEADERS) do
        local value = get_header_value(headers, header_name)
        if value then
            -- Bearer 토큰 처리
            if header_name:lower() == "authorization" and type(value) == "string" then
                if value:sub(1, 7):lower() == "bearer " then
                    value = value:sub(8)
                end
            end
            
            -- 보안: API 키 정보를 로그에 노출하지 않음
            return value, nil
        end
    end
    
    return nil, "No API key found in headers"
end

-- API 키 전달 설정
function auth_handler.forward_api_key(api_key, target_header)
    if not api_key then
        kong.log.err("[auth_handler] No API key to forward")
        return false, "No API key provided"
    end
    
    target_header = target_header or "X-API-Key"
    
    -- 보안 검증: API 키 형식 확인
    if type(api_key) ~= "string" or #api_key < 10 then
        kong.log.err("[auth_handler] Invalid API key format")
        return false, "Invalid API key format"
    end
    
    -- Kong 서비스 요청 헤더 설정
    kong.service.request.set_header(target_header, api_key)
    
    -- Anthropic 특별 처리
    if target_header == "X-API-Key" or target_header == "Anthropic-Api-Key" then
        -- Anthropic은 x-api-key 헤더 사용
        kong.service.request.set_header("x-api-key", api_key)
        kong.service.request.set_header("anthropic-version", "2023-06-01")
    end
    
    -- API 키 전달 완료
    return true, nil
end

-- 헤더 로깅 (민감 정보 마스킹)
function auth_handler.log_headers(headers, prefix)
    if not headers then return end
    
    prefix = prefix or "[auth_handler]"
    local log_entries = {}
    
    for name, value in pairs(headers) do
        local lower_name = name:lower()
        if SENSITIVE_HEADERS[lower_name] then
            -- 민감한 헤더는 마스킹
            local masked_value = "***" .. string.sub(tostring(value), -4) -- 마지막 4자만 표시
            table.insert(log_entries, name .. ": " .. masked_value)
        else
            table.insert(log_entries, name .. ": " .. tostring(value))
        end
    end
    
    if #log_entries > 0 then
        kong.log.debug(prefix .. " Headers: " .. table.concat(log_entries, ", "))
    end
end

-- 환경 변수에서 API 키 가져오기
function auth_handler.get_api_key_from_env()
    -- Docker 환경에서 환경 변수 읽기
    kong.log.info("[auth_handler] Checking environment variable ANTHROPIC_API_KEY...")
    local env_api_key = os.getenv("ANTHROPIC_API_KEY")
    if env_api_key then
        -- 보안: API 키 길이 정보 노출하지 않음
        if #env_api_key > 0 then
            kong.log.info("[auth_handler] API key loaded from environment variable")
            return env_api_key
        else
            kong.log.warn("[auth_handler] Environment variable is empty")
        end
    else
        kong.log.warn("[auth_handler] Environment variable ANTHROPIC_API_KEY not found")
    end
    
    -- Kong 설정에서 읽기 시도
    local kong_config = kong and kong.configuration
    if kong_config and kong_config.anthropic_api_key then
        kong.log.info("[auth_handler] API key loaded from Kong configuration")
        return kong_config.anthropic_api_key
    end
    
    return nil
end

-- API 인증 처리 메인 함수
function auth_handler.handle_authentication(plugin_conf)
    -- 1. 요청 헤더에서 API 키 추출
    local headers = kong.request.get_headers()
    
    -- 보안: 헤더 정보 로깅 제거
    
    if headers then
        local header_count = 0
        for k, v in pairs(headers) do
            header_count = header_count + 1
            -- 헤더 값이 테이블인 경우 처리
            local value_str = type(v) == "table" and table.concat(v, ", ") or tostring(v)
            -- API 키는 마스킹
            if k:lower():find("api") or k:lower():find("key") or k:lower():find("auth") then
                value_str = "***" .. value_str:sub(-4)
            end
            -- 보안: 헤더 정보를 로그에 출력하지 않음
        end
        -- 헤더 카운트 완료
    else
        kong.log.warn("[auth_handler] Headers is nil!")
    end
    
    auth_handler.log_headers(headers, "[auth_handler] Request")
    
    local api_key, err = auth_handler.extract_api_key(headers)
    
    -- 2. 요청에 API 키가 없으면 플러그인 설정에서 가져오기
    if not api_key then
        kong.log.warn("[auth_handler] " .. (err or "No API key in request"))
        
        -- 플러그인 설정에서 API 키 확인
        if plugin_conf and plugin_conf.anthropic_api_key then
            kong.log.info("[auth_handler] Using API key from plugin configuration")
            api_key = plugin_conf.anthropic_api_key
        else
            kong.log.info("[auth_handler] Attempting to load API key from environment...")
            api_key = auth_handler.get_api_key_from_env()
        end
        
        if not api_key then
            kong.log.err("[auth_handler] No API key available from any source")
            -- 보안: API 키가 없으면 실패
            return false, "API key not found"
        else
            kong.log.info("[auth_handler] Successfully loaded API key")
        end
    end
    
    -- 3. API 키 전달
    local success, forward_err = auth_handler.forward_api_key(api_key)
    if not success then
        kong.log.err("[auth_handler] Failed to forward API key: " .. (forward_err or "unknown error"))
        return false, forward_err
    end
    
    -- 4. 추가 헤더 설정 (Anthropic 요구사항)
    kong.service.request.set_header("Content-Type", "application/json")
    kong.service.request.set_header("Accept", "application/json")
    
    return true, nil
end

-- 응답 인증 오류 처리
function auth_handler.check_auth_response(status_code, body)
    if status_code == 401 then
        kong.log.err("[auth_handler] Authentication failed (401)")
        
        -- 응답 본문 분석
        if body then
            local error_msg = body:match('"error":%s*"([^"]+)"') or 
                            body:match('"message":%s*"([^"]+)"') or
                            "Unknown authentication error"
            kong.log.err("[auth_handler] Auth error: " .. error_msg)
        end
        
        return false, "Authentication failed"
    elseif status_code == 403 then
        kong.log.err("[auth_handler] Access forbidden (403)")
        return false, "Access forbidden"
    end
    
    return true, nil
end

-- 보안 검증 함수
function auth_handler.validate_security()
    -- API 키 존재 확인
    local api_key = auth_handler.get_api_key_from_env()
    if not api_key then
        return false, "No API key configured"
    end
    
    -- API 키 형식 검증
    if not api_key:match("^sk%-ant%-api%d+%-") then
        kong.log.warn("[auth_handler] API key format validation failed")
        -- 형식이 다를 수 있으므로 경고만
    end
    
    return true, "Security validation passed"
end

return auth_handler