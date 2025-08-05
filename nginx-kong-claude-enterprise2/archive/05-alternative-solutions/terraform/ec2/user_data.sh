#!/bin/bash

# Kong AWS Masking Enterprise 2 - EC2 자동 설치 스크립트
# Amazon Linux 2에서 Kong 시스템을 자동으로 설치하고 구성

set -euo pipefail

# 로그 설정
LOG_FILE="/var/log/kong-install.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=================================================="
echo "Kong AWS Masking Enterprise 2 - 자동 설치 시작"
echo "시작 시간: $(date)"
echo "환경: ${environment}"
echo "=================================================="

# 환경 변수 설정
export ENVIRONMENT="${environment}"
export ANTHROPIC_API_KEY="${anthropic_api_key}"
export REDIS_PASSWORD="${redis_password}"
export KONG_ADMIN_TOKEN="${kong_admin_token}"
export ENABLE_MONITORING="${enable_monitoring}"
export CLOUDWATCH_LOG_GROUP="${cloudwatch_log_group}"

# 시스템 업데이트
echo "1. 시스템 패키지 업데이트..."
yum update -y

# 필수 패키지 설치
echo "2. 필수 패키지 설치..."
yum install -y \
    docker \
    git \
    curl \
    wget \
    unzip \
    jq \
    htop \
    vim \
    aws-cli

