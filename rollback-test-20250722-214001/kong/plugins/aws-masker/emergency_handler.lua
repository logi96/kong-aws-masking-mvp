-- emergency_handler.lua
-- 보안 최우선: 위험 감지 시 즉시 대응
-- 이 모듈은 Kong AWS Masking 시스템의 최후 방어선입니다

local kong = kong
local ngx = ngx

local emergency_handler = {
    VERSION = "1.0.0",
    -- 현재 모드 (NORMAL, DEGRADED, BYPASS, BLOCK_ALL)
    current_mode = "NORMAL",
    -- 실패 카운터
    failure_count = 0,
    -- 마지막 실패 시간
    last_failure_time = 0,
    -- 설정
    config = {
        failure_threshold = 5,        -- 5회 실패 시 모드 전환
        time_window = 60,            -- 60초 내 실패 카운트
        recovery_time = 300,         -- 5분 후 정상 모드 복귀 시도
        critical_patterns = {        -- 절대 놓치면 안 되는 패턴
            "aws_account_id",
            "iam_access_key",
            "iam_secret_key"
        }
    }
}

-- 로그 함수 (보안 감사용)
local function security_log(level, message, context)
    local log_entry = {
        timestamp = ngx.now(),
        level = level,
        message = message,
        mode = emergency_handler.current_mode,
        context = context or {}
    }
    
    -- 보안 감사 로그에 기록
    kong.log[level](message, log_entry)
    
    -- 파일에도 기록 (감사 추적용)
    local audit_file = io.open("/secure/logs/emergency-handler.log", "a")
    if audit_file then
        audit_file:write(string.format("[%s] %s: %s\n", 
            os.date("%Y-%m-%d %H:%M:%S"), 
            level:upper(), 
            kong.log.serialize(log_entry)))
        audit_file:close()
    end
end

-- 모드 전환 함수
local function switch_mode(new_mode, reason)
    local old_mode = emergency_handler.current_mode
    emergency_handler.current_mode = new_mode
    
    security_log("warn", string.format("Mode switched: %s -> %s", old_mode, new_mode), {
        reason = reason,
        failure_count = emergency_handler.failure_count
    })
    
    -- 알림 발송 (실제 환경에서는 실제 알림 시스템 연동)
    if new_mode == "BLOCK_ALL" then
        security_log("crit", "CRITICAL: System entered BLOCK_ALL mode!", {
            reason = reason,
            action = "All requests will be blocked"
        })
    end
end

-- 실패 기록 함수
function emergency_handler:record_failure(error_type, details)
    local current_time = ngx.now()
    
    -- 시간 윈도우 확인
    if current_time - self.last_failure_time > self.config.time_window then
        self.failure_count = 1
    else
        self.failure_count = self.failure_count + 1
    end
    
    self.last_failure_time = current_time
    
    security_log("error", "Failure recorded", {
        error_type = error_type,
        details = details,
        failure_count = self.failure_count
    })
    
    -- 임계값 확인
    if self.failure_count >= self.config.failure_threshold then
        if self.current_mode == "NORMAL" then
            switch_mode("DEGRADED", "Failure threshold exceeded")
        elseif self.current_mode == "DEGRADED" then
            switch_mode("BYPASS", "Continued failures in degraded mode")
        elseif self.current_mode == "BYPASS" then
            switch_mode("BLOCK_ALL", "Critical failure - security risk")
        end
    end
end

-- 성공 기록 함수 (복구용)
function emergency_handler:record_success()
    if self.current_mode ~= "NORMAL" and 
       ngx.now() - self.last_failure_time > self.config.recovery_time then
        self.failure_count = 0
        switch_mode("NORMAL", "Recovery time elapsed with success")
    end
end

-- 1. 완전 차단 모드 (최고 위험)
function emergency_handler.BLOCK_ALL(reason)
    security_log("crit", "BLOCK_ALL mode activated", {reason = reason})
    
    return kong.response.exit(503, {
        error = "Service temporarily unavailable",
        message = "System is under security maintenance",
        request_id = kong.request.get_header("X-Request-ID") or "unknown"
    }, {
        ["X-Security-Mode"] = "BLOCK_ALL",
        ["Retry-After"] = "300"
    })
