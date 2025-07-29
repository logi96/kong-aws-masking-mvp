-- kong-integration-loader.lua
-- Phase 4 - 1단계: Kong 환경에서 통합 패턴 로드 및 검증
-- 보안 최우선: 모든 패턴의 안전한 로드와 검증

-- 필요한 모듈 로드
local ok, text_masker_v2 = pcall(require, "kong.plugins.aws-masker.text_masker_v2")
if not ok then
    error("Failed to load text_masker_v2: " .. tostring(text_masker_v2))
end

local ok, pattern_integrator = pcall(require, "kong.plugins.aws-masker.pattern_integrator")
if not ok then
    error("Failed to load pattern_integrator: " .. tostring(pattern_integrator))
end

-- 보안 체크포인트 1: 환경 격리 확인
print("=======================================")
print("🔒 보안 체크포인트 1: 환경 격리")
print("=======================================")
print("Kong 환경: " .. (os.getenv("KONG_ENV") or "development"))
print("Lua 버전: " .. _VERSION)
print("")

-- Phase 2 기존 패턴 로드
local original_patterns = {
    -- Critical 패턴
    {
        name = "iam_access_key",
        pattern = "AKIA[A-Z0-9]{16}",
        replacement = "ACCESS_KEY_%03d",
        priority = 1,
        critical = true
    },
    {
        name = "iam_secret_key",
        pattern = "[A-Za-z0-9/+=]{40}",
        replacement = "SECRET_KEY_%03d",
        priority = 2,
        critical = true
    },
    {
        name = "aws_account_in_arn",
        pattern = "(arn:aws:[^:]+:[^:]*:)(%d{12})(:[^%s]+)",
        replacement = function(prefix, account, suffix, counter)
            return prefix .. "ACCOUNT_" .. string.format("%03d", counter) .. suffix
        end,
        priority = 3,
        critical = true
    },
    -- 기타 패턴들 (4-19)
    {
        name = "aws_account_standalone",
        pattern = "\\b%d{12}\\b",
        replacement = "ACCOUNT_%03d",
        priority = 4
    },
    {
        name = "iam_arn_full",
        pattern = "arn:aws:iam::[^%s]+",
        replacement = "IAM_ARN_%03d",
        priority = 5
    },
    {
        name = "ec2_instance_id",
        pattern = "i%-[0-9a-f]{8,17}",
        replacement = "EC2_%03d",
        priority = 6
    },
    {
        name = "vpc_id",
        pattern = "vpc%-[0-9a-f]{8,17}",
        replacement = "VPC_%03d",
        priority = 7
    },
    {
        name = "subnet_id",
        pattern = "subnet%-[0-9a-f]{8,17}",
        replacement = "SUBNET_%03d",
        priority = 8
    },
    {
        name = "security_group_id",
        pattern = "sg%-[0-9a-f]{8,17}",
        replacement = "SG_%03d",
        priority = 9
    },
    {
        name = "s3_bucket_in_arn",
        pattern = "arn:aws:s3:::([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])",
        replacement = "arn:aws:s3:::BUCKET_%03d",
        priority = 10
    },
    {
        name = "s3_uri",
        pattern = "s3://([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])",
        replacement = "s3://BUCKET_%03d",
        priority = 11
    },
    {
        name = "ebs_volume_id",
        pattern = "vol%-[0-9a-f]{8,17}",
        replacement = "VOLUME_%03d",
        priority = 12
    },
    {
        name = "ami_id",
        pattern = "ami%-[0-9a-f]{8,17}",
        replacement = "AMI_%03d",
        priority = 13
    },
    {
        name = "snapshot_id",
        pattern = "snap%-[0-9a-f]{8,17}",
        replacement = "SNAPSHOT_%03d",
        priority = 14
    },
    {
        name = "private_ip_10",
        pattern = "10%.%d+%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 15
    },
    {
        name = "private_ip_172",
        pattern = "172%.1[6-9]%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 16
    },
    {
        name = "private_ip_172_20s",
        pattern = "172%.2[0-9]%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 17
    },
    {
        name = "private_ip_172_30s",
        pattern = "172%.3[01]%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 18
    },
    {
        name = "private_ip_192",
        pattern = "192%.168%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 19
    }
}

