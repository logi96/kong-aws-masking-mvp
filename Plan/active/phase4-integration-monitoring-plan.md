# Phase 4: 통합 테스트 및 모니터링 실행 계획

**작성일**: 2025-07-22
**목표**: Kong 환경에서 실제 통합 테스트 및 모니터링 시스템 구축
**보안 우선순위**: 🔴 최고 (실제 운영 환경 준비)

## 🎯 Phase 4 목표
1. Kong 환경에서 47개 통합 패턴 실제 테스트
2. 성능 벤치마크 달성 (10KB < 100ms)
3. 실시간 모니터링 시스템 구축
4. 프로덕션 준비 상태 100% 달성

## 📋 3단계 실행 계획

### 1단계: Kong 통합 테스트 환경 구축 (Day 1-2)

#### 1.1 Docker 환경 검증
```bash
# Docker 환경 상태 확인
docker-compose ps
docker-compose logs kong

# Kong 플러그인 디렉토리 마운트 확인
docker-compose exec kong ls -la /usr/local/share/lua/5.1/kong/plugins/aws-masker/
```

#### 1.2 통합 플러그인 로드
**파일**: `/tests/kong-integration-loader.lua`
```lua
-- Kong 환경에서 통합 패턴 로드 및 검증
local text_masker = require "kong.plugins.aws-masker.text_masker_v2"
local pattern_integrator = require "kong.plugins.aws-masker.pattern_integrator"

-- 기존 패턴 로드
local original_patterns = text_masker.get_patterns()

-- 패턴 통합
local integrated_patterns, conflicts = pattern_integrator.integrate_patterns(original_patterns)

-- 통합 결과 검증
assert(#integrated_patterns == 47, "Expected 47 patterns, got " .. #integrated_patterns)
assert(#conflicts == 0, "Pattern conflicts detected")

print("✅ Kong 통합 성공: " .. #integrated_patterns .. "개 패턴")
```

#### 1.3 실제 API 테스트
**파일**: `/tests/kong-api-test.sh`
```bash
#!/bin/bash
# 실제 Kong API를 통한 마스킹 테스트

# 테스트 데이터 준비
cat > test-claude-request.json << EOF
{
  "model": "claude-3-sonnet-20240229",
  "system": "Analyzing AWS account 123456789012 resources",
  "messages": [
    {
      "role": "user",
      "content": "Check these resources:\nEC2: i-1234567890abcdef0\nKMS: arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012\nLambda: arn:aws:lambda:us-east-1:123456789012:function:myFunction\nSecrets: arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db/password-AbCdEf"
    }
  ]
}
EOF

# Kong을 통해 요청
curl -X POST http://localhost:8000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: test-key" \
  -d @test-claude-request.json \
  -o response.json

# 마스킹 검증
echo "마스킹 검증:"
grep -E "(123456789012|i-[0-9a-f]+|myFunction|password)" response.json && echo "❌ 마스킹 실패!" || echo "✅ 마스킹 성공!"
```

### 2단계: 성능 벤치마크 및 최적화 (Day 3-4)

#### 2.1 성능 테스트 스위트
**파일**: `/tests/performance-benchmark.lua`
```lua
-- 성능 벤치마크 테스트
local socket = require "socket"

local function benchmark_masking(text_size_kb, pattern_count)
    -- 테스트 텍스트 생성
    local test_text = generate_test_text(text_size_kb, pattern_count)
    
    -- 마스킹 시작
    local start_time = socket.gettime()
    local masked_text, context = text_masker.mask_text(test_text)
    local end_time = socket.gettime()
    
    -- 결과 계산
    local elapsed_ms = (end_time - start_time) * 1000
    local throughput_mb_s = (text_size_kb / 1024) / (elapsed_ms / 1000)
    
    return {
        size_kb = text_size_kb,
        patterns_found = context.masked_count,
        elapsed_ms = elapsed_ms,
        throughput_mb_s = throughput_mb_s,
        passed = elapsed_ms < 100  -- 목표: 10KB < 100ms
    }
end

-- 다양한 크기로 테스트
local test_sizes = {1, 5, 10, 20, 50}
local results = {}

for _, size in ipairs(test_sizes) do
    local result = benchmark_masking(size, 50)  -- 50개 패턴 포함
    table.insert(results, result)
    
    print(string.format("%dKB: %.2fms (%.2fMB/s) - %s",
        size, result.elapsed_ms, result.throughput_mb_s,
        result.passed and "✅ PASS" or "❌ FAIL"))
end
```

