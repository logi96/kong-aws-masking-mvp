# Kong AWS Masker 실시간 모니터링 개선 계획 - Part 1: 개요 및 Phase 1-2

## 📋 프로젝트 개요

Kong AWS Masker 플러그인의 마스킹/언마스킹 이벤트를 Backend에서 실시간으로 모니터링할 수 있도록 개선하는 프로젝트입니다. `/kong/plugins/aws-masker/docs/new2/` 문서 분석을 통해 발견된 중요 기술적 이슈들을 해결하는 개선된 구현 방식을 채택합니다.

### 🎯 목표 (GOAL)
- Kong에서 발생하는 마스킹/언마스킹 이벤트를 Backend에서 실시간 확인
- **중요 기술적 문제 해결**: Redis 연결 경쟁 조건, 대용량 응답 처리, 성능 영향 최소화
- 프로덕션 환경에서 안전하게 운영 가능한 모니터링 시스템 구축

### 📊 성공 지표 (METRIC)
- [ ] 100% 하위 호환성 유지 (기존 기능 영향 없음)
- [ ] 성능 오버헤드 < 10% (샘플링 및 배치 처리 적용)
- [ ] Redis 연결 경쟁 조건 해결 (연결 재사용)
- [ ] 대용량 응답 처리 가능 (청크 단위 처리)
- [ ] 모든 테스트 통과 및 test-report 생성
- [ ] 24시간 안정성 테스트 통과

### 🛠️ 접근 방법 (PLAN)
1. **개선된 구현 방식 채택** (`06-IMPROVED-IMPLEMENTATION.md` 기반)
   - 플러그인 설정 기반 제어 (환경변수 대신)
   - Redis 연결 재사용 메커니즘
   - 청크 단위 body_filter 처리
   - 샘플링 및 배치 처리 옵션
2. **단계적 배포 전략** (Canary Deployment)
3. **포괄적 테스트 시나리오** 실행

### 📁 관련 문서
- **Part 1**: 개요 및 Phase 1-2 (현재 문서)
- **Part 2**: [Phase 3-4 구현 및 테스트](./kong-realtime-monitoring-improvement-plan-02-implementation.md)
- **Part 3**: [Phase 5 및 배포 전략](./kong-realtime-monitoring-improvement-plan-03-deployment.md)
- **Part 4**: [기술 상세 및 참고사항](./kong-realtime-monitoring-improvement-plan-04-technical.md)

---

## 📅 Phase 1: 사전 준비 및 문제점 분석 (Day 1)

### 🚨 중요 문제점 인식 (`05-CRITICAL-ISSUES-ANALYSIS.md` 기반)
**초기 접근법의 심각한 기술적 문제들을 반드시 해결해야 함**

#### 심각도: 높음 (Critical)
1. **Redis 연결 경쟁 조건 (Race Condition)**
   - 문제: handler.lua와 monitoring.lua가 동시에 Redis 연결 획득 시 데드락 가능
   - 영향: Kong 프로세스 행업, 서비스 중단
   - 해결: 기존 연결 재사용 메커니즘 구현

2. **body_filter 성능 문제**
   - 문제: `kong.response.get_raw_body()`가 전체 응답을 메모리에 버퍼링
   - 영향: 대용량 응답(>8MB) 처리 불가, OOM 위험
   - 해결: 청크 단위 처리 구현

3. **성능 영향 과소평가**
   - 문제: 실제 성능 영향 10-30% (문서의 1% 주장은 비현실적)
   - 영향: 프로덕션 SLA 위반 가능성
   - 해결: 샘플링, 배치 처리, Fire-and-forget 패턴

### 작업 목록
- [ ] 기존 Redis 연결 관리 로직 상세 분석 (경쟁 조건 파악)
- [ ] body_filter 현재 구현 방식 검토
- [ ] 실제 성능 영향 벤치마크 (baseline 측정)
- [ ] schema.lua 확장 가능성 검토

### 상세 작업

