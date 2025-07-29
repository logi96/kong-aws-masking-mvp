# 4. 환경 설정 가이드

## 4.1 전체 환경 구성 개요

### 4.1.1 컴포넌트 구성

| 컴포넌트 | 버전 | 용도 | 포트 |
|----------|------|------|------|
| Backend App | 현재 | 비즈니스 로직 | 3000 |
| Envoy Proxy | v1.28+ | 투명 프록시 | 15001 |
| Kong Gateway | 3.9.0.1 | API Gateway | 8000/8001 |
| Redis | 7-alpine | 마스킹 매핑 | 6379 |

### 4.1.2 네트워크 구성

```
Docker Networks:
- kong_frontend: Backend + Envoy + Kong
- kong_backend: Kong + Redis
```

## 4.2 Envoy 환경 설정

### 4.2.1 Envoy 설정 파일 생성

**파일 경로: `envoy/envoy.yaml`**

```yaml
# 관리 인터페이스 설정
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901
  
# 정적 리소스 설정
static_resources:
  # 아웃바운드 리스너
  listeners:
  - name: outbound_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 15001
    # 투명 프록시 모드 활성화
    transparent: true
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: outbound_http
          
          # 액세스 로그 설정
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
              format: "[%START_TIME%] %REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL% %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% \"%REQ(X-FORWARDED-FOR)%\" \"%REQ(USER-AGENT)%\" \"%REQ(X-REQUEST-ID)%\" \"%REQ(:AUTHORITY)%\" \"%UPSTREAM_HOST%\"\n"
          
          # HTTP 필터 체인
          http_filters:
          # Lua 스크립트 필터
          - name: envoy.filters.http.lua
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
              inline_code: |
                function envoy_on_request(request_handle)
                  -- 원본 호스트 헤더 추출
                  local authority = request_handle:headers():get(":authority")
                  if authority then
                    -- 디버깅 로그
                    request_handle:logInfo("Intercepting request to: " .. authority)
                    
                    -- 원본 호스트를 헤더에 저장
                    request_handle:headers():add("x-original-host", authority)
                    request_handle:headers():add("x-original-path", request_handle:headers():get(":path"))
                    
                    -- Kong Gateway로 리다이렉트
                    request_handle:headers():replace(":authority", "kong-gateway:8000")
                    request_handle:headers():replace(":path", "/")
                  end
                end
                
                function envoy_on_response(response_handle)
                  -- 응답 추적 헤더 추가
                  response_handle:headers():add("x-envoy-proxy", "true")
                end
          
          # 라우터 필터
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          
          # 라우트 설정
          route_config:
            name: outbound_route
            virtual_hosts:
            - name: all_external
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: kong_gateway
                  timeout: 30s

  # 클러스터 설정
  clusters:
  - name: kong_gateway
    connect_timeout: 5s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    lb_policy: ROUND_ROBIN
    
    # 헬스체크 설정
    health_checks:
    - timeout: 1s
      interval: 5s
      unhealthy_threshold: 2
      healthy_threshold: 2
      path: "/status"
      
    # 엔드포인트 설정
    load_assignment:
      cluster_name: kong_gateway
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: kong-gateway
                port_value: 8000
```

### 4.2.2 Envoy 디버그 설정

**파일: `envoy/envoy-debug.yaml`**

```yaml
# 디버그 모드 설정 (개발 환경용)
static_resources:
  listeners:
  - name: outbound_listener
    # ... 기본 설정 동일 ...
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          # 상세 로그 레벨
          common_http_protocol_options:
            headers_with_underscores_action: REJECT_REQUEST
          
          # 추가 디버그 헤더
          request_headers_to_add:
          - header:
              key: "x-envoy-debug"
              value: "true"
```

## 4.3 Kong 환경 설정

### 4.3.1 Kong 설정 업데이트

**파일: `kong/kong.yml`**

