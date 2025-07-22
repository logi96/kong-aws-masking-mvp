-- masker_test_adapter.lua
-- 테스트 환경에서 실제 마스킹 엔진 연동을 위한 어댑터
-- Phase 1 테스트를 Phase 2 구현과 연결

-- Mock Kong 환경 설정
_G.kong = _G.kong or {
    log = {
        info = function(msg, ctx) print("[INFO] " .. msg) end,
        warn = function(msg, ctx) print("[WARN] " .. msg) end,
        error = function(msg, ctx) print("[ERROR] " .. msg) end,
        debug = function(msg, ctx) end,
        crit = function(msg, ctx) print("[CRITICAL] " .. msg) end
    },
    request = {
        get_header = function(name) return "test-request-id" end
    },
    ctx = {
        plugin = {}
    }
}

_G.ngx = _G.ngx or {
    now = function() return os.clock() end,
    var = { request_id = "test-" .. tostring(os.time()) },
    encode_base64 = function(str) 
        -- 간단한 base64 시뮬레이션
        return "base64:" .. str:gsub(".", function(c)
            return string.format("%02x", string.byte(c))
        end)
    end
}

-- 마스킹 엔진 로드
package.path = package.path .. ";../kong/plugins/aws-masker/?.lua"
local text_masker = require "text_masker_v2"
local circuit_breaker = require "circuit_breaker"
local emergency_handler = require "emergency_handler"

-- cjson 대체 (테스트용)
if not pcall(require, "cjson") then
    package.loaded["cjson"] = {
        encode = function(data)
            -- 간단한 JSON 인코딩
            if type(data) == "table" then
                local parts = {}
                for k, v in pairs(data) do
                    local value = type(v) == "string" and '"' .. v .. '"' or tostring(v)
                    table.insert(parts, '"' .. k .. '":' .. value)
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
            return tostring(data)
        end,
        decode = function(str)
            -- 테스트용 간단한 디코더
            return loadstring("return " .. str:gsub('(["\'])(.-)\1', function(q, s)
                return string.format('%q', s)
            end))()
        end
    }
end

-- 테스트 어댑터
local test_adapter = {
    -- 초기화 상태
    initialized = false,
    
    -- 통계
    stats = {
        total_tests = 0,
        passed_tests = 0,
        failed_tests = 0,
        masked_patterns = {}
    }
}

-- 초기화
function test_adapter.init()
    if not test_adapter.initialized then
        text_masker.init()
        circuit_breaker:init()
        emergency_handler:init()
        test_adapter.initialized = true
        print("[TEST-ADAPTER] Initialized successfully")
    end
end

-- 텍스트 마스킹 테스트
function test_adapter.test_mask_text(input_text, expected_patterns)
    test_adapter.stats.total_tests = test_adapter.stats.total_tests + 1
    
    local masked_text, context = text_masker.mask_text(input_text, "test-" .. test_adapter.stats.total_tests)
    
    if not masked_text then
        print("[TEST-ADAPTER] Masking failed: " .. (context and context.error or "unknown error"))
        test_adapter.stats.failed_tests = test_adapter.stats.failed_tests + 1
        return false, context
    end
    
    -- 패턴 검증
    local success = true
    local results = {
        input = input_text,
        masked = masked_text,
        context = context,
        pattern_validation = {}
    }
    
    if expected_patterns then
        for pattern_name, expected_count in pairs(expected_patterns) do
            local actual_count = 0
            if context.pattern_stats then
                actual_count = context.pattern_stats[pattern_name] or 0
            end
            
            results.pattern_validation[pattern_name] = {
                expected = expected_count,
                actual = actual_count,
                match = actual_count == expected_count
            }
            
            if actual_count ~= expected_count then
                success = false
            end
        end
    end
    
    -- Roundtrip 테스트
    local unmasked_text = text_masker.unmask_text(masked_text)
    results.roundtrip_success = (unmasked_text == input_text)
    
    if not results.roundtrip_success then
        success = false
        print("[TEST-ADAPTER] Roundtrip failed!")
        print("  Original: " .. input_text:sub(1, 50))
        print("  Unmasked: " .. unmasked_text:sub(1, 50))
    end
    
    -- 보안 체크포인트
    local secure, security_err = text_masker.security_checkpoint(masked_text)
    results.security_check = secure
    
    if not secure then
        success = false
        print("[TEST-ADAPTER] SECURITY CHECK FAILED: " .. security_err)
    end
    
    if success then
        test_adapter.stats.passed_tests = test_adapter.stats.passed_tests + 1
    else
        test_adapter.stats.failed_tests = test_adapter.stats.failed_tests + 1
    end
    
    return success, results
end

