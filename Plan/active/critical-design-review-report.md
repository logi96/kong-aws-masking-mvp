# Kong AWS Masking System - Critical Design Review Report

## 🔒 시스템 중요도 (CRITICALITY)
**Level: CRITICAL** - AWS 인프라 정보 노출 시 심각한 보안 위반 발생

## 📋 설계 문서 심층 분석

### 1. 현재 설계 구조 분석

#### 1.1 데이터 플로우 검증
```
Backend API → Kong Gateway → Claude API
     ↓              ↓              ↓
AWS 데이터 수집   마스킹 처리    AI 분석
```

**✅ 검증 결과**: 
- 데이터 흐름이 명확하고 단방향
- Kong이 중간에서 모든 트래픽 검사 가능
- 마스킹 실패 시 요청 차단 메커니즘 필요

#### 1.2 마스킹 대상 확인
```json
{
  "messages": [{
    "role": "user", 
    "content": "텍스트 형태의 AWS 리소스 정보..."  // ← 실제 마스킹 대상
  }]
}
```

**✅ 핵심 발견**: 
- JSON 구조가 아닌 텍스트 필드 마스킹
- 복합 패턴이 한 문자열에 혼재
- 순서와 위치가 가변적

### 2. 위험 요소 분석 (RISK ANALYSIS)

#### 2.1 보안 위험 (Security Risks)
| 위험 요소 | 영향도 | 발생 가능성 | 대응 방안 |
|-----------|--------|-------------|-----------|
| **패턴 누락 (False Negative)** | 치명적 | 중간 | 포괄적 패턴 + 화이트리스트 검증 |
| **잘못된 언마스킹** | 치명적 | 낮음 | 고유 ID + 암호화된 매핑 |
| **매핑 데이터 유출** | 높음 | 낮음 | 메모리 내 저장 + TTL |
| **패턴 우회 시도** | 높음 | 중간 | 다층 검증 + 로깅 |

#### 2.2 정확성 위험 (Accuracy Risks)
| 위험 요소 | 영향도 | 발생 가능성 | 대응 방안 |
|-----------|--------|-------------|-----------|
| **과도한 마스킹 (False Positive)** | 중간 | 높음 | 컨텍스트 검증 + 우선순위 |
| **패턴 충돌** | 높음 | 중간 | 구체적→일반적 순서 처리 |
| **부분 매칭 오류** | 중간 | 중간 | 완전 매칭 + 경계 검증 |
| **인코딩 문제** | 낮음 | 낮음 | UTF-8 정규화 |

#### 2.3 성능/안정성 위험 (Performance/Stability Risks)
| 위험 요소 | 영향도 | 발생 가능성 | 대응 방안 |
|-----------|--------|-------------|-----------|
| **메모리 누수** | 높음 | 중간 | TTL + 주기적 정리 |
| **처리 지연** | 중간 | 낮음 | 패턴 캐싱 + 최적화 |
| **Kong 충돌** | 치명적 | 매우 낮음 | 에러 격리 + 우회 모드 |
| **대용량 텍스트** | 중간 | 중간 | 스트리밍 처리 |

### 3. 참조해야 할 핵심 설계 요소

#### 3.1 필수 구현 사항 (MUST HAVE)
```lua
-- 1. 우선순위 기반 패턴 매칭 (updated-aws-masking-expansion-plan.md)
local aws_patterns = {
    {name = "aws_account_in_arn", pattern = "...", priority = 1},  -- 가장 구체적
    {name = "ec2_instance_id", pattern = "...", priority = 3},
    {name = "rds_general", pattern = "...", priority = 16}          -- 가장 일반적
}

-- 2. 안전한 매핑 저장소 (kong-plugin-modification-plan.md)
local mapping_store = {
    forward = {},   -- 원본 → 마스킹 (TTL 적용)
    reverse = {},   -- 마스킹 → 원본 (암호화 고려)
    counters = {},  -- 패턴별 카운터
    timestamps = {} -- TTL 관리용
}

-- 3. 복합 패턴 테스트 (enhanced-pattern-test-plan.md)
local test_cases = {
    realistic_aws_analysis = {
        input = "EC2 i-123... in vpc-456... accessing s3://bucket...",
        expected_patterns = {ec2 = 1, vpc = 1, s3 = 1}
    }
}
```

#### 3.2 검증 체크포인트 (VALIDATION CHECKPOINTS)
```lua
-- 1. 마스킹 전 검증
function pre_masking_validation(text)
    -- 텍스트 크기 제한 (10MB)
    if #text > 10 * 1024 * 1024 then
        return false, "Text too large"
    end
    
    -- 의심스러운 패턴 감지
    if text:match("PRIVATE_IP_%d+") then
        return false, "Already masked content detected"
    end
    
    return true
end

-- 2. 마스킹 후 검증
function post_masking_validation(original, masked)
    -- 최소 변경 확인
    if original == masked and contains_aws_patterns(original) then
        return false, "No masking applied despite AWS patterns"
    end
    
    -- 과도한 마스킹 확인
    local change_ratio = calculate_change_ratio(original, masked)
    if change_ratio > 0.5 then  -- 50% 이상 변경
        return false, "Excessive masking detected"
    end
    
    return true
end

-- 3. 언마스킹 후 검증
function roundtrip_validation(original, unmasked)
    if original ~= unmasked then
        return false, "Roundtrip validation failed"
    end
    return true
end
```

### 4. 안전한 구현 로드맵 (SAFE IMPLEMENTATION ROADMAP)

#### Phase 0: 기반 준비 (1-2일)
- [ ] **위험 분석 문서화**: 모든 팀원 공유
- [ ] **테스트 환경 격리**: 프로덕션 영향 차단
- [ ] **롤백 계획 수립**: 즉시 복원 가능

