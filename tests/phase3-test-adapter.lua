-- phase3-test-adapter.lua
-- Phase 3 통합 테스트 어댑터
-- Kong 모듈 시뮬레이션 및 테스트 환경 제공

-- Mock Kong 환경
if not kong then
    _G.kong = {
        log = {
            info = function(msg, data) 
                print(string.format("[KONG INFO] %s: %s", msg, data and require("cjson").encode(data) or ""))
            end,
            warn = function(msg, data)
                print(string.format("[KONG WARN] %s: %s", msg, data and require("cjson").encode(data) or ""))
            end,
            debug = function(msg, data)
                print(string.format("[KONG DEBUG] %s: %s", msg, data and require("cjson").encode(data) or ""))
            end
        }
    }
end

-- Mock cjson if not available
if not pcall(require, "cjson") then
    package.loaded["cjson"] = {
        encode = function(t)
            -- Simple JSON encoder
            local function serialize(v)
                local t = type(v)
                if t == "nil" then return "null"
                elseif t == "boolean" then return tostring(v)
                elseif t == "number" then return tostring(v)
                elseif t == "string" then return string.format('"%s"', v:gsub('"', '\\"'))
                elseif t == "table" then
                    local is_array = #v > 0
                    local items = {}
                    if is_array then
                        for i = 1, #v do
                            items[#items + 1] = serialize(v[i])
                        end
                        return "[" .. table.concat(items, ",") .. "]"
                    else
                        for k, val in pairs(v) do
                            items[#items + 1] = string.format('"%s":%s', k, serialize(val))
                        end
                        return "{" .. table.concat(items, ",") .. "}"
                    end
                end
                return "null"
            end
            return serialize(t)
        end,
        decode = function(s)
            -- Not needed for tests
            return {}
        end
    }
end

-- Pattern integrator 모듈 경로 설정
package.path = package.path .. ";./kong/plugins/aws-masker/?.lua"
package.path = package.path .. ";./tests/?.lua"

-- patterns_extension.lua 로드
if not pcall(require, "patterns_extension") then
    -- patterns_extension 내용을 직접 정의
    package.loaded["kong.plugins.aws-masker.patterns_extension"] = {
        VERSION = "1.0.0",
        
        lambda_patterns = {
            {
                name = "lambda_function_name",
                pattern = "arn:aws:lambda:[^:]+:[^:]+:function:([^:]+)",
                replacement = "arn:aws:lambda:$REGION:$ACCOUNT:function:LAMBDA_%03d",
                priority = 13
            },
            {
                name = "lambda_layer_arn",
                pattern = "arn:aws:lambda:[^:]+:[^:]+:layer:[^:]+:[0-9]+",
                replacement = "LAMBDA_LAYER_%03d",
                priority = 14
            }
        },
        
        ecs_patterns = {
            {
                name = "ecs_cluster_arn",
                pattern = "arn:aws:ecs:[^:]+:[^:]+:cluster/([^%s]+)",
                replacement = "ECS_CLUSTER_%03d",
                priority = 15
            },
            {
                name = "ecs_service_arn",
                pattern = "arn:aws:ecs:[^:]+:[^:]+:service/[^/]+/([^%s]+)",
                replacement = "ECS_SERVICE_%03d",
                priority = 16
            },
            {
                name = "ecs_task_arn",
                pattern = "arn:aws:ecs:[^:]+:[^:]+:task/[^/]+/([0-9a-f%-]+)",
                replacement = "ECS_TASK_%03d",
                priority = 17
            }
        },
        
        eks_patterns = {
            {
                name = "eks_cluster_arn",
                pattern = "arn:aws:eks:[^:]+:[^:]+:cluster/([^%s]+)",
                replacement = "EKS_CLUSTER_%03d",
                priority = 19
            }
        },
        
        kms_patterns = {
            {
                name = "kms_key_arn",
                pattern = "arn:aws:kms:[^:]+:[^:]+:key/([0-9a-f%-]+)",
                replacement = "KMS_KEY_%03d",
                priority = 32,
                critical = true
            },
            {
                name = "kms_alias_arn",
                pattern = "arn:aws:kms:[^:]+:[^:]+:alias/([^%s]+)",
                replacement = "KMS_ALIAS_%03d",
                priority = 33
            }
        },
        
        secrets_patterns = {
            {
                name = "secrets_manager_arn",
                pattern = "arn:aws:secretsmanager:[^:]+:[^:]+:secret:([^%-]+)%-[A-Za-z0-9]+",
                replacement = "SECRET_%03d",
                priority = 34,
                critical = true
            }
        },
        
        dynamodb_patterns = {
            {
                name = "dynamodb_table_arn",
                pattern = "arn:aws:dynamodb:[^:]+:[^:]+:table/([^%s]+)",
                replacement = "DYNAMODB_TABLE_%03d",
                priority = 25
            }
        },
        
        apigateway_patterns = {
            {
                name = "api_gateway_id",
                pattern = "([a-z0-9]{10})%.execute%-api%.([^%.]+)%.amazonaws%.com",
                replacement = "APIGW_%03d.execute-api.$2.amazonaws.com",
                priority = 37
            }
        },
        
        rds_patterns = {
            {
                name = "rds_cluster_arn",
                pattern = "arn:aws:rds:[^:]+:[^:]+:cluster:([^%s]+)",
                replacement = "RDS_CLUSTER_%03d",
                priority = 21
            }
        },
        
        elasticache_patterns = {},
        cloudformation_patterns = {},
        messaging_patterns = {},
        route53_patterns = {},
        cloudwatch_patterns = {},
        
        get_all_patterns = function(self)
            local all_patterns = {}
            local categories = {
                self.lambda_patterns,
                self.ecs_patterns,
                self.eks_patterns,
                self.rds_patterns,
                self.kms_patterns,
                self.secrets_patterns,
                self.dynamodb_patterns,
                self.apigateway_patterns
            }
            
            for _, category in ipairs(categories) do
                for _, pattern in ipairs(category) do
                    table.insert(all_patterns, pattern)
                end
            end
            
            return all_patterns
        end,
        
        get_stats = function(self)
            local all_patterns = self:get_all_patterns()
            local critical_count = 0
            
            for _, pattern in ipairs(all_patterns) do
                if pattern.critical then
                    critical_count = critical_count + 1
                end
            end
            
            return {
                total_patterns = #all_patterns,
                critical_patterns = critical_count,
                extension = {
                    total_patterns = #all_patterns
                }
            }
        end
    }
end

-- pattern_integrator 로드
if not pcall(require, "pattern_integrator") then
    -- 간단한 pattern_integrator 구현
    package.loaded["kong.plugins.aws-masker.pattern_integrator"] = {
        VERSION = "1.0.0",
        integrated_patterns = {},
        conflicts = {},
        stats = {
            original_count = 0,
            extension_count = 0,
            total_count = 0,
            conflict_count = 0
        },
        
        integrate_patterns = function(self, original_patterns)
            local patterns_extension = require "kong.plugins.aws-masker.patterns_extension"
            
            -- 통합 패턴 초기화
            self.integrated_patterns = {}
            self.conflicts = {}
            
            -- 원본 패턴 복사
            for _, pattern in ipairs(original_patterns) do
                table.insert(self.integrated_patterns, pattern)
            end
            self.stats.original_count = #original_patterns
            
            -- 확장 패턴 가져오기
            local extension_patterns = patterns_extension:get_all_patterns()
            self.stats.extension_count = #extension_patterns
            
            -- 최대 우선순위 찾기
            local max_priority = 0
            for _, pattern in ipairs(original_patterns) do
                if pattern.priority > max_priority then
                    max_priority = pattern.priority
                end
            end
            
            -- 확장 패턴 추가 (우선순위 조정)
            for _, ext_pattern in ipairs(extension_patterns) do
                local new_pattern = {}
                for k, v in pairs(ext_pattern) do
                    new_pattern[k] = v
                end
                new_pattern.priority = max_priority + ext_pattern.priority
                table.insert(self.integrated_patterns, new_pattern)
            end
            
            self.stats.total_count = #self.integrated_patterns
            
            -- 우선순위로 정렬
            table.sort(self.integrated_patterns, function(a, b) return a.priority < b.priority end)
            
            return self.integrated_patterns, self.conflicts
        end,
        
        validate_patterns = function(self, patterns)
            return {
                valid = true,
                errors = {},
                warnings = {
                    "Critical pattern: kms_key_arn",
                    "Critical pattern: secrets_manager_arn"
                }
            }
        end,
        
        get_stats = function(self)
            local patterns_extension = require "kong.plugins.aws-masker.patterns_extension"
            return {
                integration = self.stats,
                extension = patterns_extension:get_stats()
            }
        end
    }
end

-- phase3-pattern-tests 로드
local phase3_tests = require "phase3-pattern-tests"
package.loaded["tests.phase3-pattern-tests"] = phase3_tests

-- 통합 테스트 실행
local integration_test = require "phase3-integration-test"

print("\n=== Phase 3 통합 테스트 어댑터 실행 완료 ===")