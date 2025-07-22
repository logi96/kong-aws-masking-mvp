# Kong AWS Masking MVP - 코드 표준 및 Base Rule

## 개요
일관되고 유지보수 가능한 코드를 위한 최소한의 표준과 규칙입니다.

## 1. 언어별 코딩 표준

### 1.1 JavaScript/Node.js (with JSDoc)
```javascript
// ✅ Good - 명확하고 일관된 스타일 + JSDoc 타입 주석
/**
 * @typedef {Object.<string, RegExp>} AwsPatterns
 * @property {RegExp} EC2_INSTANCE - EC2 인스턴스 ID 패턴
 * @property {RegExp} PRIVATE_IP - Private IP 주소 패턴
 */

/** @type {AwsPatterns} */
const AWS_PATTERNS = {
  EC2_INSTANCE: /i-[0-9a-f]+/,
  PRIVATE_IP: /10\.\d+\.\d+\.\d+/
};

/**
 * AWS 리소스를 마스킹합니다
 * @param {Object} data - 마스킹할 데이터
 * @param {string} [data.instanceId] - EC2 인스턴스 ID
 * @param {string} [data.privateIp] - Private IP 주소
 * @returns {Promise<{success: boolean, data?: Object, error?: string}>} 마스킹 결과
 */
async function maskAWSResources(data) {
  try {
    const maskedData = await processData(data);
    return { success: true, data: maskedData };
  } catch (error) {
    logger.error('Masking failed:', error);
    return { success: false, error: error.message };
  }
}

// ❌ Bad - 일관성 없고 불명확, JSDoc 없음
var patterns = {ec2:/i-[0-9a-f]+/}
function mask(d){
  return processData(d).then(r=>({ok:1,d:r})).catch(e=>({ok:0,e}))
}
```

### 1.2 Lua (Kong Plugin)
```lua
-- ✅ Good - Kong 스타일 가이드 준수
local AwsMaskerHandler = {
  VERSION = "0.1.0",
  PRIORITY = 900
}

function AwsMaskerHandler:access(conf)
  local body = kong.request.get_raw_body()
  if not body then
    return
  end
  
  -- 명확한 변수명과 주석
  local masked_body = self:mask_sensitive_data(body)
  kong.service.request.set_raw_body(masked_body)
end

-- ❌ Bad
function h:a(c)
  b=kong.request.get_raw_body()
  if b then kong.service.request.set_raw_body(mask(b)) end
end
```

## 2. 기본 코드 규칙 (Base Rules)

### 2.1 명명 규칙
| 유형 | 규칙 | 예시 |
|------|------|------|
| 변수 | camelCase | `userId`, `maskingPattern` |
| 상수 | UPPER_SNAKE_CASE | `MAX_RETRIES`, `API_TIMEOUT` |
| 함수 | camelCase (동사) | `maskData()`, `validateInput()` |
| 클래스 | PascalCase | `AwsMasker`, `ErrorHandler` |
| 파일 | kebab-case | `aws-masker.js`, `error-handler.js` |

### 2.2 파일 구조
```javascript
// 1. Imports/Requires
const express = require('express');
const { maskData } = require('./utils/masking');

// 2. Constants
const PORT = process.env.PORT || 3000;
const API_VERSION = 'v1';

// 3. Type Definitions (JSDoc)
/**
 * @typedef {Object} MaskingConfig
 * @property {string[]} patterns - 마스킹 패턴 목록
 * @property {boolean} preserveLength - 길이 보존 여부
 */

// 4. Main Logic
/**
 * AWS 리소스 마스킹 서비스
 * @class
 */
class MaskingService {
  /**
   * @param {MaskingConfig} config - 마스킹 설정
   */
  constructor(config) {
    this.config = config;
  }
  
  /**
   * 데이터를 마스킹합니다
   * @param {string} data - 원본 데이터
   * @returns {string} 마스킹된 데이터
   */
  mask(data) {
    // ...
  }
}

// 5. Exports
module.exports = MaskingService;
```

