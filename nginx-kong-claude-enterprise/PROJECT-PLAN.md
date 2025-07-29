# Nginx Proxy with Kong - Enterprise Claude Code Integration Project

## 🎯 프로젝트 개요

### 목적
엔터프라이즈 수준의 Claude Code 통합 솔루션 구축
- Nginx를 통한 고성능 HTTP 프록시
- Kong Gateway의 aws-masker 플러그인을 통한 AWS 리소스 마스킹
- Redis를 통한 마스킹 데이터 영속성
- Claude Code SDK 테스트 환경

### 아키텍처
```
[Claude Code Client]
        ↓ HTTP (port 8082)
[Nginx Proxy Container]
        ↓ HTTP (internal)
[Kong Gateway Container + aws-masker]
        ↓ Redis (port 6379)
[Redis Container]
        ↑
        └── [Kong] → HTTPS → [Claude API]
```

## 📁 프로젝트 구조

```
nginx-kong-claude-enterprise/
├── README.md
├── docker-compose.yml
├── .env.example
├── .gitignore
│
├── nginx/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── conf.d/
│       └── claude-proxy.conf
│
├── kong/
│   ├── Dockerfile
│   ├── kong.yml
│   └── plugins/
│       └── aws-masker/       # 메인 프로젝트에서 복사
│           ├── handler.lua
│           ├── schema.lua
│           ├── masker_ngx_re.lua
│           ├── patterns.lua
│           ├── json_safe.lua
│           ├── monitoring.lua
│           ├── auth_handler.lua
│           ├── error_codes.lua
│           ├── health_check.lua
│           ├── event_publisher.lua
│           └── pattern_integrator.lua
│
├── redis/
│   ├── Dockerfile
│   ├── redis.conf           # 메인 프로젝트에서 복사
│   └── data/               # 볼륨 마운트
│
├── claude-client/
│   ├── Dockerfile
│   ├── test-claude.sh
│   ├── test-scenarios/
│   │   ├── ec2-test.json
│   │   ├── s3-test.json
│   │   └── multi-resource.json
│   └── package.json
│
├── scripts/
│   ├── start.sh
│   ├── stop.sh
│   ├── health-check.sh
│   └── test-e2e.sh
│
├── logs/
│   ├── nginx/
│   ├── kong/
│   └── redis/
│
└── monitoring/
    └── health-dashboard.html
```

## 🐳 컨테이너별 상세 역할

### 1. **Nginx Container** (엔터프라이즈 프록시)
**역할:**
- Claude Code의 HTTP 요청 수신 (포트 8082)
- Kong Gateway로 요청 전달
- 로드 밸런싱 (향후 확장 대비)
- 액세스 로깅 및 에러 처리

**프로세스:**
```
1. HTTP 요청 수신 (:8082)
2. 헤더 정규화 (Host: api.anthropic.com)
3. Kong으로 리버스 프록시
4. 응답 스트리밍
5. 액세스 로그 기록
```

**설정 (nginx.conf):**
```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format claude_log '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         'rt=$request_time uct="$upstream_connect_time"';

    access_log /var/log/nginx/access.log claude_log;

    # 성능 최적화
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    # 업스트림 정의
    upstream kong_backend {
        server kong:8000 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    include /etc/nginx/conf.d/*.conf;
}
```

### 2. **Kong Container** (API Gateway + 마스킹)
**역할:**
- AWS 리소스 마스킹 (aws-masker 플러그인)
- Claude API로 HTTPS 요청 전달
- Redis에 마스킹 매핑 저장
- 응답 언마스킹

**프로세스:**
```
1. Nginx로부터 요청 수신
2. aws-masker 플러그인 실행
   - AWS 패턴 검색
   - 리소스 마스킹
   - Redis에 매핑 저장
3. Claude API로 HTTPS 전송
4. 응답 수신 및 언마스킹
5. Nginx로 응답 반환
```

**설정 (kong.yml):**
```yaml
_format_version: "3.0"
_transform: true

services:
  - name: claude-api-service
    url: https://api.anthropic.com/v1/messages
    protocol: https
    host: api.anthropic.com
    port: 443
    path: /v1/messages
    retries: 3
    connect_timeout: 5000
    write_timeout: 60000
    read_timeout: 60000

routes:
  - name: claude-proxy
    service: claude-api-service
    paths:
      - /claude-proxy/v1/messages
    methods:
      - POST
    strip_path: true
    preserve_host: false

plugins:
  - name: aws-masker
    route: claude-proxy
    config:
      use_redis: true
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
      mask_private_ips: true
      preserve_structure: true
      log_masked_requests: true
      mapping_ttl: 86400  # 24시간
```

### 3. **Redis Container** (데이터 저장소)
**역할:**
- 마스킹 매핑 데이터 저장
- 이벤트 발행 (Pub/Sub)
- 세션 데이터 관리
- 데이터 영속성 보장

