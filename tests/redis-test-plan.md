# Redis 전환 테스트 계획서

## 테스트 목표
Redis 전환 후에도 기존 기능이 100% 동작하며, 새로운 Redis 기능이 올바르게 작동함을 검증

## 테스트 원칙
1. **기존 호환성**: 모든 기존 테스트 100% 통과
2. **Redis 특화**: Redis 전용 기능 검증
3. **Fallback 검증**: Redis 장애 시 메모리 모드 동작
4. **성능 목표**: 전체 응답시간 5초 이내 유지

## 1. 단위 테스트 계획

### 1.1 Redis 연결 관리 테스트
#### 테스트 대상
- `masker_ngx_re.lua`의 Redis 연결 함수들

#### 테스트 케이스
```bash
# 연결 성공 테스트
test_redis_connection_success() {
  # Redis가 실행 중일 때
  # 연결이 성공하고 ping 응답을 받아야 함
}

# 연결 실패 테스트  
test_redis_connection_failure() {
  # Redis가 중단된 상태에서
  # 메모리 모드로 자동 전환되어야 함
}

# Connection Pool 테스트
test_redis_connection_pool() {
  # 여러 요청에서 연결이 재사용되어야 함
  # Pool 크기 제한이 올바르게 동작해야 함
}
```

### 1.2 마스킹/언마스킹 정확성 테스트
#### 테스트 대상
- Redis 기반 마스킹 로직
- Redis 기반 언마스킹 로직

#### 테스트 케이스
```bash
# 기본 마스킹 테스트
test_redis_masking_accuracy() {
  # 동일한 AWS 리소스는 동일한 마스킹 ID 반환
  # 다른 AWS 리소스는 다른 마스킹 ID 반환
  # 카운터가 올바르게 증가
}

# 언마스킹 정확성 테스트
test_redis_unmasking_accuracy() {
  # 마스킹된 ID가 원본 값으로 정확히 복원
  # 여러 마스킹 ID가 동시에 올바르게 복원
}

# TTL 테스트
test_redis_ttl_behavior() {
  # 설정된 TTL 후 데이터가 자동 삭제
  # TTL 내에서는 데이터 유지
}
```

### 1.3 Fallback 메커니즘 테스트
#### 테스트 대상
- Redis 장애 시 메모리 모드 전환

#### 테스트 케이스
```bash
# Redis 중단 시 Fallback 테스트
test_redis_fallback_on_failure() {
  # Redis 중단 → 메모리 모드로 전환
  # 기능은 계속 동작해야 함
  # 경고 로그가 기록되어야 함
}

# Redis 복구 시 재연결 테스트
test_redis_reconnect_on_recovery() {
  # Redis 복구 후 다음 요청에서 재연결
  # 데이터 일관성 유지
}
```

## 2. 통합 테스트 계획

### 2.1 기존 테스트 호환성 검증
#### 목표
현재 100% 통과하는 모든 테스트가 Redis 전환 후에도 동일하게 통과

#### 검증 대상 테스트
```bash
# 기존 핵심 테스트들
1. ngx-re-final-test.sh - ngx.re 구현 검증
2. comprehensive-security-test.sh - 보안 검증
3. 50개 AWS 패턴 테스트
4. Echo 테스트
5. 성능 테스트
```

#### 성공 기준
- 모든 기존 테스트 100% 통과
- 응답시간 변화 +5ms 이내
- 보안 수준 동일 유지

### 2.2 Redis 특화 기능 테스트
#### 테스트 시나리오

**시나리오 1: 멀티 워커 일관성**
```bash
test_multi_worker_consistency() {
  # 동일한 AWS 리소스를 여러 워커에서 처리
  # 모든 워커가 동일한 마스킹 ID 반환해야 함
  # 카운터 동기화 확인
}
```

**시나리오 2: 재시작 후 데이터 영속성**
```bash
test_restart_persistence() {
  # 1. AWS 리소스 마스킹 → 마스킹 ID 저장
  # 2. Kong 재시작
  # 3. 동일 AWS 리소스 요청 → 동일 마스킹 ID 반환
  # 4. 언마스킹 → 원본 값 정확히 복원
}
```