#### 2.2 메모리 프로파일링
**파일**: `/tests/memory-profile.lua`
```lua
-- 메모리 사용량 모니터링
local function profile_memory_usage()
    collectgarbage("collect")
    local before = collectgarbage("count")
    
    -- 1000번 마스킹 작업 수행
    for i = 1, 1000 do
        local test_text = generate_random_aws_text()
        local masked, _ = text_masker.mask_text(test_text)
        
        if i % 100 == 0 then
            collectgarbage("collect")
            local current = collectgarbage("count")
            print(string.format("Iteration %d: %.2f KB", i, current))
        end
    end
    
    collectgarbage("collect")
    local after = collectgarbage("count")
    
    print(string.format("Memory usage: %.2f KB (증가: %.2f KB)",
        after, after - before))
    
    return after - before < 10240  -- 10MB 미만 증가
end
```

#### 2.3 최적화 구현
**파일**: `/kong/plugins/aws-masker/performance_optimizer.lua`
```lua
-- 성능 최적화 모듈
local optimizer = {}

-- 패턴 캐싱
local pattern_cache = {}

-- 컴파일된 패턴 캐시
function optimizer.compile_patterns(patterns)
    for _, pattern in ipairs(patterns) do
        if not pattern_cache[pattern.name] then
            pattern_cache[pattern.name] = {
                regex = pattern.pattern,
                compiled = true,
                hit_count = 0
            }
        end
    end
end

-- 자주 사용되는 패턴 우선순위 조정
function optimizer.adaptive_priority()
    local sorted_patterns = {}
    
    for name, cache in pairs(pattern_cache) do
        table.insert(sorted_patterns, {
            name = name,
            hit_count = cache.hit_count
        })
    end
    
    -- 히트 수로 정렬
    table.sort(sorted_patterns, function(a, b)
        return a.hit_count > b.hit_count
    end)
    
    return sorted_patterns
end

return optimizer
```

### 3단계: 모니터링 시스템 구축 (Day 5-6)

