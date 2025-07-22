# 🛠️ **Kong AWS Masking MVP Development Guide - 개발 환경 허브**

<!-- Tags: #development #environment #setup #mvp #kong #aws-masking -->

> **PURPOSE**: Kong AWS Masking MVP 개발 환경 설정, 개발 표준, MVP 워크플로우 가이드  
> **SCOPE**: 환경 구성, 개발 표준, 테스트 전략, MVP 구현 체크리스트  
> **COMPLEXITY**: ⭐⭐⭐ Intermediate | **DURATION**: 30-45 minutes  
> **NAVIGATION**: 8초 규칙 준수 - MVP 개발 환경 마스터리

---

## ⚡ **QUICK NAVIGATION - 8 Second Rule**

### 🎯 **Essential MVP Setup**
```bash
# MVP 즉시 시작
1. [Quick Setup Guide](./setup/quick-setup.md)           # 5분 개발 환경
2. [Environment Variables](./setup/environment-variables.md) # 필수 환경 변수
3. [Technology Stack](./setup/technology-stack.md)       # Kong 3.9 + Node.js 20
4. [MVP Implementation Guide](../CLAUDE.md)              # MVP 구현 가이드
```

### 🔍 **Quick MVP Workflow**
```
Setup → Environment → Implementation → Testing → Validation
  ↓        ↓              ↓             ↓          ↓
5 min    .env file    Kong Plugin    Basic Test  Health Check
```

---

## 📋 **MVP COMPONENTS**

### **Core MVP Setup**
| Component | Purpose | Key Concepts | Complexity |
|-----------|---------|--------------|------------|
| **[Quick Setup](./setup/quick-setup.md)** | 5분 환경 설정 | Docker, Node.js, Kong | ⭐⭐⭐ |
| **[Environment Variables](./setup/environment-variables.md)** | API 키, AWS 설정 | .env 관리 | ⭐⭐ |
| **[Local Environment](./setup/local-environment-guide.md)** | Docker Compose 환경 | Kong DB-less, Backend | ⭐⭐⭐ |
| **[Technology Stack](./setup/technology-stack.md)** | MVP 기술 스택 | Kong 3.9, Node.js 20 | ⭐⭐ |

### **Development Standards**
| Component | Purpose | Key Concepts | Complexity |
|-----------|---------|--------------|------------|
| **[JavaScript + JSDoc](../Docs/Standards/02_코드_표준_및_Base_Rule.md)** | 코드 표준 | ES2022, JSDoc 타입 | ⭐⭐⭐ |
| **[TDD Strategy](../Docs/Standards/01_TDD_전략_가이드.md)** | 테스트 전략 | Jest, MVP 테스트 | ⭐⭐⭐ |
| **[Code Quality](../Docs/Standards/04_코드_품질_보증_체계.md)** | 품질 보증 | ESLint, Prettier | ⭐⭐ |

---

## 🚀 **MVP DEVELOPMENT WORKFLOWS**

### **🎯 MVP 초기 설정 (30분)**
```bash
# Kong AWS Masking MVP 환경 준비
1. git clone <repository>
2. cd kong-aws-masking-mvp
3. cp .env.example .env                    # 환경 변수 설정
4. docker-compose up --build               # 전체 시스템 시작
5. curl http://localhost:3000/health       # 헬스 체크
6. curl -X POST http://localhost:3000/analyze  # 기능 테스트
```

### **🔧 Daily MVP Development**
```bash
# 일일 개발 워크플로우
1. docker-compose up -d                    # 백그라운드 실행
2. docker-compose logs -f backend         # 백엔드 로그 확인
3. docker-compose logs -f kong            # Kong 로그 확인
4. npm test                               # 테스트 실행
5. docker-compose down                    # 종료
```

### **🔒 MVP 보안 검증**
```bash
# 마스킹 기능 검증
1. AWS 리소스 수집 확인
2. Kong 플러그인 마스킹 검증
3. Claude API 요청/응답 확인
4. 언마스킹 정확도 테스트
```

---

## 🎯 **MVP ARCHITECTURE**

### **System Architecture**
```typescript
interface MVPArchitecture {
  backend: "Node.js 20 + Express (Port 3000)";
  gateway: "Kong 3.9.0.1 DB-less (Port 8000)";
  plugin: "Lua-based AWS resource masking";
  ai: "Claude 3.5 Sonnet API";
  infrastructure: "Docker Compose 3.8";
}
```

### **Masking Rules**
```typescript
interface MaskingRules {
  ec2Instance: "i-[0-9a-f]+ → EC2_001";
  privateIP: "10.\\d+.\\d+.\\d+ → PRIVATE_IP_001";
  s3Bucket: "[a-z0-9-]+-bucket → BUCKET_001";
  rdsInstance: "prod-[a-z]+-[0-9]+ → RDS_001";
}
```

---

## 🚨 **MVP REQUIREMENTS**

### **MUST IMPLEMENT (MVP 필수)**
```typescript
// ✅ MVP 필수 구현
MUST SETUP: Docker Compose 환경
MUST IMPLEMENT: Kong 플러그인 마스킹/언마스킹
MUST CREATE: /analyze 엔드포인트
MUST CONFIGURE: AWS CLI 읽기 전용 접근
MUST TEST: 기본 마스킹 기능
```