**시나리오 3: 7일 TTL 검증**
```bash
test_seven_day_ttl() {
  # TTL 설정이 7일(604800초)로 올바르게 적용
  # Redis에서 EXPIRE 명령으로 확인
  # 시간 경과 시뮬레이션으로 자동 삭제 확인
}
```

## 3. 성능 테스트 계획

### 3.1 응답시간 벤치마크
#### 측정 항목
```bash
# 현재 메모리 기반 (기준)
- 마스킹 처리: ~0.1ms
- 언마스킹 처리: ~0.1ms  
- 전체 요청: ~100ms

# Redis 기반 (목표)
- 마스킹 처리: 1-3ms (30배 증가 허용)
- 언마스킹 처리: 2-5ms (50배 증가 허용)
- 전체 요청: ~110ms (10% 증가 허용)
```

#### 테스트 방법
```bash
test_performance_comparison() {
  # 동일한 테스트를 메모리/Redis 모드에서 각각 실행
  # 100회 반복 측정으로 평균값 계산
  # 95th percentile 응답시간 확인
}
```

### 3.2 부하 테스트
#### 테스트 시나리오
```bash
test_concurrent_load() {
  # 동시 요청 50개로 부하 테스트
  # Connection pool 효율성 확인
  # 메모리 사용량 모니터링
}

test_sustained_load() {
  # 10분간 지속적 요청으로 안정성 확인
  # Redis 메모리 누수 없음 확인
  # 성능 저하 없음 확인
}
```

## 4. 장애 시나리오 테스트

### 4.1 Redis 장애 테스트
#### 시나리오
```bash
test_redis_failure_scenarios() {
  # 시나리오 1: Redis 프로세스 중단
  # 시나리오 2: Redis 네트워크 연결 실패
  # 시나리오 3: Redis 메모리 부족
  # 시나리오 4: Redis 타임아웃 발생
}
```

#### 검증 항목
- 서비스 중단 없이 메모리 모드로 전환
- 적절한 에러 로그 기록
- 성능 저하 최소화

### 4.2 복구 시나리오 테스트
#### 시나리오
```bash
test_redis_recovery_scenarios() {
  # 1. Redis 장애 → 메모리 모드 전환
  # 2. Redis 복구
  # 3. 다음 요청에서 Redis 재연결
  # 4. 정상 동작 확인
}
```

## 5. 테스트 실행 스크립트

### 5.1 전체 테스트 스위트
```bash
#!/bin/bash
# tests/redis-comprehensive-test.sh

echo "========================================="
echo "     Redis 전환 종합 테스트 스위트"
echo "========================================="

# Phase 1: 환경 준비
setup_test_environment() {
  echo "1. 테스트 환경 준비 중..."
  docker-compose up -d
  sleep 30
  
  # Redis 상태 확인
  docker exec redis-cache redis-cli ping || exit 1
  echo "   ✅ Redis 준비 완료"
  
  # Kong 상태 확인
  curl -f http://localhost:8001/status || exit 1
  echo "   ✅ Kong 준비 완료"
}

# Phase 2: 기존 테스트 호환성 검증
test_backward_compatibility() {
  echo "2. 기존 테스트 호환성 검증 중..."
  
  # 기존 핵심 테스트들 실행
  ./ngx-re-final-test.sh || exit 1
  echo "   ✅ ngx.re 테스트 통과"
  
  ./comprehensive-security-test.sh || exit 1  
  echo "   ✅ 보안 테스트 통과"
}

# Phase 3: Redis 특화 테스트
test_redis_specific_features() {
  echo "3. Redis 특화 기능 테스트 중..."
  
  test_persistence_after_restart
  test_multi_worker_consistency
  test_ttl_behavior
  
  echo "   ✅ Redis 기능 테스트 통과"
}

# Phase 4: 성능 테스트
test_performance_impact() {
  echo "4. 성능 영향 측정 중..."
  
  measure_response_times
  run_load_test
  
  echo "   ✅ 성능 테스트 완료"
}

# Phase 5: 장애 시나리오 테스트
test_failure_scenarios() {
  echo "5. 장애 시나리오 테스트 중..."
  
  test_redis_failure_fallback
  test_redis_recovery
  
  echo "   ✅ 장애 시나리오 테스트 완료"
}

# 전체 테스트 실행
main() {
  setup_test_environment
  test_backward_compatibility
  test_redis_specific_features  
  test_performance_impact
  test_failure_scenarios
  
  echo "========================================="
  echo "     🎉 모든 테스트 성공적으로 완료!"
  echo "========================================="
}

main "$@"
```

