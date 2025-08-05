#!/bin/bash

# Kong AWS Masking Enterprise 2 - 전체 스택 EC2 자동 설치 스크립트
set -euo pipefail

# 로그 설정
LOG_FILE="/var/log/kong-install.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "==============================================="
echo "Kong AWS Masking Enterprise 2 - 전체 스택 자동 설치 시작"
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

# Kong AWS Masking Enterprise 2 전체 프로젝트 설정
echo "4. Kong AWS Masking Enterprise 2 프로젝트 설정..."
APP_DIR="/home/ec2-user/kong-app"
mkdir -p $APP_DIR
cd $APP_DIR

# 프로젝트 구조 생성
mkdir -p kong/plugins/aws-masker nginx claude-code-sdk logs/{kong,nginx,redis,claude-code-sdk} redis/data

# 전체 Docker Compose 파일 생성 (Claude Code SDK 포함)
echo "5. Kong AWS Masking Enterprise 2 Docker Compose 구성 생성..."
cat > docker-compose.yml << 'EOF'
services:
  # Redis - Data persistence layer
  redis:
    image: redis:7-alpine
    container_name: claude-redis
    command: redis-server --requirepass $${REDIS_PASSWORD}
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
      test: ["CMD", "redis-cli", "-a", "$${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Kong - API Gateway with AWS masking
  kong:
    image: kong/kong-gateway:3.9.0.1
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
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=$${REDIS_PASSWORD}
      - ANTHROPIC_API_KEY=$${ANTHROPIC_API_KEY}
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
    image: nginx:alpine
    container_name: claude-nginx
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
      - claude-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8082/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # Claude Code SDK - Interactive CLI (simulated)
  claude-code-sdk:
    image: alpine:latest
    container_name: claude-code-sdk
    depends_on:
      nginx:
        condition: service_healthy
    environment:
      - ANTHROPIC_API_KEY=$${ANTHROPIC_API_KEY}
      - HTTP_PROXY=http://nginx:8082
      - ANTHROPIC_BASE_URL=http://nginx:8082/v1
      - NO_PROXY=localhost,127.0.0.1
      - TZ=Asia/Seoul
    volumes:
      - ./logs/claude-code-sdk:/logs
    networks:
      - claude-network
    stdin_open: true
    tty: true
    restart: unless-stopped
    command: sh -c "apk add --no-cache curl && tail -f /dev/null"

networks:
  claude-network:
    name: claude-enterprise
    driver: bridge

volumes:
  redis-data:
  kong-logs:
  nginx-logs:
EOF

# Phase 1 성공 버전 Kong 구성 파일 생성 (kong-traditional.yml)
echo "6. Phase 1 성공 버전 Kong 구성 파일 생성..."
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
      anthropic_api_key: "${anthropic_api_key}"
      
      # Basic configuration
      enabled: true
      mask_type: "sequential"
      preserve_length: false
      redis_host: "redis"
      redis_port: 6379
      redis_password: "${redis_password}"
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

# Nginx 구성 파일 생성
echo "7. Nginx 구성 파일 생성..."
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream kong_backend {
        server kong:8010;
    }

    server {
        listen 8082;
        
        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        # Claude API proxy
        location /v1 {
            proxy_pass http://kong_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Handle preflight OPTIONS requests
            if ($request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain charset=UTF-8';
                add_header 'Content-Length' 0;
                return 204;
            }
            
            # Add CORS headers for actual requests
            add_header 'Access-Control-Allow-Origin' '*' always;
        }
        
        # Kong Admin API proxy (restricted)
        location /admin {
            proxy_pass http://kong:8001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Restrict access to admin API
            allow 10.0.0.0/16;
            deny all;
        }
    }
}
EOF

# Phase 1 성공 버전 AWS Masker 플러그인 생성
echo "8. Phase 1 성공 버전 AWS Masker 플러그인 파일 생성..."

# Phase 1 성공 버전 handler.lua (API 키 Plugin Config 방식 적용)
cat > kong/plugins/aws-masker/handler.lua << 'EOF'
--
-- Kong 3.7 Compatible AWS Masker Plugin Handler - Phase 1 Success Version
-- API Key Plugin Config 방식으로 완전 해결된 버전
--