#### Phase 1: 테스트 프레임워크 구축 (3-5일)
```bash
# 1. 복합 패턴 테스트 구현
lua tests/run-enhanced-pattern-tests.lua

# 2. 부하 테스트 준비
lua tests/load-test-masking.lua --concurrent=100 --duration=300

# 3. 보안 테스트 케이스
lua tests/security-bypass-tests.lua
```

**참조**: `enhanced-pattern-test-plan.md`의 복합 패턴 테스트 케이스

#### Phase 2: 핵심 마스킹 엔진 구현 (5-7일)
```lua
-- 1. 최소 기능 구현 (MVP)
local critical_patterns = {
    "aws_account_in_arn",  -- 가장 중요
    "ec2_instance_id",
    "private_ip_10",
    "iam_access_key"       -- AKIA로 시작하는 키
}

-- 2. 실패 시 안전 모드
function safe_mask_with_fallback(text)
    local success, masked = pcall(mask_text, text)
    if not success then
        -- 마스킹 실패 시 요청 차단
        kong.log.err("Masking failed, blocking request", {error = masked})
        return nil, "MASKING_FAILED"
    end
    return masked
end
```

**참조**: `updated-aws-masking-expansion-plan.md`의 단순화된 텍스트 마스킹 엔진

#### Phase 3: 단계별 패턴 추가 (7-14일)
```lua
-- 각 패턴 그룹별 독립 테스트 후 추가
local pattern_groups = {
    week1 = {"ec2", "private_ip", "account_id"},      -- 핵심 패턴
    week2 = {"vpc", "subnet", "security_group"},      -- 네트워크 패턴
    week3 = {"s3", "rds", "iam"},                    -- 서비스 패턴
    week4 = {"lambda", "ecs", "eks"}                  -- 추가 패턴
}
```

#### Phase 4: 통합 테스트 및 검증 (3-5일)
- [ ] **실제 AWS 데이터로 테스트**: 익명화된 프로덕션 샘플
- [ ] **Claude API 통합 테스트**: 실제 API 응답 검증
- [ ] **성능 벤치마크**: 목표 지표 달성 확인
- [ ] **보안 감사**: 외부 보안팀 검토

#### Phase 5: 단계적 배포 (5-7일)
```yaml
# 1. Canary 배포 (5% 트래픽)
deployment:
  canary:
    percentage: 5
    duration: 24h
    rollback_on_error: true

# 2. 점진적 증가
  stages:
    - {percentage: 10, duration: 24h}
    - {percentage: 25, duration: 48h}
    - {percentage: 50, duration: 48h}
    - {percentage: 100, duration: stable}
```

### 5. 모니터링 및 알림 체계

#### 5.1 실시간 모니터링 지표
```lua
-- Kong 플러그인 내 메트릭
local metrics = {
    masking_success_rate = prometheus:gauge("aws_masking_success_rate"),
    masking_latency = prometheus:histogram("aws_masking_latency_ms"),
    pattern_matches = prometheus:counter("aws_pattern_matches"),
    masking_errors = prometheus:counter("aws_masking_errors")
}
```

#### 5.2 알림 임계값
| 지표 | 경고 임계값 | 치명적 임계값 | 대응 |
|------|------------|--------------|------|
| 성공률 | < 99.9% | < 99% | 자동 롤백 |
| 지연시간 | > 50ms | > 100ms | 스케일 아웃 |
| 에러율 | > 0.1% | > 1% | 우회 모드 |
| 메모리 | > 80% | > 95% | 정리 실행 |

### 6. 비상 대응 계획 (EMERGENCY RESPONSE)

#### 6.1 즉시 대응 시나리오
```lua
-- 1. 마스킹 완전 실패 시
function emergency_bypass()
    -- 옵션 1: 모든 요청 차단
    return kong.response.exit(503, {
        message = "Service temporarily unavailable for security maintenance"
    })
    
    -- 옵션 2: 수동 검토 큐로 전환
    -- redirect_to_manual_review_queue()
end

-- 2. 성능 저하 시
function performance_degradation_handler()
    -- 복잡한 패턴 임시 비활성화
    disable_patterns({"rds_general", "s3_general"})
    
    -- 캐시 크기 증가
    increase_cache_size(2.0)  -- 2배 증가
end
```

#### 6.2 롤백 절차
```bash
#!/bin/bash
# 즉시 롤백 스크립트
kubectl rollout undo deployment/kong-gateway
kubectl scale deployment/kong-gateway --replicas=10
kubectl exec -it kong-pod -- kong reload
```

### 7. 최종 검증 체크리스트

#### 배포 전 필수 확인사항
- [ ] 모든 패턴 테스트 95% 이상 정확도
- [ ] 10KB 텍스트 100ms 이내 처리
- [ ] 메모리 누수 테스트 72시간 통과
- [ ] 보안팀 승인 완료
- [ ] 롤백 계획 검증 완료
- [ ] 모니터링 대시보드 준비
- [ ] 비상 연락망 확인

### 8. 결론 및 권고사항

**핵심 원칙**:
1. **보안 우선**: 의심스러우면 차단
2. **단계적 접근**: 검증된 것만 배포
3. **투명한 모니터링**: 모든 지표 실시간 추적
4. **빠른 복원**: 30초 내 롤백 가능

**다음 단계**:
1. 이 검토 보고서를 모든 이해관계자와 공유
2. Phase 0부터 순차적으로 진행
3. 각 Phase 완료 시 체크포인트 검토
4. 문제 발생 시 즉시 중단 및 재평가

이 시스템은 **AWS 보안의 최전선**입니다. 
**완벽한 구현**만이 허용됩니다.