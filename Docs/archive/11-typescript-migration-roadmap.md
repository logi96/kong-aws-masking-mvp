# Kong AWS Masking - TypeScript 마이그레이션 로드맵

## 개요
MVP 완료 후 JavaScript에서 TypeScript로 점진적으로 전환하는 전략적 로드맵입니다.

## 1. 마이그레이션 필요성 평가

### 1.1 TypeScript 전환 시점
| 조건 | 상태 | 권장 |
|------|------|------|
| 팀 규모 3명 이상 | ✅ | TypeScript 권장 |
| 코드베이스 10,000줄 이상 | ✅ | TypeScript 권장 |
| 외부 API 인터페이스 복잡 | ✅ | TypeScript 권장 |
| 장기 유지보수 예정 | ✅ | TypeScript 필수 |
| 빈번한 리팩토링 | ✅ | TypeScript 권장 |

### 1.2 ROI 분석
```
투자 비용:
- 초기 설정: 4-8시간
- 타입 정의: 2-3일
- 팀 교육: 1-2주

예상 이익:
- 버그 감소: 15-30%
- 개발 속도: 초기 -20% → 3개월 후 +25%
- 유지보수: 50% 시간 단축
```

## 2. 단계별 마이그레이션 전략

### Phase 0: 준비 (현재 - MVP)
```javascript
// 1. JSDoc 타입 완성도 높이기
// 2. 타입 체크 활성화
// 3. 팀 TypeScript 교육
```

### Phase 1: 기반 구축 (1주)
```bash
# TypeScript 설치
npm install --save-dev typescript @types/node @types/express @types/jest

# tsconfig.json 생성
npx tsc --init
```

#### tsconfig.json 초기 설정
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "allowJs": true,           // JS 파일 허용
    "checkJs": false,          // JS 파일은 체크하지 않음
    "strict": false,           // 초기에는 엄격 모드 OFF
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

### Phase 2: 타입 정의 (1주)
```typescript
// src/types/index.d.ts
export interface MaskingPattern {
  pattern: RegExp;
  prefix: string;
  description?: string;
}

export interface MaskingResult {
  masked: string;
  mappings: Map<string, string>;
  count: number;
  duration: number;
}

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  timestamp: string;
}

export type ResourceType = 'ec2' | 's3' | 'rds';
export type Status = 'pending' | 'processing' | 'completed' | 'failed';
```

### Phase 3: 유틸리티 전환 (2-3일)
```typescript
// src/utils/logger.ts
import winston from 'winston';

export interface LoggerOptions {
  level?: string;
  format?: winston.Logform.Format;
}

export function createLogger(options: LoggerOptions = {}): winston.Logger {
  return winston.createLogger({
    level: options.level || 'info',
    format: options.format || winston.format.combine(
      winston.format.timestamp(),
      winston.format.json()
    ),
    transports: [
      new winston.transports.Console(),
      new winston.transports.File({ filename: 'error.log', level: 'error' }),
      new winston.transports.File({ filename: 'combined.log' })
    ]
  });
}

export const logger = createLogger();
```

### Phase 4: 서비스 계층 전환 (1주)
```typescript
// src/services/maskingService.ts
import { MaskingPattern, MaskingResult } from '@/types';

export class MaskingService {
  private patterns: MaskingPattern[];
  private mappings: Map<string, string>;
  private counters: Record<string, number>;

  constructor() {
    this.patterns = [
      { pattern: /i-[0-9a-f]+/, prefix: 'EC2_' },
      { pattern: /10\.\d+\.\d+\.\d+/, prefix: 'PRIVATE_IP_' },
      { pattern: /[a-z0-9-]+\.s3\.amazonaws\.com/, prefix: 'S3_BUCKET_' }
    ];
    this.mappings = new Map();
    this.counters = {};
  }

  mask(text: string): MaskingResult {
    const startTime = Date.now();
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
      duration: Date.now() - startTime
    };
  }

  unmask(text: string): string {
    let unmasked = text;
    
    for (const [maskId, original] of this.mappings.entries()) {
      unmasked = unmasked.replace(new RegExp(maskId, 'g'), original);
    }
    
    return unmasked;
  }
}
```

