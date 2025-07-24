-- patterns_extension.lua
-- Phase 3: 추가 AWS 패턴 정의
-- 보안 최우선: 모든 AWS 서비스 리소스 완벽 마스킹

local patterns_extension = {
    VERSION = "1.0.0",
    -- Phase 3에서 추가되는 패턴들
}

-- Lambda 관련 패턴
patterns_extension.lambda_patterns = {
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
}

-- ECS 관련 패턴
patterns_extension.ecs_patterns = {
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
    },
    {
        name = "ecs_task_definition",
        pattern = "arn:aws:ecs:[^:]+:[^:]+:task%-definition/([^:]+):[0-9]+",
        replacement = "ECS_TASKDEF_%03d",
        priority = 18
    }
}

-- EKS 관련 패턴
patterns_extension.eks_patterns = {
    {
        name = "eks_cluster_arn",
        pattern = "arn:aws:eks:[^:]+:[^:]+:cluster/([^%s]+)",
        replacement = "EKS_CLUSTER_%03d",
        priority = 19
    },
    {
        name = "eks_nodegroup_arn",
        pattern = "arn:aws:eks:[^:]+:[^:]+:nodegroup/[^/]+/([^/]+)/[^%s]+",
        replacement = "EKS_NODEGROUP_%03d",
        priority = 20
    }
}

-- RDS 확장 패턴
patterns_extension.rds_patterns = {
    {
        name = "rds_cluster_arn",
        pattern = "arn:aws:rds:[^:]+:[^:]+:cluster:([^%s]+)",
        replacement = "RDS_CLUSTER_%03d",
        priority = 21
    },
    {
        name = "rds_snapshot_arn",
        pattern = "arn:aws:rds:[^:]+:[^:]+:snapshot:([^%s]+)",
        replacement = "RDS_SNAPSHOT_%03d",
        priority = 22
    }
}

-- ElastiCache 패턴
patterns_extension.elasticache_patterns = {
    {
        name = "elasticache_cluster",
        pattern = "([a-z][a-z0-9%-]*cache[a-z0-9%-]*)",
        replacement = "CACHE_%03d",
        priority = 23
    },
    {
        name = "redis_endpoint",
        pattern = "([a-z0-9%-]+)%.([a-z0-9]+)%.cache%.amazonaws%.com",
        replacement = "REDIS_%03d.$2.cache.amazonaws.com",
        priority = 24
    }
}

-- DynamoDB 패턴
patterns_extension.dynamodb_patterns = {
    {
        name = "dynamodb_table_arn",
        pattern = "arn:aws:dynamodb:[^:]+:[^:]+:table/([^%s]+)",
        replacement = "DYNAMODB_TABLE_%03d",
        priority = 25
    },
    {
        name = "dynamodb_stream_arn",
        pattern = "arn:aws:dynamodb:[^:]+:[^:]+:table/[^/]+/stream/([^%s]+)",
        replacement = "DYNAMODB_STREAM_%03d",
        priority = 26
    }
}

-- CloudFormation 패턴
patterns_extension.cloudformation_patterns = {
    {
        name = "cloudformation_stack_arn",
        pattern = "arn:aws:cloudformation:[^:]+:[^:]+:stack/([^/]+)/[^%s]+",
        replacement = "CF_STACK_%03d",
        priority = 27
    },
    {
        name = "cloudformation_stack_id",
        pattern = "arn:aws:cloudformation:[^:]+:[^:]+:stack/[^/]+/([0-9a-f%-]+)",
        replacement = "CF_STACKID_%03d",
        priority = 28
    }
}

-- SNS/SQS 패턴
patterns_extension.messaging_patterns = {
    {
        name = "sns_topic_arn",
        pattern = "arn:aws:sns:[^:]+:[^:]+:([^%s]+)",
        replacement = "SNS_TOPIC_%03d",
        priority = 29
    },
    {
        name = "sqs_queue_arn",
        pattern = "arn:aws:sqs:[^:]+:[^:]+:([^%s]+)",
        replacement = "SQS_QUEUE_%03d",
        priority = 30
    },
    {
        name = "sqs_queue_url",
        pattern = "https://sqs%.([^%.]+)%.amazonaws%.com/([0-9]+)/([^%s]+)",
        replacement = "https://sqs.$1.amazonaws.com/ACCOUNT_%03d/QUEUE_%03d",
        priority = 31
    }
}

