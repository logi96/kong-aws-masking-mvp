# Kong AWS Masking Enterprise 2 - EC2 Terraform 변수 정의

# 환경 설정
variable "environment" {
  description = "배포 환경 (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# AWS 설정
variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key" {
  description = "AWS Access Key (LocalStack에서는 'test' 사용)"
  type        = string
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key (LocalStack에서는 'test' 사용)"
  type        = string
  default     = "test"
  sensitive   = true
}

# LocalStack 설정
variable "localstack_enabled" {
  description = "LocalStack 사용 여부"
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  description = "LocalStack 엔드포인트 URL"
  type        = string
  default     = "http://localhost:4566"
}

# 네트워크 설정
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "사용할 가용 영역 목록"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "allowed_ssh_cidrs" {
  description = "SSH 접근을 허용할 CIDR 블록"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_admin_cidrs" {
  description = "Kong Admin API 접근을 허용할 CIDR 블록"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# EC2 인스턴스 설정
variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "t2.micro", "t2.small", "t2.medium", "t2.large",
      "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "instance_count" {
  description = "생성할 EC2 인스턴스 수"
  type        = number
  default     = 1
  
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "Instance count must be between 1 and 5."
  }
}

variable "key_pair_name" {
  description = "EC2 인스턴스에 사용할 키 페어 이름"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "루트 볼륨 크기 (GB)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.root_volume_size >= 10 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 10 and 100 GB."
  }
}

# Kong 애플리케이션 설정
variable "anthropic_api_key" {
  description = "Anthropic API 키"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis 패스워드"
  type        = string
  default     = "kong-redis-secure-2024"
  sensitive   = true
}

variable "kong_admin_token" {
  description = "Kong Admin API 토큰"
  type        = string
  default     = "kong-admin-secure-token-2024"
  sensitive   = true
}

# 모니터링 설정
variable "enable_monitoring" {
  description = "CloudWatch 모니터링 활성화"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch 로그 보존 기간 (일)"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# 로드 밸런서 설정
variable "enable_load_balancer" {
  description = "Application Load Balancer 생성 여부"
  type        = bool
  default     = true
}

# 태그 설정
variable "additional_tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}

# 백업 설정
variable "enable_daily_backups" {
  description = "일일 백업 활성화"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "백업 보존 기간 (일)"
  type        = number
  default     = 7
}