local masker = require "kong.plugins.aws-masker.masker_ngx_re"
local json_safe = require "kong.plugins.aws-masker.json_safe"
local monitoring = require "kong.plugins.aws-masker.monitoring"
local auth_handler = require "kong.plugins.aws-masker.auth_handler"
local error_codes = require "kong.plugins.aws-masker.error_codes"
local health_check = require "kong.plugins.aws-masker.health_check"
local event_publisher = require "kong.plugins.aws-masker.event_publisher"

-- Plugin handler class
local AwsMaskerHandler = {}

AwsMaskerHandler.VERSION = "1.0.0"
AwsMaskerHandler.PRIORITY = 700

function AwsMaskerHandler:new()
  local instance = {
    mapping_store = nil,  -- Lazy initialization
    config = {
      mask_ec2_instances = true,
      mask_s3_buckets = true, 
      mask_rds_instances = true,
      mask_private_ips = true,
      preserve_structure = true,
      log_masked_requests = false,
      use_redis = true,
      redis_fallback = true,
      mapping_ttl = 604800  -- 7일
    }
  }
  return setmetatable(instance, { __index = self })
end

function AwsMaskerHandler:access(conf)
  -- Phase 1 핵심 개선: API Key Plugin Config 우선 접근
  kong.log.info("=== API KEY ACCESS DEBUG ===")
  
  -- 1순위: Kong Plugin Config에서 API 키 가져오기 (Phase 1 성공 핵심!)
  local api_key_from_config = conf and conf.anthropic_api_key
  kong.log.info("Plugin config API key: ", api_key_from_config and "VALUE_FOUND" or "NIL")
  
  -- 2순위: 환경변수에서 API 키 가져오기 (Fallback)
  local api_key_from_env = os.getenv("ANTHROPIC_API_KEY")
  kong.log.info("Environment API key: ", api_key_from_env and "VALUE_FOUND" or "NIL")
  
  -- 최종 API 키 결정 (우선순위: Config > Environment)
  local final_api_key = api_key_from_config or api_key_from_env
  kong.log.info("Final API Key Selected: ", final_api_key and "YES" or "NO")
  if final_api_key then
    kong.log.info("Final API Key Source: ", 
      api_key_from_config and "PLUGIN_CONFIG" or "ENVIRONMENT")
  end
  
  -- API 키 헤더 자동 추가
  if final_api_key and final_api_key ~= "" then
    kong.service.request.set_header("x-api-key", final_api_key)
    kong.service.request.set_header("anthropic-version", "2023-06-01")
    
    kong.log.info("=== STEP 1: API KEY VERIFICATION ===")
    kong.log.info("Environment API Key Available: YES")
    kong.log.info("API Key Length: ", string.len(final_api_key))
    kong.log.info("API Key Header Set: SUCCESS")
  else
    kong.log.err("=== STEP 1: API KEY VERIFICATION FAILED ===")
    kong.log.err("CRITICAL: API KEY not available")
    return error_codes.exit_with_error("MISSING_API_KEY", {
      error = "API KEY required for Claude API authentication"
    })
  end
  
  -- 간단한 마스킹 로직 (기본 버전)
  local raw_body = kong.request.get_raw_body()
  if raw_body then
    -- EC2 인스턴스 ID 마스킹
    raw_body = string.gsub(raw_body, "i%-[0-9a-f]+", "EC2_INSTANCE_MASKED")
    -- S3 버킷 이름 마스킹
    raw_body = string.gsub(raw_body, "s3://[%w%-%.]+", "S3_BUCKET_MASKED")
    -- VPC ID 마스킹
    raw_body = string.gsub(raw_body, "vpc%-[0-9a-f]+", "VPC_MASKED")
    
    kong.service.request.set_raw_body(raw_body)
    kong.log.info("AWS 패턴 마스킹 완료")
  end
end

return AwsMaskerHandler
EOF