```yaml
_format_version: "3.0"
_transform: true

# 서비스 정의
services:
  # 동적 외부 API 서비스
  - name: dynamic-external-api
    url: http://placeholder.invalid  # Dynamic Router가 실제 URL 설정
    retries: 3
    connect_timeout: 5000
    write_timeout: 30000
    read_timeout: 30000

# 라우트 정의
routes:
  # 모든 요청을 받는 라우트
  - name: external-api-route
    service: dynamic-external-api
    paths:
      - /
    strip_path: false
    preserve_host: false
    request_buffering: true
    response_buffering: true

# 플러그인 설정
plugins:
  # Dynamic Router 플러그인 (우선순위 높음)
  - name: dynamic-router
    service: dynamic-external-api
    config:
      allowed_hosts:
        # Anthropic Claude API
        api.anthropic.com: "https://api.anthropic.com"
        # OpenAI API
        api.openai.com: "https://api.openai.com"
        # Google Vertex AI
        aiplatform.googleapis.com: "https://aiplatform.googleapis.com"
        # AWS Services (추가 가능)
        bedrock-runtime.us-east-1.amazonaws.com: "https://bedrock-runtime.us-east-1.amazonaws.com"
      debug: true  # 개발 환경에서만 true
      
  # AWS Masker 플러그인 (기존 유지)
  - name: aws-masker
    service: dynamic-external-api
    config:
      use_redis: true
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
      mask_private_ips: false  # Public IP만 마스킹
      preserve_structure: true
      log_masked_requests: false
      
  # Rate Limiting
  - name: rate-limiting
    service: dynamic-external-api
    config:
      minute: 100
      hour: 10000
      policy: local
      
  # 요청/응답 로깅 (개발 환경)
  - name: http-log
    service: dynamic-external-api
    config:
      http_endpoint: http://localhost:8080/logs
      method: POST
      timeout: 1000
      keepalive: 1000
```

### 4.3.2 Dynamic Router 플러그인 설치

```bash
# 플러그인 디렉토리 생성
mkdir -p kong/plugins/dynamic-router

# 플러그인 파일 복사
cp dynamic-router/handler.lua kong/plugins/dynamic-router/
cp dynamic-router/schema.lua kong/plugins/dynamic-router/

# Kong 환경변수에 플러그인 추가
export KONG_PLUGINS="bundled,dynamic-router"
```

## 4.4 Docker 환경 설정

### 4.4.1 Docker Compose 설정

**파일: `docker-compose.yml`**

```yaml
version: '3.8'

networks:
  kong_frontend:
    driver: bridge
  kong_backend:
    driver: bridge

services:
  # Backend Application
  backend-api:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: backend-api
    hostname: backend-api
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - TZ=Asia/Seoul
      # Envoy를 통해 자동 라우팅되므로 Kong URL 불필요
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    networks:
      - kong_frontend
    depends_on:
      - kong-gateway
    cap_add:
      - NET_ADMIN  # iptables 권한
    
  # Envoy Sidecar (별도 컨테이너로 구성)
  envoy-sidecar:
    image: envoyproxy/envoy:v1.28-latest
    container_name: envoy-sidecar
    network_mode: "service:backend-api"  # Backend와 네트워크 네임스페이스 공유
    volumes:
      - ./envoy/envoy.yaml:/etc/envoy/envoy.yaml:ro
      - ./scripts/setup-iptables.sh:/setup-iptables.sh:ro
    command: |
      sh -c "
        # iptables 설정
        /setup-iptables.sh &&
        # Envoy 실행
        /usr/local/bin/envoy -c /etc/envoy/envoy.yaml --service-node backend-sidecar
      "
    cap_add:
      - NET_ADMIN
    user: "1337"  # Envoy 전용 사용자
    
  # Kong Gateway
  kong-gateway:
    image: kong:3.9.0.1
    container_name: kong-gateway
    hostname: kong-gateway
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: "/opt/kong/kong.yml"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: '0.0.0.0:8001'
      KONG_PROXY_LISTEN: '0.0.0.0:8000'
      KONG_LOG_LEVEL: debug
      KONG_PLUGINS: "bundled,aws-masker,dynamic-router"
      KONG_LUA_PACKAGE_PATH: "/opt/kong/?.lua;/opt/kong/?/init.lua;;"
      # Redis 설정
      REDIS_HOST: redis-cache
      REDIS_PORT: 6379
    ports:
      - "8000:8000"
      - "8001:8001"
    volumes:
      - ./kong/kong.yml:/opt/kong/kong.yml:ro
      - ./kong/plugins:/opt/kong/plugins:ro
    networks:
      - kong_frontend
      - kong_backend
    depends_on:
      - redis-cache
      
  # Redis Cache
  redis-cache:
    image: redis:7-alpine
    container_name: redis-cache
    hostname: redis
    ports:
      - "6379:6379"
    networks:
      - kong_backend
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  redis-data:
```