### Phase 5: API 계층 전환 (1주)
```typescript
// src/controllers/analyzeController.ts
import { Request, Response, NextFunction } from 'express';
import { MaskingService } from '@/services/maskingService';
import { ApiResponse, ResourceType } from '@/types';

interface AnalyzeRequestBody {
  action: 'analyze';
  resources?: ResourceType[];
}

interface AnalyzeResponseData {
  analysis: string;
  maskedCount: number;
}

export class AnalyzeController {
  constructor(private maskingService: MaskingService) {}

  async analyze(
    req: Request<{}, {}, AnalyzeRequestBody>,
    res: Response<ApiResponse<AnalyzeResponseData>>,
    next: NextFunction
  ): Promise<void> {
    try {
      const { action, resources = ['ec2', 's3', 'rds'] } = req.body;
      
      if (action !== 'analyze') {
        res.status(400).json({
          success: false,
          error: 'Invalid action',
          timestamp: new Date().toISOString()
        });
        return;
      }

      // 처리 로직
      const awsData = await this.collectAwsResources(resources);
      const { masked, count } = this.maskingService.mask(JSON.stringify(awsData));
      const analysis = await this.callClaudeApi(masked);

      res.json({
        success: true,
        data: {
          analysis,
          maskedCount: count
        },
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      next(error);
    }
  }

  private async collectAwsResources(resources: ResourceType[]): Promise<any> {
    // 구현
  }

  private async callClaudeApi(maskedData: string): Promise<string> {
    // 구현
  }
}
```

### Phase 6: 테스트 전환 (3-4일)
```typescript
// src/services/__tests__/maskingService.test.ts
import { MaskingService } from '../maskingService';
import { MaskingResult } from '@/types';

describe('MaskingService', () => {
  let service: MaskingService;

  beforeEach(() => {
    service = new MaskingService();
  });

  describe('mask', () => {
    it('should mask EC2 instance IDs', () => {
      const input = 'Instance i-1234567890abcdef0 is running';
      const result: MaskingResult = service.mask(input);
      
      expect(result.masked).toBe('Instance EC2_001 is running');
      expect(result.count).toBe(1);
      expect(result.mappings.get('EC2_001')).toBe('i-1234567890abcdef0');
    });

    it('should mask multiple resource types', () => {
      const input = 'EC2 i-123 at 10.0.1.100 uses bucket my-bucket.s3.amazonaws.com';
      const result = service.mask(input);
      
      expect(result.masked).toContain('EC2_001');
      expect(result.masked).toContain('PRIVATE_IP_001');
      expect(result.masked).toContain('S3_BUCKET_001');
      expect(result.count).toBe(3);
    });
  });
});
```

### Phase 7: 빌드 시스템 (2-3일)
```json
// package.json 업데이트
{
  "scripts": {
    "build": "tsc",
    "dev": "ts-node-dev --respawn --transpile-only src/app.ts",
    "start": "node dist/app.js",
    "test": "jest",
    "type-check": "tsc --noEmit",
    "lint": "eslint . --ext .ts,.tsx,.js,.jsx"
  },
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^6.0.0",
    "@typescript-eslint/parser": "^6.0.0",
    "ts-jest": "^29.0.0",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.0.0"
  }
}
```

#### Jest 설정 (jest.config.js)
```javascript
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.ts', '**/?(*.)+(spec|test).ts'],
  transform: {
    '^.+\\.ts$': 'ts-jest'
  },
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1'
  }
};
```

### Phase 8: 완전 전환 (1-2주)
```typescript
// tsconfig.json - 엄격 모드 활성화
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "noImplicitThis": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true
  }
}
```

## 3. 마이그레이션 체크리스트

