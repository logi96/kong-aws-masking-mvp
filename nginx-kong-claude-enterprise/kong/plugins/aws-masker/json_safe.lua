-- json_safe.lua
-- Phase 4-1 Fix: cjson 호환성 문제 해결
-- Kong/OpenResty 환경에 안전한 JSON 처리 모듈

local json_safe = {}

-- JSON 라이브러리 로드 시도
local json_lib = nil
local json_decode = nil
local json_encode = nil

-- 1. cjson 시도
local ok, cjson = pcall(require, "cjson")
if ok then
    json_lib = cjson
    json_decode = cjson.decode
    json_encode = cjson.encode
else
    -- 2. cjson.safe 시도
    ok, cjson = pcall(require, "cjson.safe")
    if ok then
        json_lib = cjson
        json_decode = cjson.decode
        json_encode = cjson.encode
    else
        -- 3. Kong의 내장 JSON 시도
        ok, cjson = pcall(require, "kong.tools.cjson")
        if ok then
            json_lib = cjson
            json_decode = cjson.decode
            json_encode = cjson.encode
        end
    end
end

-- 안전한 디코드 함수
function json_safe.decode(str)
    if not str or type(str) ~= "string" then
        return nil, "Invalid input: expected string"
    end
    
    if not json_decode then
        -- JSON 라이브러리가 없으면 오류 반환 (보안: 원본 반환 금지)
        kong.log.err("[json_safe] CRITICAL: No JSON library available")
        return nil, "No JSON decoder available"
    end
    
    -- 안전한 디코드 시도
    local ok, result = pcall(json_decode, str)
    if ok then
        return result, nil
    else
        return nil, "JSON decode error: " .. tostring(result)
    end
end

-- 안전한 인코드 함수
function json_safe.encode(obj)
    if obj == nil then
        return "null", nil
    end
    
    if not json_encode then
        -- JSON 라이브러리가 없으면 기본 직렬화
        kong.log.warn("[json_safe] No JSON library available, using fallback")
        if type(obj) == "string" then
            return '"' .. obj:gsub('"', '\\"') .. '"', nil
        elseif type(obj) == "number" or type(obj) == "boolean" then
            return tostring(obj), nil
        else
            return tostring(obj), nil  -- 테이블은 문자열로
        end
    end
    
    -- 안전한 인코드 시도
    local ok, result = pcall(json_encode, obj)
    if ok then
        return result, nil
    else
        return nil, "JSON encode error: " .. tostring(result)
    end
end

-- JSON 라이브러리 상태 확인
function json_safe.is_available()
    return json_lib ~= nil
end

-- 사용 중인 라이브러리 이름 반환
function json_safe.get_library_name()
    if not json_lib then
        return "none (fallback mode)"
    end
    
    -- 라이브러리 타입 확인
    if json_lib._NAME then
        return json_lib._NAME
    elseif json_lib.version then
        return "cjson " .. json_lib.version
    else
        return "unknown json library"
    end
end

-- 테스트 함수
function json_safe.test()
    local test_data = {
        string = "test",
        number = 123,
        boolean = true,
        array = {1, 2, 3},
        object = {key = "value"}
    }
    
    -- 인코드 테스트
    local encoded, err = json_safe.encode(test_data)
    if err then
        return false, "Encode test failed: " .. err
    end
    
    -- 디코드 테스트
    local decoded, err = json_safe.decode(encoded)
    if err then
        return false, "Decode test failed: " .. err
    end
    
    -- 기본 검증
    if decoded.string ~= test_data.string or decoded.number ~= test_data.number then
        return false, "Data integrity test failed"
    end
    
    return true, "JSON safe module working correctly with: " .. json_safe.get_library_name()
end

return json_safe