# Kong AWS Masking - 테스트 스크립트 영향도 분석 및 수정 계획

**분석일시**: 2025년 7월 23일  
**대상**: Kong API Gateway 패턴 변경에 따른 모든 테스트 스크립트  
**총 테스트 파일**: 43개  
**긴급도**: CRITICAL - 누락 시 전체 테스트 시스템 마비

---

## 🚨 **핵심 문제: 테스트 스크립트 대대적 수정 필요**

### **현재 → 변경 후 URL 패턴 변화**

| 현재 (잘못된 구조) | 변경 후 (올바른 구조) | 영향도 |
|-------------------|---------------------|--------|
| `localhost:8000/analyze-claude` | **제거됨** (Kong 전용 라우트) | **HIGH** |
| `localhost:8000/analyze` | `localhost:3000/analyze` | **MEDIUM** |
| `localhost:8000/test-masking` | **제거됨** (테스트 전용 라우트) | **HIGH** |
| `localhost:8000/quick-mask-test` | **제거됨** (테스트 전용 라우트) | **HIGH** |
| `localhost:3000/analyze` | `localhost:3000/analyze` | **영향 없음** |
| `localhost:3000/test-masking` | `localhost:3000/test-masking` | **영향 없음** |

---

## 📊 **테스트 파일 영향도 분석**

### 🔴 **HIGH IMPACT: Kong 포트 직접 호출 (36개 파일)**

#### **localhost:8000 사용 테스트들**
```bash
# 영향 받는 파일들
/Users/tw.kim/Documents/AGA/test/Kong/tests/production-comprehensive-test.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/comprehensive-flow-test.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/quick-security-test.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/production-security-test.sh
# ... 총 36개 파일
```

**문제점**:
- Kong Gateway를 직접 호출하는 패턴 (올바른 API Gateway 패턴 무시)
- 대부분 `localhost:8000/analyze` 또는 `localhost:8000/analyze-claude` 호출
- API Gateway 변경 후 동작하지 않음

**수정 방향**:
- `localhost:8000/analyze` → `localhost:3000/analyze` (Backend API 직접 호출)
- `localhost:8000/analyze-claude` → **테스트 방식 완전 변경 필요**

### 🔴 **CRITICAL IMPACT: Kong 전용 라우트 사용 (30개 파일)**

#### **analyze-claude 사용 테스트들**
```bash
# 완전 재작성 필요한 파일들
/Users/tw.kim/Documents/AGA/test/Kong/tests/direct-kong-test.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/50-patterns-full-visualization.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/simple-flow-test.sh
# ... 총 30개 파일
```

**현재 테스트 패턴**:
```bash
# 현재 (완전히 잘못됨)
curl -X POST http://localhost:8000/analyze-claude \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model":"claude-3-5-sonnet-20241022","messages":[...]}'
```

**문제점**:
- Kong을 별도 서비스로 사용하는 잘못된 패턴
- API Gateway 변경 후 `/analyze-claude` 라우트 존재하지 않음
- 이런 직접적인 Kong 호출은 올바른 API Gateway 패턴에서 불가능

**수정 방향**:
- **테스트 목적 재정의 필요**: Kong의 마스킹 동작을 어떻게 검증할 것인가?
- **간접 검증 방식**: Backend API를 통해 마스킹 동작 확인
- **Kong 로그 분석**: Kong이 실제로 intercept했는지 로그로 확인

### 🟡 **MEDIUM IMPACT: Backend 포트 직접 호출 (6개 파일)**

#### **localhost:3000 사용 테스트들**
```bash
# 영향 없는 파일들 (올바른 패턴)
/Users/tw.kim/Documents/AGA/test/Kong/tests/individual-pattern-security-test.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/echo-flow-test.sh
/Users/tw.kim/Documents/AGA/test/Kong/tests/security-masking-test.sh
# ... 총 6개 파일
```

**현재 테스트 패턴**:
```bash
# 현재 (올바름 - 영향 없음)
curl -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}'
```

