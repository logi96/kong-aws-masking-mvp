# Kong AWS Masker Plugin Integration Plan for PoC (Redis 포함)

## 🎯 목표
Claude Code PoC에 실제 Kong AWS Masker 플러그인을 통합하여 완전한 end-to-end 마스킹 솔루션 구현

## 📋 현재 상황 분석

### 1. **메인 프로젝트 구조**
```
/Users/tw.kim/Documents/AGA/test/Kong/
├── kong/
│   ├── kong.yml          # 프로덕션 Kong 설정
│   └── plugins/
│       └── aws-masker/   # 커스텀 플러그인 (11개 파일)
├── docker-compose.yml    # Redis 포함 프로덕션 설정
└── docker/kong/Dockerfile # Kong 3.7 커스텀 이미지
```

### 2. **PoC 프로젝트 구조**
```
/Users/tw.kim/Documents/AGA/test/Kong/claude-code-poc/
├── kong.yml              # 간단한 Kong 설정 (플러그인 없음)
├── kong-masking-proxy/   # Python 기반 마스킹 프록시
└── docker-compose.yml    # Redis 없는 간단한 설정
```

### 3. **주요 차이점**
- **Kong 버전**: 메인(3.7) vs PoC(3.9)
- **플러그인**: 메인(aws-masker 포함) vs PoC(빌트인만)
- **Redis**: 메인(필수) vs PoC(없음)
- **마스킹**: 메인(Kong 플러그인) vs PoC(Python 프록시)

### 4. **Redis 의존성 분석**
aws-masker 플러그인의 Redis 의존성이 매우 깊음:
- **handler.lua**: Redis 건강 체크, fail-secure 정책
- **event_publisher.lua**: Redis Pub/Sub 이벤트 발행
- **monitoring.lua**: 메트릭 저장
- **masker_ngx_re.lua**: 마스킹 매핑 저장/조회

Redis 제거 시 대규모 코드 수정이 필요하므로 **Redis를 포함한 통합이 현실적**

## ⚠️ 의사결정 필요 사항

### 1. **Redis 통합 시 고려사항**
- **복잡도 증가**: PoC가 단순함을 잃고 프로덕션에 가까워짐
- **보안 설정**: Redis 패스워드, 네트워크 격리 필요
- **리소스 사용**: 추가 컨테이너로 메모리/CPU 증가
- **데이터 영속성**: 마스킹 매핑 데이터 관리 필요

### 2. **대안 검토**
| 옵션 | 장점 | 단점 |
|------|------|------|
| **A. Redis 포함** | 플러그인 수정 최소화, 실제 프로덕션과 동일 | PoC 복잡도 증가, 리소스 사용 증가 |
| **B. Redis 제거** | 단순한 PoC, 독립 실행 가능 | 대규모 코드 수정 필요 (2-3일 작업) |
| **C. Python 프록시 유지** | 이미 작동 중, 단순함 유지 | Kong 플러그인 미사용 |

## 🏗️ 통합 계획 (Redis 포함 버전)

### Phase 1: Redis 서비스 추가

#### 1.1 docker-compose.yml에 Redis 추가
```yaml
services:
  # Redis 추가
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    environment:
      - REDIS_PASSWORD=testpassword123
    command: redis-server --requirepass testpassword123
    volumes:
      - redis-data:/data
    networks:
      - poc-net
    healthcheck:
      test: ["CMD", "redis-cli", "--pass", "testpassword123", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
```

#### 1.2 디렉토리 구조 생성
```bash
mkdir -p claude-code-poc/kong/plugins/aws-masker
```

#### 1.3 플러그인 파일 전체 복사
```bash
# 모든 핵심 파일 복사 (수정 없이)
- handler.lua         # 메인 플러그인 로직
- schema.lua          # 설정 스키마
- masker_ngx_re.lua   # 마스킹 엔진
- patterns.lua        # AWS 패턴 정의
- json_safe.lua       # JSON 처리
- monitoring.lua      # 모니터링
- auth_handler.lua    # 인증 처리
- error_codes.lua     # 에러 코드
- health_check.lua    # 건강 체크
- event_publisher.lua # 이벤트 발행
- pattern_integrator.lua # 패턴 통합
```

### Phase 2: Kong 설정 수정

#### 2.1 Dockerfile 생성
```dockerfile
FROM kong:3.9-ubuntu

# 커스텀 플러그인 복사
COPY ./kong/plugins/aws-masker /usr/local/share/lua/5.1/kong/plugins/aws-masker

ENV KONG_PLUGINS="bundled,aws-masker"
ENV KONG_DATABASE="off"
ENV REDIS_HOST="redis"
ENV REDIS_PORT="6379"
ENV REDIS_PASSWORD="testpassword123"
```

#### 2.2 kong.yml 수정
```yaml
plugins:
  - name: aws-masker
    route: claude-proxy-route
    config:
      use_redis: true        # Redis 활성화
      redis_fallback: true   # Redis 실패 시 fallback
      mapping_ttl: 3600      # 1시간 (PoC용 단축)
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
      mask_private_ips: true
      log_masked_requests: true
```

#### 2.3 Kong 환경 변수 추가
```yaml
kong:
  environment:
    - KONG_DATABASE=off
    - KONG_PLUGINS=bundled,aws-masker
    - REDIS_HOST=redis
    - REDIS_PORT=6379
    - REDIS_PASSWORD=testpassword123
  depends_on:
    redis:
      condition: service_healthy
```

### Phase 3: 통합 아키텍처