#### 3.1 실시간 모니터링 대시보드
**파일**: `/kong/plugins/aws-masker/monitoring.lua`
```lua
-- 모니터링 모듈
local monitoring = {
    stats = {
        total_requests = 0,
        total_masked = 0,
        pattern_hits = {},
        performance = {
            avg_latency_ms = 0,
            max_latency_ms = 0,
            min_latency_ms = 999999
        },
        errors = {
            total = 0,
            by_type = {}
        }
    }
}

-- 메트릭 수집
function monitoring:record_request(context)
    self.stats.total_requests = self.stats.total_requests + 1
    self.stats.total_masked = self.stats.total_masked + (context.masked_count or 0)
    
    -- 패턴별 통계
    if context.pattern_stats then
        for pattern, count in pairs(context.pattern_stats) do
            self.stats.pattern_hits[pattern] = 
                (self.stats.pattern_hits[pattern] or 0) + count
        end
    end
    
    -- 성능 통계
    if context.elapsed_ms then
        local current_avg = self.stats.performance.avg_latency_ms
        local total_requests = self.stats.total_requests
        
        self.stats.performance.avg_latency_ms = 
            (current_avg * (total_requests - 1) + context.elapsed_ms) / total_requests
        
        self.stats.performance.max_latency_ms = 
            math.max(self.stats.performance.max_latency_ms, context.elapsed_ms)
        
        self.stats.performance.min_latency_ms = 
            math.min(self.stats.performance.min_latency_ms, context.elapsed_ms)
    end
end

-- Critical 패턴 모니터링
function monitoring:check_critical_patterns()
    local critical_patterns = {"iam_access_key", "iam_secret_key", "kms_key_arn", "secrets_manager_arn"}
    local alerts = {}
    
    for _, pattern in ipairs(critical_patterns) do
        local hits = self.stats.pattern_hits[pattern] or 0
        if hits > 0 then
            table.insert(alerts, {
                pattern = pattern,
                count = hits,
                severity = "HIGH",
                message = string.format("Critical pattern '%s' matched %d times", pattern, hits)
            })
        end
    end
    
    return alerts
end

-- 상태 리포트 생성
function monitoring:generate_report()
    return {
        timestamp = os.date("%Y-%m-%dT%H:%M:%SZ"),
        summary = {
            total_requests = self.stats.total_requests,
            total_masked = self.stats.total_masked,
            masking_rate = self.stats.total_masked / math.max(1, self.stats.total_requests)
        },
        performance = self.stats.performance,
        top_patterns = self:get_top_patterns(10),
        critical_alerts = self:check_critical_patterns(),
        health_status = self:calculate_health_status()
    }
end

-- 건강 상태 계산
function monitoring:calculate_health_status()
    local status = "HEALTHY"
    local issues = {}
    
    -- 성능 체크
    if self.stats.performance.avg_latency_ms > 100 then
        status = "DEGRADED"
        table.insert(issues, "Average latency exceeds 100ms")
    end
    
    -- 에러율 체크
    local error_rate = self.stats.errors.total / math.max(1, self.stats.total_requests)
    if error_rate > 0.05 then  -- 5% 이상
        status = "UNHEALTHY"
        table.insert(issues, string.format("Error rate: %.2f%%", error_rate * 100))
    end
    
    return {
        status = status,
        issues = issues
    }
end

return monitoring
```

#### 3.2 로깅 및 알림 시스템
**파일**: `/kong/plugins/aws-masker/alerting.lua`
```lua
-- 알림 시스템
local alerting = {
    thresholds = {
        latency_ms = 100,
        error_rate = 0.05,
        memory_mb = 100
    }
}

function alerting:check_thresholds(metrics)
    local alerts = {}
    
    -- 레이턴시 체크
    if metrics.avg_latency_ms > self.thresholds.latency_ms then
        table.insert(alerts, {
            type = "PERFORMANCE",
            severity = "WARNING",
            message = string.format("Average latency %.2fms exceeds threshold %dms",
                metrics.avg_latency_ms, self.thresholds.latency_ms)
        })
    end
    
    -- Critical 패턴 노출 체크
    for _, alert in ipairs(metrics.critical_alerts or {}) do
        table.insert(alerts, {
            type = "SECURITY",
            severity = "CRITICAL",
            message = alert.message
        })
    end
    
    return alerts
end

-- 알림 전송
function alerting:send_alerts(alerts)
    for _, alert in ipairs(alerts) do
        kong.log.err(string.format("[%s] %s: %s",
            alert.severity, alert.type, alert.message))
        
        -- Critical 알림은 즉시 조치
        if alert.severity == "CRITICAL" then
            self:trigger_emergency_response(alert)
        end
    end
end

-- 긴급 대응
function alerting:trigger_emergency_response(alert)
    if alert.type == "SECURITY" then
        kong.log.crit("SECURITY BREACH DETECTED - Initiating emergency protocol")
        -- 필요시 요청 차단 또는 격리 모드 전환
    end
end

return alerting
```

