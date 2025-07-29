# 2. 아키텍처 설계

## 2.1 전체 시스템 아키텍처

### 2.1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Backend Pod                               │
│  ┌─────────────────┐         ┌─────────────────────────┐       │
│  │  Backend App    │ ──────► │    Envoy Sidecar        │       │
│  │  (Port 3000)    │         │    (Port 15001)         │       │
│  └─────────────────┘         └──────────┬──────────────┘       │
│                                          │                       │
│  iptables rules:                        │                       │
│  - OUTPUT → REDIRECT to 15001           │                       │
└──────────────────────────────────────────┼───────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Kong Gateway Pod                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Kong Gateway                                            │   │
│  │  - Dynamic Router Plugin                                 │   │
│  │  - AWS Masker Plugin                                     │   │
│  │  - Rate Limiting                                         │   │
│  └──────────────────────┬──────────────────────────────────┘   │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
                 ┌─────────────────┐
                 │  External APIs   │
                 │ - Anthropic      │
                 │ - OpenAI         │
                 │ - Google AI      │
                 └─────────────────┘
```

### 2.1.2 네트워크 플로우

```
1. Backend App이 https://api.anthropic.com/v1/messages 호출
2. iptables가 트래픽을 Envoy (15001)로 리다이렉트
3. Envoy가 원본 호스트 정보를 헤더에 추가
4. Envoy가 Kong Gateway로 전달
5. Kong Dynamic Router가 원본 호스트 확인
6. Kong AWS Masker가 요청 본문 마스킹
7. Kong이 실제 외부 API로 전달
8. 응답이 역순으로 전달 (언마스킹 포함)
```

## 2.2 컴포넌트 상세 설계

### 2.2.1 Envoy Sidecar

**역할:**
- 투명한 프록시로 모든 외부 트래픽 가로채기
- 원본 호스트 정보 보존
- Kong Gateway로 라우팅

**주요 설정:**
```yaml
static_resources:
  listeners:
  - name: outbound_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 15001
    transparent: true  # 투명 프록시 모드
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: outbound_http
          route_config:
            name: outbound_route
            virtual_hosts:
            - name: all_domains
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: kong_gateway
                  timeout: 30s
```

### 2.2.2 iptables 규칙

**역할:**
- 네트워크 레벨에서 트래픽 강제 리다이렉션
- Envoy 자체 트래픽은 제외

**주요 규칙:**
```bash
# Envoy UID
ENVOY_UID=1337

# 리다이렉션 체인
iptables -t nat -N ENVOY_REDIRECT
iptables -t nat -A ENVOY_REDIRECT -p tcp -j REDIRECT --to-port 15001

# OUTPUT 규칙
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner $ENVOY_UID -j RETURN
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1/32 -j RETURN
iptables -t nat -A OUTPUT -p tcp -j ENVOY_REDIRECT
```

### 2.2.3 Kong Dynamic Router Plugin

**역할:**
- Envoy가 전달한 원본 호스트 정보로 동적 라우팅
- 승인된 외부 API만 허용
- AWS Masker와 통합

**주요 로직:**
```lua
function DynamicRouter:access(conf)
    local original_host = kong.request.get_header("x-original-host")
    
    -- 승인된 호스트 확인
    if not conf.allowed_hosts[original_host] then
        return kong.response.exit(403, {
            message = "Unauthorized external API",
            host = original_host
        })
    end
    
    -- 동적 upstream 설정
    kong.service.set_upstream(conf.host_mappings[original_host])
end
```

## 2.3 데이터 흐름

### 2.3.1 요청 처리 흐름

```
Backend App
    │
    ▼ POST https://api.anthropic.com/v1/messages
    │ Body: {"messages": [{"content": "Analyze EC2 i-1234567890abcdef0"}]}
    │
iptables redirect
    │
    ▼
Envoy Sidecar
    │ Add header: x-original-host: api.anthropic.com
    │
    ▼ POST http://kong-gateway:8000/