### 3.1 파일별 전환 순서
- [ ] 타입 정의 파일 (types/*.d.ts)
- [ ] 유틸리티 함수 (utils/*.ts)
- [ ] 설정 파일 (config/*.ts)
- [ ] 서비스 클래스 (services/*.ts)
- [ ] 미들웨어 (middleware/*.ts)
- [ ] 컨트롤러 (controllers/*.ts)
- [ ] 메인 앱 (app.ts)
- [ ] 테스트 파일 (*.test.ts)

### 3.2 품질 기준
- [ ] 모든 any 타입 제거
- [ ] strict 모드 통과
- [ ] 100% 타입 커버리지
- [ ] 기존 테스트 모두 통과

## 4. 일반적인 마이그레이션 패턴

### 4.1 Express 미들웨어
```typescript
// Before (JavaScript)
function authMiddleware(req, res, next) {
  if (!req.headers.authorization) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// After (TypeScript)
import { Request, Response, NextFunction } from 'express';

interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    role: string;
  };
}

function authMiddleware(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void {
  if (!req.headers.authorization) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  // 사용자 정보 추가
  req.user = decodeToken(req.headers.authorization);
  next();
}
```

### 4.2 비동기 함수
```typescript
// 에러 타입 정의
class AppError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public code: string
  ) {
    super(message);
  }
}

// 비동기 함수 타입
async function fetchAwsResources(): Promise<AwsResources> {
  try {
    const data = await awsClient.describeInstances();
    return parseAwsResponse(data);
  } catch (error) {
    if (error instanceof Error) {
      throw new AppError(error.message, 500, 'AWS_ERROR');
    }
    throw new AppError('Unknown error', 500, 'UNKNOWN_ERROR');
  }
}
```

## 5. 팀 전환 전략

### 5.1 교육 계획
1. **Week 1**: TypeScript 기초
   - 타입 시스템 이해
   - 인터페이스 vs 타입
   - 제네릭 기초

2. **Week 2**: 실전 적용
   - Express + TypeScript
   - 테스트 작성
   - 디버깅

### 5.2 코드 리뷰 가이드
```typescript
// ❌ 피해야 할 패턴
const data: any = fetchData();
const items = data as Item[]; // 무분별한 타입 단언

// ✅ 권장 패턴
const data = await fetchData();
if (isItemArray(data)) {
  // 타입 가드 사용
  processItems(data);
}
```

## 6. 도구 및 자동화

### 6.1 마이그레이션 도구
```bash
# 자동 변환 도구
npx ts-migrate migrate src/

# 타입 커버리지 확인
npx type-coverage

# 점진적 타입 추가
npx typescript-strict-plugin
```

### 6.2 CI/CD 업데이트
```yaml
# .github/workflows/ci.yml
- name: Type Check
  run: npm run type-check

- name: Build
  run: npm run build

- name: Type Coverage
  run: npx type-coverage --at-least 95
```

## 7. 위험 요소 및 대응

### 7.1 일반적인 문제
| 문제 | 해결 방법 |
|------|-----------|
| 타입 정의 누락 | @types 패키지 설치 또는 직접 작성 |
| 빌드 시간 증가 | 증분 빌드, 캐싱 활용 |
| any 타입 남용 | ESLint 규칙으로 제한 |
| 복잡한 타입 | 단순화, 유틸리티 타입 활용 |

### 7.2 롤백 계획
```bash
# 문제 발생 시 JavaScript로 롤백
git checkout javascript-stable
npm run build:js
```

## 8. 성공 지표

### 8.1 정량적 지표
- 타입 커버리지: 95% 이상
- 빌드 시간: 30초 이내
- 타입 관련 버그: 50% 감소
- 개발 속도: 3개월 후 25% 향상

### 8.2 정성적 지표
- 팀 만족도 향상
- 코드 리뷰 시간 단축
- 리팩토링 신뢰도 증가
- 신규 개발자 온보딩 시간 단축

## 9. 결론

TypeScript 마이그레이션은:
- **점진적**: 한 번에 하나씩 전환
- **실용적**: 비즈니스 영향 최소화
- **측정 가능**: 명확한 성공 지표
- **되돌릴 수 있음**: 문제 시 롤백 가능

"The best time to migrate to TypeScript was yesterday. The second best time is now."