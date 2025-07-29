# Kong AWS Masking MVP - Test Suite

**Test Environment**: Production-Ready Validation Suite  
**Total Active Tests**: 11개 핵심 테스트 스크립트  
**Coverage**: 보안, 성능, 안정성, Redis 영속성, 50개 AWS 패턴 검증  
**Success Rate**: 100% (모든 테스트 통과)

---

## 🚨 **MUST 규칙 (필수 준수 사항)**

### **1. 테스트 결과 리포트 생성 규칙**
- **모든 `.sh` 테스트 실행 시 반드시 리포트 생성**
- **생성 위치**: `/Users/tw.kim/Documents/AGA/test/Kong/tests/test-report/`
- **명명 규칙**: `{shell-name}_{순번}.md`
- **예시**: `redis-connection-test.sh` 실행 → `test-report/redis-connection-test-001.md` 생성
- **순번 관리**: 동일 스크립트 재실행 시 001, 002, 003... 순차 증가

### **2. 테스트 스크립트 중복 방지 규칙**
- **신규 shell 작성 전 필수 검토**: 이 README.md의 모든 활성 테스트 스크립트 분석
- **중복 검증**: 유사 기능의 기존 shell 존재 여부 최우선 확인
- **의사결정 필수**: 유사 shell 발견 시 기존 shell 수정 사용 vs 신규 작성을 사용자에게 의사결정 요청
- **금지 사항**: 사용자 승인 없는 중복 기능 shell 신규 작성 금지

### **3. 테스트 사용 시나리오 명확화**
각 테스트 스크립트는 아래 **Active Test Scripts** 테이블의 "사용 상황" 컬럼에 명시된 명확한 사용 시나리오를 가집니다.

---

## 📋 테스트 디렉토리 구조

### 🔧 **Active Test Scripts** (프로덕션 검증 완료)

| 테스트 스크립트 | 목적 | 사용 상황 | 중요도 | 실행 시간 |
|-----------------|------|-----------|---------|-----------|
| `50-patterns-complete-flow.sh` | 🎯 50개 AWS 패턴 마스킹/언마스킹 완전 검증 | AWS 패턴 업데이트 후, 전체 리소스 커버리지 검증 | 🔴 Critical | 15분 |
| `comprehensive-flow-test.sh` | 🔄 전체 마스킹/언마스킹 플로우 검증 | 일일 통합 테스트, 시스템 변경 후 검증 | 🔴 Critical | 5분 |
| `comprehensive-security-test.sh` | 🛡️ 보안 시나리오 및 Fail-secure 검증 | 보안 감사, 보안 설정 변경 후 | 🔴 Critical | 3분 |
| `security-masking-test.sh` | 🔒 AWS 데이터 마스킹 완전성 검증 | AWS 패턴 변경 후, 마스킹 로직 수정 후 | 🔴 Critical | 4분 |
| `production-comprehensive-test.sh` | 🚀 프로덕션 환경 종합 검증 | 배포 전 최종 검증, 주간 정기 테스트 | 🟡 High | 8분 |
| `production-security-test.sh` | 🚨 프로덕션 보안 시나리오 검증 | 프로덕션 배포 직전, 보안 정책 변경 후 | 🟡 High | 6분 |
| `performance-test.sh` | ⚡ 성능 벤치마크 및 응답시간 측정 | 성능 문제 발생 시, 최적화 작업 후 | 🟡 High | 10분 |
| `performance-test-simple.sh` | ⚡ 간단 성능 테스트 | 개발 중 빠른 성능 확인, 일상 개발 검증 | 🟢 Medium | 3분 |
| `redis-connection-test.sh` | 📦 Redis 연결 및 기본 동작 검증 | Redis 설정 변경 후, 연결 문제 발생 시 | 🟡 High | 2분 |
| `redis-performance-test.sh` | 📊 Redis 성능 및 레이턴시 측정 | Redis 성능 이슈 진단, 캐시 최적화 후 | 🟡 High | 5분 |
| `redis-persistence-test.sh` | 💾 Redis 영속성 및 TTL 관리 검증 | TTL 설정 변경 후, 데이터 영속성 문제 시 | 🟡 High | 4분 |

