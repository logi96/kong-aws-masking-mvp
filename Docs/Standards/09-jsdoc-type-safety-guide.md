# Kong AWS Masking MVP - JSDoc을 활용한 타입 안정성 가이드

## 개요
TypeScript 없이도 JavaScript에서 타입 안정성을 확보하는 실용적인 방법입니다.

## 1. JSDoc 기본 개념

### 1.1 왜 JSDoc인가?
- **빠른 개발**: 컴파일 단계 없이 즉시 실행
- **타입 힌트**: IDE의 자동완성 및 타입 체크 지원
- **문서화**: 코드와 문서를 동시에 관리
- **점진적 전환**: 향후 TypeScript 전환 용이

### 1.2 VS Code 설정
```json
// .vscode/settings.json
{
  "javascript.implicitProjectConfig.checkJs": true,
  "javascript.suggest.autoImports": true,
  "javascript.updateImportsOnFileMove.enabled": "always",
  "javascript.preferences.includePackageJsonAutoImports": "on"
}
```

## 2. 타입 정의 패턴

### 2.1 기본 타입
```javascript
/**
 * @param {string} resourceId - AWS 리소스 ID
 * @param {number} retryCount - 재시도 횟수
 * @param {boolean} [cache=true] - 캐시 사용 여부 (선택)
 * @returns {string} 마스킹된 ID
 */
function maskResource(resourceId, retryCount, cache = true) {
  // 구현
}
```

### 2.2 객체 타입
```javascript
/**
 * @typedef {Object} MaskingOptions
 * @property {string[]} patterns - 사용할 패턴 목록
 * @property {number} [maxItems=1000] - 최대 항목 수
 * @property {boolean} [preserveStructure=false] - 구조 유지 여부
 */

/**
 * @typedef {Object} MaskingResult
 * @property {string} masked - 마스킹된 텍스트
 * @property {Map<string, string>} mappings - 원본-마스킹 매핑
 * @property {number} count - 마스킹된 항목 수
 * @property {number} duration - 처리 시간 (ms)
 */

/**
 * AWS 리소스를 마스킹합니다
 * @param {string} text - 마스킹할 텍스트
 * @param {MaskingOptions} options - 마스킹 옵션
 * @returns {MaskingResult} 마스킹 결과
 */
function maskAwsResources(text, options) {
  // 구현
}
```

### 2.3 클래스 타입
```javascript
/**
 * AWS 리소스 마스킹 서비스
 * @class
 */
class MaskingService {
  /**
   * @param {Object} config - 서비스 설정
   * @param {number} [config.maxCacheSize=5000] - 최대 캐시 크기
   * @param {number} [config.ttl=300] - 캐시 TTL (초)
   */
  constructor(config = {}) {
    /** @type {Map<string, string>} */
    this.mappings = new Map();
    
    /** @type {number} */
    this.maxCacheSize = config.maxCacheSize || 5000;
    
    /** @private */
    this.counter = 0;
  }

  /**
   * 리소스를 마스킹합니다
   * @param {string} resource - 리소스 문자열
   * @returns {string} 마스킹된 문자열
   * @throws {Error} 유효하지 않은 리소스
   */
  mask(resource) {
    // 구현
  }
}
```

## 3. 고급 타입 패턴

### 3.1 Union 타입
```javascript
/**
 * @typedef {'ec2' | 's3' | 'rds'} ResourceType
 * @typedef {'pending' | 'processing' | 'completed' | 'failed'} Status
 */

/**
 * @param {ResourceType} type - 리소스 타입
 * @param {Status} status - 현재 상태
 * @returns {boolean} 처리 가능 여부
 */
function canProcess(type, status) {
  return status === 'pending' || status === 'processing';
}
```

### 3.2 제네릭 타입
```javascript
/**
 * @template T
 * @typedef {Object} ApiResponse
 * @property {boolean} success - 성공 여부
 * @property {T} [data] - 응답 데이터
 * @property {string} [error] - 에러 메시지
 */

/**
 * API 응답을 생성합니다
 * @template T
 * @param {boolean} success - 성공 여부
 * @param {T} [data] - 데이터
 * @param {string} [error] - 에러
 * @returns {ApiResponse<T>}
 */
function createResponse(success, data, error) {
  return { success, data, error };
}

// 사용 예시
/** @type {ApiResponse<{id: string, name: string}>} */
const userResponse = createResponse(true, { id: '123', name: 'John' });
```

