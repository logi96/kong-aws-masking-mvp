-- multi-pattern-test-cases.lua
-- 보안 최우선: 실제 Claude API content와 동일한 복합 AWS 패턴 테스트
-- 이 파일의 테스트 케이스는 실제 운영 환경의 보안 위협을 검증합니다

local multi_pattern_cases = {
    -- 실제 Claude API content 시뮬레이션
    realistic_aws_analysis = {
        input = [[
Please analyze the following AWS infrastructure data for security_and_optimization:

EC2 Resources (3 items):
[
  ["i-1234567890abcdef0", "t2.micro", "running", "10.0.1.100", "203.0.113.1"],
  ["i-abcdef1234567890", "t3.medium", "stopped", "10.0.2.50", ""],
  ["i-9876543210fedcba", "m5.large", "running", "172.16.0.10", "54.239.28.85"]
]

S3 Resources (2 items):
[
  ["my-app-logs-bucket", "2023-01-01"],
  ["production-data-bucket-2024", "2023-06-15"]
]

RDS Resources (1 items):
[
  ["production-mysql-db", "mysql", "db.t3.micro", "available"]
]

VPC Resources:
- VPC: vpc-12345678901234567
- Subnets: subnet-abcdef123456789, subnet-98765432109876
- Security Groups: sg-1a2b3c4d5e6f7890

IAM Resources:
- Role ARN: arn:aws:iam::123456789012:role/EC2-S3-Access-Role
- Policy ARN: arn:aws:iam::999888777666:policy/CustomS3Policy

Network Configuration:
- Private IPs: 10.0.1.100, 10.0.2.50, 172.16.0.10, 192.168.1.254
- Public IPs: 203.0.113.1, 54.239.28.85

Analysis shows potential security issues with instance i-1234567890abcdef0 
accessing bucket my-app-logs-bucket from private IP 10.0.1.100 through 
security group sg-1a2b3c4d5e6f7890.

The RDS instance production-mysql-db should not be accessible from 
public subnets. Consider moving it to private subnet subnet-98765432109876.
        ]],
        expected_patterns = {
            ec2_instances = 3,      -- i-xxx 패턴 3개
            s3_buckets = 2,         -- bucket 패턴 2개  
            rds_instances = 1,      -- db 패턴 1개
            vpc_ids = 1,            -- vpc- 패턴 1개
            subnet_ids = 2,         -- subnet- 패턴 2개
            security_groups = 2,    -- sg- 패턴 2개 (중복 포함)
            iam_arns = 2,           -- arn:aws:iam 패턴 2개
            account_ids = 2,        -- 12자리 숫자 2개
            private_ips = 4,        -- 사설 IP 4개
            public_ips = 2          -- 공인 IP 2개 (마스킹 안됨)
        }
    },
    
    -- 패턴 간섭 테스트 케이스
    pattern_interference = {
        input = "Instance i-1234567890abcdef0 in vpc-1234567890abcdef0 has IP 10.0.1.100",
        expected_patterns = {
            ec2_instances = 1,
            vpc_ids = 1, 
            private_ips = 1
        },
        interference_check = {
            -- vpc ID가 instance ID 패턴에 잘못 매칭되지 않는지 확인
            vpc_not_as_instance = "vpc-1234567890abcdef0 should not match EC2 pattern"
        }
    },
    
    -- 중첩 패턴 테스트
    overlapping_patterns = {
        input = "arn:aws:iam::123456789012:role/my-role-for-production-db-access",
        expected_patterns = {
            iam_arns = 1,           -- 전체 ARN
            account_ids = 1,        -- ARN 내부의 account ID
            rds_references = 0      -- 'db' 키워드 (ARN 컨텍스트에서는 매칭 안됨)
        }
    },
    
    -- 보안 위반 시나리오 테스트 (반드시 마스킹되어야 함)
    security_breach_scenario = {
        input = [[
CRITICAL: Security breach detected!
AWS Access Key AKIAIOSFODNN7EXAMPLE was found exposed in EC2 instance i-0123456789abcdef0.
The key has access to RDS database production-mysql-db and S3 bucket sensitive-data-bucket.
Account ID 123456789012 may be compromised.
VPC vpc-0a1b2c3d4e5f6789 contains vulnerable subnet subnet-1234567890abcdef.
        ]],
        expected_patterns = {
            ec2_instances = 1,
            iam_access_keys = 1,    -- AKIA 패턴
            rds_instances = 1,
            s3_buckets = 1,
            account_ids = 1,
            vpc_ids = 1,
            subnet_ids = 1
        },
        critical = true  -- 이 테스트는 반드시 통과해야 함
    },
    
    -- 대용량 텍스트 성능 테스트
    large_mixed_content = function(size_multiplier)
        local base_content = [[
EC2 Instance i-1234567890abcdef0 connects to RDS production-mysql-db
via private IP 10.0.1.100 in VPC vpc-abcd1234efgh5678.
S3 bucket my-logs-bucket-2024 stores access logs.
IAM role arn:aws:iam::123456789012:role/AppRole provides access.
Security group sg-0123456789abcdef allows traffic from subnet-abcd1234.
        ]]
        
        local large_content = ""
        for i = 1, size_multiplier do
            -- 각 반복마다 ID 변경하여 고유한 패턴 생성
            local iteration_content = base_content:gsub("1234567890abcdef0", 
                string.format("1234567890abcde%02d", i % 100))
            large_content = large_content .. iteration_content .. "\n\n"
        end
        
        return {
            input = large_content,
            expected_patterns = {
                ec2_instances = size_multiplier,
                rds_instances = size_multiplier,
                private_ips = size_multiplier,
                vpc_ids = size_multiplier,
                s3_buckets = size_multiplier,
                iam_arns = size_multiplier,
                account_ids = size_multiplier,
                security_groups = size_multiplier,
                subnet_ids = size_multiplier
            }
        }
    end,
    
    -- Claude API 구조별 테스트
    claude_api_structure_test = {
        -- system 프롬프트에 AWS 정보
        system_prompt = {
            input = "You are an AWS expert analyzing account 123456789012 resources",
            expected_patterns = {
                account_ids = 1
            }
        },
        
        -- 멀티모달 content 배열
        multimodal_content = {
            input = {
                {type = "text", text = "Check EC2 instance i-abcd1234efgh5678"},
                {type = "image", source = {type = "base64", data = "..."}},
                {type = "text", text = "Also review S3 bucket my-data-bucket"}
            },
            expected_patterns = {
                ec2_instances = 1,
                s3_buckets = 1
            }
        },
        
        -- tools 설명에 AWS 정보
        tools_description = {
            input = "This tool accesses RDS database prod-mysql-db in VPC vpc-123456",
            expected_patterns = {
                rds_instances = 1,
                vpc_ids = 1
            }
        }
    },
    
    -- 엣지 케이스 테스트
    edge_cases = {
        -- 빈 문자열
        empty_string = {
            input = "",
            expected_patterns = {}
        },
        
        -- 매우 긴 ID
        long_ids = {
            input = "Instance i-1234567890abcdef01234567890abcdef0 is invalid",
            expected_patterns = {
                ec2_instances = 0  -- 너무 긴 ID는 매칭하지 않음
            }
        },
        
        -- 특수 문자 포함
        special_chars = {
            input = "EC2: i-1234567890abcdef0\nS3: my-bucket-2024\tRDS: prod-db",
            expected_patterns = {
                ec2_instances = 1,
                s3_buckets = 1,
                rds_instances = 1
            }
        }
    }
}

return multi_pattern_cases