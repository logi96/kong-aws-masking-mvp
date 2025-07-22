# Plan: Team A - Infrastructure (FIRST)

## 🚨 우선순위: 가장 먼저 시작 (DAY 1-3)

## 팀 개요
**팀명**: Infrastructure Team  
**역할**: Docker 환경 구축, 네트워크 설정, 기본 인프라 제공  
**독립성**: 다른 팀의 작업 없이 완전히 독립적으로 진행 가능  

## CLAUDE.md 핵심 준수사항
- [ ] **Type Safety**: 모든 설정 파일에 명확한 타입 정의
- [ ] **Testing First**: 인프라 검증 스크립트 우선 작성
- [ ] **Security**: AWS 자격 증명 읽기 전용 마운트
- [ ] **Performance**: 컨테이너 리소스 최적화

## 목표 (Task Planning Rule)
- **PLAN**: Docker Compose 기반 완전한 개발/운영 환경 구축
- **GOAL**: 다른 팀이 즉시 개발을 시작할 수 있는 인프라 제공
- **METRIC**: `docker-compose up`으로 전체 시스템 기동 가능, 모든 헬스체크 통과

## 작업 목록

### Phase 1: 프로젝트 구조 초기화 (Day 1 - 4시간)

#### 1.1 디렉토리 구조 생성
```bash
kong-aws-masking-mvp/
├── docker/
│   ├── kong/
│   │   └── Dockerfile
│   └── backend/
│       └── Dockerfile
├── config/
│   ├── kong/
│   └── backend/
├── scripts/
│   ├── health-check.sh
│   └── setup.sh
└── .docker/
    └── volumes/
```

**Tasks**:
- [ ] 프로젝트 루트 디렉토리 구조 생성
- [ ] `.gitignore` 파일 작성 (`.env`, `node_modules/`, `.docker/volumes/`)
- [ ] `README-INFRA.md` 작성 (인프라 팀 문서)

#### 1.2 환경 설정 템플릿
**Tasks**:
- [ ] `.env.example` 파일 생성
- [ ] `.env.test` 파일 생성 (테스트용)
- [ ] 환경별 설정 분리 (development, staging, production)

### Phase 2: Docker Compose 구성 (Day 1-2 - 8시간)

#### 2.1 기본 docker-compose.yml 작성
```yaml
version: '3.8'

x-common-variables: &common-variables
  TZ: UTC
  LOG_LEVEL: ${LOG_LEVEL:-info}

services:
  kong:
    build:
      context: ./docker/kong
      args:
        KONG_VERSION: 3.9.0.1
    # ... 상세 설정
    
  backend:
    build:
      context: ./docker/backend
      args:
        NODE_VERSION: 20-alpine
    # ... 상세 설정

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true

volumes:
  kong-data:
  backend-data:
```

**Tasks**:
- [ ] Multi-stage Dockerfile 작성 (Kong, Backend)
- [ ] 서비스 의존성 및 헬스체크 설정
- [ ] 네트워크 격리 구성 (frontend/backend)
- [ ] 볼륨 및 바인드 마운트 설정
- [ ] 리소스 제한 설정 (CPU, Memory)
- [ ] 로깅 드라이버 구성

#### 2.2 보안 강화 설정
**Tasks**:
- [ ] Non-root 사용자 설정 (user: "1000:1000")
- [ ] Read-only 파일시스템 적용
- [ ] 시크릿 관리 체계 구축
- [ ] AWS 자격 증명 안전한 마운트

### Phase 3: Kong Gateway 인프라 (Day 2 - 6시간)

#### 3.1 Kong 컨테이너 설정
**Tasks**:
- [ ] Kong DB-less 모드 구성
- [ ] 선언적 구성 파일 경로 설정
- [ ] 플러그인 디렉토리 마운트
- [ ] Admin API 및 Proxy 포트 설정

#### 3.2 Kong 초기 설정 파일
```yaml
# config/kong/kong.template.yml
_format_version: "3.0"

services:
  - name: backend-api
    url: http://backend:3000
    routes:
      - name: analyze-route
        paths:
          - /analyze
```

