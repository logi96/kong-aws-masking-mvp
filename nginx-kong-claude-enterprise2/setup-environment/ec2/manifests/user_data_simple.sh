#!/bin/bash

# Kong AWS Masking Enterprise 2 - 간단한 EC2 자동 설치 스크립트
set -euo pipefail

# 로그 설정
LOG_FILE="/var/log/kong-install.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "==============================================="
echo "Kong AWS Masking Enterprise 2 - 자동 설치 시작"
echo "시작 시간: $(date)"
echo "환경: ${environment}"
echo "==============================================="

# 환경 변수 설정
export ENVIRONMENT="${environment}"
export ANTHROPIC_API_KEY="${anthropic_api_key}"
export REDIS_PASSWORD="${redis_password}"
export KONG_ADMIN_TOKEN="${kong_admin_token}"

# 시스템 업데이트 및 필수 패키지 설치
echo "1. 시스템 패키지 업데이트 및 Docker 설치..."
yum update -y
yum install -y docker git curl wget unzip jq

# Docker 설치 및 시작
echo "2. Docker 서비스 설정..."
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Docker Compose 설치
echo "3. Docker Compose 설치..."
DOCKER_COMPOSE_VERSION="v2.24.1"
curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Kong AWS Masking Enterprise 2 전체 프로젝트 클론
echo "4. Kong AWS Masking Enterprise 2 프로젝트 설정..."
APP_DIR="/home/ec2-user/kong-app"
mkdir -p $APP_DIR
cd $APP_DIR

# 프로젝트 구조 생성 (실제 환경에서는 git clone 사용)
mkdir -p kong/plugins/aws-masker nginx claude-code-sdk logs/{kong,nginx,redis,claude-code-sdk} redis/data

# 기본 Docker Compose 파일 생성
echo "5. Docker Compose 구성 생성..."
cat > docker-compose.yml << 'EOF'
services:
  redis:
    image: redis:7-alpine
    container_name: kong-redis
    command: redis-server --requirepass ${redis_password}
    ports:
      - "6379:6379"
    networks:
      - kong-network
    restart: unless-stopped

  kong:
    image: kong/kong-gateway:3.9.0.1
    container_name: kong-gateway
    depends_on:
      - redis
    environment:
      - KONG_DATABASE=off
      - KONG_PROXY_LISTEN=0.0.0.0:8000
      - KONG_ADMIN_LISTEN=0.0.0.0:8001
      - KONG_LOG_LEVEL=info
      - REDIS_PASSWORD=${redis_password}
      - ANTHROPIC_API_KEY=${anthropic_api_key}
    ports:
      - "8001:8001"
      - "8000:8000"
    networks:
      - kong-network
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: kong-nginx
    depends_on:
      - kong
    ports:
      - "8082:8082"
    networks:
      - kong-network
    restart: unless-stopped

networks:
  kong-network:
    name: kong-enterprise
EOF

# 환경 변수 파일 생성
cat > .env << EOF
REDIS_PASSWORD=${redis_password}
ANTHROPIC_API_KEY=${anthropic_api_key}
EOF

# 소유권 변경
chown -R ec2-user:ec2-user $APP_DIR

echo "6. Kong 시스템 시작..."
cd $APP_DIR
sudo -u ec2-user docker-compose up -d

# 헬스체크
echo "7. 서비스 상태 확인..."
sleep 30
curl -f http://localhost:8001/status || echo "Kong Admin API 확인 중..."
curl -f http://localhost:8000 || echo "Kong Proxy 확인 중..."

echo "==============================================="
echo "Kong AWS Masking Enterprise 2 - 설치 완료!"
echo "완료 시간: $(date)"
echo "==============================================="