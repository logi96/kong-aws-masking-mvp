#!/bin/bash

# Kong AWS Masking Enterprise 2 - Phase 1 성공 버전 EC2 배포 스크립트
set -euo pipefail

# 로그 설정
LOG_FILE="/var/log/kong-install.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "==============================================="
echo "Kong AWS Masking Enterprise 2 - Phase 1 성공 버전 배포"
echo "시작 시간: $(date)"
echo "Phase 1 주요 개선사항:"
echo "- API 키 Plugin Config 방식 적용"
echo "- kong-traditional.yml 설정 방식"
echo "- 완전 검증된 handler.lua 적용"
echo "==============================================="

# 환경 변수 설정
export ANTHROPIC_API_KEY="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"
export REDIS_PASSWORD="CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL"

# 시스템 업데이트 및 필수 패키지 설치
echo "1. 시스템 패키지 업데이트 및 Docker 설치..."
yum update -y
yum install -y docker git curl wget unzip jq htop vim

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

# Kong AWS Masking Enterprise 2 프로젝트 설정
echo "4. Kong AWS Masking Enterprise 2 Phase 1 성공 버전 설정..."
APP_DIR="/home/ec2-user/kong-app"
mkdir -p $APP_DIR
cd $APP_DIR

# 프로젝트 구조 생성
mkdir -p kong/plugins/aws-masker nginx claude-code-sdk logs/{kong,nginx,redis,claude-code-sdk} redis/data

# Phase 1 성공 버전 Docker Compose 파일 생성
echo "5. Phase 1 성공 버전 Docker Compose 구성 생성..."
cat > docker-compose.yml << 'EOF'
services:
  # Redis - Data persistence layer
  redis:
    image: redis:7-alpine
    container_name: claude-redis
    command: redis-server --requirepass ${REDIS_PASSWORD}
    ports:
      - "6379:6379"
    volumes:
      - ./redis/data:/data
      - ./logs/redis:/var/log/redis
    environment:
      - TZ=Asia/Seoul
    networks:
      - claude-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Kong - API Gateway with AWS masking (Phase 1 성공 버전)
  kong:
    build:
      context: ./kong
      dockerfile: Dockerfile
    container_name: claude-kong
    depends_on:
      redis:
        condition: service_healthy
    environment:
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong-traditional.yml
      - KONG_PROXY_ACCESS_LOG=/usr/local/kong/logs/access.log
      - KONG_ADMIN_ACCESS_LOG=/usr/local/kong/logs/admin-access.log
      - KONG_PROXY_ERROR_LOG=/usr/local/kong/logs/error.log
      - KONG_ADMIN_ERROR_LOG=/usr/local/kong/logs/admin-error.log
      - KONG_PROXY_LISTEN=0.0.0.0:8010
      - KONG_ADMIN_LISTEN=0.0.0.0:8001
      - KONG_LOG_LEVEL=info
      - KONG_MEM_CACHE_SIZE=2048m
      - KONG_PLUGINS=bundled,aws-masker
      - KONG_LUA_PACKAGE_PATH=/usr/local/kong/plugins/?.lua;/usr/local/kong/plugins/?/init.lua;;
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - TZ=Asia/Seoul
    volumes:
      - ./kong/kong-traditional.yml:/usr/local/kong/declarative/kong-traditional.yml:ro
      - ./kong/plugins:/usr/local/kong/plugins:ro
      - ./logs/kong:/usr/local/kong/logs
    ports:
      - "8001:8001"
      - "8010:8010"
    networks:
      - claude-network
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # Nginx - Enterprise proxy layer
  nginx:
    build:
      context: ./nginx
      dockerfile: Dockerfile
    container_name: claude-nginx
    depends_on:
      kong:
        condition: service_healthy
    ports:
      - "8082:8082"
    volumes:
      - ./logs/nginx:/var/log/nginx
    environment:
      - TZ=Asia/Seoul
    networks:
      - claude-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # Claude Code SDK - Interactive CLI
  claude-code-sdk:
    build:
      context: ./claude-code-sdk
      dockerfile: Dockerfile
    container_name: claude-code-sdk
    depends_on:
      nginx:
        condition: service_healthy
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - HTTP_PROXY=http://nginx:8082
      - ANTHROPIC_BASE_URL=http://nginx:8082/v1
      - NO_PROXY=localhost,127.0.0.1
      - TZ=Asia/Seoul
    volumes:
      - ./claude-code-sdk/scripts:/home/claude/scripts:ro
      - ./logs/claude-code-sdk:/home/claude/logs
      - ./logs:/logs:ro
    networks:
      - claude-network
    stdin_open: true
    tty: true
    restart: unless-stopped