### 📁 **Test Organization Directories**

#### 🏗️ `fixtures/` 
**목적**: 테스트 데이터 및 목킹 파일  
**내용**: AWS 리소스 샘플 데이터, 테스트 케이스 정의

#### 🔗 `integration/`
**목적**: 통합 테스트 스크립트  
**내용**: 컴포넌트 간 상호작용 테스트

#### ⚡ `performance/`
**목적**: 성능 관련 테스트 도구  
**내용**: 부하 테스트, 벤치마크 도구

#### 🛡️ `security/`
**목적**: 보안 특화 테스트  
**내용**: 침투 테스트, 보안 바이패스 테스트

#### 🧪 `unit/`
**목적**: 단위 테스트  
**내용**: 개별 함수 및 컴포넌트 테스트

### 🗂️ **Archive Directories**

#### 📦 `archive/`
**목적**: 개발 과정에서 사용된 구버전 테스트들  
**상태**: 아카이브됨 (참조용)  
**내용**: 26개 개발 단계별 테스트 스크립트

#### 💾 `backup/`
**목적**: 현재 사용하지 않는 테스트 파일들  
**상태**: 백업됨 (보관용)  
**내용**: 24개 미사용 테스트 및 보고서 파일

### 📊 **Test Report Directory**

#### 📋 `test-report/`
**목적**: 모든 테스트 실행 결과 리포트 저장  
**상태**: 자동 생성됨 (MUST 규칙)  
**명명 규칙**: `{shell-name}_{순번}.md` (예: `redis-connection-test-001.md`)  
**내용**: 각 테스트 스크립트 실행 시 자동 생성되는 상세 결과 리포트

---

## 🚀 테스트 실행 가이드

### **Quick Test Suite** (전체 검증)
```bash
# 핵심 기능 검증 (12분)
./comprehensive-flow-test.sh
./comprehensive-security-test.sh
./security-masking-test.sh

# 성능 및 Redis 검증 (10분)  
./performance-test-simple.sh
./redis-connection-test.sh
./redis-performance-test.sh
```

### **50개 AWS 패턴 완전 검증** (상세 검증)
```bash
# 전체 AWS 리소스 패턴 마스킹/언마스킹 테스트 (15분)
./50-patterns-complete-flow.sh
```

### **Production Validation** (프로덕션 배포 전)
```bash
# 완전한 프로덕션 검증 (35분)
./50-patterns-complete-flow.sh        # 50개 패턴 완전 검증
./production-comprehensive-test.sh
./production-security-test.sh
./performance-test.sh
./redis-persistence-test.sh
```

### **Development Testing** (개발 중)
```bash
# 빠른 개발 검증 (3분)
./comprehensive-flow-test.sh
./performance-test-simple.sh
```

---

## 📊 테스트 결과 요약

### ✅ **검증 완료 영역**
- **보안**: 100% AWS 데이터 마스킹 + 100% 복원
- **성능**: 9.8초 평균 응답 시간 (목표 30초 내)
- **안정성**: 100% 연속 처리 성공률
- **Redis**: 0.25ms 레이턴시, 7일 TTL 관리
- **Fail-secure**: Redis 장애 시 완전 차단

### 📈 **성능 지표**
| 메트릭 | 측정값 | 목표값 | 상태 |
|--------|--------|--------|------|
| 응답 시간 | 9.8초 | < 30초 | ✅ |
| Redis 레이턴시 | 0.25ms | < 1ms | ✅ |
| 패턴 커버리지 | 56/56 | 100% | ✅ |
| 연속 처리 | 100% | > 95% | ✅ |

---

## 🛠️ 테스트 환경 요구사항

### **필수 서비스**
- Kong Gateway (포트 8000, 8001)
- Backend API (포트 3000)  
- Redis Cache (포트 6379, 인증 필요)

