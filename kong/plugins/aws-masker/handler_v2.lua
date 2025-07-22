-- handler_v2.lua
-- 보안 최우선: Kong AWS Masking 플러그인 핵심 핸들러
-- Circuit Breaker와 Emergency Handler로 보호되는 안전한 마스킹 시스템

local BasePlugin = require "kong.plugins.base_plugin"
local text_masker = require "kong.plugins.aws-masker.text_masker_v2"
local circuit_breaker = require "kong.plugins.aws-masker.circuit_breaker"
local emergency_handler = require "kong.plugins.aws-masker.emergency_handler"

local AWSMaskerHandler = BasePlugin:extend()

AWSMaskerHandler.VERSION = "2.0.0"
AWSMaskerHandler.PRIORITY = 1000  -- 높은 우선순위로 일찍 실행

function AWSMaskerHandler:new()
    AWSMaskerHandler.super.new(self, "aws-masker")
end

-- 플러그인 초기화
function AWSMaskerHandler:init_worker()
    AWSMaskerHandler.super.init_worker(self)
    
    -- 컴포넌트 초기화
    text_masker.init()
    circuit_breaker:init()
    emergency_handler:init()
    
    -- 주기적 정리 타이머 설정
    local ok, err = ngx.timer.every(300, function()  -- 5분마다
        text_masker.cleanup_old_mappings(100)
    end)
    
    if not ok then
        kong.log.error("Failed to create cleanup timer: " .. err)
    end
    
    kong.log.info("[AWS-MASKER] Plugin initialized", {
        version = self.VERSION,
        priority = self.PRIORITY
    })
end

-- Access 단계: 요청 버퍼링 활성화
function AWSMaskerHandler:access(conf)
    AWSMaskerHandler.super.access(self)
    
    -- 요청 본문 버퍼링 활성화
    kong.service.request.enable_buffering()
    
    -- 요청 ID 생성
    local request_id = kong.request.get_header("X-Request-ID") or 
                      "req-" .. ngx.now() .. "-" .. math.random(1000, 9999)
    kong.ctx.plugin.request_id = request_id
    kong.service.request.set_header("X-Request-ID", request_id)
end

-- Request 단계: 요청 마스킹
function AWSMaskerHandler:rewrite(conf)
    AWSMaskerHandler.super.rewrite(self)
    
    local ctx = kong.ctx.plugin
    
    -- Emergency Handler 상태 확인
    local emergency_result = emergency_handler:handle(nil, ctx)
    if emergency_result then
        return emergency_result  -- BLOCK_ALL 또는 다른 비상 모드
    end
    
    -- 요청 본문 가져오기
    local body = kong.request.get_raw_body()
    if not body or #body == 0 then
        return  -- 본문이 없으면 통과
    end
    
    -- Circuit Breaker로 마스킹 실행
    local masked_body, context, error_msg = circuit_breaker:call(function()
        return text_masker.mask_claude_request(body, conf)
    end)
    
    if not masked_body then
        -- 마스킹 실패 시 처리
        if error_msg == "CIRCUIT_OPEN" then
            kong.log.error("[AWS-MASKER] Circuit breaker is OPEN")
            -- Emergency handler로 폴백
            local basic_masked = emergency_handler.BASIC_ONLY(body)
            if basic_masked then
                kong.service.request.set_raw_body(basic_masked)
                ctx.basic_mode = true
            else
                -- 완전 차단
                return kong.response.exit(503, {
                    error = "Service temporarily unavailable",
                    message = "AWS masking service is experiencing issues",
                    request_id = ctx.request_id
                })
            end
        else
            -- 다른 에러
            emergency_handler:record_failure("masking_failed", error_msg)
            kong.log.error("[AWS-MASKER] Masking failed", {
                error = error_msg,
                request_id = ctx.request_id
            })
            
            -- 안전을 위해 요청 차단
            return kong.response.exit(500, {
                error = "Internal server error",
                message = "Failed to process request safely",
                request_id = ctx.request_id
            })
        end
    else
        -- 마스킹 성공
        kong.service.request.set_raw_body(masked_body)
        ctx.masking_context = context
        
        -- 보안 체크포인트
        local secure, security_err = text_masker.security_checkpoint(masked_body)
        if not secure then
            kong.log.crit("[AWS-MASKER] SECURITY CHECKPOINT FAILED", {
                error = security_err,
                request_id = ctx.request_id
            })
            
            -- 즉시 차단
            return kong.response.exit(500, {
                error = "Security validation failed",
                message = "Request contains unmasked sensitive data",
                request_id = ctx.request_id
            })
        end
        
        -- 성능 메트릭 기록
        if context.masked_count > 0 then
            kong.log.info("[AWS-MASKER] Request masked", {
                masked_count = context.masked_count,
                request_id = ctx.request_id,
                mode = ctx.basic_mode and "BASIC" or "FULL"
            })
        end
    end
end

-- Response 단계: 응답 언마스킹
function AWSMaskerHandler:body_filter(conf)
    AWSMaskerHandler.super.body_filter(self)
    
    local ctx = kong.ctx.plugin
    
    -- 마스킹하지 않은 요청은 스킵
    if not ctx.masking_context and not ctx.basic_mode then
        return
    end
    
    -- 응답 본문 수집
    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]
    
    ctx.response_chunks = ctx.response_chunks or {}
    if chunk then
        table.insert(ctx.response_chunks, chunk)
    end
    
    if eof then
        -- 전체 응답 조합
        local body = table.concat(ctx.response_chunks)
        if #body > 0 then
            -- Circuit Breaker로 언마스킹 실행
            local unmasked_body = circuit_breaker:call(function()
                return text_masker.unmask_claude_response(body, ctx.masking_context or {})
            end)
            
            if unmasked_body then
                ngx.arg[1] = unmasked_body
                
                kong.log.info("[AWS-MASKER] Response unmasked", {
                    request_id = ctx.request_id,
                    response_length = #unmasked_body
                })
            else
                -- 언마스킹 실패 시 원본 반환
                kong.log.error("[AWS-MASKER] Unmasking failed, returning original")
                ngx.arg[1] = body
            end
        end
        
        -- 컨텍스트 정리
        ctx.response_chunks = nil
        ctx.masking_context = nil
        ctx.basic_mode = nil
    else
        -- EOF가 아니면 빈 청크 전송 (버퍼링)
        ngx.arg[1] = nil
    end
end

-- Log 단계: 메트릭 및 감사 로깅
function AWSMaskerHandler:log(conf)
    AWSMaskerHandler.super.log(self)
    
    local ctx = kong.ctx.plugin
    
    -- Circuit Breaker 상태 로깅
    local cb_status = circuit_breaker:get_status()
    if cb_status.state ~= "CLOSED" then
        kong.log.warn("[AWS-MASKER] Circuit breaker status", cb_status)
    end
    
    -- Emergency Handler 상태 로깅
    local eh_status = emergency_handler:get_status()
    if eh_status.mode ~= "NORMAL" then
        kong.log.warn("[AWS-MASKER] Emergency handler status", eh_status)
    end
    
    -- 감사 로그
    if ctx.masking_context and ctx.masking_context.masked_count > 0 then
        kong.log.info("[AWS-MASKER] Request processed", {
            request_id = ctx.request_id,
            masked_count = ctx.masking_context.masked_count,
            latency = kong.ctx.shared.get_latency(),
            upstream_status = kong.response.get_status(),
            client_ip = kong.client.get_forwarded_ip()
        })
    end
end

return AWSMaskerHandler