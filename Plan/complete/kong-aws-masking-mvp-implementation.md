# Plan: Kong AWS Masking MVP Implementation

## 🚨 CLAUDE.md 핵심 지침 준수 사항

### 필수 규칙 체크리스트
- [ ] **Type Safety**: 모든 JavaScript 코드에 JSDoc annotations 사용
- [ ] **Testing First**: 구현 전 테스트 작성 (TDD)
- [ ] **Lint & Typecheck**: 코드 변경 후 `npm run lint` 및 `npm run type-check` 실행
- [ ] **Documentation**: 프로젝트 문서는 `/Docs/`, 표준은 `/Docs/Standards/`에 위치
- [ ] **Security**: AWS 리소스는 외부 API 호출 전 반드시 마스킹
- [ ] **Performance**: 모든 작업 5초 이내 응답

### Task Planning Rule (필수)
- **PLAN**: 각 작업의 구체적인 실행 방법
- **GOAL**: 달성하고자 하는 목표
- **METRIC**: 성공 측정 기준

## 프로젝트 개요

**목적**: AWS 리소스 식별자를 Claude API 분석 전에 마스킹하는 보안 중심 API Gateway MVP 구현

**아키텍처**:
```
Backend API (3000) → Kong Gateway (8000) → Claude API
    ↓                      ↓                    ↓
AWS CLI 실행         마스킹/언마스킹        AI 분석
```

## 구현 계획

### Phase 1: 환경 설정 및 기본 구조 (Day 1-2)

#### 1.1 프로젝트 초기화
- **PLAN**: 필수 디렉토리 구조 생성 및 설정 파일 구성
- **GOAL**: 표준 준수하는 프로젝트 구조 확립
- **METRIC**: 모든 필수 디렉토리와 설정 파일 존재

**Tasks**:
- [ ] 프로젝트 루트 디렉토리 구조 생성
- [ ] `.gitignore` 파일 생성 (`.env`, `node_modules/` 등)
- [ ] `jsconfig.json` 설정 (Type Safety)
- [ ] `.vscode/settings.json` 설정 (자동 타입 체크)
- [ ] `package.json` 생성 및 기본 스크립트 설정

#### 1.2 Docker 환경 구성
- **PLAN**: Docker Compose 기반 개발 환경 구축
- **GOAL**: 일관된 개발/배포 환경 제공
- **METRIC**: `docker-compose up` 명령으로 전체 시스템 실행 가능

**Tasks**:
- [ ] `docker-compose.yml` 작성 (Kong, Backend, 네트워크 설정)
- [ ] Kong 설정 디렉토리 구조 생성
- [ ] Backend Dockerfile 작성
- [ ] 환경 변수 템플릿 (`.env.example`) 생성

### Phase 2: Kong Gateway 설정 (Day 3-4)

#### 2.1 Kong 기본 구성
- **PLAN**: DB-less 모드 Kong Gateway 설정
- **GOAL**: 선언적 구성으로 Kong 운영
- **METRIC**: Kong Admin API 및 Proxy 정상 작동

**Tasks**:
- [ ] `kong/kong.yml` 선언적 구성 파일 작성
- [ ] 서비스 및 라우트 정의
- [ ] 플러그인 디렉토리 구조 생성

#### 2.2 AWS Masker 플러그인 개발
- **PLAN**: Lua 기반 커스텀 Kong 플러그인 구현
- **GOAL**: AWS 리소스 자동 마스킹/언마스킹
- **METRIC**: 모든 정의된 AWS 리소스 패턴 100% 마스킹

**Tasks**:
- [ ] 플러그인 테스트 작성 (TDD)
- [ ] `handler.lua` - 요청/응답 처리 로직
- [ ] `schema.lua` - 플러그인 설정 스키마
- [ ] 마스킹 패턴 구현 (EC2, S3, RDS, Private IP)
- [ ] 마스킹 맵 저장 메커니즘

### Phase 3: Backend API 개발 (Day 5-6)

#### 3.1 Node.js API 서버
- **PLAN**: Express 기반 RESTful API 구현
- **GOAL**: AWS CLI 실행 및 결과 처리
- **METRIC**: 모든 엔드포인트 5초 이내 응답

**Tasks**:
- [ ] API 테스트 작성 (TDD)
- [ ] `server.js` 구현 (JSDoc 타입 포함)
- [ ] `/analyze` 엔드포인트 - AWS 데이터 분석
- [ ] `/health` 엔드포인트 - 헬스 체크
- [ ] 에러 핸들링 미들웨어
- [ ] AWS CLI 실행 모듈

