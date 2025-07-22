# Environment Variables - AIDA Phase 2

## 🔧 환경 변수 설정

### .env 파일 템플릿
```env
# ===========================================
# A2A Configuration
# ===========================================
GATEWAY_PORT=8000
INVESTIGATOR_PORT=8001
K8S_HEALTH_ANALYZER_PORT=8002    # Phase 2

# ===========================================
# PostgreSQL Database
# ===========================================
DATABASE_URL=postgresql://postgres:Wonder9595!!@localhost:5432/aida
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=Wonder9595!!
DB_NAME=aida

# Production Database (Kubernetes)
DB_HOST_PROD=postgresql.observability.svc.cluster.local
DB_SSL_MODE=require

# ===========================================
# ClickHouse (Optional - Phase 2)
# ===========================================
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=
CLICKHOUSE_DATABASE=aida_metrics

# ===========================================
# Redis Cache
# ===========================================
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=
REDIS_DB=0

# ===========================================
# Kubernetes Configuration
# ===========================================
KUBECONFIG=/Users/tw.kim/.kube/remote-clusters/master-config
K8S_NAMESPACE_WHITELIST=default,aida-test,production,observability
K8S_CLUSTER_NAME=production
K8S_API_TIMEOUT=30000

# ===========================================
# Alert Management
# ===========================================
ALERTMANAGER_WEBHOOK_SECRET=your-webhook-secret
ALERT_DEDUPLICATION_WINDOW=300    # 5 minutes
ALERT_STORM_THRESHOLD=100         # alerts/minute
MAX_CONCURRENT_INVESTIGATIONS=50

# ===========================================
# Security
# ===========================================
JWT_SECRET=your-jwt-secret
API_KEY_SALT=your-api-key-salt
ENCRYPTION_KEY=your-encryption-key

# ===========================================
# Monitoring & Logging
# ===========================================
LOG_LEVEL=info                    # debug, info, warn, error
LOG_FORMAT=json                   # json, pretty
METRICS_ENABLED=true
METRICS_PORT=9090
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# ===========================================
# Performance Tuning
# ===========================================
NODE_ENV=development              # development, production
NODE_OPTIONS=--max-old-space-size=4096
UV_THREADPOOL_SIZE=16

# ===========================================
# Feature Flags
# ===========================================
ENABLE_K8S_HEALTH_ANALYZER=true   # Phase 2
ENABLE_CLICKHOUSE_QUERIES=false   # Phase 2
ENABLE_AUTO_REMEDIATION=false     # Phase 3
ENABLE_ML_PREDICTIONS=false       # Future
```

## 📋 환경별 설정

### 개발 환경 (.env.development)
```env
NODE_ENV=development
LOG_LEVEL=debug
LOG_FORMAT=pretty
DB_HOST=localhost
REDIS_URL=redis://localhost:6379
METRICS_ENABLED=false
```

### 테스트 환경 (.env.test)
```env
NODE_ENV=test
LOG_LEVEL=error
DB_NAME=aida_test
REDIS_DB=1
ALERT_DEDUPLICATION_WINDOW=10
MAX_CONCURRENT_INVESTIGATIONS=3
```

### 프로덕션 환경 (.env.production)
```env
NODE_ENV=production
LOG_LEVEL=info
LOG_FORMAT=json
DB_HOST=postgresql.observability.svc.cluster.local
DB_SSL_MODE=require
REDIS_URL=redis://redis.observability.svc.cluster.local:6379
METRICS_ENABLED=true
ENABLE_K8S_HEALTH_ANALYZER=true
```

## 🔐 비밀 관리

### Kubernetes Secrets
```bash
# PostgreSQL 비밀 생성
kubectl create secret generic postgres-secret \
  --from-literal=username=postgres \
  --from-literal=password=Wonder9595!! \
  -n observability

# AlertManager 웹훅 비밀
kubectl create secret generic alertmanager-webhook \
  --from-literal=secret=your-webhook-secret \
  -n observability

# 애플리케이션 비밀
kubectl create secret generic aida-secrets \
  --from-literal=jwt-secret=your-jwt-secret \
  --from-literal=api-key-salt=your-api-key-salt \
  --from-literal=encryption-key=your-encryption-key \
  -n observability
```

### Secret 마운트 (Deployment)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway-agent
spec:
  template:
    spec:
      containers:
      - name: gateway
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        - name: ALERTMANAGER_WEBHOOK_SECRET
          valueFrom:
            secretKeyRef:
              name: alertmanager-webhook
              key: secret
