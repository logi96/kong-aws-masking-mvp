-- phase3-pattern-tests.lua
-- Phase 3: 확장 패턴 테스트 케이스
-- 보안 최우선: 모든 AWS 서비스 패턴의 정확한 마스킹 검증

local phase3_test_cases = {
    -- Lambda 패턴 테스트
    lambda_tests = {
        {
            name = "Lambda function ARN",
            input = "Invoking arn:aws:lambda:us-east-1:123456789012:function:myFunction",
            expected_patterns = {
                lambda_function_name = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"myFunction", "123456789012"}
        },
        {
            name = "Lambda layer ARN",
            input = "Using layer arn:aws:lambda:us-west-2:987654321098:layer:myLayer:42",
            expected_patterns = {
                lambda_layer_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"myLayer", "987654321098"}
        }
    },
    
    -- ECS 패턴 테스트
    ecs_tests = {
        {
            name = "ECS cluster ARN",
            input = "Cluster arn:aws:ecs:us-east-1:123456789012:cluster/production-cluster",
            expected_patterns = {
                ecs_cluster_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"production-cluster"}
        },
        {
            name = "ECS service ARN",
            input = "Service arn:aws:ecs:us-east-1:123456789012:service/prod-cluster/web-service",
            expected_patterns = {
                ecs_service_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"web-service", "prod-cluster"}
        },
        {
            name = "ECS task ARN",
            input = "Task arn:aws:ecs:us-east-1:123456789012:task/prod-cluster/1234567890abcdef",
            expected_patterns = {
                ecs_task_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"1234567890abcdef"}
        }
    },
    
    -- EKS 패턴 테스트
    eks_tests = {
        {
            name = "EKS cluster ARN",
            input = "EKS cluster arn:aws:eks:us-west-2:123456789012:cluster/prod-k8s-cluster",
            expected_patterns = {
                eks_cluster_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"prod-k8s-cluster"}
        }
    },
    
    -- KMS 패턴 테스트 (Critical)
    kms_tests = {
        {
            name = "KMS key ARN",
            input = "Encryption key arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012",
            expected_patterns = {
                kms_key_arn = 1,
                aws_account_standalone = 1
            },
            critical = true,
            masked_should_not_contain = {"12345678-1234-1234-1234-123456789012"}
        },
        {
            name = "KMS alias ARN",
            input = "Key alias arn:aws:kms:us-east-1:123456789012:alias/prod-encryption-key",
            expected_patterns = {
                kms_alias_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"prod-encryption-key"}
        }
    },
    
    -- Secrets Manager 패턴 테스트 (Critical)
    secrets_tests = {
        {
            name = "Secrets Manager ARN",
            input = "Secret arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db/password-AbCdEf",
            expected_patterns = {
                secrets_manager_arn = 1,
                aws_account_standalone = 1
            },
            critical = true,
            masked_should_not_contain = {"prod/db/password", "AbCdEf"}
        }
    },
    
    -- DynamoDB 패턴 테스트
    dynamodb_tests = {
        {
            name = "DynamoDB table ARN",
            input = "Table arn:aws:dynamodb:us-east-1:123456789012:table/UserSessions",
            expected_patterns = {
                dynamodb_table_arn = 1,
                aws_account_standalone = 1
            },
            masked_should_not_contain = {"UserSessions"}
        }
    },
    
    -- API Gateway 패턴 테스트
    apigateway_tests = {
        {
            name = "API Gateway endpoint",
            input = "API endpoint: https://abc123def4.execute-api.us-east-1.amazonaws.com/prod",
            expected_patterns = {
                api_gateway_id = 1
            },
            masked_should_not_contain = {"abc123def4"}
        }
    },
    
    -- 복합 시나리오 테스트
    complex_scenarios = {
        {
            name = "Multi-service infrastructure",
            input = [[
Deploying application with:
- Lambda: arn:aws:lambda:us-east-1:123456789012:function:api-handler
- ECS Service: arn:aws:ecs:us-east-1:123456789012:service/prod/web-app
- RDS: arn:aws:rds:us-east-1:123456789012:cluster:prod-mysql-cluster
- S3: s3://my-app-bucket-2024/static/
- DynamoDB: arn:aws:dynamodb:us-east-1:123456789012:table/Sessions
- KMS: arn:aws:kms:us-east-1:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab
- API Gateway: https://xyz9876543.execute-api.us-east-1.amazonaws.com
Connecting via VPC vpc-1234567890abcdef0 in subnet subnet-abcdef0123456789
            ]],
            expected_patterns = {
                lambda_function_name = 1,
                ecs_service_arn = 1,
                rds_cluster_arn = 1,
                s3_uri = 1,
                dynamodb_table_arn = 1,
                kms_key_arn = 1,
                api_gateway_id = 1,
                vpc_id = 1,
                subnet_id = 1,
                aws_account_standalone = 1  -- 여러 번 나타나지만 같은 계정
            },
            critical = true,  -- KMS 키 포함
            performance_test = true  -- 성능 측정 대상
        }
    },
    
    -- 성능 테스트용 대용량 텍스트
    performance_test = {
        generate_large_text = function(size_kb)
            local services = {
                "arn:aws:lambda:us-east-1:123456789012:function:func-%d",
                "arn:aws:ecs:us-east-1:123456789012:service/cluster/service-%d",
                "arn:aws:eks:us-west-2:123456789012:cluster/k8s-cluster-%d",
                "arn:aws:dynamodb:us-east-1:123456789012:table/Table-%d",
                "s3://bucket-%d-2024/data/",
                "https://api%d.execute-api.us-east-1.amazonaws.com",
                "arn:aws:kms:us-east-1:123456789012:key/%08x-%04x-%04x-%04x-%012x"
            }
            
            local text = "AWS Infrastructure Report\n"
            local current_size = #text
            local target_size = size_kb * 1024
            local index = 1
            
            while current_size < target_size do
                local service = services[(index % #services) + 1]
                local line = string.format("Resource %d: %s\n", index, 
                    string.format(service, index, index, index, index, index, index))
                text = text .. line
                current_size = current_size + #line
                index = index + 1
            end
            
            return {
                input = text,
                size_kb = size_kb,
                expected_min_patterns = index - 1,
                performance_threshold_ms = 100  -- 10KB should process < 100ms
            }
        end
    }
}

-- 테스트 실행 함수
function phase3_test_cases.run_test(test_case, masker_func)
    local start_time = os.clock()
    local masked_text, context = masker_func(test_case.input)
    local end_time = os.clock()
    
    local results = {
        name = test_case.name,
        success = true,
        elapsed_ms = (end_time - start_time) * 1000,
        errors = {}
    }
    
    -- 마스킹 성공 확인
    if not masked_text then
        results.success = false
        table.insert(results.errors, "Masking failed: " .. (context and context.error or "unknown"))
        return results
    end
    
    -- 민감 정보 제거 확인
    if test_case.masked_should_not_contain then
        for _, sensitive in ipairs(test_case.masked_should_not_contain) do
            if masked_text:find(sensitive, 1, true) then
                results.success = false
                table.insert(results.errors, "Sensitive data not masked: " .. sensitive)
            end
        end
    end
    
    -- 패턴 카운트 확인
    if test_case.expected_patterns and context.pattern_stats then
        for pattern, expected_count in pairs(test_case.expected_patterns) do
            local actual_count = context.pattern_stats[pattern] or 0
            if actual_count ~= expected_count then
                results.success = false
                table.insert(results.errors, string.format(
                    "Pattern %s: expected %d, got %d", 
                    pattern, expected_count, actual_count))
            end
        end
    end
    
    -- Critical 패턴 확인
    if test_case.critical and not context.critical_patterns_masked then
        results.success = false
        table.insert(results.errors, "Critical patterns not properly handled")
    end
    
    -- 성능 확인
    if test_case.performance_test and test_case.performance_threshold_ms then
        if results.elapsed_ms > test_case.performance_threshold_ms then
            results.success = false
            table.insert(results.errors, string.format(
                "Performance threshold exceeded: %.2fms > %dms",
                results.elapsed_ms, test_case.performance_threshold_ms))
        end
    end
    
    -- Roundtrip 테스트
    if masker_func.unmask then
        local unmasked = masker_func.unmask(masked_text)
        if unmasked ~= test_case.input then
            results.success = false
            table.insert(results.errors, "Roundtrip test failed")
        end
    end
    
    results.context = context
    return results
end

-- 카테고리별 테스트 실행
function phase3_test_cases.run_category_tests(category_name, test_list, masker_func)
    local results = {
        category = category_name,
        total = 0,
        passed = 0,
        failed = 0,
        critical_failures = 0,
        performance_issues = 0,
        test_results = {}
    }
    
    for _, test_case in ipairs(test_list) do
        results.total = results.total + 1
        local test_result = phase3_test_cases.run_test(test_case, masker_func)
        
        table.insert(results.test_results, test_result)
        
        if test_result.success then
            results.passed = results.passed + 1
        else
            results.failed = results.failed + 1
            if test_case.critical then
                results.critical_failures = results.critical_failures + 1
            end
            if test_result.elapsed_ms > (test_case.performance_threshold_ms or 1000) then
                results.performance_issues = results.performance_issues + 1
            end
        end
    end
    
    results.success_rate = (results.passed / results.total) * 100
    return results
end

-- 전체 Phase 3 테스트 스위트 실행
function phase3_test_cases.run_all_tests(masker_func)
    local overall_results = {
        timestamp = os.date("%Y-%m-%dT%H:%M:%SZ"),
        categories = {},
        summary = {
            total_tests = 0,
            total_passed = 0,
            total_failed = 0,
            critical_failures = 0,
            performance_issues = 0
        }
    }
    
    -- 각 카테고리 테스트 실행
    local test_categories = {
        {name = "Lambda", tests = phase3_test_cases.lambda_tests},
        {name = "ECS", tests = phase3_test_cases.ecs_tests},
        {name = "EKS", tests = phase3_test_cases.eks_tests},
        {name = "KMS", tests = phase3_test_cases.kms_tests},
        {name = "Secrets", tests = phase3_test_cases.secrets_tests},
        {name = "DynamoDB", tests = phase3_test_cases.dynamodb_tests},
        {name = "API Gateway", tests = phase3_test_cases.apigateway_tests},
        {name = "Complex", tests = phase3_test_cases.complex_scenarios}
    }
    
    for _, category in ipairs(test_categories) do
        local category_results = phase3_test_cases.run_category_tests(
            category.name, category.tests, masker_func)
        
        table.insert(overall_results.categories, category_results)
        
        -- 전체 통계 업데이트
        overall_results.summary.total_tests = overall_results.summary.total_tests + category_results.total
        overall_results.summary.total_passed = overall_results.summary.total_passed + category_results.passed
        overall_results.summary.total_failed = overall_results.summary.total_failed + category_results.failed
        overall_results.summary.critical_failures = overall_results.summary.critical_failures + category_results.critical_failures
        overall_results.summary.performance_issues = overall_results.summary.performance_issues + category_results.performance_issues
    end
    
    -- 성능 테스트 실행
    if phase3_test_cases.performance_test then
        local perf_test = phase3_test_cases.performance_test.generate_large_text(10)  -- 10KB
        local perf_result = phase3_test_cases.run_test(perf_test, masker_func)
        
        overall_results.performance_test = {
            size_kb = perf_test.size_kb,
            elapsed_ms = perf_result.elapsed_ms,
            patterns_processed = perf_test.expected_min_patterns,
            throughput_mb_per_sec = (perf_test.size_kb / 1024) / (perf_result.elapsed_ms / 1000),
            success = perf_result.success
        }
    end
    
    overall_results.summary.success_rate = 
        (overall_results.summary.total_passed / overall_results.summary.total_tests) * 100
    
    return overall_results
end

return phase3_test_cases