### 2.3 함수 규칙
```javascript
// ✅ Good - 단일 책임, 명확한 이름
function maskEC2InstanceId(instanceId) {
  if (!instanceId || !instanceId.startsWith('i-')) {
    return null;
  }
  return 'EC2_' + generateMaskId();
}

// ❌ Bad - 너무 많은 책임
function processEverything(data) {
  // 검증, 마스킹, 저장, 로깅 등 모든 것을 한 함수에서...
}
```

## 3. 에러 처리 표준

### 3.1 일관된 에러 구조
```javascript
// errors/AppError.js
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
    /** @type {number} */
    this.statusCode = statusCode;
    /** @type {string} */
    this.code = code;
    /** @type {boolean} */
    this.isOperational = true;
  }
}

// 사용 예시
throw new AppError('API key is required', 401, 'AUTH_MISSING_KEY');
```

### 3.2 에러 처리 패턴
```javascript
// ✅ Good - 명확한 에러 처리
async function analyzeResources(data) {
  // 입력 검증
  if (!data || typeof data !== 'object') {
    throw new AppError('Invalid input data', 400, 'INVALID_INPUT');
  }

  try {
    const masked = await maskService.mask(data);
    const result = await claudeAPI.analyze(masked);
    return result;
  } catch (error) {
    // 에러 타입별 처리
    if (error.code === 'ECONNREFUSED') {
      throw new AppError('Service unavailable', 503, 'SERVICE_DOWN');
    }
    throw error;
  }
}
```

## 4. 로깅 표준

### 4.1 로그 레벨
```javascript
// 로그 레벨 사용 가이드
logger.error('Critical error occurred', { error, userId });   // 시스템 에러
logger.warn('API rate limit approaching', { remaining: 10 }); // 경고 상황
logger.info('Request processed', { duration: 150 });          // 중요 정보
logger.debug('Masking pattern matched', { pattern, value });  // 디버깅용
```

### 4.2 구조화된 로깅
```javascript
// ✅ Good - 구조화된 로그
logger.info('API request', {
  method: req.method,
  path: req.path,
  duration: Date.now() - startTime,
  statusCode: res.statusCode
});

// ❌ Bad - 문자열 연결
console.log('Request: ' + method + ' ' + path + ' took ' + duration + 'ms');
```

## 5. 보안 기본 규칙

### 5.1 민감 정보 처리
```javascript
// ✅ Good - 환경변수 사용
const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  throw new AppError('API key not configured', 500, 'CONFIG_ERROR');
}

// ❌ Bad - 하드코딩
const apiKey = 'sk-ant-api03-xxxxx';
```

### 5.2 입력 검증
```javascript
// 모든 외부 입력은 검증
function validateAwsData(data) {
  const schema = {
    instanceId: /^i-[0-9a-f]{8,17}$/,
    region: /^[a-z]{2}-[a-z]+-\d$/,
    bucket: /^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/
  };
  
  for (const [key, pattern] of Object.entries(schema)) {
    if (data[key] && !pattern.test(data[key])) {
      throw new AppError(`Invalid ${key} format`, 400, 'VALIDATION_ERROR');
    }
  }
}
```

## 6. 주석 및 문서화 (JSDoc 중심)

### 6.1 JSDoc 타입 주석 및 문서화
```javascript
// Type Definitions
/**
 * @typedef {Object} AwsResourceData
 * @property {string} instanceId - EC2 인스턴스 ID (i-xxxxx)
 * @property {string} privateIp - Private IP 주소
 * @property {string} [bucketName] - S3 버킷 이름 (선택)
 */

/**
 * @typedef {Object} MaskingResult
 * @property {AwsResourceData} masked - 마스킹된 데이터
 * @property {Map<string, string>} mappings - 원본->마스킹 매핑
 * @property {number} count - 마스킹된 항목 수
 */

// Function with complete JSDoc
/**
 * AWS 리소스 데이터를 마스킹합니다
 * @param {AwsResourceData} data - AWS 리소스 데이터
 * @returns {Promise<MaskingResult>} 마스킹된 데이터와 매핑 정보
 * @throws {AppError} 유효하지 않은 데이터 형식
 * @example
 * const result = await maskAwsResources({
 *   instanceId: 'i-1234567890abcdef0',
 *   privateIp: '10.0.0.1'
 * });
 */
async function maskAwsResources(data) {
  // 구현...
}

// Variable Type Annotations
/** @type {string[]} */
const supportedRegions = ['us-east-1', 'us-west-2', 'ap-northeast-1'];

/** @type {Map<string, string>} */
const maskingCache = new Map();
```