### 3.3 콜백과 Promise
```javascript
/**
 * @callback MaskingCallback
 * @param {Error|null} error - 에러 객체
 * @param {string} [result] - 마스킹 결과
 * @returns {void}
 */

/**
 * 비동기 마스킹 처리
 * @param {string} text - 입력 텍스트
 * @param {MaskingCallback} callback - 콜백 함수
 */
function maskAsync(text, callback) {
  // 구현
}

/**
 * Promise 기반 마스킹
 * @param {string} text - 입력 텍스트
 * @returns {Promise<MaskingResult>} 마스킹 결과
 */
async function maskPromise(text) {
  // 구현
}
```

## 4. Express 앱 타입 정의

### 4.1 Request/Response 타입
```javascript
/**
 * @typedef {import('express').Request} Request
 * @typedef {import('express').Response} Response
 * @typedef {import('express').NextFunction} NextFunction
 */

/**
 * @typedef {Object} AnalyzeRequestBody
 * @property {string} action - 실행할 작업
 * @property {ResourceType[]} [resources] - 분석할 리소스
 */

/**
 * AWS 리소스 분석 핸들러
 * @param {Request<{}, {}, AnalyzeRequestBody>} req - 요청
 * @param {Response} res - 응답
 * @param {NextFunction} next - 다음 미들웨어
 */
async function analyzeHandler(req, res, next) {
  try {
    const { action, resources } = req.body;
    
    // 타입이 보장된 코드
    const result = await analyzeResources(resources || ['ec2', 's3', 'rds']);
    
    res.json(createResponse(true, result));
  } catch (error) {
    next(error);
  }
}
```

### 4.2 미들웨어 타입
```javascript
/**
 * 에러 처리 미들웨어
 * @param {Error} err - 에러 객체
 * @param {Request} req - 요청
 * @param {Response} res - 응답
 * @param {NextFunction} next - 다음 미들웨어
 */
function errorHandler(err, req, res, next) {
  const status = err.statusCode || 500;
  res.status(status).json(createResponse(false, null, err.message));
}
```

## 5. 모듈 타입 정의

### 5.1 모듈 exports
```javascript
// masking.js
/**
 * @module masking
 */

/**
 * @typedef {Object} MaskingModule
 * @property {typeof maskAwsResources} maskAwsResources
 * @property {typeof unmaskAwsResources} unmaskAwsResources
 * @property {typeof MaskingService} MaskingService
 */

/** @type {MaskingModule} */
module.exports = {
  maskAwsResources,
  unmaskAwsResources,
  MaskingService
};
```

### 5.2 타입 파일 분리
```javascript
// types/index.js
/**
 * @typedef {Object} AwsResource
 * @property {string} id - 리소스 ID
 * @property {ResourceType} type - 리소스 타입
 * @property {string} region - AWS 리전
 * @property {Object.<string, string>} tags - 태그
 */

/**
 * @typedef {Object} MaskingPattern
 * @property {RegExp} pattern - 정규식 패턴
 * @property {string} prefix - 마스킹 접두사
 * @property {string} [description] - 패턴 설명
 */

// 다른 파일에서 임포트
/** @typedef {import('./types').AwsResource} AwsResource */
/** @typedef {import('./types').MaskingPattern} MaskingPattern */
```

## 6. 실제 프로젝트 적용

### 6.1 서비스 클래스 예시
```javascript
// services/maskingService.js

/** @typedef {import('../types').MaskingPattern} MaskingPattern */
/** @typedef {import('../types').MaskingResult} MaskingResult */

/**
 * AWS 리소스 마스킹 서비스
 */
class MaskingService {
  constructor() {
    /** @type {MaskingPattern[]} */
    this.patterns = [
      { pattern: /i-[0-9a-f]+/, prefix: 'EC2_' },
      { pattern: /10\.\d+\.\d+\.\d+/, prefix: 'PRIVATE_IP_' },
      { pattern: /[a-z0-9-]+\.s3\.amazonaws\.com/, prefix: 'S3_BUCKET_' }
    ];
    
    /** @type {Map<string, string>} */
    this.mappings = new Map();
    
    /** @type {Object.<string, number>} */
    this.counters = {};
  }

  /**
   * 텍스트를 마스킹합니다
   * @param {string} text - 입력 텍스트
   * @returns {MaskingResult} 마스킹 결과
   */
  mask(text) {
    let masked = text;
    let count = 0;

    for (const { pattern, prefix } of this.patterns) {
      masked = masked.replace(pattern, (match) => {
        this.counters[prefix] = (this.counters[prefix] || 0) + 1;
        const maskId = `${prefix}${String(this.counters[prefix]).padStart(3, '0')}`;
        
        this.mappings.set(maskId, match);
        count++;
        
        return maskId;
      });
    }

    return {
      masked,
      mappings: new Map(this.mappings),
      count,
      duration: 0 // 실제로는 측정
    };
  }

  /**
   * 마스킹을 해제합니다
   * @param {string} text - 마스킹된 텍스트
   * @returns {string} 원본 텍스트
   */
  unmask(text) {
    let unmasked = text;
    
    for (const [maskId, original] of this.mappings.entries()) {
      unmasked = unmasked.replace(new RegExp(maskId, 'g'), original);
    }
    
    return unmasked;
  }
}

module.exports = MaskingService;
```