```

## 🚀 환경 변수 로딩

### TypeScript 설정
```typescript
// src/shared/config/env.ts
import dotenv from 'dotenv';
import { z } from 'zod';

// 환경별 .env 파일 로드
const envFile = `.env.${process.env.NODE_ENV || 'development'}`;
dotenv.config({ path: envFile });
dotenv.config(); // 기본 .env 파일

// 환경 변수 스키마 정의
const envSchema = z.object({
  // A2A Configuration
  GATEWAY_PORT: z.string().transform(Number).default('8000'),
  INVESTIGATOR_PORT: z.string().transform(Number).default('8001'),
  
  // Database
  DATABASE_URL: z.string(),
  DB_HOST: z.string(),
  DB_PORT: z.string().transform(Number).default('5432'),
  DB_USER: z.string(),
  DB_PASSWORD: z.string(),
  DB_NAME: z.string(),
  
  // Kubernetes
  KUBECONFIG: z.string().optional(),
  K8S_NAMESPACE_WHITELIST: z.string().transform(val => val.split(',')),
  
  // Security
  ALERTMANAGER_WEBHOOK_SECRET: z.string(),
  
  // Performance
  MAX_CONCURRENT_INVESTIGATIONS: z.string().transform(Number).default('50'),
  ALERT_DEDUPLICATION_WINDOW: z.string().transform(Number).default('300'),
  
  // Feature Flags
  ENABLE_K8S_HEALTH_ANALYZER: z.string().transform(val => val === 'true').default('false'),
});

// 환경 변수 검증 및 export
export const env = envSchema.parse(process.env);
```

### 사용 예제
```typescript
import { env } from '@shared/config/env';

// 데이터베이스 연결
const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: 20,
});

// 서버 시작
const app = express();
app.listen(env.GATEWAY_PORT, () => {
  console.log(`Gateway Agent listening on port ${env.GATEWAY_PORT}`);
});

// Feature Flag 확인
if (env.ENABLE_K8S_HEALTH_ANALYZER) {
  // K8s Health Analyzer 로직
}
```

## 📊 환경 변수 검증

### 시작 시 검증
```typescript
// src/shared/config/validate-env.ts
export function validateEnvironment(): void {
  const required = [
    'DATABASE_URL',
    'DB_PASSWORD',
    'ALERTMANAGER_WEBHOOK_SECRET',
  ];
  
  const missing = required.filter(key => !process.env[key]);
  
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}`
    );
  }
  
  // 추가 검증
  if (process.env.NODE_ENV === 'production') {
    if (!process.env.DB_SSL_MODE || process.env.DB_SSL_MODE !== 'require') {
      throw new Error('DB_SSL_MODE must be "require" in production');
    }
  }
}
```

### 테스트 환경 설정
```typescript
// test/setup.ts
import { config } from 'dotenv';

// 테스트 환경 변수 로드
config({ path: '.env.test' });

// 테스트용 환경 변수 오버라이드
process.env.LOG_LEVEL = 'error';
process.env.DB_NAME = 'aida_test';
process.env.REDIS_DB = '1';
```

## 🔍 디버깅

### 환경 변수 출력 (개발용)
```typescript
// scripts/check-env.ts
if (process.env.NODE_ENV !== 'production') {
  console.log('=== Environment Variables ===');
  console.log('NODE_ENV:', process.env.NODE_ENV);
  console.log('GATEWAY_PORT:', process.env.GATEWAY_PORT);
  console.log('DB_HOST:', process.env.DB_HOST);
  console.log('DB_NAME:', process.env.DB_NAME);
  console.log('KUBECONFIG exists:', !!process.env.KUBECONFIG);
  console.log('Features enabled:');
  console.log('  - K8S_HEALTH_ANALYZER:', process.env.ENABLE_K8S_HEALTH_ANALYZER);
  console.log('  - CLICKHOUSE:', process.env.ENABLE_CLICKHOUSE_QUERIES);
}
```

### 일반적인 문제 해결

#### 환경 변수를 찾을 수 없음
1. `.env` 파일이 프로젝트 루트에 있는지 확인
2. 파일 권한 확인: `ls -la .env`
3. dotenv 로드 순서 확인

#### 타입 불일치
1. 숫자 변환: `parseInt()` 또는 `Number()`
2. Boolean 변환: `=== 'true'`
3. 배열 변환: `split(',')`

#### 프로덕션 배포 시
1. 환경 변수가 ConfigMap/Secret에 정의되어 있는지 확인
2. Pod 내부에서 환경 변수 확인: `kubectl exec -it <pod> -- env`
3. 컨테이너 로그 확인: `kubectl logs <pod>`