### **SKIP FOR MVP (MVP 제외)**
```typescript
// ❌ MVP에서 제외
SKIP: 복잡한 CI/CD 파이프라인
SKIP: 성능 최적화
SKIP: 고급 에러 처리
SKIP: 모니터링 시스템
SKIP: TypeScript 마이그레이션
```

---

## 📊 **MVP METRICS**

### **MVP Success Criteria**
```typescript
const mvpMetrics = {
  setup_time: "30분 이내 전체 설정",
  response_time: "5초 이내 분석 완료",
  masking_accuracy: "100% 패턴 매칭",
  error_rate: "기본 동작 에러 없음",
  docker_health: "모든 컨테이너 정상"
};
```

### **MVP Validation Commands**
```bash
# MVP 검증 명령어
./tests/quick-check.sh                   # 빠른 시스템 체크
node tests/simple-test.js                # 기본 기능 테스트
docker-compose ps                        # 컨테이너 상태
curl http://localhost:8001/status        # Kong 상태
```

---

## 📚 **RELATED DOCUMENTATION**

### **MVP Implementation**
- **[CLAUDE.md](../CLAUDE.md)** - 프로젝트 개요, 기술 스택, 개발 워크플로우
- **[PRD Update](../Docs/kong-aws-masking-mvp-prd.md)** - MVP 상세 요구사항, 간소화된 구현 계획
- **[Kong Plugin Guide](../Docs/04-kong-plugin-improvements.md)** - 플러그인 구현 가이드

### **Development Standards**
- **[Code Standards](../Docs/Standards/02-code-standards-base-rules.md)** - JavaScript ES2022, JSDoc 타입 안정성
- **[Project Guidelines](../Docs/Standards/03-project-development-guidelines.md)** - MVP 개발 지침, 모범 사례
- **[Quality Assurance](../Docs/Standards/04-code-quality-assurance.md)** - ESLint 설정, 코드 품질

### **Testing & Validation**
- **[TDD Strategy](../Docs/Standards/01-tdd-strategy-guide.md)** - MVP 테스트 전략, Jest 설정
- **[Quick Check Script](../tests/quick-check.sh)** - 시스템 검증 스크립트
- **[Simple Test](../tests/simple-test.js)** - 기본 기능 테스트

---

## 🎯 **USAGE SCENARIOS**

### **For New Developers**
```bash
# MVP 온보딩 워크플로우
1. [Quick Setup Guide](./setup/quick-setup.md)        # 환경 설정
2. [CLAUDE.md](../CLAUDE.md)                         # 프로젝트 이해
3. [Simple Test](../tests/simple-test.js)            # 기능 확인
4. Kong 플러그인 코드 리뷰                             # 핵심 로직 이해
```

### **For Backend Developers**
```bash
# 백엔드 개발 워크플로우
1. [server.js](../backend/server.js) 구조 이해
2. AWS CLI 명령어 확인
3. Claude API 통합 테스트
4. 에러 핸들링 개선
```

### **For Kong Plugin Developers**
```bash
# Kong 플러그인 개발 워크플로우
1. [handler.lua](../kong/plugins/aws-masker/handler.lua) 분석
2. 마스킹 패턴 추가/수정
3. 플러그인 재로드 테스트
4. 성능 영향 확인
```

---

## 💡 **MVP BEST PRACTICES**

### **Development Strategy**
1. **Simple First** - 복잡한 기능 제외, 핵심만 구현
2. **Test Early** - 기본 기능 우선 테스트
3. **Document Inline** - JSDoc으로 즉시 문서화
4. **Fail Fast** - 빠른 실패, 빠른 수정

### **Common Issues & Solutions**
```typescript
const commonIssues = {
  "Kong not starting": "Check kong.yml syntax",
  "API Key error": "Verify .env ANTHROPIC_API_KEY",
  "AWS access denied": "Check ~/.aws credentials",
  "Masking not working": "Review Lua patterns",
  "Claude API 400": "Check request body format"
};
```

---

## 🔧 **TROUBLESHOOTING**

### **Quick Fixes**
```bash
# 일반적인 문제 해결
docker-compose down && docker-compose up --build  # 전체 재시작
docker-compose logs kong | grep ERROR             # Kong 에러 확인
docker exec -it kong-backend-1 npm test          # 컨테이너 내 테스트
curl -i http://localhost:8001/plugins            # 플러그인 상태
```

### **Debug Commands**
```bash
# 디버깅 명령어
docker-compose exec backend node --inspect        # Node.js 디버깅
docker-compose exec kong kong migrations up       # Kong 마이그레이션 (불필요)
docker logs kong-kong-1 --tail 50 -f            # Kong 실시간 로그
```

---

**🔑 Key Message**: Kong AWS Masking MVP는 2-3일 내 구현 가능한 간소화된 프로젝트입니다. 복잡한 기능은 제외하고 핵심 마스킹 기능에 집중하여 빠른 검증을 목표로 합니다.