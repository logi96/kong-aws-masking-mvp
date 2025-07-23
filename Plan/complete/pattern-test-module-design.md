# Pattern Test Module Design & Implementation

## 🧪 테스트 모듈 설계 (TEST MODULE DESIGN)

### 목표 (GOAL)
실제 AWS 데이터를 시뮬레이션하여 패턴 매칭 정확도 검증 및 false positive/negative 방지

### 측정 기준 (METRIC)
- 패턴 매칭 정확도: 95% 이상
- False positive rate: 5% 미만
- 처리 성능: 1MB JSON < 100ms
- 메모리 사용량: 50MB 미만

## 📋 테스트 모듈 구현

### 4.1 패턴 테스트 프레임워크
**파일**: `/tests/pattern-matcher-test.lua`

```lua
local pattern_tester = {}
local masker_v2 = require "kong.plugins.aws-masker.masker_v2"
local cjson = require "cjson"

-- 테스트 케이스 데이터
local test_cases = {
    -- EC2 인스턴스 테스트
    ec2_instances = {
        valid = {
            "i-1234567890abcdef0",  -- 17자리
            "i-12345678",           -- 8자리 (구형)
            "i-abcdef1234567890"    -- 17자리 hex
        },
        invalid = {
            "instance-123",         -- 잘못된 형식
            "i-12345",              -- 너무 짧음
            "i-1234567890abcdef01234"  -- 너무 길음
        },
        context_samples = {
            valid_contexts = {
                '{"Instances": [{"InstanceId": "i-1234567890abcdef0"}]}',
                '{"Instance": "i-12345678"}',
                '"InstanceId": "i-abcdef1234567890"'
            },
            invalid_contexts = {
                '{"Description": "This i-1234567890abcdef0 is mentioned"}',  -- 설명 텍스트
                '{"UserData": "echo i-12345678"}',  -- 스크립트 내용
            }
        }
    },
    
    -- S3 버킷 테스트
    s3_buckets = {
        valid = {
            "my-app-bucket-2024",
            "production.logs.bucket",
            "test-bucket-123"
        },
        invalid = {
            "MyBucket",             -- 대문자 포함
            "bucket..name",         -- 연속 점
            "192.168.1.1",          -- IP 주소 형식
            "ab"                    -- 너무 짧음
        },
        context_samples = {
            valid_contexts = {
                's3://my-app-bucket-2024/path/file.txt',
                '{"Bucket": "production.logs.bucket"}',
                'arn:aws:s3:::test-bucket-123'
            },
            invalid_contexts = {
                '{"Description": "Store data in my-app-bucket-2024"}',  -- 설명 텍스트
            }
        }
    },
    
    -- AWS Account ID 테스트
    aws_accounts = {
        valid = {
            "123456789012",         -- 표준 12자리
            "999999999999"
        },
        invalid = {
            "12345678901",          -- 11자리
            "1234567890123",        -- 13자리
            "abcd56789012"          -- 숫자 아님
        },
        context_samples = {
            valid_contexts = {
                'arn:aws:iam::123456789012:role/MyRole',
                '{"Account": "999999999999"}'
            },
            invalid_contexts = {
                '{"PhoneNumber": "123456789012"}',  -- 전화번호일 수 있음
                '{"TransactionId": "999999999999"}'  -- 다른 12자리 ID
            }
        }
    },
    
    -- Private IP 테스트
    private_ips = {
        valid = {
            "10.0.1.100",
            "172.16.0.1", 
            "192.168.1.1"
        },
        invalid = {
            "8.8.8.8",              -- 공인 IP
            "127.0.0.1",            -- 로컬호스트
            "172.15.0.1",           -- 172.16-31 범위 외
            "172.32.0.1"            -- 172.16-31 범위 외
        }
    }
}

-- 성능 테스트용 대용량 JSON 생성
function pattern_tester.generate_large_json(size_kb)
    local data = {
        Resources = {},
        Metadata = {
            Timestamp = os.date("%Y-%m-%dT%H:%M:%SZ"),
            Region = "us-east-1"
        }
    }
    
    local target_size = size_kb * 1024
    local current_size = 0
    local resource_id = 1
    
    while current_size < target_size do
        -- 다양한 AWS 리소스 타입 생성
        local resource_types = {
            {
                Type = "EC2::Instance",
                Properties = {
                    InstanceId = "i-" .. string.format("%017x", resource_id),
                    PrivateIpAddress = string.format("10.0.%d.%d", 
                        math.floor(resource_id / 256), resource_id % 256),
                    SecurityGroups = {
                        string.format("sg-%017x", resource_id)
                    }
                }
            },
            {
                Type = "S3::Bucket", 
                Properties = {
                    BucketName = string.format("app-bucket-%d", resource_id),
                    Arn = string.format("arn:aws:s3:::app-bucket-%d", resource_id)
                }
            },
            {
                Type = "RDS::DBInstance",
                Properties = {
                    DBInstanceIdentifier = string.format("mydb-%d", resource_id),
                    VpcId = string.format("vpc-%017x", resource_id)
                }
            }
        }
        
        local resource = resource_types[(resource_id % #resource_types) + 1]
        resource.ResourceId = string.format("resource-%d", resource_id)
        
        table.insert(data.Resources, resource)
        
        -- 현재 크기 추정
        current_size = #cjson.encode(data)
        resource_id = resource_id + 1
    end
    
    return cjson.encode(data)
end

-- 개별 패턴 테스트
function pattern_tester.test_pattern_accuracy(pattern_name, test_data)
    local results = {
        pattern_name = pattern_name,
        total_tests = 0,
        correct_matches = 0,
        false_positives = 0,
        false_negatives = 0,
        accuracy = 0,
        details = {}
    }
    
    -- Valid 케이스 테스트
    for _, test_value in ipairs(test_data.valid or {}) do
        results.total_tests = results.total_tests + 1
        
        local mock_body = cjson.encode({TestValue = test_value})
        local masked_body, context = masker_v2.mask_request(mock_body, {})
        local masked_data = cjson.decode(masked_body)
        
        if masked_data.TestValue ~= test_value then
            -- 마스킹됨 (정상)
            results.correct_matches = results.correct_matches + 1
            table.insert(results.details, {
                input = test_value,
                output = masked_data.TestValue,
                expected = "masked",
                result = "correct"
            })
        else
            -- 마스킹 안됨 (false negative)
            results.false_negatives = results.false_negatives + 1
            table.insert(results.details, {
                input = test_value,
                output = masked_data.TestValue, 
                expected = "masked",
                result = "false_negative"
            })
        end
    end
    
    -- Invalid 케이스 테스트
    for _, test_value in ipairs(test_data.invalid or {}) do
        results.total_tests = results.total_tests + 1
        
        local mock_body = cjson.encode({TestValue = test_value})
        local masked_body, context = masker_v2.mask_request(mock_body, {})
        local masked_data = cjson.decode(masked_body)
        
        if masked_data.TestValue == test_value then
            -- 마스킹 안됨 (정상)
            results.correct_matches = results.correct_matches + 1
            table.insert(results.details, {
                input = test_value,
                output = masked_data.TestValue,
                expected = "unchanged", 
                result = "correct"
            })
        else
            -- 마스킹됨 (false positive)
            results.false_positives = results.false_positives + 1
            table.insert(results.details, {
                input = test_value,
                output = masked_data.TestValue,
                expected = "unchanged",
                result = "false_positive"
            })
        end
    end
    
    -- 컨텍스트 기반 테스트
    if test_data.context_samples then
        -- Valid context 테스트
        for _, context_json in ipairs(test_data.context_samples.valid_contexts or {}) do
            results.total_tests = results.total_tests + 1
            
            local masked_body, context = masker_v2.mask_request(context_json, {})
            local has_masking = masked_body ~= context_json
            
            if has_masking then
                results.correct_matches = results.correct_matches + 1
                table.insert(results.details, {
                    input = context_json,
                    output = masked_body,
                    expected = "context_masked",
                    result = "correct"
                })
            else
                results.false_negatives = results.false_negatives + 1
                table.insert(results.details, {
                    input = context_json,
                    output = masked_body,
                    expected = "context_masked",
                    result = "false_negative"
                })
            end
        end
        
        -- Invalid context 테스트
        for _, context_json in ipairs(test_data.context_samples.invalid_contexts or {}) do
            results.total_tests = results.total_tests + 1
            
            local masked_body, context = masker_v2.mask_request(context_json, {})
            local has_masking = masked_body ~= context_json
            
            if not has_masking then
                results.correct_matches = results.correct_matches + 1
                table.insert(results.details, {
                    input = context_json,
                    output = masked_body,
                    expected = "context_unchanged",
                    result = "correct"
                })
            else
                results.false_positives = results.false_positives + 1
                table.insert(results.details, {
                    input = context_json,
                    output = masked_body,
                    expected = "context_unchanged",
                    result = "false_positive"
                })
            end
        end
    end
    
    -- 정확도 계산
    if results.total_tests > 0 then
        results.accuracy = (results.correct_matches / results.total_tests) * 100
    end
    
    return results
end

-- 성능 테스트
function pattern_tester.test_performance(size_kb)
    local test_json = pattern_tester.generate_large_json(size_kb)
    local start_time = os.clock()
    local start_memory = collectgarbage("count")
    
    -- 마스킹 수행
    local masked_body, context = masker_v2.mask_request(test_json, {})
    
    local end_time = os.clock()
    local end_memory = collectgarbage("count")
    
    -- 언마스킹 수행
    local unmasked_body = masker_v2.unmask_response(masked_body, context)
    
    local final_time = os.clock()
    local final_memory = collectgarbage("count")
    
    return {
        input_size_kb = size_kb,
        input_size_bytes = #test_json,
        masked_count = context.masked_count or 0,
        masking_time_ms = (end_time - start_time) * 1000,
        unmasking_time_ms = (final_time - end_time) * 1000,
        total_time_ms = (final_time - start_time) * 1000,
        memory_used_kb = end_memory - start_memory,
        peak_memory_kb = final_memory,
        performance_score = (#test_json / 1024) / ((final_time - start_time) * 1000) -- KB/ms
    }
end

-- 전체 패턴 테스트 실행
function pattern_tester.run_all_tests()
    local overall_results = {
        timestamp = os.date("%Y-%m-%dT%H:%M:%SZ"),
        pattern_results = {},
        performance_results = {},
        summary = {
            total_patterns_tested = 0,
            patterns_passed = 0,
            overall_accuracy = 0,
            total_false_positives = 0,
            total_false_negatives = 0
        }
    }
    
    -- 각 패턴별 정확도 테스트
    for pattern_name, test_data in pairs(test_cases) do
        local result = pattern_tester.test_pattern_accuracy(pattern_name, test_data)
        table.insert(overall_results.pattern_results, result)
        
        overall_results.summary.total_patterns_tested = overall_results.summary.total_patterns_tested + 1
        overall_results.summary.total_false_positives = overall_results.summary.total_false_positives + result.false_positives
        overall_results.summary.total_false_negatives = overall_results.summary.total_false_negatives + result.false_negatives
        
        if result.accuracy >= 95 then
            overall_results.summary.patterns_passed = overall_results.summary.patterns_passed + 1
        end
    end
    
    -- 성능 테스트 (다양한 크기)
    local performance_sizes = {1, 10, 100, 500, 1024}  -- KB
    for _, size in ipairs(performance_sizes) do
        local perf_result = pattern_tester.test_performance(size)
        table.insert(overall_results.performance_results, perf_result)
    end
    
    -- 전체 정확도 계산
    local total_correct = 0
    local total_tests = 0
    for _, result in ipairs(overall_results.pattern_results) do
        total_correct = total_correct + result.correct_matches
        total_tests = total_tests + result.total_tests
    end
    
    if total_tests > 0 then
        overall_results.summary.overall_accuracy = (total_correct / total_tests) * 100
    end
    
    return overall_results
end

-- 테스트 결과 출력
function pattern_tester.print_results(results)
    print("==========================================")
    print("AWS Masking Pattern Test Results")
    print("==========================================")
    print(string.format("Test Time: %s", results.timestamp))
    print(string.format("Overall Accuracy: %.2f%%", results.summary.overall_accuracy))
    print(string.format("Patterns Passed (≥95%%): %d/%d", 
        results.summary.patterns_passed, results.summary.total_patterns_tested))
    print(string.format("Total False Positives: %d", results.summary.total_false_positives))
    print(string.format("Total False Negatives: %d", results.summary.total_false_negatives))
    print("")
    
    -- 패턴별 상세 결과
    print("Pattern-by-Pattern Results:")
    print("------------------------------------------")
    for _, result in ipairs(results.pattern_results) do
        local status = result.accuracy >= 95 and "✅ PASS" or "❌ FAIL"
        print(string.format("%s %s: %.2f%% (%d/%d)", 
            status, result.pattern_name, result.accuracy, 
            result.correct_matches, result.total_tests))
        
        if result.accuracy < 95 then
            print(string.format("  False Positives: %d", result.false_positives))
            print(string.format("  False Negatives: %d", result.false_negatives))
        end
    end
    print("")
    
    -- 성능 결과
    print("Performance Test Results:")
    print("------------------------------------------")
    for _, perf in ipairs(results.performance_results) do
        local status = perf.total_time_ms < 100 and "✅" or "⚠️"
        print(string.format("%s %dKB: %.2fms (masked %d items, %.2f KB/ms)", 
            status, perf.input_size_kb, perf.total_time_ms, 
            perf.masked_count, perf.performance_score))
    end
end

-- 상세 실패 케이스 분석
function pattern_tester.analyze_failures(results)
    print("\n==========================================")
    print("Failure Analysis")
    print("==========================================")
    
    for _, result in ipairs(results.pattern_results) do
        if result.accuracy < 95 then
            print(string.format("\n❌ %s (%.2f%% accuracy):", result.pattern_name, result.accuracy))
            
            for _, detail in ipairs(result.details) do
                if detail.result ~= "correct" then
                    print(string.format("  %s: '%s' → '%s' (expected: %s)", 
                        detail.result, detail.input, detail.output, detail.expected))
                end
            end
        end
    end
end

return pattern_tester
```

