# Kong AWS Masking Enterprise 2 - EC2 Terraform 출력값

# VPC 정보
output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.kong_vpc.id
}

output "vpc_cidr" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.kong_vpc.cidr_block
}

# 서브넷 정보
output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.kong_public_subnet[*].id
}

# 보안 그룹 정보
output "security_group_id" {
  description = "Kong 보안 그룹 ID"
  value       = aws_security_group.kong_sg.id
}

# EC2 인스턴스 정보
output "instance_ids" {
  description = "Kong EC2 인스턴스 ID 목록"
  value       = aws_instance.kong_instance[*].id
}

output "instance_public_ips" {
  description = "Kong EC2 인스턴스 퍼블릭 IP 목록"
  value       = aws_instance.kong_instance[*].public_ip
}

output "instance_private_ips" {
  description = "Kong EC2 인스턴스 프라이빗 IP 목록"
  value       = aws_instance.kong_instance[*].private_ip
}

output "instance_public_dns" {
  description = "Kong EC2 인스턴스 퍼블릭 DNS 목록"
  value       = aws_instance.kong_instance[*].public_dns
}

# 로드 밸런서 정보
output "load_balancer_dns" {
  description = "Application Load Balancer DNS 이름"
  value       = var.enable_load_balancer ? aws_lb.kong_alb[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Application Load Balancer Zone ID"
  value       = var.enable_load_balancer ? aws_lb.kong_alb[0].zone_id : null
}

output "load_balancer_arn" {
  description = "Application Load Balancer ARN"
  value       = var.enable_load_balancer ? aws_lb.kong_alb[0].arn : null
}

# CloudWatch 로그 정보
output "cloudwatch_log_group_name" {
  description = "CloudWatch 로그 그룹 이름"
  value       = aws_cloudwatch_log_group.kong_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch 로그 그룹 ARN"
  value       = aws_cloudwatch_log_group.kong_logs.arn
}

# IAM 정보
output "iam_role_arn" {
  description = "EC2 인스턴스 IAM 역할 ARN"
  value       = aws_iam_role.kong_ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "EC2 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.kong_instance_profile.name
}

# 연결 정보
output "kong_admin_urls" {
  description = "Kong Admin API URL 목록"
  value       = [for ip in aws_instance.kong_instance[*].public_ip : "http://${ip}:8001"]
}

output "kong_proxy_urls" {
  description = "Kong Proxy URL 목록"
  value       = [for ip in aws_instance.kong_instance[*].public_ip : "http://${ip}:8000"]
}

output "nginx_proxy_urls" {
  description = "Nginx Proxy URL 목록"
  value       = [for ip in aws_instance.kong_instance[*].public_ip : "http://${ip}:8082"]
}

# SSH 연결 정보
output "ssh_connection_commands" {
  description = "SSH 연결 명령어 목록"
  value = var.key_pair_name != "" ? [
    for i, ip in aws_instance.kong_instance[*].public_ip :
    "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${ip}"
  ] : []
}

# 헬스체크 URL
output "health_check_urls" {
  description = "서비스 헬스체크 URL 목록"
  value = {
    kong_admin = [for ip in aws_instance.kong_instance[*].public_ip : "http://${ip}:8001/status"]
    kong_proxy = [for ip in aws_instance.kong_instance[*].public_ip : "http://${ip}:8000/health"]
    nginx_proxy = [for ip in aws_instance.kong_instance[*].public_ip : "http://${ip}:8082/health"]
    load_balancer = var.enable_load_balancer ? "http://${aws_lb.kong_alb[0].dns_name}/health" : null
  }
}

# 환경 정보
output "deployment_environment" {
  description = "배포 환경"
  value       = var.environment
}

output "deployment_region" {
  description = "배포 리전"
  value       = var.aws_region
}

# 리소스 요약
output "resource_summary" {
  description = "생성된 리소스 요약"
  value = {
    vpc_id             = aws_vpc.kong_vpc.id
    instance_count     = length(aws_instance.kong_instance)
    instance_type      = var.instance_type
    load_balancer      = var.enable_load_balancer ? "enabled" : "disabled"
    monitoring         = var.enable_monitoring ? "enabled" : "disabled"
    environment        = var.environment
    estimated_hourly_cost = local.estimated_hourly_cost
  }
}

# 비용 추정 (대략적)
locals {
  instance_cost_per_hour = {
    "t3.micro"   = 0.0104
    "t3.small"   = 0.0208
    "t3.medium"  = 0.0416
    "t3.large"   = 0.0832
    "t3.xlarge"  = 0.1664
    "t2.micro"   = 0.0116
    "t2.small"   = 0.023
    "t2.medium"  = 0.046
    "t2.large"   = 0.092
    "m5.large"   = 0.096
    "m5.xlarge"  = 0.192
    "m5.2xlarge" = 0.384
  }
  
  alb_cost_per_hour = 0.0225
  
  estimated_hourly_cost = (
    lookup(local.instance_cost_per_hour, var.instance_type, 0.05) * var.instance_count +
    (var.enable_load_balancer ? local.alb_cost_per_hour : 0)
  )
}