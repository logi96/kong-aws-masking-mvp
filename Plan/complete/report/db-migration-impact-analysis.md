# Kong DB-less에서 DB 모드 전환 영향도 분석 보고서

## 요약
- **영향도**: 매우 높음 (★★★★★)
- **예상 작업량**: 2-3주
- **권장사항**: 현재 MVP 단계에서는 **DB-less 유지 권장**

## 1. 현재 상태 분석

### 현재 아키텍처 (DB-less)
```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Backend    │────▶│  Kong        │────▶│  Claude API  │
│  (Node.js)  │     │  (DB-less)   │     │              │
└─────────────┘     └──────────────┘     └──────────────┘
                           │
                    ┌──────────────┐
                    │ Memory Store │ (TTL: 1시간)
                    │  - mappings  │
                    │  - counters  │
                    └──────────────┘
```

### 매핑 데이터 현재 저장 방식
- **저장 위치**: 메모리 (Kong 프로세스 내)
- **TTL**: 3600초 (1시간)
- **용량**: 최대 10,000 엔트리
- **영속성**: 없음 (재시작 시 손실)

## 2. DB 모드 전환 시 변경사항

### 2.1 아키텍처 변경
```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Backend    │────▶│  Kong        │────▶│  Claude API  │
│  (Node.js)  │     │  (DB mode)   │     │              │
└─────────────┘     └──────────────┘     └──────────────┘
                           │
                    ┌──────────────┐
                    │  PostgreSQL  │ (TTL: 7일)
                    │  Database    │
                    └──────────────┘
```

### 2.2 주요 변경 필요 사항

#### Docker Compose 수정
```yaml
# 추가 서비스
postgres:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB: kong
    POSTGRES_USER: kong
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  volumes:
    - postgres-data:/var/lib/postgresql/data
  healthcheck:
    test: ["CMD", "pg_isready", "-U", "kong"]
    interval: 10s
    timeout: 5s
    retries: 5

# Kong 설정 변경
kong:
  environment:
    KONG_DATABASE: "postgres"  # "off" → "postgres"
    KONG_PG_HOST: postgres
    KONG_PG_USER: kong
    KONG_PG_PASSWORD: ${POSTGRES_PASSWORD}
    # KONG_DECLARATIVE_CONFIG 제거
  depends_on:
    postgres:
      condition: service_healthy
```

#### 플러그인 코드 수정
1. **데이터 저장 로직 전면 재작성**
   - 메모리 저장 → DB 쿼리로 변경
   - Kong DAO 사용 필요
   - 트랜잭션 처리 추가

2. **새로운 파일 필요**
   - `daos.lua`: DB 스키마 정의
   - `migrations/init.lua`: DB 마이그레이션
   - `migrations/001_initial_schema.lua`: 테이블 생성

3. **handler.lua 수정 예시**
```lua
-- 현재 (메모리)
mapping_store.mappings[masked_id] = original_value

-- DB 모드
local entity, err = kong.db.aws_maskings:insert({
  masked_id = masked_id,
  original_value = original_value,
  resource_type = resource_type,
  ttl = 604800  -- 7일
})
```

## 3. 성능 영향 분석

### 3.1 응답 시간 변화
| 작업 | 현재 (메모리) | DB 모드 | 증가량 |
|------|--------------|---------|--------|
| 마스킹 조회 | ~0.1ms | 1-5ms | 10-50배 |
| 마스킹 저장 | ~0.1ms | 2-10ms | 20-100배 |
| 전체 요청 | <100ms | 110-200ms | 10-100% |

### 3.2 리소스 사용량
- **추가 메모리**: PostgreSQL 최소 512MB
- **디스크**: 매핑 데이터 + 인덱스 (예상 1-10GB)
- **CPU**: DB 쿼리 처리로 10-20% 증가
- **네트워크**: Kong ↔ DB 간 트래픽 추가

## 4. 리스크 분석