### 6.2 인라인 주석
```javascript
// ✅ Good - 왜(Why)를 설명
// Claude API는 동시 요청을 5개로 제한하므로 큐 사용
const requestQueue = new Queue({ concurrency: 5 });

// ❌ Bad - 무엇(What)을 설명
// i를 1 증가시킴
i++;
```

## 7. Git 커밋 규칙

### 7.1 커밋 메시지 형식
```
<type>: <subject>

<body>

<footer>
```

### 7.2 타입 종류
- `feat`: 새로운 기능
- `fix`: 버그 수정
- `docs`: 문서 변경
- `style`: 코드 스타일 변경
- `refactor`: 리팩토링
- `test`: 테스트 추가/수정
- `chore`: 빌드, 설정 변경

### 7.3 예시
```
feat: EC2 인스턴스 ID 마스킹 기능 추가

- i-로 시작하는 패턴 매칭
- 순차 번호로 마스킹 (EC2_001, EC2_002...)
- 매핑 정보 메모리 저장

Closes #123
```

## 8. 프로젝트 구조 표준

```
kong-aws-masking-mvp/
├── .env.example          # 환경변수 템플릿
├── .gitignore           # Git 제외 파일
├── docker-compose.yml   # 컨테이너 구성
├── package.json         # 프로젝트 메타데이터
├── README.md           # 프로젝트 설명
├── kong/               # Kong 관련
│   ├── kong.yml       # Kong 설정
│   └── plugins/       # 커스텀 플러그인
├── src/               # 소스 코드
│   ├── services/      # 비즈니스 로직
│   ├── utils/         # 유틸리티
│   ├── errors/        # 에러 클래스
│   └── app.js         # 메인 앱
├── tests/             # 테스트
│   ├── unit/          # 단위 테스트
│   └── integration/   # 통합 테스트
└── docs/              # 문서
```

## 9. 코드 리뷰 체크리스트

### 9.1 필수 확인 사항
- [ ] 코드가 의도한 대로 작동하는가?
- [ ] 에러 처리가 적절한가?
- [ ] 보안 취약점은 없는가?
- [ ] 테스트가 작성되었는가?
- [ ] 성능 문제는 없는가?

### 9.2 코드 품질
- [ ] 명명 규칙을 따르는가?
- [ ] 함수가 단일 책임을 가지는가?
- [ ] 중복 코드는 없는가?
- [ ] 주석이 적절한가?

## 10. 린터 설정

### 10.1 ESLint 설정 (.eslintrc.json)
```json
{
  "env": {
    "node": true,
    "es2021": true,
    "jest": true
  },
  "extends": ["eslint:recommended"],
  "parserOptions": {
    "ecmaVersion": 12
  },
  "rules": {
    "indent": ["error", 2],
    "quotes": ["error", "single"],
    "semi": ["error", "always"],
    "no-unused-vars": ["error", { "argsIgnorePattern": "^_" }],
    "no-console": ["warn", { "allow": ["warn", "error"] }]
  }
}
```

### 10.2 자동 포맷팅 (Prettier)
```json
{
  "singleQuote": true,
  "trailingComma": "es5",
  "tabWidth": 2,
  "semi": true,
  "printWidth": 100
}
```

## 11. 결론

이 코드 표준은:
- **최소한의 규칙**: MVP에 필요한 것만
- **일관성 중심**: 팀 협업 효율성
- **실용적**: 과도한 규칙 배제

"좋은 코드는 주석이 필요 없다. 하지만 왜 그렇게 했는지는 설명이 필요하다."