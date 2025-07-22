# Plan: Team C - Backend API Development

## 팀 개요
**팀명**: Backend API Team  
**역할**: Node.js API 서버, AWS CLI 통합, Claude API 연동  
**독립성**: Mock Kong Gateway를 사용하여 독립적 개발 가능  
**시작 조건**: Infrastructure 팀의 Docker 환경 준비 완료 후

## CLAUDE.md 핵심 준수사항
- [ ] **Type Safety**: 모든 JavaScript 코드에 JSDoc annotations 필수
- [ ] **Testing First**: Jest를 사용한 TDD 적용
- [ ] **Lint & Typecheck**: 모든 커밋 전 `npm run lint` 및 `npm run type-check`
- [ ] **Response Time**: 모든 API 응답 < 5초

## 목표 (Task Planning Rule)
- **PLAN**: Express.js 기반 RESTful API로 AWS 데이터 수집 및 Claude AI 분석
- **GOAL**: AWS CLI 실행 결과를 Kong을 통해 마스킹 후 Claude API로 분석
- **METRIC**: 모든 엔드포인트 5초 이내 응답, 테스트 커버리지 > 70%

## 작업 목록

### Phase 1: 프로젝트 초기화 (Day 2 - 4시간)

#### 1.1 Node.js 프로젝트 설정
```
backend/
├── src/
│   ├── api/
│   │   ├── routes/
│   │   └── middlewares/
│   ├── services/
│   │   ├── aws/
│   │   └── claude/
│   ├── utils/
│   ├── types/
│   └── app.js
├── tests/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── server.js
├── package.json
├── jsconfig.json
└── .eslintrc.js
```

**Tasks**:
- [ ] package.json 생성 및 의존성 정의
- [ ] jsconfig.json 설정 (Type checking)
- [ ] .eslintrc.js 설정 (Code standards)
- [ ] 기본 디렉토리 구조 생성
- [ ] Git hooks 설정 (pre-commit lint/typecheck)

#### 1.2 개발 환경 설정
**Tasks**:
- [ ] VS Code 설정 (.vscode/settings.json)
- [ ] nodemon 개발 서버 설정
- [ ] 환경 변수 관리 체계 구축
- [ ] 로깅 설정 (winston/morgan)

### Phase 2: 기본 API 구조 (Day 2-3 - 8시간)

#### 2.1 Express.js 앱 구성
```javascript
// src/app.js
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');

/**
 * Express 애플리케이션 생성 및 설정
 * @returns {express.Application} 설정된 Express 앱
 */
function createApp() {
  const app = express();
  
  // 미들웨어 설정
  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: '10mb' }));
  
  // 라우트 등록
  app.use('/api/v1', routes);
  
  // 에러 핸들러
  app.use(errorHandler);
  
  return app;
}
```

**Tasks**:
- [ ] TDD: Express 앱 테스트 작성
- [ ] 기본 Express 서버 구성
- [ ] 보안 미들웨어 설정 (helmet, cors)
- [ ] 요청 파싱 미들웨어 설정
- [ ] 전역 에러 핸들러 구현

#### 2.2 라우트 구조 설계
```javascript
// src/api/routes/analyze.route.js
/**
 * @typedef {Object} AnalyzeRequest
 * @property {string} command - AWS CLI 명령어
 * @property {Object} [options] - 추가 옵션
 */

/**
 * @typedef {Object} AnalyzeResponse
 * @property {boolean} success
 * @property {Object} data
 * @property {string} timestamp
 */

/**
 * AWS 리소스 분석 라우트
 * @param {express.Request<{}, {}, AnalyzeRequest>} req
 * @param {express.Response<AnalyzeResponse>} res
 */
async function analyzeRoute(req, res) {
  // 구현
}
```

**Tasks**:
- [ ] TDD: 라우트 테스트 작성
- [ ] `/analyze` POST 엔드포인트
- [ ] `/health` GET 엔드포인트
- [ ] `/status` GET 엔드포인트
- [ ] 요청 검증 미들웨어

### Phase 3: AWS CLI 통합 (Day 3-4 - 12시간)

#### 3.1 AWS 서비스 모듈
```javascript
// src/services/aws/awsClient.js
const { exec } = require('child_process');
const { promisify } = require('util');

/**
 * AWS CLI 명령 실행 서비스
 */
class AWSClient {
  /**
   * AWS CLI 명령 실행
   * @param {string} command - AWS CLI 명령
   * @param {Object} options - 실행 옵션
   * @returns {Promise<Object>} 실행 결과
   */
  async execute(command, options = {}) {
    // 구현
  }
}
```

**Tasks**:
- [ ] TDD: AWS CLI 실행 테스트 작성
- [ ] AWS CLI 명령 실행 모듈
- [ ] 명령어 검증 및 sanitization
- [ ] 실행 결과 파싱
- [ ] 에러 처리 및 재시도 로직
- [ ] 타임아웃 처리 (5초 제한)

#### 3.2 지원 AWS 명령어
**Tasks**:
- [ ] EC2 인스턴스 목록 조회
- [ ] S3 버킷 목록 조회
- [ ] RDS 인스턴스 정보 조회
- [ ] VPC 네트워크 정보 조회
- [ ] 명령어 화이트리스트 구현

### Phase 4: Claude API 통합 (Day 4-5 - 10시간)

