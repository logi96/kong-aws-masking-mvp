# Kong AWS Masker 실시간 모니터링 - 배포 체크리스트

## 📋 배포 단계별 체크리스트

### 🔍 Phase 1: 사전 준비 (Pre-deployment)

#### 1.1 코드 준비
- [ ] Git 브랜치 생성: `feature/real-time-monitoring`
- [ ] 모든 코드 변경 완료
  - [ ] `monitoring.lua` 수정 완료
  - [ ] `handler.lua` 수정 완료  
  - [ ] `redisSubscriber.js` 생성 완료
  - [ ] `app.js` 수정 완료
- [ ] 코드 리뷰 완료
- [ ] 단위 테스트 통과

#### 1.2 환경 확인
- [ ] Docker 버전 확인 (>= 20.10)
- [ ] Docker Compose 버전 확인 (>= 1.29)
- [ ] 디스크 공간 확인 (최소 2GB 여유)
- [ ] 네트워크 연결 확인

#### 1.3 백업
```bash
# Kong 플러그인 백업
tar -czf kong-plugins-backup-$(date +%Y%m%d).tar.gz kong/plugins/aws-masker/

# Backend 백업
tar -czf backend-backup-$(date +%Y%m%d).tar.gz backend/

# 환경 설정 백업
cp .env .env.backup-$(date +%Y%m%d)
cp docker-compose.yml docker-compose.yml.backup-$(date +%Y%m%d)
```

---

### 🚀 Phase 2: 개발 환경 배포 (Development)

#### 2.1 환경 설정
```bash
# 개발 환경 설정
export NODE_ENV=development
export ENABLE_REDIS_EVENTS=true
export LOG_LEVEL=debug
```

#### 2.2 의존성 설치
```bash
# Backend Redis 패키지 설치
cd backend
npm install
cd ..
```

#### 2.3 개발 환경 배포
```bash
# 시스템 중지
docker-compose down

# 이미지 재빌드 (필요시)
docker-compose build --no-cache

# 시스템 시작
docker-compose up -d

# 상태 확인
docker-compose ps
```

#### 2.4 개발 환경 검증
- [ ] Kong 헬스체크: `curl http://localhost:8001/status`
- [ ] Backend 헬스체크: `curl http://localhost:3000/health`
- [ ] Redis 연결: `docker exec -it redis-cache redis-cli ping`
- [ ] 이벤트 구독 확인: Backend 로그에 "Subscribed to kong:masking:events" 표시

---

### 🧪 Phase 3: 스테이징 환경 배포 (Staging)

#### 3.1 환경 설정
```bash
# 스테이징 환경 설정
export NODE_ENV=staging
export ENABLE_REDIS_EVENTS=true
export LOG_LEVEL=info

# 스테이징용 .env 파일
cp .env.staging .env
```

#### 3.2 성능 최적화 설정
```yaml
# docker-compose.override.yml
version: '3.8'
services:
  kong:
    deploy:
      resources:
        limits:
          memory: 1g
          cpus: '1.0'
  
  backend:
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: '0.5'
```

#### 3.3 스테이징 배포
```bash
# 스테이징 배포 스크립트
cat > deploy-staging.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting staging deployment..."

# 1. 환경 검증
if [ "$NODE_ENV" != "staging" ]; then
  echo "❌ NODE_ENV must be 'staging'"
  exit 1
fi

# 2. 헬스체크
echo "🔍 Running health checks..."
curl -f http://localhost:8001/status || exit 1
curl -f http://localhost:3000/health || exit 1

# 3. 배포
echo "📦 Deploying to staging..."
docker-compose down
docker-compose up -d

# 4. 배포 검증
sleep 10
docker-compose ps

echo "✅ Staging deployment completed"
EOF

chmod +x deploy-staging.sh
./deploy-staging.sh
```

#### 3.4 스테이징 테스트
- [ ] 부하 테스트 실행 (100 requests)
- [ ] 24시간 안정성 테스트
- [ ] 메모리 누수 확인
- [ ] 로그 분석

---

### 🏭 Phase 4: 프로덕션 환경 배포 (Production)

#### 4.1 프로덕션 체크리스트
- [ ] 변경 승인 완료
- [ ] 배포 일정 공지
- [ ] 롤백 계획 준비
- [ ] 모니터링 대시보드 준비

#### 4.2 프로덕션 환경 설정
```bash
# 프로덕션 환경 설정
export NODE_ENV=production
export ENABLE_REDIS_EVENTS=false  # 초기에는 비활성화
export LOG_LEVEL=warn

# 프로덕션 보안 설정
export REDIS_PASSWORD=$(openssl rand -base64 32)
```

#### 4.3 단계적 배포 (Canary Deployment)

##### Step 1: 기능 비활성화 상태로 배포
```bash
# ENABLE_REDIS_EVENTS=false로 배포
docker-compose up -d

# 기본 기능 검증
./run-basic-tests.sh
```

