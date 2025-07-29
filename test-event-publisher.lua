#!/usr/bin/env lua

-- Event Publisher 단독 테스트 스크립트
-- Kong 환경 외부에서 모듈 기본 동작 검증

print("=== Kong AWS Masker Event Publisher 테스트 ===")

-- 기본 함수 및 상수 테스트
local event_publisher = require "kong.plugins.aws-masker.event_publisher"

print("1. 모듈 로딩: ✅ 성공")

-- 채널 상수 확인
print("2. 채널 상수 확인:")
for key, value in pairs(event_publisher.CHANNELS) do
  print("   " .. key .. ": " .. value)
end

-- 이벤트 발행 가능 여부 확인
local enabled = event_publisher.is_event_publishing_enabled()
print("3. 이벤트 발행 가능: " .. (enabled and "✅ 예" or "❌ 아니오"))

print("4. 기본 검증 완료")
print("")
print("주의: 실제 Redis 연결 테스트는 Kong 환경에서 수행해야 합니다.")