networks:
  claude-network:
    name: claude-enterprise
    driver: bridge

volumes:
  redis-data:
  kong-logs:
  nginx-logs:
EOF

# Kong Dockerfile 생성
echo "6. Kong Dockerfile 생성..."
cat > kong/Dockerfile << 'EOF'
FROM kong:3.9.0-ubuntu

USER root

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    lua5.1-cjson \
    lua5.1-socket \
    lua5.1-lpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create plugin directory
RUN mkdir -p /usr/local/share/lua/5.1/kong/plugins/aws-masker

# Copy plugin files
COPY plugins/aws-masker/*.lua /usr/local/share/lua/5.1/kong/plugins/aws-masker/

# Set ownership
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/aws-masker

USER kong
EOF

# Phase 1 성공 버전 Kong 구성 파일 생성 (kong-traditional.yml)
echo "7. Phase 1 성공 버전 Kong 구성 파일 생성..."
cat > kong/kong-traditional.yml << 'EOF'
_format_version: "3.0"
_transform: true

services:
  - name: claude-api-service
    url: https://api.anthropic.com
    protocol: https
    host: api.anthropic.com
    port: 443
    retries: 3
    connect_timeout: 5000
    write_timeout: 60000
    read_timeout: 60000
    tags:
      - claude
      - production

routes:
  - name: claude-proxy-route
    service: claude-api-service
    paths:
      - /v1
    methods:
      - GET
      - POST
      - OPTIONS
    strip_path: false
    preserve_host: false
    regex_priority: 0
    tags:
      - claude
      - proxy

plugins:
  - name: aws-masker
    route: claude-proxy-route
    config:
      # Basic masking features
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
      mask_private_ips: true
      
      # Behavior configuration
      preserve_structure: true
      log_masked_requests: true
      
      # API Authentication Configuration - Phase 1 성공 핵심!
      anthropic_api_key: "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"
      
      # Traditional Redis configuration (Local/Development)
      use_redis: true
      redis_type: "traditional"
      mapping_ttl: 86400  # 24 hours
      max_entries: 10000
      
      # Traditional Redis connection settings
      redis_host: "redis"
      redis_port: 6379
      redis_database: 0
      redis_password: "${REDIS_PASSWORD}"
      
      # ElastiCache fields explicitly disabled for traditional mode
      redis_ssl_enabled: false
      redis_ssl_verify: false
      redis_auth_token: null
      redis_user: null
      redis_cluster_mode: false
      redis_cluster_endpoint: null
    tags:
      - security
      - masking
      - traditional

  - name: correlation-id
    config:
      header_name: X-Correlation-ID
      generator: uuid
      echo_downstream: true
    tags:
      - observability

  - name: request-transformer
    route: claude-proxy-route
    config:
      add:
        headers:
          - "anthropic-version:2023-06-01"
          - "x-api-key:${ANTHROPIC_API_KEY}"
      remove:
        headers:
          - "X-Real-IP"
          - "X-Forwarded-For"
    tags:
      - security

  - name: response-transformer
    route: claude-proxy-route
    config:
      add:
        headers:
          - "X-Kong-Proxy:true"
          - "X-Masked-Response:true"
          - "X-Redis-Mode:traditional"
    tags:
      - metadata

upstreams:
  - name: claude-api-upstream
    algorithm: round-robin
    slots: 10000
    healthchecks:
      active:
        healthy:
          interval: 30
          successes: 2
        unhealthy:
          interval: 5
          http_failures: 5
          tcp_failures: 5
          timeouts: 5
      passive:
        healthy:
          successes: 2
        unhealthy:
          http_failures: 5
          tcp_failures: 5
          timeouts: 5
    tags:
      - claude
      - traditional
EOF

echo "8. Phase 1 성공 버전 환경 변수 파일 생성..."
cat > .env << 'EOF'
REDIS_PASSWORD=CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL
ANTHROPIC_API_KEY=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
TZ=Asia/Seoul
KONG_CONFIG_MODE=traditional
EOF

echo "==============================================="
echo "Phase 1 성공 버전 파일 생성 완료!"
echo "다음 단계: Kong 플러그인 파일들 복사"
echo "==============================================="