# Docker 설치 및 시작
echo "3. Docker 서비스 설정..."
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Docker Compose 설치 (최신 버전)
echo "4. Docker Compose 설치..."
DOCKER_COMPOSE_VERSION="v2.24.1"
curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# CloudWatch Agent 설치 (모니터링이 활성화된 경우)
if [ "${enable_monitoring}" == "true" ]; then
    echo "5. CloudWatch Agent 설치 및 구성..."
    yum install -y amazon-cloudwatch-agent
    
    # CloudWatch Agent 구성 파일 생성
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/kong-install.log",
                        "log_group_name": "${cloudwatch_log_group}",
                        "log_stream_name": "{instance_id}/install",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/home/ec2-user/kong-app/logs/kong/*.log",
                        "log_group_name": "${cloudwatch_log_group}",
                        "log_stream_name": "{instance_id}/kong",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/home/ec2-user/kong-app/logs/nginx/*.log",
                        "log_group_name": "${cloudwatch_log_group}",
                        "log_stream_name": "{instance_id}/nginx",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/home/ec2-user/kong-app/logs/redis/*.log",
                        "log_group_name": "${cloudwatch_log_group}",
                        "log_stream_name": "{instance_id}/redis",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Kong/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

    # CloudWatch Agent 시작
    systemctl enable amazon-cloudwatch-agent
    systemctl start amazon-cloudwatch-agent
else
    echo "5. 모니터링이 비활성화되어 CloudWatch Agent 설치를 건너뜁니다."
fi

# Kong 애플리케이션 디렉토리 생성
echo "6. Kong 애플리케이션 디렉토리 설정..."
APP_DIR="/home/ec2-user/kong-app"
mkdir -p $APP_DIR
cd $APP_DIR

# Kong 프로젝트 파일 생성 (기본 구성)
echo "7. Kong 프로젝트 구성 파일 생성..."

# docker-compose.yml 생성
cat > docker-compose.yml << 'EOF'
services:
  # Redis - Data persistence layer
  redis:
    image: redis:7-alpine
    container_name: kong-redis
    command: redis-server --requirepass ${redis_password}
    ports:
      - "6379:6379"
    volumes:
      - ./redis/data:/data
      - ./logs/redis:/var/log/redis
    environment:
      - TZ=Asia/Seoul
    networks:
      - kong-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${redis_password}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Kong - API Gateway with AWS masking
  kong:
    image: kong/kong-gateway:3.9.0.1
    container_name: kong-gateway
    depends_on:
      redis:
        condition: service_healthy
    environment:
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml
      - KONG_PROXY_ACCESS_LOG=/usr/local/kong/logs/access.log
      - KONG_ADMIN_ACCESS_LOG=/usr/local/kong/logs/admin-access.log
      - KONG_PROXY_ERROR_LOG=/usr/local/kong/logs/error.log
      - KONG_ADMIN_ERROR_LOG=/usr/local/kong/logs/admin-error.log
      - KONG_PROXY_LISTEN=0.0.0.0:8000
      - KONG_ADMIN_LISTEN=0.0.0.0:8001
      - KONG_LOG_LEVEL=info
      - KONG_MEM_CACHE_SIZE=2048m
      - KONG_PLUGINS=bundled,aws-masker
      - KONG_LUA_PACKAGE_PATH=/usr/local/kong/plugins/?.lua;/usr/local/kong/plugins/?/init.lua;;
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${redis_password}
      - ANTHROPIC_API_KEY=${anthropic_api_key}
      - TZ=Asia/Seoul
    volumes:
      - ./kong/kong.yml:/usr/local/kong/declarative/kong.yml:ro
      - ./kong/plugins:/usr/local/kong/plugins:ro
      - ./logs/kong:/usr/local/kong/logs
    ports:
      - "8001:8001"
      - "8000:8000"
    networks:
      - kong-network
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # Nginx - Enterprise proxy layer
  nginx:
    image: nginx:alpine
    container_name: kong-nginx
    depends_on:
      kong:
        condition: service_healthy
    ports:
      - "8082:8082"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./logs/nginx:/var/log/nginx
    environment:
      - TZ=Asia/Seoul
    networks:
      - kong-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

networks:
  kong-network:
    name: kong-enterprise
    driver: bridge

volumes:
  redis-data:
  kong-logs:
  nginx-logs:
EOF

# 환경 변수 파일 생성
cat > .env << EOF
# Kong AWS Masking MVP - Production Environment
NODE_ENV=production
DEPLOYMENT_ENV=${environment}
TZ=Asia/Seoul

# API Configuration
ANTHROPIC_API_KEY=${anthropic_api_key}

# Redis Configuration
REDIS_PASSWORD=${redis_password}
REDIS_HOST=redis
REDIS_PORT=6379

# Kong Configuration
KONG_ADMIN_PORT=8001
KONG_PROXY_PORT=8000
KONG_LOG_LEVEL=info
KONG_ADMIN_TOKEN=${kong_admin_token}

# Network Configuration
NETWORK_NAME=kong-enterprise
EOF

# Kong 구성 디렉토리 생성
mkdir -p kong/plugins/aws-masker
mkdir -p nginx
mkdir -p logs/{kong,nginx,redis}
mkdir -p redis/data

# 기본 Kong 구성 파일 생성
cat > kong/kong.yml << 'EOF'
_format_version: "3.0"

services:
  - name: claude-api
    url: https://api.anthropic.com
    routes:
      - name: claude-proxy
        paths:
          - /v1
    plugins:
      - name: aws-masker
        config:
          enabled: true
          mask_type: "sequential"
          preserve_length: false
          redis_host: "redis"
          redis_port: 6379
          redis_password: ${redis_password}

plugins:
  - name: cors
    config:
      origins:
        - "*"
      methods:
        - GET
        - POST
        - PUT
        - DELETE
        - OPTIONS
      headers:
        - Accept
        - Content-Type
        - Authorization
        - X-Requested-With
      exposed_headers:
        - X-Custom-Header
      credentials: true
      max_age: 3600
EOF

# 기본 Nginx 구성
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream kong_backend {
        server kong:8000;
    }

    server {
        listen 8082;
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        location / {
            proxy_pass http://kong_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

# 기본 AWS Masker 플러그인 생성
cat > kong/plugins/aws-masker/handler.lua << 'EOF'
local kong = kong
local ngx = ngx

local AwsMaskerHandler = {}

AwsMaskerHandler.VERSION = "1.0.0"
AwsMaskerHandler.PRIORITY = 1000

function AwsMaskerHandler:access(conf)
    -- 기본적인 AWS 리소스 패턴 마스킹
    local body = kong.request.get_raw_body()
    if body then
        -- EC2 인스턴스 ID 마스킹
        body = string.gsub(body, "i%-[0-9a-f]+", "EC2_INSTANCE_MASKED")
        -- S3 버킷 이름 마스킹
        body = string.gsub(body, "s3://[%w%-%.]+", "S3_BUCKET_MASKED")
        -- VPC ID 마스킹
        body = string.gsub(body, "vpc%-[0-9a-f]+", "VPC_MASKED")
        
        kong.service.request.set_raw_body(body)
    end
end

return AwsMaskerHandler
EOF

cat > kong/plugins/aws-masker/schema.lua << 'EOF'
return {
  name = "aws-masker",
  fields = {
    { config = {
        type = "record",
        fields = {
          { enabled = { type = "boolean", default = true } },
          { mask_type = { type = "string", default = "sequential" } },
          { preserve_length = { type = "boolean", default = false } },
          { redis_host = { type = "string", default = "redis" } },
          { redis_port = { type = "number", default = 6379 } },
          { redis_password = { type = "string" } },
        }
    }}
  }
}
EOF

# 소유권 변경
chown -R ec2-user:ec2-user $APP_DIR

echo "8. Kong 시스템 시작..."
cd $APP_DIR

# Docker Compose로 시스템 시작
sudo -u ec2-user docker-compose up -d

# 서비스 상태 확인
echo "9. 서비스 상태 확인..."
sleep 30

# 헬스체크
echo "10. 헬스체크 수행..."
for i in {1..10}; do
    echo "헬스체크 시도 $i/10..."
    
    # Kong Admin API 확인
    if curl -f http://localhost:8001/status > /dev/null 2>&1; then
        echo "✅ Kong Admin API 정상"
    else
        echo "❌ Kong Admin API 비정상"
    fi
    
    # Kong Proxy 확인
    if curl -f http://localhost:8000 > /dev/null 2>&1; then
        echo "✅ Kong Proxy 정상"
    else
        echo "❌ Kong Proxy 비정상"  
    fi
    
    # Nginx 확인
    if curl -f http://localhost:8082/health > /dev/null 2>&1; then
        echo "✅ Nginx Proxy 정상"
        break
    else
        echo "❌ Nginx Proxy 비정상"
    fi
    
    sleep 10
done

# 시스템 상태 로그
echo "11. 최종 시스템 상태..."
sudo -u ec2-user docker-compose ps

# 자동 시작 스크립트 생성
cat > /etc/systemd/system/kong-app.service << EOF
[Unit]
Description=Kong AWS Masking Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0
User=ec2-user
Group=ec2-user

[Install]
WantedBy=multi-user.target
EOF

systemctl enable kong-app.service

echo "=================================================="
echo "Kong AWS Masking Enterprise 2 - 설치 완료!"
echo "완료 시간: $(date)"
echo ""
echo "🔗 접속 정보:"
echo "   Kong Admin API: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8001"
echo "   Kong Proxy:     http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"  
echo "   Nginx Proxy:    http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8082"
echo ""
echo "📝 로그 위치: $LOG_FILE"
echo "📁 앱 디렉토리: $APP_DIR"
echo ""
echo "✅ 설치가 성공적으로 완료되었습니다!"
echo "=================================================="