--
-- Event Publisher for Kong AWS Masker Real-time Monitoring
-- Redis Pub/Sub 이벤트 발행 담당 모듈
--

local masker = require "kong.plugins.aws-masker.masker_ngx_re"
local json_safe = require "kong.plugins.aws-masker.json_safe"

local _M = {}

-- 이벤트 채널 정의
local CHANNELS = {
  MASKING = "aws-masker:events:masking",
  UNMASKING = "aws-masker:events:unmasking",
  ALERTS = "aws-masker:alerts:security",
  METRICS = "aws-masker:metrics:performance"
}

---
-- 고유 이벤트 ID 생성
-- @return string 고유 이벤트 ID
local function generate_event_id(prefix)
  return prefix .. "_" .. ngx.now() .. "_" .. math.random(10000, 99999)
end

---
-- 마스킹 이벤트 발행 (내부 사용자 데모용 - before/after 포함)
-- @param table event_data 이벤트 데이터
-- @param table redis_conn 기존 Redis 연결 (선택적)
-- @return boolean 성공 여부
function _M.publish_masking_event(event_data, redis_conn)
  local red = redis_conn
  local need_release = false
  
  -- Redis 연결 획득
  if not red then
    red = masker.acquire_redis_connection()
    if not red then
      kong.log.warn("[EVENT_PUBLISHER] Failed to acquire Redis connection for masking event")
      return false
    end
    need_release = true
  end
  
  -- 이벤트 객체 생성 (내부 데모용 - before/after 포함)
  local event = {
    event_id = generate_event_id("mask"),
    event_type = "masking_applied",
    timestamp = ngx.now() * 1000, -- 밀리초로 변환
    request_id = ngx.var.request_id or "unknown",
    success = event_data.success or false,
    patterns_applied = event_data.patterns_used or {},
    total_patterns = event_data.count or 0,
    processing_time_ms = event_data.processing_time_ms or 0,
    request_size_bytes = event_data.request_size or 0,
    -- 내부 데모용: before/after 텍스트 (최대 500자로 제한)
    demo_data = {
      original_text = event_data.original_text and string.sub(event_data.original_text, 1, 500) or nil,
      masked_text = event_data.masked_text and string.sub(event_data.masked_text, 1, 500) or nil,
      is_demo_mode = true,
      truncated = event_data.original_text and string.len(event_data.original_text) > 500 or false
    },
    source = "kong-aws-masker",
    version = "1.0.0"
  }
  
  -- JSON 직렬화
  local event_json, encode_err = json_safe.encode(event)
  if encode_err then
    kong.log.err("[EVENT_PUBLISHER] Failed to encode masking event: ", encode_err)
    if need_release then masker.release_redis_connection(red) end
    return false
  end
  
  -- Redis Pub/Sub 발행 (fire-and-forget)
  local ok, err = red:publish(CHANNELS.MASKING, event_json)
  if not ok then
    kong.log.warn("[EVENT_PUBLISHER] Failed to publish masking event: ", err)
    if need_release then masker.release_redis_connection(red) end
    return false
  end
  
  -- 연결 해제
  if need_release then
    masker.release_redis_connection(red)
  end
  
  -- 성공 로그 (debug 레벨)
  kong.log.debug("[EVENT_PUBLISHER] Masking event published: ", event.event_id, 
                 " patterns:", event.total_patterns, " time:", event.processing_time_ms, "ms")
  
  return true
end

---
-- 언마스킹 이벤트 발행
-- @param table event_data 이벤트 데이터
-- @param table redis_conn 기존 Redis 연결 (선택적)
-- @return boolean 성공 여부
function _M.publish_unmasking_event(event_data, redis_conn)
  local red = redis_conn
  local need_release = false
  
  -- Redis 연결 획득
  if not red then
    red = masker.acquire_redis_connection()
    if not red then
      kong.log.warn("[EVENT_PUBLISHER] Failed to acquire Redis connection for unmasking event")
      return false
    end
    need_release = true
  end
  
  -- 이벤트 객체 생성
  local event = {
    event_id = generate_event_id("unmask"),
    event_type = "unmasking_applied",
    timestamp = ngx.now() * 1000, -- 밀리초로 변환
    request_id = ngx.var.request_id or "unknown",
    success = event_data.success or false,
    patterns_restored = event_data.patterns_restored or 0,
    processing_time_ms = event_data.processing_time_ms or 0,
    response_size_bytes = event_data.response_size or 0,
    source = "kong-aws-masker",
    version = "1.0.0"
  }
  
  -- JSON 직렬화
  local event_json, encode_err = json_safe.encode(event)
  if encode_err then
    kong.log.err("[EVENT_PUBLISHER] Failed to encode unmasking event: ", encode_err)
    if need_release then masker.release_redis_connection(red) end
    return false
  end
  
  -- Redis Pub/Sub 발행 (fire-and-forget)
  local ok, err = red:publish(CHANNELS.UNMASKING, event_json)
  if not ok then
    kong.log.warn("[EVENT_PUBLISHER] Failed to publish unmasking event: ", err)
    if need_release then masker.release_redis_connection(red) end
    return false
  end
  
  -- 연결 해제
  if need_release then
    masker.release_redis_connection(red)
  end
  
  -- 성공 로그 (debug 레벨)
  kong.log.debug("[EVENT_PUBLISHER] Unmasking event published: ", event.event_id, 
                 " patterns:", event.patterns_restored, " time:", event.processing_time_ms, "ms")
  
  return true
end

---
-- 이벤트 발행 가능 여부 확인
-- @return boolean 발행 가능 여부
function _M.is_event_publishing_enabled()
  -- 향후 플러그인 설정에서 제어 가능하도록 준비
  return true
end

-- 채널 상수 노출
_M.CHANNELS = CHANNELS

return _M