**Tasks**:
- [ ] kong.template.yml 작성
- [ ] 환경별 Kong 설정 분리
- [ ] 플러그인 로드 경로 설정

### Phase 4: Backend 인프라 (Day 2 - 4시간)

#### 4.1 Backend 컨테이너 설정
**Tasks**:
- [ ] Node.js 20 Alpine 기반 이미지
- [ ] nodemon 개발 환경 설정
- [ ] 환경 변수 주입 체계
- [ ] AWS CLI v2 설치 및 설정

### Phase 5: 모니터링 및 헬스체크 (Day 3 - 6시간)

#### 5.1 헬스체크 스크립트
```bash
#!/bin/bash
# scripts/health-check.sh

# Kong Admin API
curl -f http://localhost:8001/status || exit 1

# Backend API
curl -f http://localhost:3000/health || exit 1

# Kong Proxy
curl -f http://localhost:8000 || exit 1
```

**Tasks**:
- [ ] 컨테이너별 헬스체크 구현
- [ ] 통합 헬스체크 스크립트 작성
- [ ] 자동 복구 메커니즘 설정
- [ ] 로그 수집 및 모니터링 설정

### Phase 6: 개발 도구 및 유틸리티 (Day 3 - 4시간)

#### 6.1 개발 편의 스크립트
**Tasks**:
- [ ] `scripts/setup.sh` - 초기 환경 설정
- [ ] `scripts/reset.sh` - 환경 초기화
- [ ] `scripts/logs.sh` - 통합 로그 조회
- [ ] `scripts/test-infra.sh` - 인프라 테스트

#### 6.2 Mock 서비스 제공
**Tasks**:
- [ ] Kong Mock 응답 설정 (다른 팀 개발용)
- [ ] Backend Mock 엔드포인트 (Kong 팀용)
- [ ] Claude API Mock 서버 (테스트용)

## 제공 인터페이스 (다른 팀을 위한)

### Kong 팀에게 제공
```yaml
# Kong 플러그인 개발 환경
- Plugin Directory: /usr/local/share/lua/5.1/kong/plugins
- Kong Admin API: http://localhost:8001
- Kong Proxy: http://localhost:8000
- Hot Reload 지원
```

### Backend 팀에게 제공
```yaml
# Backend API 개발 환경
- Port: 3000
- Volume Mount: ./backend:/app
- Environment Variables: 자동 주입
- AWS Credentials: 읽기 전용 마운트
```

## 성공 기준

### 기능적 요구사항
- ✅ 단일 명령으로 전체 환경 구동 (`docker-compose up`)
- ✅ 모든 서비스 헬스체크 통과
- ✅ 개발/테스트/운영 환경 분리
- ✅ 자동 재시작 및 복구

### 비기능적 요구사항
- ✅ 컨테이너 시작 시간 < 30초
- ✅ 리소스 사용량 최적화
- ✅ 보안 모범 사례 준수
- ✅ 로깅 및 모니터링 완비

## 산출물

1. **Docker 설정 파일**
   - docker-compose.yml (개발/운영)
   - Dockerfile (Kong, Backend)
   - .env.example

2. **설정 템플릿**
   - Kong 설정 템플릿
   - Backend 환경 설정

3. **스크립트**
   - 환경 설정 스크립트
   - 헬스체크 스크립트
   - 유틸리티 스크립트

4. **문서**
   - 인프라 설정 가이드
   - 트러블슈팅 가이드
   - Mock 서비스 사용법

## 일정

- **Day 1**: 프로젝트 구조 및 Docker 기본 설정
- **Day 2**: Kong/Backend 컨테이너 구성
- **Day 3**: 모니터링, 헬스체크, 개발 도구

## 참조 표준
- [19-docker-compose-best-practices.md](../../Docs/Standards/19-docker-compose-best-practices.md)
- [03-project-development-guidelines.md](../../Docs/Standards/03-project-development-guidelines.md)
- [05-service-stability-strategy.md](../../Docs/Standards/05-service-stability-strategy.md)

---

**Note**: 이 계획은 다른 팀이 의존하는 기반 인프라를 제공하므로 가장 먼저 완료되어야 합니다.