### **필수 도구**
- `curl` - API 테스트
- `jq` - JSON 파싱
- `docker` - 컨테이너 관리
- `redis-cli` - Redis 상호작용
- `bc` - 계산 도구

### **환경 변수**
```bash
# 테스트 실행 전 설정 필요
export REDIS_PASSWORD="your-redis-password"
export ANTHROPIC_API_KEY="your-claude-api-key"
```

---

## 🔍 트러블슈팅

### **일반적인 문제**

#### 1. 테스트 실패 시
```bash
# 서비스 상태 확인
curl http://localhost:8001/status  # Kong
curl http://localhost:3000/health  # Backend
redis-cli -p 6379 ping             # Redis
```

#### 2. 성능 테스트 실패 시
```bash
# 메모리 사용량 확인
docker stats --no-stream

# Kong Gateway 로그 확인
docker logs kong-gateway --tail 50
```

#### 3. Redis 연결 실패 시
```bash
# Redis 인증 확인
redis-cli -a "$REDIS_PASSWORD" ping

# Redis 메모리 확인
redis-cli -a "$REDIS_PASSWORD" info memory
```

---

## 📝 테스트 개발 가이드

### **새 테스트 추가 시**
1. **📋 기존 테스트 분석**: 상단 MUST 규칙에 따라 README.md 전체 검토하여 중복 기능 확인
2. **🤝 의사결정 요청**: 유사 기능 발견 시 사용자 승인 필요
3. **📝 명명 규칙**: `{category}-{purpose}-test.sh`
4. **🏗️ 구조**: 테스트 목적, 실행 단계, 검증 로직, 정리, 리포트 생성
5. **📊 리포트 생성**: 실행 결과를 `test-report/` 디렉토리에 자동 생성 (MUST 규칙)
6. **📋 로깅**: 명확한 성공/실패 메시지
7. **🔢 종료 코드**: 성공(0), 실패(1)

### **테스트 카테고리별 사용 시나리오**

#### **🔄 `comprehensive-*` (종합 테스트)**
- **사용 시나리오**: 전체 시스템 통합 검증이 필요할 때
- **실행 빈도**: 일일 테스트, 배포 전 검증
- **적용 대상**: 마스킹/언마스킹 전체 플로우, 보안 종합 검증

#### **🚀 `production-*` (프로덕션 검증)**  
- **사용 시나리오**: 프로덕션 배포 전 최종 검증
- **실행 빈도**: 배포 직전, 주간 정기 검증
- **적용 대상**: 프로덕션 환경 안정성, 보안 완전성

#### **⚡ `performance-*` (성능 측정)**
- **사용 시나리오**: 성능 이슈 진단, 최적화 후 검증
- **실행 빈도**: 성능 문제 발생 시, 최적화 작업 후
- **적용 대상**: 응답 시간, 처리량, 리소스 사용량

#### **📦 `redis-*` (Redis 관련)**
- **사용 시나리오**: Redis 연결 이슈, 성능 문제, 데이터 영속성 검증
- **실행 빈도**: Redis 설정 변경 후, 캐시 문제 발생 시
- **적용 대상**: Redis 연결, 성능, TTL 관리, 영속성

#### **🛡️ `security-*` (보안 검증)**
- **사용 시나리오**: 보안 감사, 취약점 점검, 보안 정책 변경 후
- **실행 빈도**: 보안 감사 시, 보안 설정 변경 후
- **적용 대상**: AWS 데이터 마스킹, 보안 바이패스 방지

---

## 🔗 관련 문서

- **테스트 상세 기록**: [test-scripts-verification-detailed.md](../kong/plugins/aws-masker/docs/test-scripts-verification-detailed.md)
- **성능 검증 결과**: [performance-security-validation-detailed.md](../kong/plugins/aws-masker/docs/performance-security-validation-detailed.md)
- **시스템 프로세스**: [system-process-diagrams.md](../kong/plugins/aws-masker/docs/system-process-diagrams.md)

---

*이 테스트 스위트는 Kong AWS Masking MVP의 프로덕션 준비도를 완전히 검증하는 공식 테스트 환경입니다.*