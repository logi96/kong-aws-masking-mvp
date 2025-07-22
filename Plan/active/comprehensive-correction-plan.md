# Kong AWS Masking MVP - 종합 수정 계획서

## 🎯 목표 (GOAL)
**전체 프로젝트 준수율 100% 달성**: CLAUDE.md Critical Rules 및 Docs/Standards/*.md 지침 완전 준수

## 📊 현재 상태 분석 (METRIC)
- **Code Quality**: 70% → 100% (목표)
- **Execution Readiness**: 60% → 100% (목표)  
- **Type Safety**: 60% → 100% (목표)
- **Testing First**: 65% → 100% (목표)
- **Lint & Typecheck**: 50% → 100% (목표)

## 📋 수정 계획 (PLAN)

### Phase 1: Type Safety 완전 준수 (우선순위: 최고)
**목표**: 68개 TypeScript 오류 완전 해결 + JSDoc 타입 안전성 100% 달성

#### 1.1 JSDoc 타입 정의 강화
- **참조 문서**: [Docs/Standards/09-jsdoc-type-safety-guide.md](./Docs/Standards/09-jsdoc-type-safety-guide.md)
- **작업 범위**: 모든 JavaScript 파일 JSDoc 보완

```javascript
/**
 * Request 객체 확장 인터페이스
 * @typedef {Object} ExtendedRequest
 * @property {string} id - Request correlation ID
 * @property {Object} [body] - Request body data
 * @property {Object} [params] - Route parameters
 * @property {Object} [query] - Query parameters
 */

/**
 * Error 객체 확장 인터페이스
 * @typedef {Object} ExtendedError
 * @property {number} [statusCode] - HTTP status code
 * @property {string} [code] - Error code identifier
 * @property {Object} [details] - Additional error details
 */

/**
 * Logger 확장 인터페이스
 * @typedef {Object} ExtendedLogger
 * @property {function} performance - Performance logging
 * @property {function} security - Security event logging
 * @property {function} info - Info level logging
 * @property {function} warning - Warning level logging
 * @property {function} error - Error level logging
 */
```

#### 1.2 TypeScript 설정 업데이트
```json
// tsconfig.json 수정
{
  "compilerOptions": {
    "checkJs": true,
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true
  }
}
```

#### 1.3 VS Code 타입 체크 설정 최적화
- **참조 문서**: [Docs/Standards/10-vscode-type-check-setup-guide.md](./Docs/Standards/10-vscode-type-check-setup-guide.md)

### Phase 2: Lint & Typecheck 완전 준수 (우선순위: 최고)
**목표**: 50개 ESLint 오류 완전 해결 + 코드 품질 표준 100% 준수

#### 2.1 ESLint 규칙 준수
- **참조 문서**: [Docs/Standards/02-code-standards-base-rules.md](./Docs/Standards/02-code-standards-base-rules.md)

**주요 수정 사항**:
```javascript
// 함수 길이 제한 (최대 50줄)
function longFunction() {
  // 함수 분할 및 리팩토링 필요
}

// 들여쓰기 표준화 (2 spaces)
const config = {
  apiKey: process.env.API_KEY,
  timeout: 30000
};

// 따옴표 일관성 (single quotes)
const message = 'Error occurred';
```

#### 2.2 코드 복잡도 최적화
- **Cyclomatic Complexity**: 최대 10으로 제한
- **Cognitive Complexity**: 최대 15로 제한

#### 2.3 자동 수정 적용
```bash
npm run lint:fix  # 자동 수정 가능한 항목들 일괄 처리
```

### Phase 3: Testing First 완전 준수 (우선순위: 최고)
**목표**: 0% → 70% 브랜치 커버리지 달성 + 서비스 레이어 90% 커버리지

#### 3.1 TDD 전략 구현
- **참조 문서**: [Docs/Standards/01-tdd-strategy-guide.md](./Docs/Standards/01-tdd-strategy-guide.md)

**필수 테스트 파일 생성**:
```
tests/
├── unit/
│   ├── services/
│   │   ├── aws/
│   │   │   └── awsService.test.js      # 새로 생성 필요
│   │   └── claude/
│   │       └── claudeService.test.js   # 새로 생성 필요
│   ├── middleware/
│   │   └── errorHandler.test.js        # 새로 생성 필요
│   └── routes/
│       ├── analyze.test.js             # 새로 생성 필요
│       └── health.test.js              # 기존 업데이트
├── integration/
│   ├── api.integration.test.js         # 새로 생성 필요
│   └── kong.integration.test.js        # 새로 생성 필요
└── fixtures/
    ├── aws-sample-data.json           # 테스트 데이터
    └── claude-responses.json          # Mock 응답 데이터