-- KMS 패턴
patterns_extension.kms_patterns = {
    {
        name = "kms_key_arn",
        pattern = "arn:aws:kms:[^:]+:[^:]+:key/([0-9a-f%-]+)",
        replacement = "KMS_KEY_%03d",
        priority = 32,
        critical = true  -- KMS 키는 매우 민감함
    },
    {
        name = "kms_alias_arn",
        pattern = "arn:aws:kms:[^:]+:[^:]+:alias/([^%s]+)",
        replacement = "KMS_ALIAS_%03d",
        priority = 33
    }
}

-- Secrets Manager 패턴
patterns_extension.secrets_patterns = {
    {
        name = "secrets_manager_arn",
        pattern = "arn:aws:secretsmanager:[^:]+:[^:]+:secret:([^%-]+)%-[A-Za-z0-9]+",
        replacement = "SECRET_%03d",
        priority = 34,
        critical = true  -- 비밀 정보는 매우 민감함
    }
}

-- Route53 패턴
patterns_extension.route53_patterns = {
    {
        name = "route53_hosted_zone",
        pattern = "/hostedzone/([A-Z0-9]+)",
        replacement = "/hostedzone/ZONE_%03d",
        priority = 35
    },
    {
        name = "route53_health_check",
        pattern = "arn:aws:route53:::healthcheck/([0-9a-f%-]+)",
        replacement = "HEALTHCHECK_%03d",
        priority = 36
    }
}

-- API Gateway 패턴
patterns_extension.apigateway_patterns = {
    {
        name = "api_gateway_id",
        pattern = "([a-z0-9]{10})%.execute%-api%.([^%.]+)%.amazonaws%.com",
        replacement = "APIGW_%03d.execute-api.$2.amazonaws.com",
        priority = 37
    },
    {
        name = "api_gateway_arn",
        pattern = "arn:aws:apigateway:[^:]+::/restapis/([^/]+)",
        replacement = "APIGW_ARN_%03d",
        priority = 38
    }
}

-- CloudWatch 패턴
patterns_extension.cloudwatch_patterns = {
    {
        name = "cloudwatch_log_group",
        pattern = "arn:aws:logs:[^:]+:[^:]+:log%-group:([^:]+)",
        replacement = "LOG_GROUP_%03d",
        priority = 39
    },
    {
        name = "cloudwatch_log_stream",
        pattern = "arn:aws:logs:[^:]+:[^:]+:log%-group:[^:]+:log%-stream:([^%s]+)",
        replacement = "LOG_STREAM_%03d",
        priority = 40
    }
}

-- 모든 패턴을 하나의 테이블로 통합
function patterns_extension.get_all_patterns()
    local all_patterns = {}
    
    -- 각 카테고리의 패턴을 통합
    local categories = {
        patterns_extension.lambda_patterns,
        patterns_extension.ecs_patterns,
        patterns_extension.eks_patterns,
        patterns_extension.rds_patterns,
        patterns_extension.elasticache_patterns,
        patterns_extension.dynamodb_patterns,
        patterns_extension.cloudformation_patterns,
        patterns_extension.messaging_patterns,
        patterns_extension.kms_patterns,
        patterns_extension.secrets_patterns,
        patterns_extension.route53_patterns,
        patterns_extension.apigateway_patterns,
        patterns_extension.cloudwatch_patterns
    }
    
    for _, category in ipairs(categories) do
        for _, pattern in ipairs(category) do
            table.insert(all_patterns, pattern)
        end
    end
    
    return all_patterns
end

-- 패턴 통계
function patterns_extension.get_stats()
    local stats = {
        total_patterns = 0,
        critical_patterns = 0,
        categories = {}
    }
    
    local all_patterns = patterns_extension.get_all_patterns()
    stats.total_patterns = #all_patterns
    
    for _, pattern in ipairs(all_patterns) do
        if pattern.critical then
            stats.critical_patterns = stats.critical_patterns + 1
        end
    end
    
    stats.categories = {
        lambda = #patterns_extension.lambda_patterns,
        ecs = #patterns_extension.ecs_patterns,
        eks = #patterns_extension.eks_patterns,
        rds = #patterns_extension.rds_patterns,
        elasticache = #patterns_extension.elasticache_patterns,
        dynamodb = #patterns_extension.dynamodb_patterns,
        cloudformation = #patterns_extension.cloudformation_patterns,
        messaging = #patterns_extension.messaging_patterns,
        kms = #patterns_extension.kms_patterns,
        secrets = #patterns_extension.secrets_patterns,
        route53 = #patterns_extension.route53_patterns,
        apigateway = #patterns_extension.apigateway_patterns,
        cloudwatch = #patterns_extension.cloudwatch_patterns
    }
    
    return stats
end

return patterns_extension