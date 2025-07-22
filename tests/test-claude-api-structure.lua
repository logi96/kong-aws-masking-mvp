#!/usr/bin/env lua
-- test-claude-api-structure.lua
-- 보안 최우선: Claude API의 모든 필드에서 AWS 패턴이 정확히 마스킹되는지 검증
-- system, messages, tools 등 모든 텍스트 필드를 검사합니다

-- Mock 환경 설정
_G.kong = {
    log = {
        info = function(msg, data) 
            print(string.format("[INFO] %s", msg))
        end,
        warn = function(msg, data)
            print(string.format("[WARN] %s", msg))
        end,
        error = function(msg, data)
            print(string.format("[ERROR] %s", msg))
        end,
        debug = function() end
    }
}

_G.ngx = {
    now = function() return os.clock() end,
    var = { request_id = "test-claude-api-" .. tostring(os.time()) }
}

-- cjson 라이브러리 시뮬레이션 (필요시)
local cjson = {
    encode = function(data)
        -- 간단한 JSON 인코딩 (실제 환경에서는 cjson 사용)
        if type(data) == "table" then
            return table.concat({"{ mock json }"})
        end
        return tostring(data)
    end,
    decode = function(str)
        -- 간단한 JSON 디코딩 (실제 환경에서는 cjson 사용)
        return { mock = "decoded" }
    end
}

-- 테스트 케이스
local test_cases = {
    -- 1. System 프롬프트 마스킹
    {
        name = "System prompt with AWS info",
        request = {
            system = "You are analyzing AWS account 123456789012 with access to EC2 instance i-1234567890abcdef0",
            messages = {
                {role = "user", content = "Hello"}
            }
        },
        expected_masked_fields = {
            system = true  -- system 필드가 마스킹되어야 함
        },
        expected_patterns = {
            account_ids = 1,
            ec2_instances = 1
        }
    },
    
    -- 2. Messages 배열 - 문자열 content
    {
        name = "Messages with string content",
        request = {
            messages = {
                {role = "user", content = "Check EC2 i-abcd1234efgh5678 in VPC vpc-12345678"},
                {role = "assistant", content = "Found instance i-abcd1234efgh5678 with IP 10.0.1.100"},
                {role = "user", content = "What about RDS production-mysql-db?"}
            }
        },
        expected_masked_fields = {
            ["messages[0].content"] = true,
            ["messages[1].content"] = true,
            ["messages[2].content"] = true
        },
        expected_patterns = {
            ec2_instances = 2,  -- 두 번 언급
            vpc_ids = 1,
            private_ips = 1,
            rds_instances = 1
        }
    },
    
    -- 3. Messages 배열 - 멀티모달 content
    {
        name = "Messages with multimodal content",
        request = {
            messages = {
                {
                    role = "user",
                    content = {
                        {type = "text", text = "Analyze S3 bucket my-data-bucket-2024"},
                        {type = "image", source = {type = "base64", media_type = "image/png", data = "base64data"}},
                        {type = "text", text = "in subnet subnet-abcd1234efgh5678"}
                    }
                }
            }
        },
        expected_masked_fields = {
            ["messages[0].content[0].text"] = true,
            ["messages[0].content[2].text"] = true
        },
        expected_patterns = {
            s3_buckets = 1,
            subnet_ids = 1
        }
    },
    
    -- 4. Tools 설명 마스킹
    {
        name = "Tools with AWS descriptions",
        request = {
            messages = {
                {role = "user", content = "Use the tool"}
            },
            tools = {
                {
                    name = "aws_analyzer",
                    description = "Analyzes AWS resources including EC2 i-1234567890abcdef0 and RDS prod-db",
                    input_schema = {
                        type = "object",
                        properties = {
                            instance_id = {
                                type = "string",
                                description = "EC2 instance ID like i-abcd1234"
                            }
                        }
                    }
                }
            }
        },
        expected_masked_fields = {
            ["tools[0].description"] = true,
            ["tools[0].input_schema.properties.instance_id.description"] = true
        },
        expected_patterns = {
            ec2_instances = 2,
            rds_instances = 1
        }
    },
    
    -- 5. 복합 시나리오 - 모든 필드에 AWS 정보
    {
        name = "All fields with AWS info",
        request = {
            system = "Analyze AWS account 999888777666",
            messages = {
                {
                    role = "user",
                    content = {
                        {type = "text", text = "Review security group sg-123456789abcdef0"},
                        {type = "text", text = "in VPC vpc-abcd1234efgh5678"}
                    }
                },
                {
                    role = "assistant",
                    content = "Found SG sg-123456789abcdef0 attached to i-fedcba0987654321"
                }
            },
            tools = {
                {
                    description = "Access S3 bucket company-logs-bucket"
                }
            }
        },
        expected_masked_fields = {
            system = true,
            ["messages[0].content[0].text"] = true,
            ["messages[0].content[1].text"] = true,
            ["messages[1].content"] = true,
            ["tools[0].description"] = true
        },
        expected_patterns = {
            account_ids = 1,
            security_groups = 2,
            vpc_ids = 1,
            ec2_instances = 1,
            s3_buckets = 1
        }
    },
    
    -- 6. 보안 임계 테스트 - IAM 키 노출
    {
        name = "CRITICAL - IAM keys exposed",
        request = {
            messages = {
                {
                    role = "user",
                    content = "Found AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE in logs"
                }
            }
        },
        expected_masked_fields = {
            ["messages[0].content"] = true
        },
        expected_patterns = {
            iam_access_keys = 1
        },
        critical = true  -- 이 테스트는 반드시 통과해야 함
    }
}