-- Claude API 요청 마스킹 테스트
function test_adapter.test_claude_request(request_data, expected_field_masks)
    test_adapter.stats.total_tests = test_adapter.stats.total_tests + 1
    
    -- JSON 인코딩
    local cjson = require "cjson"
    local request_body = cjson.encode(request_data)
    
    -- 마스킹 실행
    local masked_body, context = text_masker.mask_claude_request(request_body, {})
    
    if not masked_body then
        print("[TEST-ADAPTER] Claude request masking failed")
        test_adapter.stats.failed_tests = test_adapter.stats.failed_tests + 1
        return false, context
    end
    
    -- 결과 파싱
    local masked_data = cjson.decode(masked_body)
    
    -- 필드별 검증
    local success = true
    local results = {
        original = request_data,
        masked = masked_data,
        context = context,
        field_validation = {}
    }
    
    -- system 필드 검증
    if request_data.system and expected_field_masks.system then
        local system_changed = request_data.system ~= masked_data.system
        results.field_validation.system = system_changed
        if not system_changed then
            success = false
            print("[TEST-ADAPTER] System field not masked!")
        end
    end
    
    -- messages 필드 검증
    if request_data.messages and expected_field_masks.messages then
        for i, expected in pairs(expected_field_masks.messages) do
            if expected then
                local original_msg = request_data.messages[i]
                local masked_msg = masked_data.messages[i]
                
                if type(original_msg.content) == "string" then
                    local changed = original_msg.content ~= masked_msg.content
                    results.field_validation["messages[" .. i .. "]"] = changed
                    if not changed then
                        success = false
                        print("[TEST-ADAPTER] Message " .. i .. " not masked!")
                    end
                end
            end
        end
    end
    
    if success then
        test_adapter.stats.passed_tests = test_adapter.stats.passed_tests + 1
    else
        test_adapter.stats.failed_tests = test_adapter.stats.failed_tests + 1
    end
    
    return success, results
end

-- Circuit Breaker 테스트
function test_adapter.test_circuit_breaker()
    print("\n[TEST-ADAPTER] Testing Circuit Breaker...")
    
    -- 연속 실패 시뮬레이션
    for i = 1, 6 do
        circuit_breaker:record_failure("test_failure", "Simulated failure " .. i)
    end
    
    local status = circuit_breaker:get_status()
    print("Circuit Breaker State: " .. status.state)
    print("Failure Count: " .. status.failure_count)
    
    -- OPEN 상태 확인
    if status.state ~= "OPEN" then
        print("[TEST-ADAPTER] Circuit Breaker should be OPEN!")
        return false
    end
    
    -- 요청 차단 확인
    local allowed = circuit_breaker:should_allow_request()
    if allowed then
        print("[TEST-ADAPTER] Circuit Breaker should block requests!")
        return false
    end
    
    -- 리셋
    circuit_breaker:reset()
    
    return true
end

-- Emergency Handler 테스트
function test_adapter.test_emergency_handler()
    print("\n[TEST-ADAPTER] Testing Emergency Handler...")
    
    -- BASIC_ONLY 모드 테스트
    local test_text = "EC2 instance i-1234567890abcdef0 with key AKIAIOSFODNN7EXAMPLE"
    local masked = emergency_handler.BASIC_ONLY(test_text)
    
    print("Original: " .. test_text)
    print("Masked: " .. masked)
    
    -- 기본 패턴이 마스킹되었는지 확인
    if masked:find("i%-1234567890abcdef0") or masked:find("AKIAIOSFODNN7EXAMPLE") then
        print("[TEST-ADAPTER] Emergency handler failed to mask critical patterns!")
        return false
    end
    
    return true
end

-- 통계 출력
function test_adapter.print_stats()
    print("\n========================================")
    print("TEST ADAPTER STATISTICS")
    print("========================================")
    print("Total Tests: " .. test_adapter.stats.total_tests)
    print("Passed: " .. test_adapter.stats.passed_tests)
    print("Failed: " .. test_adapter.stats.failed_tests)
    print("Success Rate: " .. string.format("%.1f%%", 
        test_adapter.stats.passed_tests / test_adapter.stats.total_tests * 100))
end

-- 종합 테스트 실행
function test_adapter.run_all_tests()
    print("\n🧪 Running Masking Engine Tests...")
    print("=====================================")
    
    -- 초기화
    test_adapter.init()
    
    -- 1. 기본 텍스트 마스킹 테스트
    print("\n[1] Basic Text Masking Test")
    local success1, result1 = test_adapter.test_mask_text(
        "EC2 instance i-1234567890abcdef0 in VPC vpc-abcd1234efgh5678",
        {ec2_instance_id = 1, vpc_id = 1}
    )
    print("Result: " .. (success1 and "✅ PASS" or "❌ FAIL"))
    
    -- 2. 보안 위반 시나리오 테스트
    print("\n[2] Security Breach Scenario Test")
    local success2, result2 = test_adapter.test_mask_text(
        "AWS Access Key AKIAIOSFODNN7EXAMPLE found!",
        {iam_access_key = 1}
    )
    print("Result: " .. (success2 and "✅ PASS" or "❌ FAIL"))
    
    -- 3. Claude API 구조 테스트
    print("\n[3] Claude API Structure Test")
    local success3, result3 = test_adapter.test_claude_request(
        {
            system = "Analyze AWS account 123456789012",
            messages = {
                {role = "user", content = "Check EC2 i-abcd1234efgh5678"}
            }
        },
        {system = true, messages = {[1] = true}}
    )
    print("Result: " .. (success3 and "✅ PASS" or "❌ FAIL"))
    
    -- 4. Circuit Breaker 테스트
    print("\n[4] Circuit Breaker Test")
    local success4 = test_adapter.test_circuit_breaker()
    print("Result: " .. (success4 and "✅ PASS" or "❌ FAIL"))
    
    -- 5. Emergency Handler 테스트
    print("\n[5] Emergency Handler Test")
    local success5 = test_adapter.test_emergency_handler()
    print("Result: " .. (success5 and "✅ PASS" or "❌ FAIL"))
    
    -- 통계 출력
    test_adapter.print_stats()
    
    -- 최종 결과
    local all_passed = test_adapter.stats.failed_tests == 0
    print("\n" .. (all_passed and "✅ All tests passed!" or "❌ Some tests failed!"))
    
    return all_passed
end

return test_adapter