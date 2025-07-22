#!/usr/bin/env lua
-- security-bypass-tests.lua
-- 보안 최우선: 악의적인 우회 시도를 감지하고 차단하는지 검증
-- 이 테스트가 실패하면 심각한 보안 위협입니다

-- Mock 환경
_G.kong = {
    log = {
        crit = function(msg) print("[CRITICAL] " .. msg) end,
        error = function(msg) print("[ERROR] " .. msg) end,
        warn = function(msg) print("[WARN] " .. msg) end,
        info = function(msg) print("[INFO] " .. msg) end
    }
}

_G.ngx = {
    now = function() return os.clock() end,
    var = { request_id = "security-test-" .. tostring(os.time()) }
}

-- 보안 우회 시도 케이스
local bypass_attempts = {
    -- 1. 인코딩 변형 시도
    encoding_attacks = {
        {
            name = "URL encoded AWS account",
            input = "Account%20123456789012%20exposed",  -- URL 인코딩
            should_detect = "123456789012",
            severity = "HIGH"
        },
        {
            name = "Base64 encoded EC2 ID",
            input = "aS0xMjM0NTY3ODkwYWJjZGVmMA==",  -- i-1234567890abcdef0 in base64
            should_detect = "EC2 instance pattern",
            severity = "MEDIUM"
        },
        {
            name = "Unicode variants",
            input = "і-1234567890abcdef0",  -- Cyrillic 'i' instead of Latin 'i'
            should_detect = "EC2-like pattern",
            severity = "HIGH"
        },
        {
            name = "Zero-width characters",
            input = "i-​1234567890​abcdef0",  -- Zero-width spaces inserted
            should_detect = "Hidden EC2 pattern",
            severity = "CRITICAL"
        }
    },
    
    -- 2. 패턴 분할 시도
    pattern_splitting = {
        {
            name = "Split account ID",
            input = "Account 123456" .. "789012 found",  -- 분할된 account ID
            should_detect = "123456789012",
            severity = "HIGH"
        },
        {
            name = "Newline split",
            input = "i-1234567890\nabcdef0",  -- 줄바꿈으로 분할
            should_detect = "Split EC2 ID",
            severity = "MEDIUM"
        },
        {
            name = "Comment injection",
            input = "arn:aws:iam::/*comment*/123456789012:role/Admin",
            should_detect = "ARN with injected comment",
            severity = "HIGH"
        }
    },
    
    -- 3. 대소문자 변형
    case_variations = {
        {
            name = "Mixed case EC2",
            input = "I-1234567890ABCDEF0",  -- 대문자 I
            should_detect = "Case variant EC2",
            severity = "MEDIUM"
        },
        {
            name = "Mixed case S3",
            input = "s3://My-BuCkEt-2024/data",
            should_detect = "Case variant S3",
            severity = "LOW"
        }
    },
    
    -- 4. 특수 문자 삽입
    special_char_injection = {
        {
            name = "Null byte injection",
            input = "i-1234567890abcdef0\0hidden",
            should_detect = "Null byte attack",
            severity = "CRITICAL"
        },
        {
            name = "Control characters",
            input = "vpc-\x081234567890abcdef",
            should_detect = "Control char in VPC",
            severity = "HIGH"
        },
        {
            name = "Homograph attack",
            input = "ѕ3://bucket-name",  -- Cyrillic 's' looks like Latin 's'
            should_detect = "Homograph S3",
            severity = "HIGH"
        }
    },
    
    -- 5. 컨텍스트 위장
    context_deception = {
        {
            name = "Fake error message",
            input = "Error: Invalid format 'i-1234567890abcdef0' is not valid",
            should_detect = "EC2 in fake error",
            severity = "MEDIUM"
        },
        {
            name = "Code comment disguise",
            input = "// Example: i-1234567890abcdef0 (do not use)",
            should_detect = "EC2 in comment",
            severity = "LOW"
        },
        {
            name = "JSON string escape",
            input = '{"example": "i-1234567890abcdef0"}',
            should_detect = "EC2 in JSON",
            severity = "MEDIUM"
        }
    },
    
    -- 6. 타이밍 공격
    timing_attacks = {
        {
            name = "Repeated patterns",
            input = string.rep("i-1234567890abcdef0 ", 1000),  -- 대량 반복
            should_detect = "DoS attempt",
            severity = "CRITICAL"
        },
        {
            name = "Regex bomb",
            input = "i-" .. string.rep("a", 1000) .. "bcdef0",  -- 긴 패턴
            should_detect = "Regex performance attack",
            severity = "CRITICAL"
        }
    },
    
    -- 7. 혼합 공격
    combined_attacks = {
        {
            name = "Multiple encoding layers",
            input = "%69%2D%31%32%33%34%35%36%37%38%39%30%61%62%63%64%65%66%30",
            should_detect = "URL encoded EC2",
            severity = "CRITICAL"
        },
        {
            name = "Nested patterns",
            input = "arn:aws:iam::arn:aws:iam::123456789012:role:role/Admin",
            should_detect = "Nested ARN attack",
            severity = "HIGH"
        }
    }
}