**프로세스:**
```
1. Kong으로부터 SET 명령 수신
2. 마스킹 매핑 저장 (TTL 적용)
3. GET 요청 시 매핑 반환
4. 주기적 RDB 스냅샷
5. AOF 로그 유지
```

### 4. **Claude Client Container** (테스트 환경)
**역할:**
- Claude Code SDK 테스트
- 다양한 AWS 리소스 시나리오 테스트
- End-to-End 검증
- 성능 측정

**프로세스:**
```
1. 테스트 시나리오 로드
2. ANTHROPIC_BASE_URL 설정
3. Claude Code SDK 호출
4. 응답 검증
5. 결과 리포트 생성
```

## 🔄 데이터 흐름

### 요청 흐름
```
1. Claude Client: POST /v1/messages (AWS 리소스 포함)
   ↓
2. Nginx: 헤더 추가, Kong으로 프록시
   ↓
3. Kong: AWS 리소스 마스킹 → Redis 저장
   ↓
4. Kong: HTTPS로 Claude API 호출
   ↓
5. Claude API: AI 응답 생성
```

### 응답 흐름
```
6. Kong: 응답 수신, 언마스킹 (Redis 조회)
   ↓
7. Nginx: 응답 스트리밍
   ↓
8. Claude Client: 원본 AWS 리소스로 복원된 응답 수신
```

## 📝 환경 변수 (.env)

```env
# Claude API
ANTHROPIC_API_KEY=sk-ant-api03-xxx

# Redis
REDIS_PASSWORD=StrongPassword123!
REDIS_MAX_MEMORY=512mb

# Kong
KONG_LOG_LEVEL=info
KONG_MEMORY_LIMIT=1024m

# Nginx
NGINX_WORKER_PROCESSES=auto
NGINX_WORKER_CONNECTIONS=1024

# Network
CLAUDE_PROXY_PORT=8082
KONG_ADMIN_PORT=8001
REDIS_PORT=6379
```

## 🚀 구현 단계

### Phase 1: 기초 설정 (2시간)
1. 프로젝트 디렉토리 생성
2. 메인 프로젝트에서 필요 파일 복사
   - Kong aws-masker 플러그인
   - Redis 설정
3. 기본 docker-compose.yml 작성
4. 네트워크 구성

### Phase 2: Nginx 구현 (1시간)
1. Nginx Dockerfile 작성
2. claude-proxy.conf 설정
3. 로깅 구성
4. 헬스체크 엔드포인트

### Phase 3: Kong 통합 (2시간)
1. Kong Dockerfile (플러그인 포함)
2. kong.yml 설정
3. 환경 변수 연결
4. Redis 연동 테스트

### Phase 4: Redis 설정 (30분)
1. redis.conf 보안 설정
2. 영속성 설정
3. 메모리 정책
4. 백업 전략

### Phase 5: Claude Client (1시간)
1. SDK 테스트 환경
2. 테스트 시나리오 작성
3. 자동화 스크립트
4. 결과 검증

### Phase 6: 통합 테스트 (1시간)
1. End-to-End 테스트
2. 성능 벤치마크
3. 에러 시나리오
4. 로그 분석

## 🛠️ 운영 스크립트

### start.sh
```bash
#!/bin/bash
echo "Starting Nginx-Kong-Claude Enterprise..."
docker-compose up -d redis
sleep 5
docker-compose up -d kong
sleep 10
docker-compose up -d nginx
docker-compose up -d claude-client
./health-check.sh
```

### health-check.sh
```bash
#!/bin/bash
echo "Checking services..."
curl -f http://localhost:8082/health || echo "Nginx: Failed"
curl -f http://localhost:8001/status || echo "Kong: Failed"
docker-compose exec redis redis-cli ping || echo "Redis: Failed"
```

## 📊 성능 목표

| 메트릭 | 목표 | 측정 방법 |
|--------|------|----------|
| 응답 시간 | < 100ms (프록시 오버헤드) | Claude Client 로그 |
| 처리량 | > 1000 RPS | 부하 테스트 |
| 메모리 | < 2GB (전체) | Docker stats |
| 가용성 | 99.9% | 헬스체크 모니터링 |

## 🔒 보안 고려사항

1. **네트워크 격리**
   - 내부 통신은 Docker 네트워크
   - 외부 노출은 Nginx 8082 포트만

2. **인증/인가**
   - API 키는 Kong에서만 관리
   - Redis 패스워드 필수

3. **로깅**
   - 민감 정보 마스킹
   - 로그 로테이션

## 🎯 성공 기준

- ✅ 4개 컨테이너 독립적 운영
- ✅ AWS 리소스 100% 마스킹/언마스킹
- ✅ 엔터프라이즈 수준 성능
- ✅ 프로덕션 배포 가능한 구조
- ✅ 기존 코드 최대한 재사용

이 계획을 통해 PoC에서 프로덕션으로 자연스럽게 전환 가능한 엔터프라이즈 솔루션을 구축할 수 있습니다.