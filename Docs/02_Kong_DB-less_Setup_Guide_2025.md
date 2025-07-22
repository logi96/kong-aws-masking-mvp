# Kong DB-less 모드 설정 가이드 (2025년 버전)

## 1. Kong DB-less 모드란?

Kong DB-less 모드는 데이터베이스 없이 Kong을 실행하는 방식입니다. 모든 설정은 YAML/JSON 파일로 관리되며, 메모리에만 저장됩니다.

### 주요 특징
- ✅ 데이터베이스 불필요
- ✅ 선언적 설정 (Declarative Configuration)
- ✅ Git으로 버전 관리 가능
- ✅ 빠른 시작과 단순한 운영
- ❌ Admin API 읽기 전용
- ❌ 노드 간 동기화 없음

## 2. 빠른 시작 가이드

### 2.1 Docker로 시작하기
```bash
# 1. kong.yml 파일 생성
cat > kong.yml << EOF
_format_version: "3.0"
_transform: true

services:
  - name: example-service
    url: http://httpbin.org
    routes:
      - name: example-route
        paths:
          - /test
EOF

# 2. Kong 실행
docker run -d --name kong \
  -e "KONG_DATABASE=off" \
  -e "KONG_DECLARATIVE_CONFIG=/kong.yml" \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
  -v "$PWD/kong.yml:/kong.yml:ro" \
  -p 8000:8000 \
  -p 8001:8001 \
  kong:3.9.0.1

# 3. 테스트
curl http://localhost:8000/test
```

### 2.2 Docker Compose로 시작하기
```yaml
# docker-compose.yml
version: '3.8'

services:
  kong:
    image: kong:3.9.0.1
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: "/kong.yml"
      KONG_PROXY_ACCESS_LOG: "/dev/stdout"
      KONG_PROXY_ERROR_LOG: "/dev/stderr"
      KONG_ADMIN_ACCESS_LOG: "/dev/stdout"
      KONG_ADMIN_ERROR_LOG: "/dev/stderr"
    volumes:
      - ./kong.yml:/kong.yml:ro
    ports:
      - "8000:8000"  # Proxy
      - "8001:8001"  # Admin API (읽기 전용)
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
```

## 3. 설정 파일 구조

### 3.1 기본 구조
```yaml
_format_version: "3.0"      # 필수: Kong 설정 형식 버전
_transform: true            # 선택: 스키마 변환 활성화

# 서비스 정의
services:
  - name: my-service
    url: https://example.com
    retries: 5
    connect_timeout: 30000
    write_timeout: 60000
    read_timeout: 60000

# 라우트 정의
routes:
  - name: my-route
    service: my-service
    paths:
      - /api
    methods:
      - GET
      - POST

# 플러그인 정의
plugins:
  - name: rate-limiting
    service: my-service
    config:
      minute: 20
      policy: local

# 컨슈머 정의 (선택)
consumers:
  - username: user1
    custom_id: "123"

# 인증 정보 (선택)
keyauth_credentials:
  - consumer: user1
    key: secret-key-123
```

### 3.2 커스텀 플러그인 추가
```yaml
# 커스텀 플러그인이 있는 경우
plugins:
  - name: aws-masker  # 커스텀 플러그인 이름
    service: my-service
    config:
      ttl: 300
      enabled: true
```

## 4. 커스텀 플러그인 설정

### 4.1 플러그인 파일 구조
```
/kong/plugins/
└── aws-masker/
    ├── handler.lua    # 플러그인 로직
    └── schema.lua     # 플러그인 설정 스키마
```

### 4.2 Kong 환경변수 설정
```bash
# 커스텀 플러그인 활성화
KONG_PLUGINS=bundled,aws-masker

# Lua 경로 추가
KONG_LUA_PACKAGE_PATH=/kong/plugins/?.lua;;
```

### 4.3 Docker에서 커스텀 플러그인 사용
```dockerfile
FROM kong:3.9.0.1

# 커스텀 플러그인 복사
COPY ./plugins/aws-masker /usr/local/share/lua/5.1/kong/plugins/aws-masker

# 환경변수 설정
ENV KONG_PLUGINS="bundled,aws-masker"
```

## 5. 중요 제한사항

### 5.1 Admin API 제한
DB-less 모드에서는 Admin API가 **읽기 전용**입니다:
```bash
# ✅ 가능: GET 요청
curl http://localhost:8001/services

# ❌ 불가능: POST, PUT, PATCH, DELETE
curl -X POST http://localhost:8001/services \
  -d "name=new-service" \
  -d "url=http://example.com"
# 응답: HTTP 405 Method Not Allowed
```

### 5.2 플러그인 호환성
일부 플러그인은 DB-less 모드에서 작동하지 않습니다:
- ❌ oauth2 (데이터베이스 필요)
- ❌ session (데이터베이스 필요)
- ✅ key-auth (메모리 사용 가능)
- ✅ rate-limiting (local 정책만)
- ✅ 대부분의 커스텀 플러그인

### 5.3 메모리 설정
```bash
# LMDB 메모리 맵 크기 설정 (기본값: 2048m)
KONG_LMDB_MAP_SIZE=1024m

# Nginx shared dict 크기
lua_shared_dict kong_cache 128m;
lua_shared_dict masking_cache 100m;  # 커스텀 캐시
```

## 6. 운영 팁

### 6.1 설정 검증
```bash
# 설정 파일 검증
kong config parse /path/to/kong.yml

# Docker에서 검증
docker run --rm -v "$PWD/kong.yml:/kong.yml:ro" \
  kong:3.9.0.1 kong config parse /kong.yml
```

### 6.2 설정 리로드
DB-less 모드에서는 설정 변경 시 Kong을 재시작해야 합니다:
```bash
# Docker 재시작
docker restart kong

# 또는 SIGHUP 시그널 (일부 변경사항만 적용)
docker kill -s HUP kong
```

### 6.3 디버깅
```bash
# 로그 레벨 설정
KONG_LOG_LEVEL=debug

# 플러그인 디버깅
kong.log.debug("마스킹 전:", original_value)
kong.log.info("마스킹 후:", masked_value)
```

## 7. 성능 고려사항

### 7.1 메모리 사용량
- 모든 설정이 메모리에 로드됨
- 대규모 설정 시 충분한 메모리 필요
- 권장: 최소 512MB, 프로덕션 2GB+

### 7.2 시작 시간
- 설정 파일 크기에 비례
- 1000개 서비스 기준 약 5-10초

### 7.3 제한사항
- 동적 설정 변경 불가
- 실시간 모니터링 제한
- 중앙 집중식 관리 불가

## 8. 프로덕션 체크리스트

- [ ] 설정 파일 버전 관리 (Git)
- [ ] 자동화된 검증 파이프라인
- [ ] 충분한 메모리 할당
- [ ] 헬스체크 설정
- [ ] 로그 수집 설정
- [ ] 백업 전략 수립

## 9. 문제 해결

### 9.1 자주 발생하는 오류
```bash
# 오류: "database" 설정 누락
Error: no configuration file found

# 해결: KONG_DATABASE=off 환경변수 확인

# 오류: 플러그인 찾을 수 없음
Error: plugin 'aws-masker' not found

# 해결: KONG_PLUGINS 환경변수에 플러그인 추가
```

### 9.2 유용한 명령어
```bash
# Kong 버전 확인
kong version

# 설정 덤프
curl http://localhost:8001/ | jq .

# 로드된 플러그인 확인
curl http://localhost:8001/plugins/enabled | jq .
```

---
이 가이드를 따라 Kong DB-less 모드를 빠르게 시작하고 운영할 수 있습니다.
