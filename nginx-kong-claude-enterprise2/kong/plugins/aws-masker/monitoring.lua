-- monitoring.lua
-- Phase 4 - 3단계: 실시간 모니터링 시스템
-- 보안 최우선: Critical 패턴 감시 및 비상 대응

local kong = kong
local ngx = ngx

local monitoring = {}

-- 메트릭 저장소
local metrics = {
    -- 요청 통계
    total_requests = 0,
    masked_requests = 0,
    failed_requests = 0,
    
    -- 패턴별 통계
    pattern_counts = {},
    critical_pattern_alerts = {},
    
    -- 성능 메트릭
    response_times = {},
    slow_requests = 0,
    
    -- 보안 이벤트
    security_events = {},
    emergency_mode_triggers = 0,
    
    -- 시스템 상태
    last_reset = ngx.now(),
    circuit_breaker_trips = 0
}

-- 임계값 설정
local THRESHOLDS = {
    -- 성능 임계값
    SLOW_REQUEST_MS = 100,       -- 100ms 이상 = 느린 요청
    CRITICAL_SLOW_MS = 500,      -- 500ms 이상 = 위험
    MAX_RESPONSE_TIME = 5000,    -- 5초 = 최대 허용 시간
    
    -- 보안 임계값
    CRITICAL_PATTERN_THRESHOLD = 10,  -- 10회 이상 critical 패턴 = 알림
    FAILURE_RATE_THRESHOLD = 0.1,     -- 10% 실패율 = 경고
    EMERGENCY_TRIGGER_RATE = 0.2,     -- 20% 실패율 = 비상 모드
    
    -- 메모리 임계값 (메모리 96.63% 위험으로 인한 긴급 최적화)
    MAX_METRICS_SIZE = 1000,     -- 최대 메트릭 항목 수 (10000→1000, 90% 감소)
    CLEANUP_INTERVAL = 60,       -- 1분마다 정리 (300→60초, 80% 단축)
    
    -- 세부 메트릭 제한 (추가 메모리 절약)
    MAX_RESPONSE_TIME_RECORDS = 100,  -- 응답시간 기록 최대 100개
    MAX_SECURITY_EVENTS = 50,         -- 보안 이벤트 최대 50개
    MAX_PATTERN_ALERTS = 30           -- 패턴 알림 최대 30개
}

-- Critical 패턴 정의
local CRITICAL_PATTERNS = {
    "iam_access_key",
    "iam_secret_key",
    "kms_key_arn",
    "secrets_manager_arn",
    "rds_password",
    "private_key",
    "aws_account_id"
}

-- 메트릭 수집 함수
function monitoring.collect_request_metric(context)
    metrics.total_requests = metrics.total_requests + 1
    
    -- 성공/실패 카운트
    if context.success then
        metrics.masked_requests = metrics.masked_requests + 1
    else
        metrics.failed_requests = metrics.failed_requests + 1
    end
    
    -- 응답 시간 기록
    if context.elapsed_time then
        table.insert(metrics.response_times, {
            time = ngx.now(),
            duration = context.elapsed_time,
            size = context.request_size or 0
        })
        
        -- 느린 요청 감지
        if context.elapsed_time > THRESHOLDS.SLOW_REQUEST_MS then
            metrics.slow_requests = metrics.slow_requests + 1
            
            -- 위험 수준 체크
            if context.elapsed_time > THRESHOLDS.CRITICAL_SLOW_MS then
                monitoring.trigger_performance_alert(context)
            end
        end
    end
    
    -- 메모리 크기 체크
    if monitoring.get_metrics_size() > THRESHOLDS.MAX_METRICS_SIZE then
        monitoring.cleanup_old_metrics()
    end
end

-- 패턴 사용 추적
function monitoring.track_pattern_usage(pattern_name, count)
    metrics.pattern_counts[pattern_name] = 
        (metrics.pattern_counts[pattern_name] or 0) + count
    
    -- Critical 패턴 체크
    for _, critical in ipairs(CRITICAL_PATTERNS) do
        if pattern_name == critical then
            monitoring.track_critical_pattern(pattern_name, count)
        end
    end