**영향도**: **없음** - 이미 올바른 패턴 사용 중

---

## 📋 **카테고리별 상세 수정 계획**

### 🔥 **Category 1: Production Test Files (최우선)**

#### **파일들**:
- `production-comprehensive-test.sh`
- `production-security-test.sh`
- `comprehensive-flow-test.sh`
- `final-integration-test.sh`

#### **현재 코드**:
```bash
# 현재 (잘못됨)
response=$(curl -s -X POST "http://localhost:8000/analyze" \
    -H "Content-Type: application/json" \
    -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}')
```

#### **수정 후**:
```bash
# 수정 후 (올바름)
response=$(curl -s -X POST "http://localhost:3000/analyze" \
    -H "Content-Type: application/json" \
    -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}')

# Kong intercept 확인 (선택적)
echo "Kong intercept 확인:"
docker logs kong-gateway --since=1m | grep "api.anthropic.com" || echo "No intercept logs found"
```

### 🔥 **Category 2: Direct Kong Test Files (완전 재작성)**

#### **파일들**:
- `direct-kong-test.sh`
- `kong-api-test.sh`
- `debug-headers.sh`
- 모든 `analyze-claude` 사용 파일들

#### **현재 코드**:
```bash
# 현재 (완전히 잘못됨)
curl -X POST http://localhost:8000/analyze-claude \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model":"claude-3-5-sonnet-20241022","messages":[...]}'
```

#### **수정 후 (간접 검증 방식)**:
```bash
# 방법 1: Backend API를 통한 간접 검증
response=$(curl -s -X POST "http://localhost:3000/analyze" \
    -H "Content-Type: application/json" \
    -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}')

# 방법 2: Kong 로그를 통한 마스킹 검증
echo "Kong intercept 및 마스킹 확인:"
docker logs kong-gateway --since=1m | grep -E "(aws-masker|api.anthropic.com|EC2_|PRIVATE_IP_)" || echo "No masking logs found"

# 방법 3: Redis에서 마스킹 패턴 확인
echo "Redis 마스킹 패턴 확인:"
docker exec redis-cache redis-cli KEYS "*" | head -10
```

### 🔥 **Category 3: Performance & Stress Test Files**

#### **파일들**:
- `performance-test.sh`
- `performance-test-simple.sh`
- `redis-performance-test.sh`

#### **현재 코드**:
```bash
# 현재 - 동시 Kong 호출
for i in {1..10}; do
  curl -X POST http://localhost:8000/analyze-claude & 
done
```

#### **수정 후**:
```bash
# 수정 후 - Backend API를 통한 실제 프로덕션 패턴 테스트
for i in {1..10}; do
  curl -X POST http://localhost:3000/analyze \
    -H "Content-Type: application/json" \
    -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' &
done
wait

# Kong 처리량 확인
echo "Kong 처리 통계:"
docker logs kong-gateway --since=1m | grep -c "api.anthropic.com" || echo "0"
```

### 🟡 **Category 4: Visualization & Debug Test Files**

#### **파일들**:
- `full-flow-visualization-test.sh`
- `complete-flow-visualization.sh`
- `debug-flow-test.sh`
- `mapping-flow-test.sh`

#### **수정 전략**:
1. **플로우 시각화 재정의**: Backend → Kong (투명) → Claude API
2. **디버깅 방식 변경**: Kong 로그 + Redis 상태 + Backend 응답 조합
3. **매핑 확인 방식**: Redis KEYS 명령어 + Kong 로그 조합

### 🟢 **Category 5: Backend Direct Test Files (영향 없음)**

#### **파일들**:
- `individual-pattern-security-test.sh`
- `security-masking-test.sh`
- `echo-flow-test.sh`

#### **현재 코드 (유지)**:
```bash
# 이미 올바른 패턴 - 수정 불필요
curl -X POST http://localhost:3000/test-masking \
  -H "Content-Type: application/json" \
  -d '{"testText":"i-1234567890abcdef0"}'
```