#### 1.1 위험 요소 분석
```bash
# Redis 연결 풀 현황 확인
docker exec -it redis-cache redis-cli client list | wc -l
docker exec -it redis-cache redis-cli config get maxclients

# 현재 body_filter 메모리 사용량 측정
docker stats kong-gateway --no-stream

# 기존 성능 baseline 측정
ab -n 100 -c 10 http://localhost:8000/analyze-claude
```

#### 1.2 개선 방안 검증
- **Redis 연결 재사용**: `masker_ngx_re.lua`의 기존 연결 풀 활용
- **청크 처리**: `kong.arg[1]`, `kong.arg[2]` 활용
- **플러그인 설정**: 환경변수 대신 schema 기반 동적 제어

### 완료 기준
- [ ] 모든 기술적 위험 요소 파악 및 해결방안 검증
- [ ] 성능 baseline 측정 완료
- [ ] 개선된 아키텍처 설계 완료

---

## 📅 Phase 2: Kong 플러그인 개선 구현 (Day 2-3)

### 🔧 개선된 구현 방식 (`06-IMPROVED-IMPLEMENTATION.md` 기반)

#### 주요 개선사항
1. **플러그인 설정 기반 제어** - 환경변수 대신 동적 설정
2. **Redis 연결 재사용** - 경쟁 조건 해결
3. **청크 단위 처리** - 대용량 응답 지원
4. **샘플링 및 배치 처리** - 성능 최적화
5. **환경별 로깅 차별화** - 보안 강화

### 작업 목록
- [ ] schema.lua 확장 (플러그인 설정 추가)
- [ ] monitoring.lua 개선 (연결 재사용, 샘플링, 배치)
- [ ] handler.lua 수정 (청크 처리, 설정 전달)
- [ ] 단위 테스트 작성 및 실행

### 상세 작업

#### 2.1 Schema 확장
```lua
-- kong/plugins/aws-masker/schema.lua에 추가
{
  enable_event_monitoring = { type = "boolean", default = false },
  event_sampling_rate = { type = "number", default = 1.0, between = {0.0, 1.0} },
  redis_event_channel = { type = "string", default = "kong:masking:events" },
  event_batch_size = { type = "integer", default = 1, between = {1, 100} },
  max_response_size = { type = "integer", default = 8388608 } -- 8MB
}
```

#### 2.2 Monitoring 모듈 개선
```lua
-- 핵심 개선 함수들
- monitoring.should_sample(rate) -- 샘플링 결정
- monitoring.publish_single_event(event, config, redis_conn) -- 단일 발행
- monitoring.buffer_event(event, config, redis_conn) -- 배치 버퍼링
- monitoring.flush_event_buffer(config, redis_conn) -- 배치 플러시

-- 기존 연결 재사용 패턴
local red = redis_conn or masker.acquire_redis_connection()
local need_release = not redis_conn
```

#### 2.3 Handler 개선
```lua
-- ACCESS phase
kong.ctx.plugin.start_time = ngx.now()
kong.ctx.plugin.config = conf  -- 설정 저장

-- BODY_FILTER phase (청크 처리)
local chunk = kong.arg[1]
local eof = kong.arg[2]

if not eof then
  -- 청크 누적 및 크기 제한 확인
  kong.ctx.plugin.body_buffer = (kong.ctx.plugin.body_buffer or "") .. chunk
  if string.len(kong.ctx.plugin.body_buffer) > conf.max_response_size then
    kong.ctx.plugin.skip_unmask = true
  end
  return
end
```

### 코드 변경 검증
```bash
# Lua 문법 검사
luac -p kong/plugins/aws-masker/monitoring.lua
luac -p kong/plugins/aws-masker/handler.lua

# 테스트 실행 (CLAUDE.md 준수)
cd tests/
./comprehensive-flow-test.sh
./comprehensive-security-test.sh
```

### 완료 기준
- [ ] 모든 critical 이슈 해결 구현
- [ ] 코드 리뷰 완료
- [ ] 단위 테스트 통과
- [ ] test-report 생성 확인

---

## 다음 문서
- **Part 2**: [Phase 3-4 구현 및 테스트](./kong-realtime-monitoring-improvement-plan-02-implementation.md)로 계속