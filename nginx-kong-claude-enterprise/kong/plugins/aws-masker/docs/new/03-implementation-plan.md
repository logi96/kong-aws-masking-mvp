# 3. 구현 계획

## 3.1 구현 로드맵

### 3.1.1 전체 일정 (5주)

| 주차 | 작업 내용 | 산출물 |
|------|-----------|--------|
| 1주차 | Envoy 설정 및 PoC | Envoy 컨테이너, 기본 라우팅 |
| 2주차 | Kong Dynamic Router 개발 | 플러그인 코드, 단위 테스트 |
| 3주차 | 통합 및 AWS Masker 연동 | 통합 시스템, 통합 테스트 |
| 4주차 | 성능 최적화 및 모니터링 | 성능 벤치마크, 대시보드 |
| 5주차 | 문서화 및 배포 준비 | 운영 문서, 배포 스크립트 |

## 3.2 주요 변경사항 (Before/After)

### 3.2.1 Backend 배포 설정

**BEFORE: (docker-compose.yml)**
```yaml
version: '3.8'
services:
  backend-api:
    build: ./backend
    container_name: backend-api
    ports:
      - "3000:3000"
    environment:
      - CLAUDE_API_URL=http://kong:8000/claude-proxy/v1/messages
    networks:
      - kong_frontend
```

**AFTER: (docker-compose.yml)**
```yaml
version: '3.8'
services:
  backend-api:
    build: ./backend
    container_name: backend-api
    ports:
      - "3000:3000"
    # Envoy Sidecar 제거 - 환경변수 불필요
    networks:
      - kong_frontend
    # Sidecar 컨테이너 추가
    depends_on:
      - envoy-sidecar
      
  envoy-sidecar:
    image: envoyproxy/envoy:v1.28-latest
    container_name: backend-envoy
    volumes:
      - ./envoy/envoy.yaml:/etc/envoy/envoy.yaml:ro
    cap_add:
      - NET_ADMIN
    network_mode: "container:backend-api"  # 네트워크 네임스페이스 공유
    command: ["/usr/local/bin/envoy", "-c", "/etc/envoy/envoy.yaml"]
```

### 3.2.2 Backend 서비스 코드

**BEFORE: (claudeService.js)**
```javascript
class ClaudeService {
  constructor() {
    this.apiKey = process.env.ANTHROPIC_API_KEY;
    this.model = process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-20241022';
    // 환경변수로 Kong URL 지정
    this.claudeApiUrl = process.env.CLAUDE_API_URL || 'https://api.anthropic.com/v1/messages';
  }
  
  async sendClaudeRequest(request) {
    const response = await axios.post(
      this.claudeApiUrl,  // Kong URL 사용
      request,
      {
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': '2023-06-01'
        }
      }
    );
    return response.data;
  }
}
```

**AFTER: (claudeService.js)**
```javascript
class ClaudeService {
  constructor() {
    this.apiKey = process.env.ANTHROPIC_API_KEY;
    this.model = process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-20241022';
    // 직접 외부 API URL 사용 (Envoy가 자동으로 가로챔)
    this.claudeApiUrl = 'https://api.anthropic.com/v1/messages';
  }
  
  async sendClaudeRequest(request) {
    const response = await axios.post(
      this.claudeApiUrl,  // 직접 호출 (투명하게 Kong 경유)
      request,
      {
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': '2023-06-01'
        }
      }
    );
    return response.data;
  }
}
```

### 3.2.3 Kong 설정

**BEFORE: (kong.yml)**
```yaml
_format_version: "3.0"

services:
  - name: claude-api-service
    url: https://api.anthropic.com/v1/messages
    
routes:
  - name: claude-proxy
    service: claude-api-service
    paths:
      - /claude-proxy/v1/messages
      
plugins:
  - name: aws-masker
    route: claude-proxy
    config:
      use_redis: true
      mask_ec2_instances: true
```

**AFTER: (kong.yml)**
```yaml
_format_version: "3.0"

services:
  - name: dynamic-external-api
    url: http://placeholder  # Dynamic Router가 실제 URL 설정
    
routes:
  - name: external-api-route
    service: dynamic-external-api
    paths:
      - /
    preserve_host: false
    
plugins:
  # 새로운 Dynamic Router 플러그인
  - name: dynamic-router
    service: dynamic-external-api
    config:
      allowed_hosts:
        api.anthropic.com: "https://api.anthropic.com"
        api.openai.com: "https://api.openai.com"
        aiplatform.googleapis.com: "https://aiplatform.googleapis.com"
        
  # 기존 AWS Masker 플러그인 유지
  - name: aws-masker
    service: dynamic-external-api
    config:
      use_redis: true
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
```

### 3.2.4 Kong Dynamic Router 플러그인 (신규)