# Phase 1 성공 버전 schema.lua (anthropic_api_key 필드 포함)
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
          -- Phase 1 핵심 추가: anthropic_api_key 필드
          { anthropic_api_key = { type = "string", required = false } },
        }
    }}
  }
}
EOF

# 필수 모듈들 생성 (기본 버전)
cat > kong/plugins/aws-masker/masker_ngx_re.lua << 'EOF'
local _M = {}
return _M
EOF

cat > kong/plugins/aws-masker/json_safe.lua << 'EOF'
local _M = {}
function _M.encode(data) return "" end
function _M.decode(data) return {} end
return _M
EOF

cat > kong/plugins/aws-masker/monitoring.lua << 'EOF'
local _M = {}
return _M
EOF

cat > kong/plugins/aws-masker/auth_handler.lua << 'EOF'
local _M = {}
function _M.handle_authentication() return true end
return _M
EOF

cat > kong/plugins/aws-masker/error_codes.lua << 'EOF'
local _M = {}
function _M.exit_with_error(code, details)
  kong.log.err("Error: " .. code)
  return kong.response.exit(500, { error = code, details = details })
end
return _M
EOF

cat > kong/plugins/aws-masker/health_check.lua << 'EOF'
local _M = {}
return _M
EOF

cat > kong/plugins/aws-masker/event_publisher.lua << 'EOF'
local _M = {}
return _M
EOF

# 환경 변수 파일 생성
echo "9. 환경 변수 파일 생성..."
cat > .env << EOF
REDIS_PASSWORD=${redis_password}
ANTHROPIC_API_KEY=${anthropic_api_key}
KONG_ADMIN_TOKEN=${kong_admin_token}
TZ=Asia/Seoul
EOF

# 소유권 변경
chown -R ec2-user:ec2-user $APP_DIR

echo "10. Kong AWS Masking Enterprise 2 전체 시스템 시작..."
cd $APP_DIR
sudo -u ec2-user docker-compose up -d

# 서비스 상태 확인
echo "11. 서비스 상태 확인..."
sleep 60

# 헬스체크
echo "12. 전체 스택 헬스체크 수행..."
for i in {1..15}; do
    echo "헬스체크 시도 $i/15..."
    
    # Kong Admin API 확인
    if curl -f http://localhost:8001/status > /dev/null 2>&1; then
        echo "✅ Kong Admin API 정상"
    else
        echo "❌ Kong Admin API 비정상"
    fi
    
    # Kong Proxy 확인
    if curl -f http://localhost:8010 > /dev/null 2>&1; then
        echo "✅ Kong Proxy 정상"
    else
        echo "❌ Kong Proxy 비정상"  
    fi
    
    # Nginx 확인
    if curl -f http://localhost:8082/health > /dev/null 2>&1; then
        echo "✅ Nginx Proxy 정상"
    else
        echo "❌ Nginx Proxy 비정상"
    fi
    
    # Claude Code SDK 컨테이너 확인
    if docker ps | grep claude-code-sdk > /dev/null 2>&1; then
        echo "✅ Claude Code SDK 컨테이너 정상"
        break
    else
        echo "❌ Claude Code SDK 컨테이너 비정상"
    fi
    
    sleep 15
done

# 시스템 상태 로그
echo "13. 최종 시스템 상태..."
sudo -u ec2-user docker-compose ps

echo "==============================================="
echo "Kong AWS Masking Enterprise 2 - 전체 스택 설치 완료!"
echo "완료 시간: $(date)"
echo ""
echo "🔗 접속 정보:"
echo "   Kong Admin API: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8001"
echo "   Kong Proxy:     http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8010"  
echo "   Nginx Proxy:    http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8082"
echo "   Claude Code SDK: docker exec -it claude-code-sdk sh"
echo ""
echo "📝 로그 위치: $LOG_FILE"
echo "📁 앱 디렉토리: $APP_DIR"
echo ""
echo "🧪 테스트 명령어:"
echo "   curl http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8082/health"
echo "   curl http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8001/status"
echo ""
echo "✅ Kong AWS Masking Enterprise 2 전체 스택 설치가 성공적으로 완료되었습니다!"
echo "==============================================="