##### Step 2: 부분 활성화 (10%)
```bash
# 일부 트래픽만 이벤트 활성화
export ENABLE_REDIS_EVENTS=true
export REDIS_EVENT_SAMPLE_RATE=0.1  # 10% 샘플링

docker-compose up -d
```

##### Step 3: 전체 활성화
```bash
# 모든 트래픽에 대해 활성화
export REDIS_EVENT_SAMPLE_RATE=1.0  # 100%

docker-compose up -d
```

#### 4.4 프로덕션 모니터링
```bash
# 실시간 모니터링 스크립트
cat > monitor-prod.sh << 'EOF'
#!/bin/bash

echo "📊 Production Monitoring Dashboard"
echo "================================="

while true; do
  clear
  echo "🕐 $(date)"
  echo ""
  
  # CPU & Memory
  echo "📈 Resource Usage:"
  docker stats --no-stream | grep -E "(NAME|kong|backend|redis)"
  echo ""
  
  # Error logs
  echo "⚠️ Recent Errors:"
  docker-compose logs --tail=5 | grep -E "(ERROR|WARN)"
  echo ""
  
  # Redis metrics
  echo "📦 Redis Metrics:"
  docker exec -it redis-cache redis-cli info stats | grep -E "(total_commands|instantaneous_ops)"
  
  sleep 5
done
EOF

chmod +x monitor-prod.sh
```

---

### 🔄 Phase 5: 배포 후 검증 (Post-deployment)

#### 5.1 기능 검증
- [ ] 마스킹 기능 정상 동작
- [ ] 언마스킹 기능 정상 동작
- [ ] 이벤트 발행 확인 (활성화된 경우)
- [ ] 콘솔 로그 출력 확인

#### 5.2 성능 검증
- [ ] 응답 시간 기준치 이내
- [ ] CPU 사용률 < 70%
- [ ] 메모리 사용률 < 80%
- [ ] 에러율 < 0.1%

#### 5.3 보안 검증
- [ ] Redis 인증 활성화
- [ ] 민감 정보 노출 없음
- [ ] 로그 레벨 적절함
- [ ] 네트워크 격리 확인

---

### 🚨 Phase 6: 롤백 계획 (Rollback)

#### 6.1 즉시 롤백 (긴급)
```bash
# 1. 기능 비활성화
export ENABLE_REDIS_EVENTS=false
docker-compose up -d

# 2. 확인
docker-compose logs --tail=50
```

#### 6.2 완전 롤백 (코드 복원)
```bash
# 1. 백업 복원
tar -xzf kong-plugins-backup-YYYYMMDD.tar.gz
tar -xzf backend-backup-YYYYMMDD.tar.gz

# 2. 환경 설정 복원
cp .env.backup-YYYYMMDD .env
cp docker-compose.yml.backup-YYYYMMDD docker-compose.yml

# 3. 재배포
docker-compose down
docker-compose up -d
```

---

## 📊 배포 메트릭 기록

### 배포 정보 기록 템플릿
```yaml
deployment:
  date: "2025-07-24"
  version: "1.0.0"
  environment: "production"
  deployer: "Your Name"
  
metrics:
  deployment_time: "15 minutes"
  downtime: "0 minutes"
  rollback_required: false
  
performance:
  before:
    avg_response_time: "9.5s"
    error_rate: "0.05%"
  after:
    avg_response_time: "9.8s"
    error_rate: "0.05%"
    
issues:
  - none
  
notes:
  - "Smooth deployment with zero downtime"
  - "Redis events successfully integrated"
```

---

## 🔐 보안 체크리스트

### 프로덕션 보안 강화
- [ ] Redis 비밀번호 설정
- [ ] 환경변수 암호화
- [ ] 네트워크 방화벽 규칙
- [ ] 로그 접근 제한
- [ ] 모니터링 알림 설정

### 민감 정보 관리
```bash
# .env 파일 권한 설정
chmod 600 .env

# Git에서 제외 확인
grep -E "(\.env|redis\.conf)" .gitignore
```

---

## 📝 최종 확인 사항

### 문서화
- [ ] 배포 과정 문서화
- [ ] 운영 가이드 업데이트
- [ ] 트러블슈팅 가이드 업데이트
- [ ] API 문서 업데이트

### 팀 공유
- [ ] 배포 완료 공지
- [ ] 새 기능 사용법 교육
- [ ] 모니터링 대시보드 공유
- [ ] 비상 연락처 업데이트

---

## 🎯 성공 기준

### 배포 성공 지표
1. **Zero Downtime**: 서비스 중단 없음
2. **Performance**: 성능 저하 < 5%
3. **Stability**: 24시간 안정 운영
4. **Security**: 보안 이슈 없음

### 장기 성공 지표
1. **Adoption**: 팀 활용도 > 80%
2. **Value**: 문제 해결 시간 단축
3. **Reliability**: 99.9% 가용성
4. **Scalability**: 부하 증가 대응

---

*이 체크리스트를 활용하여 안전하고 성공적인 배포를 수행하세요.*