#### 4.1 Claude 서비스 모듈
```javascript
// src/services/claude/claudeClient.js
const Anthropic = require('@anthropic-ai/sdk');

/**
 * Claude API 클라이언트
 */
class ClaudeClient {
  /**
   * @param {string} apiKey - Anthropic API 키
   */
  constructor(apiKey) {
    this.client = new Anthropic({ apiKey });
  }

  /**
   * AWS 데이터 분석 요청
   * @param {Object} maskedData - 마스킹된 AWS 데이터
   * @returns {Promise<Object>} 분석 결과
   */
  async analyzeAWSData(maskedData) {
    // 구현
  }
}
```

**Tasks**:
- [ ] TDD: Claude API 통합 테스트 작성
- [ ] Claude SDK 설정 및 초기화
- [ ] 프롬프트 엔지니어링
- [ ] 응답 파싱 및 검증
- [ ] API 에러 처리
- [ ] Rate limiting 처리

#### 4.2 Mock Kong Gateway 인터페이스
```javascript
// tests/mocks/kongGateway.js
/**
 * Kong Gateway Mock for development
 */
class MockKongGateway {
  /**
   * 마스킹 시뮬레이션
   * @param {Object} data - 원본 데이터
   * @returns {Object} 마스킹된 데이터
   */
  maskData(data) {
    // Mock 마스킹 로직
  }
}
```

**Tasks**:
- [ ] Kong 마스킹 Mock 구현
- [ ] 언마스킹 Mock 구현
- [ ] Mock 응답 데이터 준비

### Phase 5: 에러 처리 및 안정성 (Day 5 - 6시간)

#### 5.1 커스텀 에러 클래스
```javascript
// src/utils/errors.js
/**
 * 애플리케이션 에러 클래스
 * @extends Error
 */
class AppError extends Error {
  /**
   * @param {string} message - 에러 메시지
   * @param {number} statusCode - HTTP 상태 코드
   * @param {string} code - 에러 코드
   */
  constructor(message, statusCode, code) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
  }
}
```

**Tasks**:
- [ ] 커스텀 에러 클래스 구현
- [ ] 에러 핸들링 미들웨어
- [ ] 에러 로깅 체계
- [ ] Circuit breaker 패턴 구현
- [ ] Graceful shutdown 처리

#### 5.2 모니터링 및 헬스체크
**Tasks**:
- [ ] 헬스체크 엔드포인트 구현
- [ ] 메트릭 수집 (응답 시간, 에러율)
- [ ] 리소스 모니터링
- [ ] 알림 시스템 연동 준비

### Phase 6: 성능 최적화 및 문서화 (Day 6 - 6시간)

#### 6.1 성능 최적화
**Tasks**:
- [ ] 응답 캐싱 전략
- [ ] 동시 요청 처리 최적화
- [ ] 메모리 사용량 프로파일링
- [ ] 부하 테스트 및 튜닝

#### 6.2 API 문서화
**Tasks**:
- [ ] OpenAPI/Swagger 스펙 작성
- [ ] API 사용 가이드
- [ ] 에러 코드 문서
- [ ] 배포 가이드

## Mock 인터페이스 정의

### Kong Gateway Mock (Backend 팀 독립 개발용)
```javascript
// Kong이 마스킹한 데이터 예시
{
  "instances": [
    { "id": "EC2_001", "ip": "PRIVATE_IP_001" }
  ],
  "buckets": ["BUCKET_001", "BUCKET_002"]
}
```

### AWS CLI Mock 응답
```javascript
// AWS CLI 실행 결과 Mock
{
  "Instances": [
    {
      "InstanceId": "i-1234567890abcdef0",
      "PrivateIpAddress": "10.0.0.1"
    }
  ]
}
```

## 성공 기준

### 기능적 요구사항
- ✅ AWS CLI 명령 안전한 실행
- ✅ Claude API 성공적 통합
- ✅ 모든 엔드포인트 정상 작동
- ✅ 에러 상황 graceful 처리

### 비기능적 요구사항
- ✅ 응답 시간 < 5초
- ✅ JSDoc 타입 100% 적용
- ✅ 테스트 커버리지 > 70%
- ✅ ESLint 규칙 100% 준수

## 산출물

1. **소스 코드**
   - Express.js API 서버
   - AWS CLI 통합 모듈
   - Claude API 클라이언트
   - 유틸리티 및 헬퍼

2. **테스트 코드**
   - 단위 테스트 (Jest)
   - 통합 테스트
   - E2E 테스트

3. **설정 파일**
   - package.json
   - jsconfig.json
   - .eslintrc.js

4. **문서**
   - API 문서 (Swagger)
   - 개발 가이드
   - 배포 가이드

## 일정

- **Day 2**: 프로젝트 초기화 및 기본 구조
- **Day 3-4**: AWS CLI 통합 개발
- **Day 4-5**: Claude API 통합
- **Day 5-6**: 안정성, 최적화, 문서화

## 참조 표준
- [02-code-standards-base-rules.md](../../Docs/Standards/02-code-standards-base-rules.md) (JavaScript 섹션)
- [09-jsdoc-type-safety-guide.md](../../Docs/Standards/09-jsdoc-type-safety-guide.md)
- [01-tdd-strategy-guide.md](../../Docs/Standards/01-tdd-strategy-guide.md)
- [03-project-development-guidelines.md](../../Docs/Standards/03-project-development-guidelines.md)
- [05-service-stability-strategy.md](../../Docs/Standards/05-service-stability-strategy.md)

---

**Note**: 이 팀은 Infrastructure 팀이 제공하는 환경에서 Mock Kong Gateway를 사용하여 독립적으로 개발합니다.