-- circuit_breaker.lua
-- 보안 최우선: 시스템 장애 시 안전한 차단으로 데이터 노출 방지
-- Circuit Breaker 패턴으로 연쇄 장애 방지 및 빠른 복구

local circuit_breaker = {
    VERSION = "1.0.0",
    -- 상태: CLOSED (정상), OPEN (차단), HALF_OPEN (복구 시도)
    state = "CLOSED",
    
    -- 실패/성공 카운터
    failure_count = 0,
    success_count = 0,
    consecutive_successes = 0,
    
    -- 시간 추적
    last_failure_time = 0,
    last_state_change = 0,
    circuit_opened_at = 0,
    
    -- 설정
    config = {
        failure_threshold = 5,        -- 5회 실패 시 OPEN
        success_threshold = 3,        -- HALF_OPEN에서 3회 연속 성공 시 CLOSED
        timeout = 60,                 -- OPEN 상태 유지 시간 (초)
        half_open_max_requests = 3,   -- HALF_OPEN에서 최대 테스트 요청 수
        error_rate_threshold = 0.5,   -- 50% 에러율 시 OPEN
        window_size = 10              -- 에러율 계산 윈도우
    },
    
    -- 통계
    stats = {
        total_requests = 0,
        total_failures = 0,
        total_successes = 0,
        state_changes = 0
    },
    
    -- 최근 결과 추적 (에러율 계산용)
    recent_results = {}
}

-- 로깅 함수
local function log_state_change(from_state, to_state, reason)
    kong.log.warn("[CIRCUIT-BREAKER] State changed: " .. from_state .. " -> " .. to_state, {
        reason = reason,
        failure_count = circuit_breaker.failure_count,
        success_count = circuit_breaker.success_count,
        timestamp = ngx.now()
    })
    
    circuit_breaker.stats.state_changes = circuit_breaker.stats.state_changes + 1
    circuit_breaker.last_state_change = ngx.now()
end

-- 상태 전환 함수
local function change_state(new_state, reason)
    local old_state = circuit_breaker.state
    circuit_breaker.state = new_state
    
    if new_state == "OPEN" then
        circuit_breaker.circuit_opened_at = ngx.now()
        circuit_breaker.consecutive_successes = 0
    elseif new_state == "CLOSED" then
        circuit_breaker.failure_count = 0
        circuit_breaker.success_count = 0
        circuit_breaker.recent_results = {}
    elseif new_state == "HALF_OPEN" then
        circuit_breaker.consecutive_successes = 0
        circuit_breaker.half_open_requests = 0
    end
    
    log_state_change(old_state, new_state, reason)
end