---

## 🛠️ **테스트 수정 템플릿**

### **Template 1: Basic Production Test**
```bash
#!/bin/bash
# Updated for correct API Gateway pattern

echo "=== Kong AWS Masking Test (API Gateway Pattern) ==="

# Test Backend API (Kong transparently intercepts)
response=$(curl -s -X POST "http://localhost:3000/analyze" \
    -H "Content-Type: application/json" \
    -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' \
    --max-time 60)

# Verify response
if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✅ Test passed"
    
    # Optional: Verify Kong intercept
    echo "Kong intercept verification:"
    docker logs kong-gateway --since=1m | grep "api.anthropic.com" | head -3
else
    echo "❌ Test failed"
    echo "Response: $response"
fi
```

### **Template 2: Security Verification Test**
```bash
#!/bin/bash
# Security test without direct Kong calls

echo "=== Security Verification (Indirect Method) ==="

# Test with AWS patterns
test_patterns=("i-1234567890abcdef0" "10.0.0.1" "vpc-abc123")

for pattern in "${test_patterns[@]}"; do
    echo -n "Testing pattern: $pattern ... "
    
    # Call Backend API
    response=$(curl -s -X POST "http://localhost:3000/test-masking" \
        -H "Content-Type: application/json" \
        -d "{\"testText\":\"Check $pattern status\"}")
    
    # Verify pattern is restored (meaning it was masked to Claude)
    if echo "$response" | jq -r '.finalResponse' | grep -q "$pattern"; then
        echo "✅ Masked & Restored"
    else
        echo "❌ Security issue"
    fi
done

# Verify Redis patterns
echo "Redis masked patterns:"
docker exec redis-cache redis-cli KEYS "*" | head -5
```

### **Template 3: Performance Test**
```bash
#!/bin/bash
# Performance test via Backend API

echo "=== Performance Test (API Gateway Pattern) ==="

# Concurrent Backend API calls
start_time=$(date +%s)

for i in {1..20}; do
    curl -s -X POST "http://localhost:3000/analyze" \
        -H "Content-Type: application/json" \
        -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' \
        > /dev/null &
done

wait
end_time=$(date +%s)
duration=$((end_time - start_time))

echo "Completed 20 concurrent requests in ${duration} seconds"

# Check Kong processing
kong_requests=$(docker logs kong-gateway --since="${duration}s" | grep -c "api.anthropic.com" || echo "0")
echo "Kong processed $kong_requests external API calls"
```

---

## 📅 **테스트 수정 실행 계획**

### **Phase A: 긴급 수정 (1일) - 프로덕션 테스트**
- [ ] `production-comprehensive-test.sh` 수정
- [ ] `production-security-test.sh` 수정
- [ ] `comprehensive-flow-test.sh` 수정
- [ ] `final-integration-test.sh` 수정

### **Phase B: 핵심 기능 테스트 (1일) - Direct Kong 호출 제거**
- [ ] `direct-kong-test.sh` 완전 재작성
- [ ] `kong-api-test.sh` 완전 재작성
- [ ] 모든 `analyze-claude` 사용 테스트 수정
- [ ] 테스트 전용 라우트 의존성 제거

### **Phase C: 성능 및 시각화 테스트 (1일)**
- [ ] `performance-test.sh` 수정
- [ ] `performance-test-simple.sh` 수정
- [ ] 모든 flow visualization 테스트 수정
- [ ] Redis 관련 테스트 검증

### **Phase D: 검증 및 정리 (0.5일)**
- [ ] 모든 테스트 실행하여 동작 확인
- [ ] 테스트 문서 업데이트
- [ ] 불필요한 테스트 파일 제거
- [ ] 테스트 실행 가이드 작성

---

## 🚨 **Critical Test Files 우선순위**

### **최우선 (즉시 수정 필요)**
1. `production-comprehensive-test.sh` - 프로덕션 준비도 검증
2. `production-security-test.sh` - 프로덕션 보안 검증
3. `comprehensive-flow-test.sh` - 전체 플로우 검증
4. `final-integration-test.sh` - 최종 통합 검증