#### 3.1 옵션 A: Kong 플러그인만 사용
```
Claude Code → Kong(aws-masker) → Claude API
```
- 장점: 심플하고 직접적
- 단점: HTTPS 이슈 여전히 존재

#### 3.2 옵션 B: 하이브리드 접근 (권장)
```
Claude Code → HTTP Proxy(8082) → Kong(aws-masker) → Claude API
```
- 장점: HTTPS 이슈 해결 + 실제 플러그인 사용
- 단점: 추가 레이어

### Phase 4: 최소 수정 사항

#### 4.1 환경 변수 설정 (handler.lua는 수정 불필요)
플러그인이 환경 변수에서 Redis 설정을 읽으므로 별도 수정 불필요:
- `REDIS_HOST`
- `REDIS_PORT`
- `REDIS_PASSWORD`

#### 4.2 보안 설정 간소화 (선택적)
PoC용으로 Redis 보안을 간소화하려면:
```lua
-- redis.conf 수정 (선택사항)
requirepass testpassword123  # 간단한 패스워드
bind 0.0.0.0                 # 컨테이너 간 통신 허용
```

#### 4.3 완전한 docker-compose.yml
```yaml
version: '3.8'

services:
  # Redis 서비스
  redis:
    image: redis:7-alpine
    container_name: poc-redis
    ports:
      - "6379:6379"
    environment:
      - REDIS_PASSWORD=testpassword123
    command: >
      redis-server 
      --requirepass testpassword123
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
    volumes:
      - redis-data:/data
    networks:
      - poc-net
    healthcheck:
      test: ["CMD", "redis-cli", "--pass", "testpassword123", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  # Kong with aws-masker
  kong:
    build:
      context: .
      dockerfile: kong/Dockerfile
    ports:
      - "8000:8000"
      - "8001:8001"
    environment:
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/kong.yml
      - KONG_PLUGINS=bundled,aws-masker
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=testpassword123
    volumes:
      - ./kong/kong.yml:/kong.yml:ro
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - poc-net

  # HTTP Masking Proxy (HTTPS 해결)
  masking-proxy:
    build:
      context: ./kong-masking-proxy
    ports:
      - "8082:8082"
    environment:
      - KONG_URL=http://kong:8000
      - KONG_ROUTE=/claude-proxy/v1/messages
    depends_on:
      - kong
    networks:
      - poc-net

volumes:
  redis-data:

networks:
  poc-net:
    driver: bridge
```

### Phase 5: 테스트 계획

#### 5.1 단위 테스트
- 플러그인 로딩 확인
- 패턴 매칭 테스트
- 마스킹/언마스킹 검증

#### 5.2 통합 테스트
- Claude Code → Kong → Mock API
- 실제 AWS 리소스 마스킹 확인
- 성능 벤치마크

### Phase 6: 리스크 및 대응

#### 6.1 주요 리스크
1. **플러그인 호환성**: Kong 3.9에서 3.7 플러그인 동작
2. **Redis 연결 실패**: fail-secure로 인한 서비스 중단
3. **복잡도 증가**: PoC가 너무 복잡해짐

#### 6.2 대응 방안
1. **호환성**: Kong 3.7로 변경 또는 플러그인 수정
2. **Redis 안정성**: health check 강화, retry 설정
3. **복잡도**: 필수 기능만 활성화, 로깅 간소화

#### 6.3 대안: 하이브리드 접근
**Python 프록시 유지 + Kong 플러그인 부분 활용**
- Python 프록시에서 1차 마스킹
- Kong에서 추가 검증만 수행
- Redis 의존성 최소화

## 📊 예상 결과

### 성공 기준
- ✅ Kong aws-masker 플러그인이 PoC에서 정상 동작
- ✅ Claude Code가 HTTP 프록시를 통해 Kong 연결
- ✅ AWS 리소스가 정확히 마스킹됨
- ✅ Redis를 포함한 완전한 마스킹 시스템 구현

### 성능 목표
- 응답 시간: < 100ms 추가 지연
- 메모리 사용: < 100MB
- CPU 사용: < 10%

## 🚀 실행 단계

1. **준비** (30분)
   - 플러그인 파일 전체 복사
   - Redis 설정 파일 준비
   - docker-compose.yml 업데이트

2. **구현** (1시간) - 코드 수정 최소화
   - Dockerfile 작성
   - kong.yml 수정
   - 환경 변수 설정

3. **테스트** (1시간)
   - Redis 연결 확인
   - 플러그인 로딩 확인
   - End-to-end 마스킹 테스트

4. **문제 해결** (30분)
   - Kong 3.9 호환성 이슈 대응
   - Redis 연결 문제 해결

## 📝 결론 및 권고사항

### Redis 포함 통합의 장단점
**장점:**
- 플러그인 코드 수정 최소화 (몇 시간 내 완료 가능)
- 실제 프로덕션과 동일한 환경
- 모든 기능 완전 지원 (이벤트, 모니터링 포함)

**단점:**
- PoC 복잡도 상당히 증가
- 추가 컨테이너 및 리소스 필요
- 보안 설정 관리 필요

### 최종 권고
1. **단기 PoC**: 현재 Python 프록시 유지 (이미 작동 중)
2. **중기 통합**: Redis 포함 Kong 플러그인 통합
3. **장기 프로덕션**: 완전한 Kong 기반 솔루션

**결정 필요**: Redis를 포함한 복잡한 통합을 진행할지, 현재의 간단한 Python 프록시를 유지할지 선택이 필요합니다.