print("📊 기존 패턴 수: " .. #original_patterns)

-- 패턴 통합 실행
print("\n=======================================")
print("🔗 패턴 통합 실행")
print("=======================================")

local integrated_patterns, conflicts = pattern_integrator.integrate_patterns(original_patterns)

-- 통합 결과 검증
local stats = pattern_integrator.get_stats()
print("통합 결과:")
print("  - 기존 패턴: " .. stats.integration.original_count)
print("  - 확장 패턴: " .. stats.integration.extension_count)
print("  - 통합 패턴: " .. stats.integration.total_count)
print("  - 충돌 발생: " .. stats.integration.conflict_count)

-- 보안 체크포인트 2: Critical 패턴 확인
print("\n=======================================")
print("🔒 보안 체크포인트 2: Critical 패턴")
print("=======================================")

local critical_count = 0
local critical_patterns = {}
for _, pattern in ipairs(integrated_patterns) do
    if pattern.critical then
        critical_count = critical_count + 1
        table.insert(critical_patterns, pattern.name)
    end
end

print("Critical 패턴 수: " .. critical_count)
for _, name in ipairs(critical_patterns) do
    print("  - " .. name)
end

-- 통합 검증
print("\n=======================================")
print("✅ 통합 검증")
print("=======================================")

local success = true
local errors = {}

-- 패턴 수 검증
if #integrated_patterns ~= 47 then
    success = false
    table.insert(errors, string.format("Expected 47 patterns, got %d", #integrated_patterns))
end

-- 충돌 검증
if #conflicts > 0 then
    success = false
    table.insert(errors, string.format("Pattern conflicts detected: %d", #conflicts))
    for _, conflict in ipairs(conflicts) do
        table.insert(errors, string.format("  - %s vs %s: %s", 
            conflict.original, conflict.extension, conflict.reason))
    end
end

-- Critical 패턴 검증
if critical_count < 5 then
    success = false
    table.insert(errors, string.format("Expected at least 5 critical patterns, got %d", critical_count))
end

-- 간단한 마스킹 테스트
print("\n=======================================")
print("🧪 마스킹 기능 테스트")
print("=======================================")

-- 테스트 마스킹 함수 생성
local function test_masking(patterns)
    local mapping_store = {
        forward = {},
        reverse = {},
        counters = {}
    }
    
    local function mask_text(text)
        local masked_text = text
        local masked_count = 0
        
        for _, pattern_def in ipairs(patterns) do
            local pattern = pattern_def.pattern
            local replacement = pattern_def.replacement
            local pattern_name = pattern_def.name
            
            if type(replacement) == "function" then
                masked_text = masked_text:gsub(pattern, function(...)
                    local matches = {...}
                    mapping_store.counters[pattern_name] = (mapping_store.counters[pattern_name] or 0) + 1
                    local counter = mapping_store.counters[pattern_name]
                    
                    local original = table.concat(matches, "")
                    local masked = replacement(matches[1], matches[2], matches[3], counter)
                    
                    mapping_store.forward[original] = masked
                    mapping_store.reverse[masked] = original
                    masked_count = masked_count + 1
                    
                    return masked
                end)
            else
                masked_text = masked_text:gsub(pattern, function(match)
                    if mapping_store.forward[match] then
                        masked_count = masked_count + 1
                        return mapping_store.forward[match]
                    end
                    
                    mapping_store.counters[pattern_name] = (mapping_store.counters[pattern_name] or 0) + 1
                    local counter = mapping_store.counters[pattern_name]
                    local masked = string.format(replacement, counter)
                    
                    mapping_store.forward[match] = masked
                    mapping_store.reverse[masked] = match
                    masked_count = masked_count + 1
                    
                    return masked
                end)
            end
        end
        
        return masked_text, masked_count
    end
    
    return mask_text
end

-- 테스트 케이스
local test_cases = {
    {
        name = "EC2 + VPC",
        input = "Instance i-1234567890abcdef0 in vpc-abcdef01",
        expected_masked = {"EC2_", "VPC_"}
    },
    {
        name = "Lambda ARN",
        input = "Function arn:aws:lambda:us-east-1:123456789012:function:myHandler",
        expected_masked = {"LAMBDA_", "ACCOUNT_"}
    },
    {
        name = "KMS Key",
        input = "Using key arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012",
        expected_masked = {"KMS_KEY_", "ACCOUNT_"}
    },
    {
        name = "Critical IAM",
        input = "Access key AKIAIOSFODNN7EXAMPLE",
        expected_masked = {"ACCESS_KEY_"}
    }
}

local mask_text = test_masking(integrated_patterns)
local test_passed = 0
local test_failed = 0

for _, test in ipairs(test_cases) do
    local masked, count = mask_text(test.input)
    local passed = true
    
    -- 원본 텍스트가 남아있으면 실패
    for pattern in test.input:gmatch("%S+") do
        if pattern:match("^[0-9]{12}$") or 
           pattern:match("^i%-[0-9a-f]+$") or
           pattern:match("^vpc%-[0-9a-f]+$") or
           pattern:match("^AKIA[A-Z0-9]+$") then
            if masked:find(pattern, 1, true) then
                passed = false
                break
            end
        end
    end
    
    -- 예상 마스킹 확인
    for _, expected in ipairs(test.expected_masked) do
        if not masked:find(expected, 1, true) then
            passed = false
            break
        end
    end
    
    if passed then
        test_passed = test_passed + 1
        print(string.format("✅ %s: PASS", test.name))
    else
        test_failed = test_failed + 1
        print(string.format("❌ %s: FAIL", test.name))
        print("    Input: " .. test.input)
        print("    Output: " .. masked)
    end
end

print(string.format("\n테스트 결과: %d/%d 통과", test_passed, #test_cases))

-- 최종 결과
print("\n=======================================")
print("📢 최종 결과")
print("=======================================")

if success and test_failed == 0 then
    print("✅ Kong 통합 성공!")
    print(string.format("   - 통합 패턴: %d개", #integrated_patterns))
    print(string.format("   - Critical 패턴: %d개", critical_count))
    print("   - 모든 테스트 통과")
    print("\n🎆 Phase 4 - 1단계 완료!")
    os.exit(0)
else
    print("❌ Kong 통합 실패")
    if #errors > 0 then
        print("\n오류:")
        for _, err in ipairs(errors) do
            print("  - " .. err)
        end
    end
    os.exit(1)
end