end

-- Critical 패턴 추적
function monitoring.track_critical_pattern(pattern_name, count)
    local key = pattern_name .. "_" .. os.date("%Y%m%d%H")
    metrics.critical_pattern_alerts[key] = 
        (metrics.critical_pattern_alerts[key] or 0) + count
    
    -- 임계값 초과 시 알림
    if metrics.critical_pattern_alerts[key] > THRESHOLDS.CRITICAL_PATTERN_THRESHOLD then
        monitoring.send_security_alert({
            type = "CRITICAL_PATTERN_THRESHOLD",
            pattern = pattern_name,
            count = metrics.critical_pattern_alerts[key],
            threshold = THRESHOLDS.CRITICAL_PATTERN_THRESHOLD,
            severity = "HIGH"
        })
    end
end

-- 보안 이벤트 기록
function monitoring.log_security_event(event)
    table.insert(metrics.security_events, {
        timestamp = ngx.now(),
        type = event.type,
        severity = event.severity,
        details = event.details,
        action_taken = event.action_taken
    })
    
    -- 고위험 이벤트 즉시 알림
    if event.severity == "CRITICAL" then
        monitoring.send_security_alert(event)
    end
end

-- 성능 알림
function monitoring.trigger_performance_alert(context)
    kong.log.warn("[Monitoring] Performance degradation detected", {
        elapsed_time = context.elapsed_time,
        request_size = context.request_size,
        pattern_count = context.pattern_count
    })
    
    monitoring.log_security_event({
        type = "PERFORMANCE_DEGRADATION",
        severity = "MEDIUM",
        details = {
            elapsed_ms = context.elapsed_time,
            threshold_ms = THRESHOLDS.SLOW_REQUEST_MS
        },
        action_taken = "Logged for analysis"
    })
end

-- 보안 알림 전송
function monitoring.send_security_alert(alert)
    kong.log.crit("[SECURITY ALERT]", alert)
    
    -- 실제 환경에서는 여기서 외부 알림 시스템 호출
    -- 예: Slack, PagerDuty, CloudWatch 등
end

-- 실시간 상태 확인
function monitoring.get_health_status()
    local total = metrics.total_requests
    local failed = metrics.failed_requests
    local failure_rate = total > 0 and (failed / total) or 0
    
    -- 상태 판단
    local status = "HEALTHY"
    local details = {}
    
    -- 실패율 체크
    if failure_rate > THRESHOLDS.EMERGENCY_TRIGGER_RATE then
        status = "CRITICAL"
        table.insert(details, string.format("Failure rate: %.1f%%", failure_rate * 100))
    elseif failure_rate > THRESHOLDS.FAILURE_RATE_THRESHOLD then
        status = "WARNING"
        table.insert(details, string.format("Failure rate: %.1f%%", failure_rate * 100))
    end
    
    -- 성능 체크
    local avg_response_time = monitoring.calculate_average_response_time()
    if avg_response_time > THRESHOLDS.CRITICAL_SLOW_MS then
        status = "CRITICAL"
        table.insert(details, string.format("Avg response: %.1fms", avg_response_time))
    elseif avg_response_time > THRESHOLDS.SLOW_REQUEST_MS then
        if status == "HEALTHY" then status = "WARNING" end
        table.insert(details, string.format("Avg response: %.1fms", avg_response_time))
    end
    
    return {
        status = status,
        details = details,
        metrics = {
            total_requests = total,
            masked_requests = metrics.masked_requests,
            failed_requests = failed,
            failure_rate = string.format("%.1f%%", failure_rate * 100),
            avg_response_time = string.format("%.1fms", avg_response_time),
            slow_requests = metrics.slow_requests,
            security_events = #metrics.security_events,
            uptime = ngx.now() - metrics.last_reset
        }
    }
