-- Simple Logger Plugin for Kong
-- Logs request method, path, headers, and response body preview (first 200 chars)

local kong = kong
local ngx = ngx
local cjson = require "cjson.safe"

local SimpleLoggerHandler = {
    PRIORITY = 1,  -- 낮은 우선순위로 다른 플러그인 이후 실행
    VERSION = "1.0.0",
}

-- Helper function to safely extract headers
local function get_headers_safe(headers)
    local result = {}
    if headers then
        for name, value in pairs(headers) do
            -- 민감한 헤더 마스킹
            if name:lower() == "authorization" or name:lower() == "x-api-key" then
                result[name] = "***masked***"
            else
                result[name] = value
            end
        end
    end
    return result
end

-- Helper function to truncate response body
local function truncate_body(body, max_length)
    if not body then
        return nil
    end
    
    max_length = max_length or 200
    
    if #body <= max_length then
        return body
    end
    
    return body:sub(1, max_length) .. "... (truncated)"
end

function SimpleLoggerHandler:access(conf)
    -- Access phase: 요청 정보 수집
    local request_data = {
        request_id = kong.request.get_id(),
        method = kong.request.get_method(),
        path = kong.request.get_path(),
        query = kong.request.get_query(),
        headers = get_headers_safe(kong.request.get_headers()),
        client_ip = kong.client.get_forwarded_ip(),
        timestamp = ngx.now(),
    }
    
    -- Context에 저장하여 나중에 사용
    kong.ctx.plugin.request_data = request_data
    
    -- 요청 본문 로깅 (필요시)
    if conf.log_request_body and kong.request.get_method() == "POST" then
        local body = kong.request.get_raw_body()
        if body then
            request_data.body_preview = truncate_body(body, conf.body_preview_size or 200)
        end
    end
    
    kong.log.info("=== REQUEST START ===")
    kong.log.info("Request ID: ", request_data.request_id)
    kong.log.info("Method: ", request_data.method)
    kong.log.info("Path: ", request_data.path)
    kong.log.info("Client IP: ", request_data.client_ip)
    
    if conf.log_headers then
        kong.log.info("Headers: ", cjson.encode(request_data.headers))
    end
end

function SimpleLoggerHandler:header_filter(conf)
    -- Header filter phase: 응답 헤더 수집
    local response_headers = get_headers_safe(kong.response.get_headers())
    local status_code = kong.response.get_status()
    
    kong.ctx.plugin.response_headers = response_headers
    kong.ctx.plugin.status_code = status_code
    
    kong.log.info("Response Status: ", status_code)
    
    if conf.log_headers then
        kong.log.info("Response Headers: ", cjson.encode(response_headers))
    end
end

function SimpleLoggerHandler:body_filter(conf)
    -- Body filter phase: 응답 본문 수집
    -- Kong은 응답을 청크로 처리하므로 모든 청크를 수집
    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]
    
    kong.ctx.plugin.response_chunks = kong.ctx.plugin.response_chunks or {}
    
    if chunk then
        table.insert(kong.ctx.plugin.response_chunks, chunk)
    end
    
    if eof then
        -- 모든 청크를 받았으므로 합치기
        local full_body = table.concat(kong.ctx.plugin.response_chunks)
        kong.ctx.plugin.response_body = full_body
    end
end

function SimpleLoggerHandler:log(conf)
    -- Log phase: 모든 정보를 종합하여 로깅
    local request_data = kong.ctx.plugin.request_data
    local response_body = kong.ctx.plugin.response_body
    local status_code = kong.ctx.plugin.status_code
    
    if not request_data then
        kong.log.err("No request data found in context")
        return
    end
    
    -- 응답 시간 계산
    local latency = (ngx.now() - request_data.timestamp) * 1000  -- milliseconds
    
    -- 로그 엔트리 생성
    local log_entry = {
        request_id = request_data.request_id,
        timestamp = ngx.now(),
        request = {
            method = request_data.method,
            path = request_data.path,
            headers = request_data.headers,
            client_ip = request_data.client_ip,
        },
        response = {
            status = status_code,
            headers = kong.ctx.plugin.response_headers,
            body_preview = truncate_body(response_body, conf.body_preview_size or 200),
            latency_ms = latency,
        },
        upstream_latency = kong.response.get_header("X-Kong-Upstream-Latency"),
        proxy_latency = kong.response.get_header("X-Kong-Proxy-Latency"),
    }
    
    -- JSON으로 로깅
    local log_json = cjson.encode(log_entry)
    kong.log.info("=== REQUEST COMPLETE ===")
    kong.log.info(log_json)
    
    -- 파일로 로깅 (옵션)
    if conf.log_file then
        local file = io.open(conf.log_file, "a")
        if file then
            file:write(log_json .. "\n")
            file:close()
        else
            kong.log.err("Failed to open log file: ", conf.log_file)
        end
    end
    
    -- 에러가 있었다면 추가 로깅
    if status_code >= 400 then
        kong.log.warn("Request resulted in error status: ", status_code)
        if response_body then
            kong.log.warn("Error response preview: ", truncate_body(response_body, 500))
        end
    end
end

return SimpleLoggerHandler