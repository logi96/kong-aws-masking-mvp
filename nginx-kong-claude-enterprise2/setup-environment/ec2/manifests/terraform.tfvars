# Kong AWS Masking Enterprise 2 - LocalStack 테스트용 설정

# 환경 설정
environment = "development"

# AWS 설정
aws_region     = "us-east-1"
aws_access_key = "test"
aws_secret_key = "test"

# LocalStack 설정
localstack_enabled  = true
localstack_endpoint = "http://localstack:4566"

# 네트워크 설정
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
allowed_ssh_cidrs  = ["0.0.0.0/0"]
allowed_admin_cidrs = ["10.0.0.0/16"]

# EC2 인스턴스 설정
instance_type     = "t3.medium"
instance_count    = 1
key_pair_name     = ""  # LocalStack에서는 키 페어 없이 테스트
root_volume_size  = 20

# Kong 애플리케이션 설정 (테스트용)
anthropic_api_key = "sk-ant-api03-test-key-for-localstack-testing"
redis_password    = "localstack-redis-password-2024"
kong_admin_token  = "localstack-kong-admin-token-2024"

# 모니터링 설정
enable_monitoring    = false  # LocalStack에서는 CloudWatch 제한
log_retention_days   = 7

# 로드 밸런서 설정
enable_load_balancer = true

# 백업 설정
enable_daily_backups   = false  # LocalStack 테스트에서는 비활성화
backup_retention_days  = 7

# 추가 태그
additional_tags = {
  Owner       = "LocalStack Test"
  Project     = "Kong AWS Masking"
  CostCenter  = "Development"
  Environment = "localstack"
}