end

-- 평균 응답 시간 계산
function monitoring.calculate_average_response_time()
    if #metrics.response_times == 0 then
        return 0
    end
    
    local total = 0
    local count = 0
    local cutoff = ngx.now() - 300  -- 최근 5분
    
    for _, record in ipairs(metrics.response_times) do
        if record.time > cutoff then
            total = total + record.duration
            count = count + 1
        end
    end
    
    return count > 0 and (total / count) or 0
end

-- 메트릭 크기 확인
function monitoring.get_metrics_size()
    return #metrics.response_times + #metrics.security_events
end

-- 개선된 메트릭 정리 (메모리 최적화)
function monitoring.cleanup_old_metrics()
    local now = ngx.now()
    local cutoff = now - THRESHOLDS.CLEANUP_INTERVAL
    local initial_response_count = #metrics.response_times
    local initial_security_count = #metrics.security_events
    
    -- 1. 응답 시간: 최신 N개만 유지 (시간+개수 기반)
    local response_count = #metrics.response_times
    if response_count > THRESHOLDS.MAX_RESPONSE_TIME_RECORDS then
        -- 최신 100개만 남기고 나머지 삭제
        local keep_count = THRESHOLDS.MAX_RESPONSE_TIME_RECORDS
        local new_response_times = {}
        for i = response_count - keep_count + 1, response_count do
            if metrics.response_times[i] and metrics.response_times[i].time > cutoff then
                table.insert(new_response_times, metrics.response_times[i])
            end
        end
        metrics.response_times = new_response_times
    else
        -- 시간 기반 정리만 수행
        local new_response_times = {}
        for _, record in ipairs(metrics.response_times) do
            if record.time > cutoff then
                table.insert(new_response_times, record)
            end
        end
        metrics.response_times = new_response_times
    end
    
    -- 2. 보안 이벤트: CRITICAL은 유지, 일반은 최신 N개
    local critical_events = {}
    local normal_events = {}
    
    for _, event in ipairs(metrics.security_events) do
        if event.severity == "CRITICAL" then
            table.insert(critical_events, event)
        elseif event.timestamp > cutoff then
            table.insert(normal_events, event)
        end
    end
    
    -- 일반 이벤트는 최신 50개만 유지
    if #normal_events > THRESHOLDS.MAX_SECURITY_EVENTS then
        local keep_count = THRESHOLDS.MAX_SECURITY_EVENTS
        local temp = {}
        for i = #normal_events - keep_count + 1, #normal_events do
            table.insert(temp, normal_events[i])
        end
        normal_events = temp
    end
    
    -- CRITICAL + 일반 이벤트 합치기
    metrics.security_events = critical_events
    for _, event in ipairs(normal_events) do
        table.insert(metrics.security_events, event)
    end
    
    -- 3. Critical 패턴 알림 정리 (시간별 키 기반)
    local current_hour = os.date("%Y%m%d%H")
    local pattern_keys_to_remove = {}
    
    for key, _ in pairs(metrics.critical_pattern_alerts) do
        -- 현재 시간에서 1시간 이전 데이터 삭제
        local key_hour = string.match(key, "_(%d+)$")
        if key_hour and key_hour ~= current_hour then
            local hour_diff = tonumber(current_hour) - tonumber(key_hour)
            if hour_diff > 1 then  -- 1시간 초과된 알림 삭제
                table.insert(pattern_keys_to_remove, key)
            end
        end
    end
    
    for _, key in ipairs(pattern_keys_to_remove) do
        metrics.critical_pattern_alerts[key] = nil
    end
    
    kong.log.info("[Monitoring] Memory cleanup completed", {
        response_times_before = initial_response_count,
        response_times_after = #metrics.response_times,
        security_events_before = initial_security_count,
        security_events_after = #metrics.security_events,
        pattern_alerts_removed = #pattern_keys_to_remove,
        memory_saved_estimate = string.format("%.1fKB", 
            (initial_response_count - #metrics.response_times) * 0.15 + 
            (initial_security_count - #metrics.security_events) * 0.5)
    })
end

-- Circuit Breaker 트립 기록
function monitoring.record_circuit_breaker_trip(reason)
    metrics.circuit_breaker_trips = metrics.circuit_breaker_trips + 1
    
    monitoring.log_security_event({
        type = "CIRCUIT_BREAKER_TRIP",
        severity = "HIGH",
        details = {
            reason = reason,
            total_trips = metrics.circuit_breaker_trips
        },
        action_taken = "Circuit opened, requests will fail fast"
    })
end

-- Emergency Mode 트리거 기록
function monitoring.record_emergency_mode_trigger(mode, reason)
    metrics.emergency_mode_triggers = metrics.emergency_mode_triggers + 1
    
    monitoring.log_security_event({
        type = "EMERGENCY_MODE_ACTIVATED",
        severity = "CRITICAL",
        details = {
            mode = mode,
            reason = reason,
            total_triggers = metrics.emergency_mode_triggers
        },
        action_taken = "System switched to " .. mode .. " mode"
    })
end

-- 모니터링 대시보드 데이터
function monitoring.get_dashboard_data()
    local health = monitoring.get_health_status()
    
    return {
        timestamp = ngx.now(),
        health = health,
        pattern_usage = monitoring.get_top_patterns(10),
        recent_alerts = monitoring.get_recent_alerts(5),
        performance_trend = monitoring.get_performance_trend(),
        security_summary = {
            critical_patterns_detected = monitoring.count_critical_patterns(),
            emergency_triggers = metrics.emergency_mode_triggers,
            circuit_breaker_trips = metrics.circuit_breaker_trips
        }
    }
end

-- Top N 패턴 조회
function monitoring.get_top_patterns(n)
    local patterns = {}
    for name, count in pairs(metrics.pattern_counts) do
        table.insert(patterns, {name = name, count = count})
    end
    
    table.sort(patterns, function(a, b) return a.count > b.count end)
    
    local result = {}
    for i = 1, math.min(n, #patterns) do
        table.insert(result, patterns[i])
    end
    
    return result
end

-- 최근 알림 조회
function monitoring.get_recent_alerts(n)
    local alerts = {}
    local count = 0
    
    -- 최신 것부터 역순으로
    for i = #metrics.security_events, 1, -1 do
        local event = metrics.security_events[i]
        if event.severity == "HIGH" or event.severity == "CRITICAL" then
            table.insert(alerts, event)
            count = count + 1
            if count >= n then break end
        end
    end
    
    return alerts
end

-- 성능 추세 분석
function monitoring.get_performance_trend()
    local intervals = {
        {name = "1min", duration = 60},
        {name = "5min", duration = 300},
        {name = "15min", duration = 900}
    }
    
    local trends = {}
    local now = ngx.now()
    
    for _, interval in ipairs(intervals) do
        local cutoff = now - interval.duration
        local sum = 0
        local count = 0
        
        for _, record in ipairs(metrics.response_times) do
            if record.time > cutoff then
                sum = sum + record.duration
                count = count + 1
            end
        end
        
        trends[interval.name] = {
            avg_response_time = count > 0 and (sum / count) or 0,
            request_count = count
        }
    end
    
    return trends
end

-- Critical 패턴 카운트
function monitoring.count_critical_patterns()
    local count = 0
    for pattern, _ in pairs(metrics.critical_pattern_alerts) do
        count = count + 1
    end
    return count
end

-- 메트릭 리셋 (테스트용)
function monitoring.reset_metrics()
    metrics = {
        total_requests = 0,
        masked_requests = 0,
        failed_requests = 0,
        pattern_counts = {},
        critical_pattern_alerts = {},
        response_times = {},
        slow_requests = 0,
        security_events = {},
        emergency_mode_triggers = 0,
        last_reset = ngx.now(),
        circuit_breaker_trips = 0
    }
end

return monitoring