end

-- 2. 기본 마스킹만 수행 (DEGRADED 모드)
function emergency_handler.BASIC_ONLY(text)
    security_log("warn", "Operating in BASIC_ONLY mode", {
        text_length = #text
    })
    
    -- 가장 중요한 패턴만 처리
    local masked_text = text
    local masked_count = 0
    
    -- AWS Account ID (12자리 숫자)
    masked_text = masked_text:gsub("(%d%d%d%d%d%d%d%d%d%d%d%d)", function(match)
        masked_count = masked_count + 1
        return "ACCOUNT_MASKED"
    end)
    
    -- IAM Access Key (AKIA로 시작)
    masked_text = masked_text:gsub("(AKIA[A-Z0-9]{16})", function(match)
        masked_count = masked_count + 1
        return "ACCESS_KEY_MASKED"
    end)
    
    -- Private IP (10.x.x.x)
    masked_text = masked_text:gsub("(10%.%d+%.%d+%.%d+)", function(match)
        masked_count = masked_count + 1
        return "PRIVATE_IP_MASKED"
    end)
    
    -- EC2 Instance ID
    masked_text = masked_text:gsub("(i%-[0-9a-f]{8,17})", function(match)
        masked_count = masked_count + 1
        return "EC2_MASKED"
    end)
    
    security_log("info", "Basic masking completed", {
        patterns_masked = masked_count
    })
    
    return masked_text, {
        mode = "BASIC_ONLY",
        masked_count = masked_count
    }
end

-- 3. 우회 모드 (BYPASS - 마스킹 없이 통과)
function emergency_handler.BYPASS(reason)
    security_log("warn", "BYPASS mode - no masking applied", {
        reason = reason
    })
    
    -- 헤더에 경고 추가
    kong.response.set_header("X-Security-Warning", "Masking bypassed")
    
    return nil -- 마스킹 하지 않음
end

-- 4. 수동 검토 큐 (의심스러운 요청)
function emergency_handler.MANUAL_REVIEW(text, context)
    local review_id = ngx.md5(text .. ngx.now())
    
    security_log("warn", "Request queued for manual review", {
        review_id = review_id,
        context = context
    })
    
    -- 검토 큐에 저장 (실제로는 Redis 등 사용)
    local review_file = io.open("/secure/logs/manual-review-queue.log", "a")
    if review_file then
        review_file:write(string.format("%s|%s|%s|%s\n",
            os.date("%Y-%m-%d %H:%M:%S"),
            review_id,
            kong.request.get_header("X-Request-ID") or "unknown",
            ngx.encode_base64(text)))
        review_file:close()
    end
    
    return kong.response.exit(202, {
        message = "Request accepted for processing",
        review_id = review_id,
        estimated_time = "5-10 minutes"
    })
end

-- 현재 모드에 따른 처리
function emergency_handler:handle(text, context)
    local mode = self.current_mode
    
    security_log("debug", "Handling request", {
        mode = mode,
        text_length = text and #text or 0
    })
    
    if mode == "BLOCK_ALL" then
        return self.BLOCK_ALL("System in emergency mode")
    elseif mode == "DEGRADED" then
        return self.BASIC_ONLY(text)
    elseif mode == "BYPASS" then
        return self.BYPASS("Performance protection mode")
    else
        -- NORMAL 모드 - 정상 처리
        return nil
    end
end

-- 상태 확인 함수
function emergency_handler:get_status()
    return {
        mode = self.current_mode,
        failure_count = self.failure_count,
        last_failure = self.last_failure_time,
        uptime = ngx.now(),
        config = self.config
    }
end

-- 수동 모드 전환 (관리자용)
function emergency_handler:set_mode(mode, reason)
    local valid_modes = {NORMAL = true, DEGRADED = true, BYPASS = true, BLOCK_ALL = true}
    
    if not valid_modes[mode] then
        return false, "Invalid mode"
    end
    
    switch_mode(mode, "Manual override: " .. (reason or "No reason provided"))
    return true
end

-- 초기화 함수
function emergency_handler:init()
    security_log("info", "Emergency handler initialized", {
        version = self.VERSION,
        mode = self.current_mode
    })
end

return emergency_handler