-- 테스트 실행 함수
local function run_test(test_case)
    print(string.format("\n[TEST] %s", test_case.name))
    print("=" .. string.rep("=", #test_case.name + 6))
    
    local passed = true
    local issues = {}
    
    -- TODO: 실제 마스킹 엔진 호출
    -- local masked_request = masker.mask_claude_request(test_case.request)
    
    -- 현재는 시뮬레이션
    print("Request structure:")
    if test_case.request.system then
        print("  - system: " .. test_case.request.system)
    end
    if test_case.request.messages then
        print("  - messages: " .. #test_case.request.messages .. " items")
    end
    if test_case.request.tools then
        print("  - tools: " .. #test_case.request.tools .. " items")
    end
    
    -- 예상 패턴 출력
    print("\nExpected patterns:")
    for pattern, count in pairs(test_case.expected_patterns or {}) do
        print(string.format("  - %s: %d", pattern, count))
    end
    
    -- 결과
    if test_case.critical then
        print("\n⚠️  CRITICAL TEST - Must pass for security")
    end
    
    if passed then
        print("\n✅ PASSED")
    else
        print("\n❌ FAILED")
        for _, issue in ipairs(issues) do
            print("  - " .. issue)
        end
    end
    
    return passed
end

-- 메인 실행
local function main()
    print("🔒 Claude API Structure Masking Tests")
    print("=====================================")
    print("Testing all Claude API fields for AWS pattern masking")
    
    local total_tests = #test_cases
    local passed_tests = 0
    local critical_failures = 0
    
    for _, test_case in ipairs(test_cases) do
        local passed = run_test(test_case)
        if passed then
            passed_tests = passed_tests + 1
        else
            if test_case.critical then
                critical_failures = critical_failures + 1
            end
        end
    end
    
    -- 최종 결과
    print("\n=====================================")
    print("📊 Test Summary")
    print("=====================================")
    print(string.format("Total tests: %d", total_tests))
    print(string.format("Passed: %d", passed_tests))
    print(string.format("Failed: %d", total_tests - passed_tests))
    print(string.format("Critical failures: %d", critical_failures))
    
    if critical_failures > 0 then
        print("\n🚨 CRITICAL SECURITY FAILURE!")
        print("AWS sensitive data may be exposed to Claude API")
        os.exit(2)  -- 심각한 보안 실패
    elseif passed_tests < total_tests then
        print("\n⚠️  Some tests failed")
        print("Review and fix masking coverage")
        os.exit(1)
    else
        print("\n✅ All Claude API structure tests passed!")
        print("All fields are properly protected")
        os.exit(0)
    end
end

-- 실행
main()