### 4.2 실행 가능한 테스트 스크립트
**파일**: `/tests/run-pattern-tests.lua`

```lua
#!/usr/bin/env lua

-- Kong 환경 시뮬레이션을 위한 mock
local mock_kong = {
    log = {
        info = function(msg, data) 
            print(string.format("[INFO] %s: %s", msg, require("cjson").encode(data or {})))
        end,
        warn = function(msg, data)
            print(string.format("[WARN] %s: %s", msg, require("cjson").encode(data or {})))
        end,
        debug = function(msg, data)
            -- print(string.format("[DEBUG] %s: %s", msg, require("cjson").encode(data or {})))
        end
    }
}

-- 전역 kong 객체 설정 (테스트용)
_G.kong = mock_kong

-- ngx 시뮬레이션
_G.ngx = {
    now = function() return os.clock() end,
    var = { request_id = "test-" .. tostring(os.time()) }
}

-- 패턴 테스터 로드
local pattern_tester = require "tests.pattern-matcher-test"

-- 메인 실행
function main()
    print("Starting AWS Masking Pattern Tests...")
    print("=====================================")
    
    -- 전체 테스트 실행
    local results = pattern_tester.run_all_tests()
    
    -- 결과 출력
    pattern_tester.print_results(results)
    
    -- 실패 케이스 분석
    if results.summary.overall_accuracy < 95 then
        pattern_tester.analyze_failures(results)
    end
    
    -- JSON 파일로 저장
    local cjson = require "cjson"
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("pattern_test_results_%s.json", timestamp)
    
    local file = io.open(filename, "w")
    if file then
        file:write(cjson.encode(results))
        file:close()
        print(string.format("\nDetailed results saved to: %s", filename))
    end
    
    -- 종료 상태 코드
    if results.summary.overall_accuracy >= 95 then
        print("\n🎉 All pattern tests passed!")
        os.exit(0)
    else
        print("\n❌ Some pattern tests failed. Review the analysis above.")
        os.exit(1)  
    end
end

-- 실행
main()
```