### 6.2 컨트롤러 예시
```javascript
// controllers/analyzeController.js

/** @typedef {import('express').Request} Request */
/** @typedef {import('express').Response} Response */
/** @typedef {import('../services/maskingService')} MaskingService */

/**
 * @type {MaskingService}
 */
const maskingService = new MaskingService();

/**
 * @typedef {Object} AnalyzeRequest
 * @property {'analyze'} action - 액션 타입
 * @property {string[]} [resources] - 리소스 목록
 */

/**
 * 분석 요청 처리
 * @param {Request<{}, {}, AnalyzeRequest>} req
 * @param {Response} res
 */
async function analyzeController(req, res) {
  const { action, resources = ['ec2', 's3', 'rds'] } = req.body;
  
  if (action !== 'analyze') {
    return res.status(400).json({
      success: false,
      error: 'Invalid action'
    });
  }

  try {
    // AWS 리소스 수집
    const awsData = await collectAwsResources(resources);
    
    // 마스킹
    const { masked, mappings, count } = maskingService.mask(JSON.stringify(awsData));
    
    // Claude API 호출
    const analysis = await callClaudeApi(masked);
    
    // 결과 반환
    res.json({
      success: true,
      data: {
        analysis,
        maskedCount: count
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
}

module.exports = analyzeController;
```

## 7. 타입 체크 자동화

### 7.1 package.json 스크립트
```json
{
  "scripts": {
    "type-check": "tsc --noEmit --allowJs --checkJs",
    "lint": "eslint . --ext .js",
    "lint:fix": "eslint . --ext .js --fix"
  }
}
```

### 7.2 tsconfig.json (타입 체크용)
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "allowJs": true,
    "checkJs": true,
    "noEmit": true,
    "strict": false,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "moduleResolution": "node",
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

## 8. 일반적인 패턴과 팁

### 8.1 외부 라이브러리 타입
```javascript
/** @type {import('express').Express} */
const app = express();

/** @type {import('axios').AxiosInstance} */
const apiClient = axios.create({
  baseURL: 'https://api.anthropic.com'
});
```

### 8.2 환경 변수 타입
```javascript
/**
 * @typedef {Object} EnvConfig
 * @property {string} ANTHROPIC_API_KEY
 * @property {string} AWS_REGION
 * @property {'development' | 'production'} NODE_ENV
 * @property {string} [PORT]
 */

/** @type {EnvConfig} */
const env = process.env;
```

### 8.3 타입 가드
```javascript
/**
 * EC2 인스턴스 ID인지 확인
 * @param {string} value - 확인할 값
 * @returns {boolean}
 */
function isEC2InstanceId(value) {
  return /^i-[0-9a-f]{8,17}$/.test(value);
}

/**
 * 리소스 타입 확인
 * @param {string} value - 확인할 값
 * @returns {value is ResourceType}
 */
function isValidResourceType(value) {
  return ['ec2', 's3', 'rds'].includes(value);
}
```

## 9. 마이그레이션 준비

### 9.1 점진적 TypeScript 도입
```javascript
// 1단계: JSDoc으로 완전히 타입 정의
// 2단계: .d.ts 파일 생성
// 3단계: 핵심 모듈부터 .ts로 전환
// 4단계: 전체 프로젝트 TypeScript 전환
```

### 9.2 타입 정의 파일 예시
```typescript
// types/masking.d.ts
export interface MaskingOptions {
  patterns: string[];
  maxItems?: number;
  preserveStructure?: boolean;
}

export interface MaskingResult {
  masked: string;
  mappings: Map<string, string>;
  count: number;
  duration: number;
}

export class MaskingService {
  mask(text: string): MaskingResult;
  unmask(text: string): string;
}
```

## 10. 결론

JSDoc을 활용하면:
- **즉시 적용**: 별도 빌드 없이 타입 안정성 확보
- **IDE 지원**: 자동완성과 타입 체크 활용
- **문서화**: 코드와 문서를 한 번에 관리
- **마이그레이션 준비**: 향후 TypeScript 전환 용이

MVP 단계에서는 이 방식으로 충분하며, 프로젝트가 성장하면 TypeScript로 전환할 수 있습니다.