Kong Gateway
    │
    ├─► Dynamic Router Plugin
    │   └─► Set upstream: https://api.anthropic.com
    │
    ├─► AWS Masker Plugin
    │   └─► Mask: i-1234567890abcdef0 → AWS_EC2_001
    │       Body: {"messages": [{"content": "Analyze EC2 AWS_EC2_001"}]}
    │
    ▼
External API (Anthropic)
```

### 2.3.2 응답 처리 흐름

```
External API Response
    │ Body: {"content": "Analysis for AWS_EC2_001..."}
    │
    ▼
Kong Gateway
    │
    ├─► AWS Masker Plugin
    │   └─► Unmask: AWS_EC2_001 → i-1234567890abcdef0
    │       Body: {"content": "Analysis for i-1234567890abcdef0..."}
    │
    ▼
Envoy Sidecar
    │ Pass through
    │
    ▼
Backend App
```

## 2.4 컴포넌트 간 통신

### 2.4.1 프로토콜 및 포트

| 컴포넌트 | 포트 | 프로토콜 | 용도 |
|-----------|------|----------|------|
| Backend App | 3000 | HTTP | 애플리케이션 서비스 |
| Envoy Sidecar | 15001 | HTTP/HTTPS | 투명 프록시 |
| Kong Gateway | 8000 | HTTP | API 프록시 |
| Kong Admin | 8001 | HTTP | 관리 API |
| Redis | 6379 | TCP | 마스킹 매핑 저장 |

### 2.4.2 헤더 전달

```
Envoy → Kong:
- x-original-host: 원본 호스트명
- x-forwarded-for: 클라이언트 IP
- x-envoy-decorator-operation: 추적 정보

Kong → External API:
- Authorization: API 키 (Kong이 주입)
- User-Agent: Kong/3.9.0
```

## 2.5 보안 경계

### 2.5.1 네트워크 격리

```
┌─────────────────────────────────────┐
│         Trust Boundary              │
│  ┌─────────────┐  ┌──────────────┐ │
│  │ Backend App │  │ Envoy Proxy  │ │
│  └─────────────┘  └──────────────┘ │
└─────────────────────────────────────┘
                 │
                 ▼ Encrypted (TLS)
┌─────────────────────────────────────┐
│         DMZ                         │
│  ┌─────────────────────────────┐   │
│  │      Kong Gateway            │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
                 │
                 ▼ Encrypted (TLS)
┌─────────────────────────────────────┐
│      External Network               │
│  ┌─────────────────────────────┐   │
│  │      External APIs           │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

### 2.5.2 보안 정책 적용 지점

1. **iptables**: 물리적 트래픽 강제
2. **Envoy**: TLS 종료/시작
3. **Kong**: 인증, 인가, 마스킹
4. **Redis**: 매핑 데이터 암호화 저장

## 2.6 확장성 고려사항

### 2.6.1 수평 확장

```
                    ┌──────────────┐
                    │ Load Balancer│
                    └──────┬───────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Backend+Envoy│    │ Backend+Envoy│    │ Backend+Envoy│
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           ▼
                    ┌─────────────┐
                    │Kong Cluster │
                    └─────────────┘
```

### 2.6.2 성능 최적화 포인트

1. **Envoy 커넥션 풀링**
2. **Kong 캐싱 레이어**
3. **Redis 커넥션 풀**
4. **비동기 처리**

## 2.7 모니터링 포인트

### 2.7.1 메트릭 수집

- Envoy: 요청 수, 레이턴시, 에러율
- Kong: API별 사용량, 마스킹 수, 성능
- Redis: 커넥션, 메모리, 처리량

### 2.7.2 로그 수집

- Envoy 액세스 로그
- Kong 플러그인 로그
- 애플리케이션 로그

## 2.8 다음 단계

아키텍처를 이해했다면 [구현 계획](03-implementation-plan.md)을 참조하여 실제 코드 변경사항을 확인하세요.