### 4.3 실시간 테스트 웹 인터페이스
**파일**: `/tests/pattern-test-web.lua`

```lua
local pattern_tester = require "tests.pattern-matcher-test"
local masker_v2 = require "kong.plugins.aws-masker.masker_v2"
local cjson = require "cjson"

-- 간단한 HTTP 서버 (OpenResty 기반)
local function start_test_server()
    local server = require "resty.http.server"
    
    server.new({
        host = "127.0.0.1",
        port = 8080
    }):start(function(req, res)
        
        if req.path == "/test" and req.method == "POST" then
            -- 실시간 패턴 테스트 API
            local body = req:read_body()
            local data = cjson.decode(body)
            
            local test_input = data.input or ""
            local expected_behavior = data.expected or "auto"
            
            -- 마스킹 테스트 수행
            local start_time = os.clock()
            local masked_body, context = masker_v2.mask_request(test_input, {})
            local unmasked_body = masker_v2.unmask_response(masked_body, context)
            local end_time = os.clock()
            
            local result = {
                input = test_input,
                masked = masked_body,
                unmasked = unmasked_body,
                is_modified = (test_input ~= masked_body),
                processing_time_ms = (end_time - start_time) * 1000,
                masked_count = context.masked_count or 0,
                roundtrip_success = (test_input == unmasked_body)
            }
            
            res:json(result)
            
        elseif req.path == "/batch-test" and req.method == "POST" then
            -- 배치 테스트 실행
            local results = pattern_tester.run_all_tests()
            res:json(results)
            
        elseif req.path == "/" then
            -- 테스트 웹 UI
            res:send([[
<!DOCTYPE html>
<html>
<head>
    <title>AWS Pattern Masking Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .test-section { margin: 20px 0; }
        textarea { width: 100%; height: 200px; font-family: monospace; }
        button { padding: 10px 20px; margin: 5px; }
        .result { background: #f5f5f5; padding: 15px; margin: 10px 0; border-left: 4px solid #007cba; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
        pre { white-space: pre-wrap; word-break: break-all; }
    </style>
</head>
<body>
    <div class="container">
        <h1>AWS Pattern Masking Test Interface</h1>
        
        <div class="test-section">
            <h2>Real-time Pattern Test</h2>
            <textarea id="input" placeholder="Enter JSON or text to test masking patterns...">
{
  "InstanceId": "i-1234567890abcdef0",
  "PrivateIpAddress": "10.0.1.100", 
  "S3Bucket": "my-app-logs-bucket",
  "ARN": "arn:aws:iam::123456789012:role/MyRole"
}
            </textarea>
            <br>
            <button onclick="runSingleTest()">Test Masking</button>
            <button onclick="runBatchTest()">Run All Pattern Tests</button>
            <button onclick="clearResults()">Clear Results</button>
        </div>
        
        <div id="results"></div>
    </div>

    <script>
    async function runSingleTest() {
        const input = document.getElementById('input').value;
        const resultsDiv = document.getElementById('results');
        
        try {
            const response = await fetch('/test', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ input: input })
            });
            
            const result = await response.json();
            
            let statusClass = 'result';
            let statusText = 'Modified';
            if (result.is_modified) {
                statusClass += ' success';
            } else {
                statusClass += ' warning';
                statusText = 'Unchanged';
            }
            
            resultsDiv.innerHTML = `
                <div class="${statusClass}">
                    <h3>Test Result: ${statusText}</h3>
                    <p><strong>Processing Time:</strong> ${result.processing_time_ms.toFixed(2)}ms</p>
                    <p><strong>Items Masked:</strong> ${result.masked_count}</p>
                    <p><strong>Roundtrip Success:</strong> ${result.roundtrip_success ? '✅ Yes' : '❌ No'}</p>
                    
                    <h4>Original Input:</h4>
                    <pre>${result.input}</pre>
                    
                    <h4>Masked Output:</h4>
                    <pre>${result.masked}</pre>
                    
                    <h4>Unmasked Output:</h4>
                    <pre>${result.unmasked}</pre>
                </div>
            `;
        } catch (error) {
            resultsDiv.innerHTML = `<div class="result error"><h3>Error</h3><pre>${error.message}</pre></div>`;
        }
    }
    
    async function runBatchTest() {
        const resultsDiv = document.getElementById('results');
        resultsDiv.innerHTML = '<div class="result">Running comprehensive pattern tests...</div>';
        
        try {
            const response = await fetch('/batch-test', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            
            const results = await response.json();
            
            let html = `
                <div class="result ${results.summary.overall_accuracy >= 95 ? 'success' : 'error'}">
                    <h3>Batch Test Results</h3>
                    <p><strong>Overall Accuracy:</strong> ${results.summary.overall_accuracy.toFixed(2)}%</p>
                    <p><strong>Patterns Passed:</strong> ${results.summary.patterns_passed}/${results.summary.total_patterns_tested}</p>
                    <p><strong>False Positives:</strong> ${results.summary.total_false_positives}</p>
                    <p><strong>False Negatives:</strong> ${results.summary.total_false_negatives}</p>
                    
                    <h4>Pattern Results:</h4>
                    <ul>
            `;
            
            results.pattern_results.forEach(result => {
                const status = result.accuracy >= 95 ? '✅' : '❌';
                html += `<li>${status} ${result.pattern_name}: ${result.accuracy.toFixed(2)}% (${result.correct_matches}/${result.total_tests})</li>`;
            });
            
            html += `
                    </ul>
                    
                    <h4>Performance Results:</h4>
                    <ul>
            `;
            
            results.performance_results.forEach(perf => {
                const status = perf.total_time_ms < 100 ? '✅' : '⚠️';
                html += `<li>${status} ${perf.input_size_kb}KB: ${perf.total_time_ms.toFixed(2)}ms (${perf.masked_count} items)</li>`;
            });
            
            html += '</ul></div>';
            
            resultsDiv.innerHTML = html;
            
        } catch (error) {
            resultsDiv.innerHTML = `<div class="result error"><h3>Error</h3><pre>${error.message}</pre></div>`;
        }
    }
    
    function clearResults() {
        document.getElementById('results').innerHTML = '';
    }
    </script>
</body>
</html>
            ]])
        else
            res:status(404):send("Not Found")
        end
    end)
    
    print("Pattern test server started at http://127.0.0.1:8080")
    print("  - Interactive UI: http://127.0.0.1:8080/")
    print("  - Single test API: POST http://127.0.0.1:8080/test")  
    print("  - Batch test API: POST http://127.0.0.1:8080/batch-test")
end

-- 서버 시작
start_test_server()
```

이 테스트 모듈을 사용하면:

1. **명령줄에서 실행**: `lua tests/run-pattern-tests.lua`
2. **웹 브라우저에서 테스트**: http://127.0.0.1:8080
3. **실시간 패턴 검증**: JSON 입력 후 즉시 결과 확인
4. **성능 벤치마크**: 다양한 크기의 데이터로 성능 측정
5. **정확도 분석**: false positive/negative 상세 분석

테스트 결과는 JSON 파일로 저장되어 추후 분석과 비교가 가능합니다.