### **2순위 (API Gateway 변경 전 완료)**
5. `direct-kong-test.sh` - Kong 직접 호출 제거
6. `kong-api-test.sh` - Kong API 테스트 재설계
7. 모든 `analyze-claude` 사용 테스트들
8. 성능 테스트들

### **3순위 (변경 후 검증)**
9. 시각화 및 디버그 테스트들
10. Redis 관련 테스트들
11. 개별 패턴 테스트들 (이미 올바른 패턴)

---

## 🔧 **새로운 테스트 검증 방식**

### **Kong Intercept 검증 방법**

#### **방법 1: Kong 로그 분석**
```bash
# Kong이 실제로 Claude API를 intercept했는지 확인
docker logs kong-gateway --since=1m | grep "api.anthropic.com"
```

#### **방법 2: Redis 패턴 확인**
```bash
# 마스킹된 패턴이 Redis에 저장되었는지 확인
docker exec redis-cache redis-cli KEYS "*"
```

#### **방법 3: 응답 분석**
```bash
# Backend 응답에 원본 AWS 패턴이 정확히 복원되었는지 확인
# (마스킹 → 언마스킹 과정을 거쳤다는 증거)
```

### **보안 검증 새로운 접근법**

```bash
# 기존: Kong을 직접 호출해서 마스킹 확인 (잘못된 방법)
curl http://localhost:8000/analyze-claude

# 새로운: Backend를 통해 간접적으로 마스킹 확인 (올바른 방법)
curl http://localhost:3000/analyze
# + Kong 로그 분석
# + Redis 패턴 확인
# + 응답에서 원본 복원 확인
```

---

## 🎯 **최종 목표: 투명한 API Gateway 테스트**

### **Before (잘못된 테스트 패턴)**:
- Kong을 직접 호출하는 테스트 (API Gateway 패턴 무시)
- 테스트가 Kong의 존재를 알고 있음
- Kong 전용 라우트에 의존

### **After (올바른 테스트 패턴)**:
- Backend API만 호출하는 테스트 (진짜 프로덕션 패턴)
- 테스트가 Kong의 존재를 모름 (투명함)
- Kong의 동작은 로그와 Redis로 간접 확인

### **핵심 원칙**: 
**"테스트도 프로덕션과 동일한 방식으로 Kong을 사용해야 함"**
- 프로덕션: Backend → Kong (투명) → External API
- 테스트: Backend → Kong (투명) → External API
- 같은 패턴으로 테스트해야 의미 있음

---

## 📊 **수정 완료 후 예상 효과**

### **Before**: 43개 테스트 파일 중 36개가 잘못된 패턴 사용
### **After**: 43개 테스트 파일 모두 올바른 API Gateway 패턴 사용

### **효과**:
1. **진짜 프로덕션 테스트**: 실제 사용자와 동일한 방식으로 테스트
2. **Kong 투명성 검증**: Kong이 정말 투명하게 동작하는지 확인
3. **보안 검증 강화**: 간접 방식으로 더 현실적인 보안 테스트
4. **유지보수성 향상**: 표준 패턴으로 테스트 관리 용이

---

## 🚀 **즉시 실행 사항**

1. **Phase A 즉시 시작**: 프로덕션 테스트 4개 파일 긴급 수정
2. **Template 적용**: 위의 3가지 템플릿을 기반으로 테스트 재작성
3. **검증 방식 전환**: Kong 직접 호출 → 간접 검증 방식
4. **문서 업데이트**: `DETAILED-MIGRATION-PLAN.md`에 테스트 수정 계획 추가

**예상 소요 시간**: 2.5일 (기존 5-7일 계획에 추가)  
**위험도**: HIGH (테스트 없이는 마이그레이션 검증 불가)  
**중요도**: CRITICAL (누락 시 전체 프로젝트 위험)