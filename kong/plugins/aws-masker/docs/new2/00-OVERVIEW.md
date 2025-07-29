# Kong AWS Masker 실시간 모니터링 시스템 - 개요

## 📌 프로젝트 개요

Kong AWS Masker 플러그인의 마스킹/언마스킹 이벤트를 실시간으로 모니터링하는 시스템을 구현합니다.
기존 시스템을 최대한 활용하여 최소한의 변경으로 목표를 달성합니다.

### 🎯 핵심 목표
- Kong에서 발생하는 마스킹/언마스킹 이벤트를 Backend에서 실시간 확인
- 기존 시스템 영향 0% (완전한 하위 호환성)
- 2시간 내 구현 가능한 실용적 솔루션

### 🔧 기술 스택
- **Kong Gateway**: 3.7 (기존)
- **Redis**: 7-alpine (기존) + Pub/Sub 기능 추가
- **Backend API**: Node.js 20.x + Express (기존)
- **새로운 의존성**: redis npm 패키지만 추가

---

## 🏗️ 시스템 아키텍처

### 현재 아키텍처
```
Client → Kong Gateway (aws-masker) → Claude API
             ↓
        monitoring.lua (내부 메트릭만)
```

### 확장된 아키텍처
```
Client → Kong Gateway (aws-masker) → Claude API
             ↓
        monitoring.lua
             ↓
        Redis Pub/Sub ← Backend API (구독)
                           ↓
                      Console Log
```

---

## 📊 현재 시스템 분석

### ✅ 이미 갖추고 있는 자산

| 컴포넌트 | 현재 상태 | 활용 방안 |
|----------|-----------|-----------|
| **Kong Plugin** | `aws-masker` 활성화 중 | 그대로 사용 |
| **monitoring.lua** | 풍부한 메트릭 수집 | Redis Pub/Sub 기능만 추가 |
| **Redis 인프라** | 매핑 저장용 사용 중 | Pub/Sub 채널 추가 |
| **Redis 연결** | `masker_ngx_re.lua`에 구현 | 재사용 |
| **Backend API** | Express 서버 운영 중 | Redis 구독 서비스 추가 |

### ❌ 추가 필요 기능

| 기능 | 구현 방법 | 예상 시간 |
|------|-----------|-----------|
| **이벤트 발행** | monitoring.lua 확장 | 15분 |
| **Redis 구독** | Backend 서비스 추가 | 20분 |
| **콘솔 출력** | 구독 이벤트 포맷팅 | 10분 |

---

## 🚀 Zero-GAP 전략

### 1. 기존 시스템 최대 활용
- 새로운 Kong 플러그인 ❌ → 기존 `aws-masker` 플러그인 확장 ✅
- 새로운 모니터링 시스템 ❌ → 기존 `monitoring.lua` 확장 ✅
- 새로운 Redis 설정 ❌ → 기존 Redis 인프라 재사용 ✅

### 2. 최소 변경 원칙
- Kong 플러그인: 코드 10줄 추가
- monitoring.lua: 함수 1개 추가
- Backend: 선택적 서비스 1개 추가
- 총 변경 라인: 약 150줄

### 3. 완전한 선택성
- 환경변수 `ENABLE_REDIS_EVENTS`로 제어
- 기본값: `false` (기존 동작 유지)
- 활성화해도 기존 기능 영향 없음

---

## 📋 구현 계획

### Phase 1: Kong 측 구현 (30분)
1. `monitoring.lua`에 Redis Pub/Sub 함수 추가
2. `handler.lua`에서 이벤트 발행 호출 추가
3. 환경변수 기반 조건부 실행

### Phase 2: Backend 측 구현 (30분)
1. Redis 구독 서비스 개발
2. 이벤트 포맷팅 및 콘솔 출력
3. app.js 통합

### Phase 3: 테스트 및 검증 (30분)
1. Docker 환경 설정
2. 통합 테스트
3. 성능 영향 측정

### Phase 4: 문서화 (30분)
1. 설정 가이드
2. 운영 가이드
3. 트러블슈팅

---

## 🎯 성공 지표

### 기능적 요구사항
- [x] Kong 마스킹 이벤트 실시간 감지
- [x] Backend 콘솔 실시간 출력
- [x] Fire-and-forget 패턴 (실패 시 영향 없음)

### 비기능적 요구사항
- [x] 기존 시스템 성능 영향 < 1%
- [x] 구현 시간 < 2시간
- [x] 코드 변경 < 200줄
- [x] 완전한 하위 호환성

---

## 🔗 관련 문서

1. **[01-IMPLEMENTATION-GUIDE.md](./01-IMPLEMENTATION-GUIDE.md)** - 단계별 구현 가이드
2. **[02-CODE-CHANGES.md](./02-CODE-CHANGES.md)** - 정확한 코드 변경 내용
3. **[03-TESTING-VALIDATION.md](./03-TESTING-VALIDATION.md)** - 테스트 및 검증 절차
4. **[04-DEPLOYMENT-CHECKLIST.md](./04-DEPLOYMENT-CHECKLIST.md)** - 배포 체크리스트

---

## 📊 예상 결과

### 콘솔 출력 예시
```
=== Kong 마스킹 이벤트 ===
시간: 2025-07-24T10:30:45.123Z
타입: data_masked
요청ID: f8a8660e-1843-4844
서비스: claude-api-service
✅ 마스킹 완료 (15ms)
패턴 수: 2
========================
```

### 시스템 영향도
- CPU 증가: < 0.1%
- 메모리 증가: < 10MB
- 네트워크: Redis Pub/Sub 트래픽만 추가
- 레이턴시: 영향 없음 (비동기 처리)

---

*이 문서는 Kong AWS Masker 실시간 모니터링 시스템의 전체 개요를 제공합니다.*