### 5.2 개별 테스트 스크립트들

#### Redis 연결 테스트
```bash
#!/bin/bash
# tests/redis-connection-test.sh

test_redis_connection() {
  echo "Redis 연결 테스트 실행 중..."
  
  # 연결 성공 테스트
  response=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d '{"model": "claude-3-5-sonnet-20241022", "messages": [{"role": "user", "content": "i-1234567890abcdef0"}], "max_tokens": 50}')
    
  if echo "$response" | grep -q "EC2_"; then
    echo "✅ Redis 연결 및 마스킹 성공"
  else
    echo "❌ Redis 연결 또는 마스킹 실패"
    exit 1
  fi
}
```

#### 데이터 영속성 테스트
```bash
#!/bin/bash
# tests/redis-persistence-test.sh

test_data_persistence() {
  echo "데이터 영속성 테스트 실행 중..."
  
  # 1단계: 마스킹 수행 및 결과 저장
  response1=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d '{"model": "claude-3-5-sonnet-20241022", "messages": [{"role": "user", "content": "i-persistence-test-12345"}], "max_tokens": 50}')
    
  masked_id=$(echo "$response1" | grep -o 'EC2_[0-9]+' | head -1)
  
  # 2단계: Kong 재시작
  echo "Kong 재시작 중..."
  docker-compose restart kong
  sleep 30
  
  # 3단계: 동일한 요청으로 일관성 확인
  response2=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d '{"model": "claude-3-5-sonnet-20241022", "messages": [{"role": "user", "content": "i-persistence-test-12345"}], "max_tokens": 50}')
    
  masked_id2=$(echo "$response2" | grep -o 'EC2_[0-9]+' | head -1)
  
  if [[ "$masked_id" == "$masked_id2" ]]; then
    echo "✅ 데이터 영속성 확인: $masked_id"
  else
    echo "❌ 데이터 영속성 실패: $masked_id != $masked_id2"
    exit 1
  fi
}
```

## 6. 성공 기준

### 6.1 필수 통과 조건
- [ ] 모든 기존 테스트 100% 통과
- [ ] Redis 특화 기능 모든 테스트 통과
- [ ] 성능 목표 달성 (응답시간 5초 이내)
- [ ] Fallback 메커니즘 정상 동작
- [ ] 데이터 영속성 확인

### 6.2 성능 허용 기준
- 평균 응답시간 증가: 최대 10%
- 95th percentile 응답시간: 5초 이내
- 메모리 사용량 증가: 최대 50MB (Redis 제외)
- CPU 사용량 증가: 최대 5%

### 6.3 안정성 기준  
- Redis 장애 시 서비스 중단 없음
- 복구 시 자동 재연결
- 24시간 연속 운영 가능
- 메모리 누수 없음

## 7. 테스트 환경 설정

### 7.1 필수 환경 변수
```bash
# .env.test
ANTHROPIC_API_KEY=your-api-key
REDIS_HOST=redis
REDIS_PORT=6379
KONG_LOG_LEVEL=info
```

### 7.2 테스트 실행 순서
1. 환경 준비 (docker-compose up)
2. 기존 테스트 실행 (호환성 확인)  
3. Redis 테스트 실행 (새 기능 검증)
4. 성능 테스트 실행
5. 장애 시나리오 테스트
6. 결과 분석 및 보고서 작성

---

**작성일**: 2025년 7월 23일  
**작성자**: Claude Assistant  
**목표**: Redis 전환 100% 검증