### 4.4.2 iptables 설정 스크립트

**파일: `scripts/setup-iptables.sh`**

```bash
#!/bin/sh
set -e

# Envoy 프로세스 UID
ENVOY_UID=1337

echo "Configuring iptables for transparent proxy..."

# NAT 테이블 초기화
iptables -t nat -N ENVOY_REDIRECT 2>/dev/null || true
iptables -t nat -F ENVOY_REDIRECT

# TCP 트래픽을 15001 포트로 리다이렉트
iptables -t nat -A ENVOY_REDIRECT -p tcp -j REDIRECT --to-port 15001

# OUTPUT 체인 규칙 설정
# 1. Envoy 자체 트래픽은 제외
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner $ENVOY_UID -j RETURN

# 2. 로컬호스트 트래픽 제외
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1/32 -j RETURN

# 3. 내부 Docker 네트워크 제외
iptables -t nat -A OUTPUT -p tcp -d 172.16.0.0/12 -j RETURN
iptables -t nat -A OUTPUT -p tcp -d 10.0.0.0/8 -j RETURN

# 4. DNS 트래픽 제외
iptables -t nat -A OUTPUT -p udp --dport 53 -j RETURN

# 5. 나머지 모든 TCP 트래픽을 Envoy로 리다이렉트
iptables -t nat -A OUTPUT -p tcp -j ENVOY_REDIRECT

echo "iptables configuration completed"
```

## 4.5 환경별 설정

### 4.5.1 개발 환경

```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  backend-api:
    environment:
      - NODE_ENV=development
      - LOG_LEVEL=debug
      
  kong-gateway:
    environment:
      - KONG_LOG_LEVEL=debug
      - KONG_ADMIN_LISTEN=0.0.0.0:8001  # Admin API 활성화
```

### 4.5.2 운영 환경

```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  backend-api:
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
      
  kong-gateway:
    environment:
      - KONG_LOG_LEVEL=info
      - KONG_ADMIN_LISTEN=127.0.0.1:8001  # 로컬만 허용
```

## 4.6 검증 절차

### 4.6.1 Envoy 동작 확인

```bash
# Envoy 관리 인터페이스 확인
curl http://localhost:9901/clusters

# Envoy 설정 확인
curl http://localhost:9901/config_dump
```

### 4.6.2 iptables 규칙 확인

```bash
# NAT 테이블 확인
docker exec backend-api iptables -t nat -L -n -v
```

### 4.6.3 트래픽 흐름 확인

```bash
# Backend 컨테이너에서 외부 API 호출 테스트
docker exec backend-api curl -v https://api.anthropic.com/v1/messages
```

## 4.7 문제 해결

### 4.7.1 일반적인 문제

| 문제 | 원인 | 해결 방법 |
|------|------|-----------|
| 트래픽이 Envoy를 거치지 않음 | iptables 규칙 미적용 | setup-iptables.sh 재실행 |
| Kong 연결 실패 | 네트워크 설정 오류 | Docker 네트워크 확인 |
| 403 Forbidden | 호스트 미등록 | Kong allowed_hosts 추가 |

### 4.7.2 디버깅 명령어

```bash
# Envoy 로그 확인
docker logs envoy-sidecar

# Kong 로그 확인
docker logs kong-gateway

# 네트워크 연결 확인
docker exec backend-api ping kong-gateway
```

## 4.8 다음 단계

환경 설정을 완료했다면 [품질 확보 방안](05-quality-assurance-plan.md)을 참조하여 품질 기준을 확인하세요.