```

#### 3.2 Jest 설정 최적화
```json
{
  "coverageThreshold": {
    "global": {
      "branches": 70,
      "functions": 70,
      "lines": 70,
      "statements": 70
    },
    "./src/services/": {
      "branches": 90,
      "functions": 90,
      "lines": 90,
      "statements": 90
    }
  }
}
```

#### 3.3 Mock 전략 구현
```javascript
// AWS CLI Mock
const mockAwsCli = {
  executeCommand: jest.fn(),
  validateCredentials: jest.fn()
};

// Claude API Mock
const mockClaudeApi = {
  analyzeData: jest.fn(),
  testConnection: jest.fn()
};
```

### Phase 4: Execution Readiness 완전 준수 (우선순위: 높음)
**목표**: Docker 서비스 정상화 + 환경 설정 완료

#### 4.1 환경 변수 설정 완료
```bash
# .env 파일 생성
cat > .env << 'EOF'
# API Keys
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
AWS_REGION=us-east-1

# Kong Configuration
KONG_PROXY_URL=http://kong:8000
KONG_ADMIN_URL=http://kong:8001

# Application Settings
NODE_ENV=development
PORT=3000
REQUEST_TIMEOUT=30000
MAX_RETRIES=3
RETRY_DELAY=1000

# Logging Configuration
LOG_LEVEL=info
LOG_FILE=logs/app.log
EOF
```

#### 4.2 Docker Compose 서비스 수정
```yaml
# docker-compose.yml 업데이트
version: '3.8'
services:
  kong:
    image: kong:3.9.0.1-alpine
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

#### 4.3 서비스 의존성 순서 수정
```yaml
backend:
  depends_on:
    kong:
      condition: service_healthy
```

### Phase 5: Code Quality 완전 준수 (우선순위: 높음)
**목표**: 코드 품질 메트릭 100% 달성

#### 5.1 품질 보증 체크리스트
- **참조 문서**: [Docs/Standards/04-code-quality-assurance.md](./Docs/Standards/04-code-quality-assurance.md)

**필수 검사 항목**:
- [ ] 함수 길이: 최대 50줄
- [ ] 파일 크기: 최대 500줄  
- [ ] 중복 코드: 0% 허용
- [ ] 주석 비율: 최소 10%
- [ ] 네이밍 일관성: 100%

#### 5.2 성능 최적화
```javascript
// 메모화 구현
const memoizedFunction = memoize(expensiveFunction);

// 비동기 최적화
const parallelRequests = await Promise.all([
  request1(),
  request2(),
  request3()
]);
```

#### 5.3 보안 강화
```javascript
// 입력 검증 강화
const { body, validationResult } = require('express-validator');

const validateRequest = [
  body('data').isObject().notEmpty(),
  body('analysisType').isIn(['security', 'cost', 'performance']),
  (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }
    next();
  }
];
```

### Phase 6: Shell Script 호환성 수정 (우선순위: 중간)
**목표**: macOS bash 3.x 호환성 확보

#### 6.1 Associative Array 대체
```bash
# 기존 (bash 4.0+ 필요)
declare -A resource_map
resource_map["ec2"]="instances"

# 수정 (bash 3.x 호환)
get_resource_key() {
    case "$1" in
        "ec2") echo "instances" ;;
        "s3") echo "buckets" ;;
        *) echo "unknown" ;;
    esac
}
```

