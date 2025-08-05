# Kong AWS Masking Enterprise 2 - EC2 배포용 Terraform 모듈
# EC2 인스턴스에서 Kong 시스템을 자동 배포하는 인프라 구성

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider 설정 (LocalStack 지원)
provider "aws" {
  region                      = var.aws_region
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = var.localstack_enabled
  skip_metadata_api_check     = var.localstack_enabled
  skip_requesting_account_id  = var.localstack_enabled
  
  # LocalStack 엔드포인트 설정
  endpoints {
    ec2            = var.localstack_enabled ? "${var.localstack_endpoint}" : null
    iam            = var.localstack_enabled ? "${var.localstack_endpoint}" : null
    cloudformation = var.localstack_enabled ? "${var.localstack_endpoint}" : null
    s3             = var.localstack_enabled ? "${var.localstack_endpoint}" : null
  }
}

# 데이터 소스: 최신 Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"] # Amazon official AMI

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC 생성
resource "aws_vpc" "kong_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-kong-vpc"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "kong_igw" {
  vpc_id = aws_vpc.kong_vpc.id

  tags = {
    Name        = "${var.environment}-kong-igw"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# 퍼블릭 서브넷
resource "aws_subnet" "kong_public_subnet" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.kong_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-kong-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = "kong-aws-masking"
    Type        = "public"
  }
}

# 라우트 테이블
resource "aws_route_table" "kong_public_rt" {
  vpc_id = aws_vpc.kong_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kong_igw.id
  }

  tags = {
    Name        = "${var.environment}-kong-public-rt"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# 라우트 테이블 연결
resource "aws_route_table_association" "kong_public_rta" {
  count = length(aws_subnet.kong_public_subnet)

  subnet_id      = aws_subnet.kong_public_subnet[count.index].id
  route_table_id = aws_route_table.kong_public_rt.id
}

# 보안 그룹
resource "aws_security_group" "kong_sg" {
  name_prefix = "${var.environment}-kong-sg"
  vpc_id      = aws_vpc.kong_vpc.id

  # SSH 접근
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Kong Admin API
  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = var.allowed_admin_cidrs
  }

  # Kong Proxy
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Nginx Proxy
  ingress {
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Redis
  ingress {
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    self      = true
  }

  # HTTP (ALB에서)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (ALB에서)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-kong-sg"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# IAM 역할 (EC2 인스턴스용)
resource "aws_iam_role" "kong_ec2_role" {
  name = "${var.environment}-kong-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-kong-ec2-role"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# IAM 정책 (CloudWatch 로그, SSM 접근 등)
resource "aws_iam_role_policy" "kong_ec2_policy" {
  name = "${var.environment}-kong-ec2-policy"
  role = aws_iam_role.kong_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.environment}/kong/*"
      }
    ]
  })
}

# IAM 인스턴스 프로파일
resource "aws_iam_instance_profile" "kong_instance_profile" {
  name = "${var.environment}-kong-instance-profile"
  role = aws_iam_role.kong_ec2_role.name

  tags = {
    Name        = "${var.environment}-kong-instance-profile"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# EC2 인스턴스
resource "aws_instance" "kong_instance" {
  count = var.instance_count

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.kong_sg.id]
  subnet_id              = aws_subnet.kong_public_subnet[count.index % length(aws_subnet.kong_public_subnet)].id
  iam_instance_profile   = aws_iam_instance_profile.kong_instance_profile.name

  user_data = base64encode(templatefile("${path.module}/user_data_full.sh", {
    environment         = var.environment
    anthropic_api_key   = var.anthropic_api_key
    redis_password      = var.redis_password
    kong_admin_token    = var.kong_admin_token
    enable_monitoring   = var.enable_monitoring
    cloudwatch_log_group = aws_cloudwatch_log_group.kong_logs.name
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true

    tags = {
      Name        = "${var.environment}-kong-root-volume-${count.index + 1}"
      Environment = var.environment
      Project     = "kong-aws-masking"
    }
  }

  tags = {
    Name        = "${var.environment}-kong-instance-${count.index + 1}"
    Environment = var.environment
    Project     = "kong-aws-masking"
    Role        = "kong-gateway"
  }

  # 인스턴스 변경 시 자동 교체 방지
  lifecycle {
    ignore_changes = [
      ami,
      user_data
    ]
  }
}

# CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "kong_logs" {
  name              = "/aws/ec2/kong/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.environment}-kong-logs"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# Application Load Balancer (ALB)
resource "aws_lb" "kong_alb" {
  count = var.enable_load_balancer ? 1 : 0

  name               = "${var.environment}-kong-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.kong_sg.id]
  subnets            = aws_subnet.kong_public_subnet[*].id

  enable_deletion_protection = var.environment == "production" ? true : false

  tags = {
    Name        = "${var.environment}-kong-alb"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# ALB 대상 그룹 (Kong Proxy)
resource "aws_lb_target_group" "kong_proxy_tg" {
  count = var.enable_load_balancer ? 1 : 0

  name     = "${var.environment}-kong-proxy-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.kong_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name        = "${var.environment}-kong-proxy-tg"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# ALB 리스너
resource "aws_lb_listener" "kong_listener" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.kong_alb[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_proxy_tg[0].arn
  }

  tags = {
    Name        = "${var.environment}-kong-listener"
    Environment = var.environment
    Project     = "kong-aws-masking"
  }
}

# ALB 대상 그룹 연결
resource "aws_lb_target_group_attachment" "kong_tg_attachment" {
  count = var.enable_load_balancer ? var.instance_count : 0

  target_group_arn = aws_lb_target_group.kong_proxy_tg[0].arn
  target_id        = aws_instance.kong_instance[count.index].id
  port             = 8000
}