-- 보안 검증 함수
local function test_bypass_attempt(category, test_case)
    print(string.format("\n[%s] Testing: %s", test_case.severity, test_case.name))
    print("Input: " .. (test_case.input:sub(1, 50) .. (#test_case.input > 50 and "..." or "")))
    print("Should detect: " .. test_case.should_detect)
    
    -- TODO: 실제 마스킹 엔진으로 테스트
    -- local result = masker.process_with_security_check(test_case.input)
    
    -- 시뮬레이션 결과
    local detected = false
    local blocked = test_case.severity == "CRITICAL"
    
    if detected then
        print("✅ Attack detected and handled")
        return true
    else
        print("❌ SECURITY BREACH - Attack not detected!")
        return false
    end
end

-- 전체 보안 테스트 실행
local function run_security_tests()
    print("🔒 Kong AWS Masking - Security Bypass Tests")
    print("===========================================")
    print("Testing malicious bypass attempts\n")
    
    local total_tests = 0
    local passed_tests = 0
    local critical_failures = {}
    
    -- 각 카테고리별 테스트 실행
    for category, test_list in pairs(bypass_attempts) do
        print("\n🛡️  Category: " .. category:gsub("_", " "):upper())
        print(string.rep("-", 40))
        
        for _, test_case in ipairs(test_list) do
            total_tests = total_tests + 1
            local passed = test_bypass_attempt(category, test_case)
            
            if passed then
                passed_tests = passed_tests + 1
            else
                if test_case.severity == "CRITICAL" then
                    table.insert(critical_failures, {
                        category = category,
                        test = test_case.name,
                        input = test_case.input
                    })
                end
            end
        end
    end
    
    -- 결과 요약
    print("\n===========================================")
    print("📊 Security Test Summary")
    print("===========================================")
    print(string.format("Total security tests: %d", total_tests))
    print(string.format("Passed: %d", passed_tests))
    print(string.format("Failed: %d", total_tests - passed_tests))
    print(string.format("Critical failures: %d", #critical_failures))
    
    -- 심각한 실패 상세 정보
    if #critical_failures > 0 then
        print("\n🚨 CRITICAL SECURITY FAILURES:")
        for _, failure in ipairs(critical_failures) do
            print(string.format("  - [%s] %s", failure.category, failure.test))
        end
    end
    
    -- 보안 평가
    local security_score = (passed_tests / total_tests) * 100
    print(string.format("\n🛡️  Security Score: %.1f%%", security_score))
    
    if #critical_failures > 0 then
        print("\n❌ CRITICAL SECURITY FAILURE!")
        print("System is vulnerable to bypass attacks")
        print("DO NOT DEPLOY TO PRODUCTION")
        return false
    elseif security_score < 95 then
        print("\n⚠️  Security level insufficient")
        print("Required: 95%, Current: " .. string.format("%.1f%%", security_score))
        return false
    else
        print("\n✅ Security tests passed!")
        print("System is resilient against bypass attempts")
        return true
    end
end

-- 추가 보안 검증 함수들
local security_validators = {
    -- 패턴 정규화 검증
    validate_normalization = function(input)
        -- URL 디코딩
        local url_decoded = input:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        
        -- 유니코드 정규화 (간단한 버전)
        local normalized = url_decoded:gsub("[^%g%s]", "")  -- 제어 문자 제거
        
        return normalized ~= input  -- 변경되었으면 의심스러움
    end,
    
    -- 성능 공격 감지
    validate_performance = function(input)
        if #input > 10000 then
            return false, "Input too large"
        end
        
        -- 반복 패턴 감지
        local repeated = input:match("(.+)%1%1%1%1")  -- 4회 이상 반복
        if repeated and #repeated > 10 then
            return false, "Repeated pattern detected"
        end
        
        return true
    end,
    
    -- 인젝션 공격 감지
    validate_injection = function(input)
        -- Null byte
        if input:find("\0") then
            return false, "Null byte detected"
        end
        
        -- 제어 문자
        if input:match("[\x00-\x1F\x7F]") then
            return false, "Control characters detected"
        end
        
        return true
    end
}

-- 메인 실행
local function main()
    -- 보안 테스트 실행
    local security_passed = run_security_tests()
    
    -- 추가 검증
    print("\n🔍 Additional Security Validations")
    print("==================================")
    
    local validation_passed = true
    for name, validator in pairs(security_validators) do
        print("\nValidating: " .. name)
        -- 테스트 입력으로 검증
        local test_input = "i-1234567890abcdef0"
        local valid, reason = validator(test_input)
        if valid == false then
            print("  ❌ Validation would block: " .. (reason or "unknown"))
        else
            print("  ✅ Validation logic ready")
        end
    end
    
    -- 최종 판정
    if security_passed and validation_passed then
        print("\n🎉 All security tests completed successfully!")
        print("✅ System is secure against known bypass attempts")
        os.exit(0)
    else
        print("\n❌ Security tests failed!")
        print("🚨 DO NOT PROCEED TO PRODUCTION")
        os.exit(1)
    end
end

-- 실행
main()