#### 6.2 스크립트 호환성 테스트
```bash
#!/bin/bash
# Bash version check
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "Using bash 3.x compatible mode"
fi
```

## 🚀 실행 단계별 순서

### 1단계: 즉시 실행 (Critical)
```bash
# 1. 환경 설정
cp .env.example .env
# API 키 수동 입력 필요

# 2. Docker 서비스 재시작
docker-compose down
docker-compose up --build -d

# 3. 기본 테스트 실행
npm test
```

### 2단계: 타입 안전성 수정 (1-2시간)
```bash
# JSDoc 업데이트 및 타입 체크
npm run type-check
# 오류 발생 시 JSDoc 보완
```

### 3단계: 린트 오류 수정 (1시간)
```bash
# 자동 수정 적용
npm run lint:fix
# 수동 수정 필요한 항목 처리
npm run lint
```

### 4단계: 테스트 커버리지 달성 (2-3시간)
```bash
# 테스트 작성
npm run test:coverage
# 커버리지 확인 후 부족한 부분 보완
```

### 5단계: 최종 검증 (30분)
```bash
# 전체 품질 검사
npm run quality:check
# 통합 테스트
npm run test:integration
```

## ✅ 성공 기준 (SUCCESS CRITERIA)

### 정량적 지표
- **Type Safety**: TypeScript 오류 0개
- **Lint Check**: ESLint 오류 0개  
- **Test Coverage**: 브랜치 70% 이상
- **Service Coverage**: 서비스 레이어 90% 이상
- **Response Time**: < 5초 (CLAUDE.md 요구사항)

### 정성적 지표
- [ ] Docker Compose 정상 실행
- [ ] Kong Gateway 연결 성공
- [ ] Claude API 통신 성공
- [ ] AWS CLI 명령 실행 성공
- [ ] 전체 파이프라인 무중단 실행

## 📊 진행 상황 추적

### Phase별 체크리스트
- [ ] **Phase 1**: Type Safety (예상 2시간)
- [ ] **Phase 2**: Lint & Typecheck (예상 1시간)
- [ ] **Phase 3**: Testing First (예상 3시간)
- [ ] **Phase 4**: Execution Readiness (예상 1시간)
- [ ] **Phase 5**: Code Quality (예상 2시간)
- [ ] **Phase 6**: Shell Compatibility (예상 30분)

### 일일 목표
- **Day 1**: Phase 1-2 완료 (Type Safety + Lint)
- **Day 2**: Phase 3-4 완료 (Testing + Execution)
- **Day 3**: Phase 5-6 완료 (Quality + Compatibility) + 최종 검증

## 🔧 필요 도구 및 참조

### 주요 명령어
```bash
# 품질 검사
npm run quality:check

# 타입 체크
npm run type-check

# 테스트 커버리지
npm run test:coverage

# Docker 상태 확인
docker-compose ps
docker-compose logs

# Kong 상태 확인
curl http://localhost:8001/status
```

### 참조 문서
1. [CLAUDE.md](./CLAUDE.md) - 프로젝트 핵심 지침
2. [Docs/Standards/01-tdd-strategy-guide.md](./Docs/Standards/01-tdd-strategy-guide.md)
3. [Docs/Standards/02-code-standards-base-rules.md](./Docs/Standards/02-code-standards-base-rules.md)
4. [Docs/Standards/04-code-quality-assurance.md](./Docs/Standards/04-code-quality-assurance.md)
5. [Docs/Standards/09-jsdoc-type-safety-guide.md](./Docs/Standards/09-jsdoc-type-safety-guide.md)

---

**최종 목표**: CLAUDE.md Critical Rules 100% 준수하는 Production-Ready MVP 완성

**예상 완료 시간**: 3일 (총 9-10시간 작업)

**담당**: Infrastructure Team

**마지막 업데이트**: 2024년 기준