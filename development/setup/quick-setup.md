# ⚡ **Quick Development Setup - AIDA 빠른 개발환경 설정**

<!-- Tags: #setup #quick-start #nodejs #postgresql #docker -->

> **목표**: 5분 내 개발환경 준비 완료  
> **위치**: Development > Setup > Quick Setup  
> **이전**: [개발 표준](../standards/README.md) | **다음**: [상세 설정](./detailed-setup.md)  
> **복잡도**: ⭐⭐ Intermediate | **소요시간**: 5분  
> **Tags**: #setup #quick-start #nodejs #postgresql #docker

---

## 🎯 **Completion Goals - 완료 목표**

✅ Node.js 20+ 환경 확인  
✅ 프로젝트 의존성 설치  
✅ PostgreSQL Docker 실행  
✅ 환경변수 설정  
✅ 기본 검증 통과

---

## 🚀 **5분 실행 스크립트**

### **전체 자동 설정**
```bash
#!/bin/bash
# AIDA Quick Setup Script

echo "🚀 AIDA 빠른 설정 시작..."

# 1. Node.js 버전 확인
node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$node_version" -lt 20 ]; then
  echo "❌ Node.js 20+ 필요. 현재: $(node --version)"
  exit 1
fi
echo "✅ Node.js $(node --version) 확인"

# 2. 의존성 설치
echo "📦 npm install 실행중..."
npm install --silent

# 3. 환경변수 설정
if [ ! -f .env ]; then
  cp .env.example .env
  echo "✅ .env 파일 생성"
fi

# 4. PostgreSQL Docker 시작
echo "🐘 PostgreSQL Docker 시작..."
docker run --name aida-postgres -d \
  -e POSTGRES_DB=aida \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=Wonder9595!! \
  -p 5432:5432 \
  postgres:15 2>/dev/null || echo "PostgreSQL 이미 실행 중"

# 5. 데이터베이스 대기 및 초기화
echo "⏳ PostgreSQL 시작 대기..."
sleep 5
npm run db:setup --silent

# 6. 검증
echo "🧪 빠른 검증 실행..."
npm run validate:quick

echo "🎉 AIDA 개발환경 설정 완료!"
echo "▶️ 다음 실행: npm run dev:all"
```

### **수동 단계별 설정**
```bash
# 1. Node.js 확인 (20+ 필요)
node --version

# 2. 의존성 설치
npm install

# 3. 환경변수 복사
cp .env.example .env

# 4. PostgreSQL 시작
docker run --name aida-postgres -d \
  -e POSTGRES_DB=aida \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=Wonder9595!! \
  -p 5432:5432 postgres:15

# 5. 데이터베이스 초기화
npm run db:setup

# 6. 검증
npm run validate:quick
```

---

## 📝 **환경변수 설정**

### **기본 .env 파일**
```env
# Node.js 환경
NODE_ENV=development
LOG_LEVEL=debug

# Gateway Agent
GATEWAY_PORT=8000
WEBHOOK_SECRET=TestSecret123AbC

# Smart Investigator
INVESTIGATOR_PORT=8001
MAX_CONCURRENT_TASKS=3

# PostgreSQL
DATABASE_URL=postgresql://postgres:Wonder9595!!@localhost:5432/aida
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=Wonder9595!!
DB_NAME=aida

# A2A Protocol
A2A_DISCOVERY_ENABLED=true
A2A_TASK_TIMEOUT=180000
```

---

## ✅ **검증 체크리스트**

### **필수 검증 (30초)**
```bash
# TypeScript 컴파일 확인
npm run typecheck

# ESLint 검증
npm run lint -- --quiet

# 기본 테스트 실행
npm run test:unit

# PostgreSQL 연결 테스트
npm run test:db
```

### **성공 기준**
- [ ] TypeScript 컴파일: 0 errors
- [ ] ESLint: 경고만 있고 에러 없음
- [ ] Unit 테스트: 모든 테스트 통과
- [ ] DB 연결: `Connection successful` 메시지

---

## 🔧 **일반적인 문제 해결**

### **Node.js 버전 문제**
```bash
# nvm으로 Node.js 20 설치
nvm install 20
nvm use 20

# 버전 확인
node --version
```

### **PostgreSQL 포트 충돌**
```bash
# 기존 PostgreSQL 프로세스 확인
lsof -i :5432

# Docker 컨테이너 정리
docker stop aida-postgres
docker rm aida-postgres
```

### **npm 캐시 문제**
```bash
# npm 캐시 정리
npm cache clean --force
rm -rf node_modules package-lock.json
npm install
```

### **권한 문제 (macOS/Linux)**
```bash
# Docker 권한 확인
sudo docker ps

# Node.js 권한 설정
sudo chown -R $(whoami) ~/.npm
```

---

## 🚀 **다음 단계**

### **개발 서버 시작**
```bash
# 모든 Agent 실행
npm run dev:all

# Health Check 확인
curl http://localhost:8000/health
curl http://localhost:8001/health
```

### **추가 설정 (선택사항)**
- [상세 개발환경 설정](./detailed-setup.md) - IDE, 디버깅, 확장
- [Docker Compose 설정](./docker-compose-setup.md) - 전체 스택 Docker
- [문제 해결 가이드](./troubleshooting.md) - 고급 문제 해결

### **개발 시작**
- [코딩 표준](../standards/coding-standards.md) - TypeScript, ESLint 규칙
- [TDD 워크플로우](../workflows/tdd-workflow.md) - 테스트 작성 패턴
- [Gateway 구현](../../agents/gateway/overview.md) - 첫 번째 Agent 구현

---

## 📊 **설정 시간 측정**

| 단계 | 예상 시간 | 실제 시간 |
|------|----------|----------|
| Node.js 확인 | 10초 | ___ |
| npm install | 2분 | ___ |
| PostgreSQL 시작 | 1분 | ___ |
| 환경변수 설정 | 30초 | ___ |
| 검증 실행 | 1분 30초 | ___ |
| **총 소요시간** | **5분** | **___** |

---

**⏱️ 목표 달성**: 5분 내에 완료되었나요?  
**⏭️ 다음**: [코딩 표준](../standards/coding-standards.md)  
**🐛 문제**: [문제 해결 가이드](./troubleshooting.md)