**NEW FILE: (kong/plugins/dynamic-router/handler.lua)**
```lua
local DynamicRouter = {
  PRIORITY = 2000,  -- AWS Masker보다 먼저 실행
  VERSION = "1.0.0"
}

function DynamicRouter:access(conf)
  -- Envoy가 전달한 원본 호스트 헤더
  local original_host = kong.request.get_header("x-original-host")
  
  if not original_host then
    kong.log.err("Missing x-original-host header")
    return kong.response.exit(400, {
      message = "Bad Gateway Configuration"
    })
  end
  
  -- 허용된 호스트 확인
  local upstream_url = conf.allowed_hosts[original_host]
  if not upstream_url then
    kong.log.warn("Unauthorized external API access attempt: ", original_host)
    return kong.response.exit(403, {
      message = "Unauthorized external API",
      attempted_host = original_host
    })
  end
  
  -- 동적으로 upstream 설정
  kong.service.set_upstream(upstream_url)
  
  -- 원본 호스트를 Host 헤더로 설정
  kong.service.request.set_header("Host", original_host)
  
  -- 추적을 위한 헤더 추가
  kong.service.request.set_header("X-Kong-Routed-Via", "dynamic-router")
  
  kong.log.info("Routing to ", upstream_url, " for host ", original_host)
end

return DynamicRouter
```

**NEW FILE: (kong/plugins/dynamic-router/schema.lua)**
```lua
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "dynamic-router",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allowed_hosts = {
              type = "map",
              keys = { type = "string" },
              values = { type = "string" },
              required = true,
              default = {}
          }},
          { debug = { type = "boolean", default = false }},
        }
    }}
  }
}
```

### 3.2.5 Envoy 설정 파일

**NEW FILE: (envoy/envoy.yaml)**
```yaml
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901

static_resources:
  listeners:
  - name: outbound_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 15001
    transparent: true
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: outbound_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.lua
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
              inline_code: |
                function envoy_on_request(request_handle)
                  -- 원본 Authority(Host) 헤더 저장
                  local authority = request_handle:headers():get(":authority")
                  if authority then
                    request_handle:headers():add("x-original-host", authority)
                    -- Kong Gateway로 리라우트
                    request_handle:headers():replace(":authority", "kong-gateway:8000")
                    request_handle:logInfo("Routing " .. authority .. " to Kong Gateway")
                  end
                end
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
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

  clusters:
  - name: kong_gateway
    connect_timeout: 5s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    lb_policy: ROUND_ROBIN
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

### 3.2.6 iptables 초기화 스크립트

**NEW FILE: (scripts/setup-iptables.sh)**
```bash
#!/bin/bash
set -e

# Envoy 사용자 UID (컨테이너 내부)
ENVOY_UID=1337

echo "Setting up iptables rules for transparent proxy..."

# 새로운 체인 생성
iptables -t nat -N ENVOY_REDIRECT 2>/dev/null || true
iptables -t nat -F ENVOY_REDIRECT

# 리다이렉션 규칙
iptables -t nat -A ENVOY_REDIRECT -p tcp -j REDIRECT --to-port 15001

# OUTPUT 체인 규칙
# Envoy 자체 트래픽은 제외
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner $ENVOY_UID -j RETURN
# 로컬 트래픽 제외
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1/32 -j RETURN
# 내부 네트워크 제외 (Docker 네트워크)
iptables -t nat -A OUTPUT -p tcp -d 172.16.0.0/12 -j RETURN
# 나머지 모든 트래픽을 Envoy로
iptables -t nat -A OUTPUT -p tcp -j ENVOY_REDIRECT

echo "iptables rules configured successfully"
```

## 3.3 단계별 구현 가이드

### 3.3.1 Phase 1: Envoy 설정 (1주차)

1. **Envoy 컨테이너 이미지 준비**
   ```bash
   docker pull envoyproxy/envoy:v1.28-latest
   ```

2. **기본 Envoy 설정 테스트**
   ```bash
   docker run --rm -v $(pwd)/envoy:/etc/envoy \
     envoyproxy/envoy:v1.28-latest \
     -c /etc/envoy/envoy.yaml --mode validate
   ```

3. **iptables 스크립트 테스트**
   ```bash
   docker run --rm --cap-add=NET_ADMIN \
     --entrypoint sh envoyproxy/envoy:v1.28-latest \
     -c "iptables -t nat -L"
   ```

### 3.3.2 Phase 2: Kong Plugin 개발 (2주차)

1. **플러그인 디렉토리 구조 생성**
   ```
   kong/plugins/dynamic-router/
   ├── handler.lua
   ├── schema.lua
   └── spec/
       └── handler_spec.lua
   ```

2. **단위 테스트 작성**
   ```lua
   -- spec/handler_spec.lua
   describe("Dynamic Router Plugin", function()
     it("routes to correct upstream", function()
       -- 테스트 구현
     end)
   end)
   ```

### 3.3.3 Phase 3: 통합 테스트 (3주차)

1. **통합 환경 구성**
2. **End-to-End 테스트**
3. **AWS Masker 연동 검증**

### 3.3.4 Phase 4: 성능 최적화 (4주차)

1. **부하 테스트**
2. **병목 지점 분석**
3. **최적화 적용**

### 3.3.5 Phase 5: 배포 준비 (5주차)

1. **배포 스크립트 작성**
2. **롤백 계획 수립**
3. **운영 문서 작성**

## 3.4 주요 고려사항

### 3.4.1 하위 호환성

- Backend 코드는 환경변수 제거 외 변경 없음
- 기존 Kong 플러그인 100% 호환
- 점진적 마이그레이션 가능

### 3.4.2 성능 영향

- 예상 추가 레이턴시: 2-3ms
- CPU 오버헤드: 5% 이내
- 메모리 사용: Envoy 약 50MB

## 3.5 다음 단계

구현 계획을 이해했다면 [환경 설정 가이드](04-environment-setup-guide.md)를 참조하여 상세 설정 방법을 확인하세요.