-- 에러율 계산
local function calculate_error_rate()
    local window = circuit_breaker.config.window_size
    if #circuit_breaker.recent_results < window then
        return 0  -- 충분한 데이터 없음
    end
    
    local failures = 0
    local start_idx = math.max(1, #circuit_breaker.recent_results - window + 1)
    
    for i = start_idx, #circuit_breaker.recent_results do
        if not circuit_breaker.recent_results[i] then
            failures = failures + 1
        end
    end
    
    return failures / window
end

-- 결과 기록
local function record_result(success)
    table.insert(circuit_breaker.recent_results, success)
    
    -- 윈도우 크기 제한
    if #circuit_breaker.recent_results > circuit_breaker.config.window_size * 2 then
        -- 오래된 결과 제거
        local new_results = {}
        local start_idx = #circuit_breaker.recent_results - circuit_breaker.config.window_size + 1
        for i = start_idx, #circuit_breaker.recent_results do
            table.insert(new_results, circuit_breaker.recent_results[i])
        end
        circuit_breaker.recent_results = new_results
    end
end

-- 성공 기록
function circuit_breaker:record_success()
    self.stats.total_requests = self.stats.total_requests + 1
    self.stats.total_successes = self.stats.total_successes + 1
    self.success_count = self.success_count + 1
    record_result(true)
    
    if self.state == "HALF_OPEN" then
        self.consecutive_successes = self.consecutive_successes + 1
        
        -- 연속 성공으로 회로 닫기
        if self.consecutive_successes >= self.config.success_threshold then
            change_state("CLOSED", "Consecutive successes in HALF_OPEN")
        end
    elseif self.state == "CLOSED" then
        -- 실패 카운터 감소 (점진적 복구)
        if self.failure_count > 0 then
            self.failure_count = self.failure_count - 1
        end
    end
end

-- 실패 기록
function circuit_breaker:record_failure(error_type, details)
    self.stats.total_requests = self.stats.total_requests + 1
    self.stats.total_failures = self.stats.total_failures + 1
    self.failure_count = self.failure_count + 1
    self.last_failure_time = ngx.now()
    record_result(false)
    
    kong.log.error("[CIRCUIT-BREAKER] Failure recorded", {
        error_type = error_type,
        details = details,
        failure_count = self.failure_count,
        state = self.state
    })
    
    if self.state == "CLOSED" then
        -- 실패 임계값 확인
        if self.failure_count >= self.config.failure_threshold then
            change_state("OPEN", "Failure threshold exceeded")
        else
            -- 에러율 확인
            local error_rate = calculate_error_rate()
            if error_rate >= self.config.error_rate_threshold then
                change_state("OPEN", "Error rate threshold exceeded: " .. error_rate)
            end
        end
    elseif self.state == "HALF_OPEN" then
        -- HALF_OPEN에서 실패 시 즉시 OPEN
        change_state("OPEN", "Failure in HALF_OPEN state")
    end
end

-- 요청 허용 여부 확인
function circuit_breaker:should_allow_request()
    if self.state == "CLOSED" then
        return true
    elseif self.state == "OPEN" then
        -- 타임아웃 확인
        if ngx.now() - self.circuit_opened_at >= self.config.timeout then
            change_state("HALF_OPEN", "Timeout expired")
            return true
        end
        return false
    elseif self.state == "HALF_OPEN" then
        -- HALF_OPEN에서 제한된 요청만 허용
        if self.half_open_requests < self.config.half_open_max_requests then
            self.half_open_requests = (self.half_open_requests or 0) + 1
            return true
        end
        return false
    end
    
    -- 기본적으로 차단
    return false
end

-- 함수 실행 래퍼
function circuit_breaker:call(func, ...)
    -- 요청 허용 여부 확인
    if not self:should_allow_request() then
        kong.log.warn("[CIRCUIT-BREAKER] Request blocked", {
            state = self.state,
            time_since_open = ngx.now() - self.circuit_opened_at
        })
        return nil, "CIRCUIT_OPEN", self.state
    end
    
    -- 함수 실행
    local start_time = ngx.now()
    local success, result, extra = pcall(func, ...)
    local duration = ngx.now() - start_time
    
    -- 성능 로깅
    if duration > 1 then  -- 1초 이상
        kong.log.warn("[CIRCUIT-BREAKER] Slow operation", {
            duration = duration,
            success = success
        })
    end
    
    if success then
        self:record_success()
        return result, extra
    else
        self:record_failure("Function error", tostring(result))
        return nil, "CIRCUIT_FAILURE", result
    end
end

-- 현재 상태 조회
function circuit_breaker:get_status()
    local status = {
        state = self.state,
        failure_count = self.failure_count,
        success_count = self.success_count,
        consecutive_successes = self.consecutive_successes,
        last_failure = self.last_failure_time,
        last_state_change = self.last_state_change,
        stats = self.stats,
        error_rate = calculate_error_rate(),
        config = self.config
    }
    
    if self.state == "OPEN" then
        status.time_until_retry = math.max(0, 
            self.config.timeout - (ngx.now() - self.circuit_opened_at))
    end
    
    return status
end

-- 수동 리셋 (관리자용)
function circuit_breaker:reset()
    kong.log.warn("[CIRCUIT-BREAKER] Manual reset triggered")
    
    self.failure_count = 0
    self.success_count = 0
    self.consecutive_successes = 0
    self.recent_results = {}
    
    if self.state ~= "CLOSED" then
        change_state("CLOSED", "Manual reset")
    end
end

-- 설정 업데이트
function circuit_breaker:update_config(new_config)
    for key, value in pairs(new_config) do
        if self.config[key] ~= nil then
            self.config[key] = value
            kong.log.info("[CIRCUIT-BREAKER] Config updated", {
                key = key,
                value = value
            })
        end
    end
end

-- 초기화
function circuit_breaker:init()
    kong.log.info("[CIRCUIT-BREAKER] Initialized", {
        version = self.VERSION,
        config = self.config
    })
end

return circuit_breaker