#### 3.3 통합 모니터링 테스트
**파일**: `/tests/monitoring-integration-test.sh`
```bash
#!/bin/bash
# 모니터링 시스템 통합 테스트

set -euo pipefail

echo "==========================================="
echo "🔍 Phase 4 모니터링 시스템 테스트"
echo "==========================================="

# 1. 부하 테스트 준비
echo "[1/4] 부하 테스트 데이터 생성"
for i in {1..100}; do
    cat > test-request-$i.json << EOF
{
    "model": "claude-3-sonnet",
    "messages": [{
        "role": "user",
        "content": "Analyze EC2 i-$(openssl rand -hex 8) in subnet-$(openssl rand -hex 8) with KMS arn:aws:kms:us-east-1:$(printf '%012d' $RANDOM):key/$(uuidgen)"
    }]
}
EOF
done

# 2. 동시 요청 발송
echo "[2/4] 동시 요청 테스트 (100 requests)"
for i in {1..100}; do
    curl -X POST http://localhost:8000/v1/messages \
        -H "Content-Type: application/json" \
        -d @test-request-$i.json \
        -o response-$i.json \
        -s &
    
    # 10개씩 배치 처리
    if [ $((i % 10)) -eq 0 ]; then
        wait
        echo "  처리 완료: $i/100"
    fi
done
wait

# 3. 모니터링 메트릭 확인
echo "[3/4] 모니터링 메트릭 수집"
curl -s http://localhost:8001/aws-masker/stats | jq .

# 4. 검증
echo "[4/4] 결과 검증"

# 마스킹 검증
MASKED_COUNT=$(grep -l "EC2_[0-9]\+" response-*.json | wc -l)
echo "마스킹된 응답: $MASKED_COUNT/100"

# 성능 검증
AVG_LATENCY=$(curl -s http://localhost:8001/aws-masker/stats | jq '.performance.avg_latency_ms')
echo "평균 레이턴시: ${AVG_LATENCY}ms"

# Critical 패턴 검증
CRITICAL_ALERTS=$(curl -s http://localhost:8001/aws-masker/stats | jq '.critical_alerts | length')
echo "Critical 패턴 감지: $CRITICAL_ALERTS"

# 최종 결과
if [ "$MASKED_COUNT" -eq 100 ] && [ $(echo "$AVG_LATENCY < 100" | bc) -eq 1 ]; then
    echo "✅ 모니터링 테스트 통과!"
    exit 0
else
    echo "❌ 모니터링 테스트 실패"
    exit 1
fi
```

## 🔒 보안 검증 체크리스트

### 각 단계별 보안 확인
- [ ] 1단계: Kong 환경 격리 확인
- [ ] 1단계: 테스트 데이터에 실제 자격 증명 없음 확인
- [ ] 2단계: 성능 테스트 중 메모리 누수 없음
- [ ] 2단계: 패턴 캐시 보안 검증
- [ ] 3단계: 모니터링 데이터 암호화
- [ ] 3단계: Critical 알림 즉시 대응 체계

## 📊 성공 기준

### 기술적 목표
- ✅ 47개 패턴 모두 Kong에서 정상 작동
- ✅ 10KB 텍스트 처리 < 100ms
- ✅ 메모리 사용 < 10MB/request
- ✅ 에러율 < 1%
- ✅ Critical 패턴 100% 감지

### 운영 목표
- ✅ 실시간 모니터링 대시보드 구동
- ✅ 자동 알림 시스템 작동
- ✅ 성능 저하 시 자동 최적화
- ✅ 보안 위협 즉시 대응

## 🚀 실행 순서

### Day 1-2: Kong 통합
1. Docker 환경 검증
2. 통합 플러그인 로드
3. API 테스트 실행

### Day 3-4: 성능 최적화
1. 벤치마크 테스트
2. 메모리 프로파일링
3. 최적화 적용

### Day 5-6: 모니터링 구축
1. 메트릭 수집 구현
2. 알림 시스템 구축
3. 통합 테스트

## 📋 체크포인트

### 1단계 완료 조건
- [ ] 47개 패턴 Kong 로드 성공
- [ ] 실제 API 요청 마스킹 확인
- [ ] 에러 없이 100회 연속 성공

### 2단계 완료 조건
- [ ] 10KB < 100ms 달성
- [ ] 메모리 증가 < 10MB
- [ ] 최적화 후 20% 성능 향상

### 3단계 완료 조건
- [ ] 모든 메트릭 수집 확인
- [ ] Critical 알림 작동 확인
- [ ] 100회 부하 테스트 통과

---

**작성자**: Kong AWS Masking Security Team
**검토자**: Security Lead
**승인**: Pending