### 4.1 높은 리스크 🔴
1. **성능 목표 미달성**
   - 현재 목표: 전체 응답 < 5초
   - DB 추가 시 달성 어려울 수 있음

2. **데이터 일관성**
   - 동시 요청 시 중복 매핑 생성 가능
   - 트랜잭션 처리 복잡도 증가
   - 레이스 컨디션 방지 필요

3. **운영 복잡도**
   - DB 백업/복구 프로세스 추가
   - 모니터링 포인트 2배 증가
   - 장애 포인트 추가 (DB 다운 시 전체 서비스 중단)

### 4.2 중간 리스크 🟡
1. **마이그레이션**
   - 기존 메모리 데이터 손실
   - 다운타임 발생 (최소 5-10분)
   - 롤백 전략 복잡

2. **확장성**
   - DB 커넥션 풀 관리 필요
   - 대용량 처리 시 DB 병목

### 4.3 낮은 리스크 🟢
1. **기술 호환성**
   - Kong 3.9 DB 모드 완벽 지원
   - PostgreSQL 15 안정성 검증됨

## 5. 구현 복잡도 상세

### 필요 작업 목록
1. **DB 스키마 설계** (3일)
   - 테이블 구조 설계
   - 인덱스 전략 수립
   - 파티셔닝 계획

2. **플러그인 코드 수정** (5-7일)
   - DAO 레이어 구현
   - 마이그레이션 스크립트 작성
   - 에러 처리 로직 추가

3. **테스트 및 검증** (3-5일)
   - 성능 테스트
   - 부하 테스트
   - 장애 시나리오 테스트

4. **배포 준비** (2일)
   - 배포 스크립트 수정
   - 모니터링 설정
   - 운영 문서 작성

**총 예상 기간: 13-17일 (2-3주)**

## 6. 대안 및 권장사항

### 6.1 대안 1: Redis 사용 (권장) ⭐
```yaml
redis:
  image: redis:7-alpine
  command: redis-server --appendonly yes
  volumes:
    - redis-data:/data
```

**장점**:
- 메모리 기반으로 빠른 성능
- TTL 네이티브 지원
- 구현 복잡도 낮음 (3-5일)
- AOF로 영속성 제공

**단점**:
- 추가 인프라 필요
- 메모리 제한 있음

### 6.2 대안 2: 하이브리드 접근
- 단기 캐시: 메모리 (1시간)
- 장기 저장: 파일 또는 S3 (7일)
- 비동기 백업으로 성능 영향 최소화

### 6.3 대안 3: 현재 구조 유지 + 모니터링
- 실제 7일 보관 필요성 검증
- 사용 패턴 분석 후 결정
- MVP 검증 우선

## 7. 최종 권장사항

### 현재 단계 (MVP)
**DB-less 모드 유지를 강력히 권장합니다.**

**이유**:
1. 구현 복잡도가 매우 높음 (2-3주 추가 개발)
2. 성능 목표(5초) 달성 위험
3. 운영 복잡도 크게 증가
4. MVP 핵심 기능 검증에 불필요

### 향후 로드맵
1. **Phase 1** (현재): DB-less로 MVP 검증
2. **Phase 2** (1개월 후): Redis 캐시 추가 검토
3. **Phase 3** (3개월 후): 사용 패턴 분석 후 DB 전환 검토

### 즉시 적용 가능한 개선안
```lua
-- masker_ngx_re.lua 수정
_M.config = {
  ttl = 86400,          -- 1시간 → 24시간으로 증가
  max_entries = 50000,  -- 10,000 → 50,000으로 증가
  clean_interval = 3600 -- 5분 → 1시간으로 조정
}
```

이 설정으로 메모리 사용량은 증가하지만 (약 100-200MB), DB 없이도 더 긴 시간 매핑을 유지할 수 있습니다.

---

**보고서 작성일**: 2025년 7월 23일
**작성자**: Claude Assistant
**결론**: DB 모드 전환은 현재 시점에서 **권장하지 않음**