#### 3.2 Claude API 통합
- **PLAN**: Anthropic SDK를 통한 Claude API 연동
- **GOAL**: 마스킹된 데이터로 안전한 AI 분석
- **METRIC**: API 키 노출 없이 정상 통신

**Tasks**:
- [ ] Claude API 클라이언트 설정
- [ ] 요청/응답 처리 로직
- [ ] 타임아웃 및 재시도 로직
- [ ] 응답 언마스킹 처리

### Phase 4: 테스트 및 검증 (Day 7-8)

#### 4.1 통합 테스트
- **PLAN**: 전체 시스템 플로우 검증
- **GOAL**: End-to-End 정상 작동 확인
- **METRIC**: 모든 테스트 케이스 통과

**Tasks**:
- [ ] `tests/simple-test.js` 구현
- [ ] `tests/quick-check.sh` 스크립트 작성
- [ ] 마스킹/언마스킹 정확도 테스트
- [ ] 성능 테스트 (5초 응답 시간)
- [ ] 에러 시나리오 테스트

#### 4.2 코드 품질 검증
- **PLAN**: 린트 및 타입 체크 통과
- **GOAL**: 코드 표준 100% 준수
- **METRIC**: 린트/타입 에러 0개

**Tasks**:
- [ ] ESLint 규칙 설정 및 실행
- [ ] JSDoc 타입 검증
- [ ] 코드 리뷰 체크리스트 적용
- [ ] 성능 벤치마크 실행

### Phase 5: 문서화 및 배포 준비 (Day 9-10)

#### 5.1 문서 완성
- **PLAN**: 프로젝트 문서 표준 준수
- **GOAL**: 완전한 프로젝트 문서화
- **METRIC**: 모든 필수 문서 작성 완료

**Tasks**:
- [ ] README.md 업데이트
- [ ] API 문서 작성
- [ ] 배포 가이드 작성
- [ ] 트러블슈팅 가이드

#### 5.2 CI/CD 파이프라인
- **PLAN**: GitHub Actions 워크플로우 구성
- **GOAL**: 자동화된 테스트 및 배포
- **METRIC**: 커밋 시 자동 검증 통과

**Tasks**:
- [ ] `.github/workflows/ci.yml` 작성
- [ ] 자동 테스트 실행 설정
- [ ] Docker 이미지 빌드 자동화
- [ ] 배포 스테이지 구성

## 성공 기준

### 기능적 요구사항
- ✅ AWS 리소스 100% 마스킹
- ✅ Claude API 정상 통합
- ✅ 5초 이내 응답 시간
- ✅ 에러 복구 메커니즘

### 비기능적 요구사항
- ✅ JSDoc 타입 안전성
- ✅ TDD 방법론 적용
- ✅ 코드 표준 준수
- ✅ 포괄적인 문서화

## 위험 관리

### 식별된 위험
1. **AWS 자격 증명 노출**: 읽기 전용 마운트로 완화
2. **마스킹 실패**: 철저한 패턴 테스트로 방지
3. **성능 저하**: 캐싱 및 최적화 적용
4. **Claude API 제한**: 재시도 로직 구현

### 완화 전략
- 보안 감사 체크리스트 적용
- 성능 모니터링 설정
- 롤백 전략 준비
- 에러 로깅 강화

## 타임라인

**총 예상 기간**: 10 작업일

- Week 1: 환경 설정, Kong 플러그인, Backend API
- Week 2: 테스트, 품질 검증, 문서화, CI/CD

## 참조 문서

### 필수 참조
- [02-code-standards-base-rules.md](../../Docs/Standards/02-code-standards-base-rules.md)
- [01-tdd-strategy-guide.md](../../Docs/Standards/01-tdd-strategy-guide.md)
- [09-jsdoc-type-safety-guide.md](../../Docs/Standards/09-jsdoc-type-safety-guide.md)
- [17-kong-plugin-development-guide.md](../../Docs/Standards/17-kong-plugin-development-guide.md)
- [18-aws-resource-masking-patterns.md](../../Docs/Standards/18-aws-resource-masking-patterns.md)

### 추가 참조
- [03-project-development-guidelines.md](../../Docs/Standards/03-project-development-guidelines.md)
- [04-code-quality-assurance.md](../../Docs/Standards/04-code-quality-assurance.md)
- [05-service-stability-strategy.md](../../Docs/Standards/05-service-stability-strategy.md)
- [06-ci-cd-pipeline-guide.md](../../Docs/Standards/06-ci-cd-pipeline-guide.md)

---

**Note**: 이 계획은 CLAUDE.md의 모든 지침을 엄격히 준수하며, 특히 Task Planning Rule (PLAN-GOAL-METRIC)을 모든 작업에 적용했습니다.