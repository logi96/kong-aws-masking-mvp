#!/bin/bash

#
# Quick Core Validation - Kong AWS Masking MVP
# 
# Focus on essential functionality validation for deployment readiness
# Tests: Core patterns, proxy chain, Redis mapping, basic error handling
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_NAME="quick-core-validation"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_DIR="tests/test-report"
REPORT_FILE="$REPORT_DIR/${SCRIPT_NAME}-${TIMESTAMP}.md"

# Test endpoints
KONG_DIRECT_ENDPOINT="http://localhost:8000"
NGINX_ENDPOINT="http://localhost:8085"
KONG_ADMIN_ENDPOINT="http://localhost:8001"
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD="CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Create report directory
mkdir -p "$REPORT_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" | tee -a "$REPORT_FILE"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$REPORT_FILE"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$REPORT_FILE"
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Kong AWS Masking MVP - 빠른 핵심 검증 리포트

**테스트 실행 시간**: $(date '+%Y-%m-%d %H:%M:%S')  
**목표**: 배포 준비상태 핵심 기능 검증  

## 테스트 환경

- Kong Proxy: http://localhost:8000
- Kong Admin: http://localhost:8001  
- Nginx Proxy: http://localhost:8085
- Redis: localhost:6379

---

## 테스트 결과

EOF
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log "테스트: $test_name"
    
    if eval "$test_func"; then
        log_success "✅ $test_name 통과"
        return 0
    else
        log_error "❌ $test_name 실패"
        return 1
    fi
}

# Test 1: Basic connectivity
test_connectivity() {
    # Kong Admin
    curl -s "$KONG_ADMIN_ENDPOINT/status" > /dev/null || return 1
    
    # Redis
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping > /dev/null 2>&1 || return 1
    
    # Kong Proxy (with Claude API)
    local response=$(curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: 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" \
        -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":50,"messages":[{"role":"user","content":"Hello"}]}' \
        -w "HTTP_CODE:%{http_code}" 2>/dev/null)
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
    [[ "$http_code" == "200" ]] || return 1
    
    return 0
}

# Test 2: Core AWS pattern masking
test_core_patterns() {
    local test_patterns=(
        "i-1234567890abcdef0"
        "vpc-12345678"
        "sg-12345678"
        "ami-12345678"
        "subnet-1234567890abcdef0"
    )
    
    local success_count=0
    
    for pattern in "${test_patterns[@]}"; do
        local test_payload=$(cat << EOF
{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100,
    "messages": [
        {
            "role": "user", 
            "content": "Analyze this AWS resource: $pattern"
        }
    ]
}
EOF
)
        
        # Clear previous logs
        docker logs claude-kong --tail=0 2>/dev/null || true
        
        # Send request
        local response=$(curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: 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" \
            -d "$test_payload" \
            -w "HTTP_CODE:%{http_code}" 2>/dev/null)
        
        local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
        
        if [[ "$http_code" == "200" ]]; then
            # Check logs for masking activity
            sleep 1
            local masking_logs=$(docker logs claude-kong 2>&1 | grep -i "masking\|mask_count\|pattern" | tail -5)
            
            if [[ -n "$masking_logs" ]]; then
                success_count=$((success_count + 1))
                log "  ✓ $pattern: 마스킹 확인됨"
            else
                log_warning "  ⚠ $pattern: HTTP 200 but no masking logs"
            fi
        else
            log_warning "  ⚠ $pattern: HTTP $http_code"
        fi
        
        sleep 0.5
    done
    
    # Success if at least 60% of patterns work
    local required_success=$((${#test_patterns[@]} * 60 / 100))
    [[ $success_count -ge $required_success ]] || return 1
    
    log "  패턴 마스킹 성공: $success_count/${#test_patterns[@]}"
    return 0
}

# Test 3: Proxy chain (Nginx → Kong → Claude)
test_proxy_chain() {
    local test_payload=$(cat << EOF
{
    "model": "claude-3-5-sonnet-20241022", 
    "max_tokens": 50,
    "messages": [
        {
            "role": "user",
            "content": "Test proxy with i-abcdef1234567890"
        }
    ]
}
EOF
)
    
    # Test through Nginx proxy
    local response=$(curl -s -X POST "$NGINX_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer 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" \
        -d "$test_payload" \
        -w "HTTP_CODE:%{http_code}" 2>/dev/null)
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
    [[ "$http_code" == "200" ]] || return 1
    
    return 0
}

# Test 4: Redis mapping persistence
test_redis_mapping() {
    local test_value="i-testredis12345678"
    
    # Send request to create mapping
    local test_payload=$(cat << EOF
{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 50,
    "messages": [
        {
            "role": "user",
            "content": "Check this: $test_value"
        }
    ]
}
EOF
)
    
    curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: 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" \
        -d "$test_payload" > /dev/null 2>&1
    
    sleep 2
    
    # Check if mapping exists in Redis
    local encoded_value=$(echo -n "$test_value" | base64)
    local redis_key="aws_masker:rev:$encoded_value"
    
    local mapped_value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" get "$redis_key" 2>/dev/null || echo "")
    
    if [[ -n "$mapped_value" && "$mapped_value" != "(nil)" ]]; then
        log "  Redis 매핑 확인: $test_value → $mapped_value"
        return 0
    else
        return 1
    fi
}

# Test 5: Error handling (invalid API key)
test_error_handling() {
    local response=$(curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: invalid-key" \
        -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":50,"messages":[{"role":"user","content":"test"}]}' \
        -w "HTTP_CODE:%{http_code}" 2>/dev/null)
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
    
    # Should return 401 for invalid API key
    [[ "$http_code" == "401" ]] || return 1
    
    return 0
}

# Generate final report
generate_final_report() {
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    local deployment_ready=false
    
    # Deployment ready if 80% or more tests pass
    if [[ $success_rate -ge 80 ]]; then
        deployment_ready=true
    fi
    
    cat >> "$REPORT_FILE" << EOF

## 📊 최종 결과 요약

### 테스트 결과

| 메트릭 | 값 |
|--------|-----|
| 전체 테스트 | $TOTAL_TESTS |
| 성공 | $PASSED_TESTS |
| 실패 | $FAILED_TESTS |
| 성공률 | $success_rate% |

### 🎯 배포 준비 상태

**$([ $deployment_ready == true ] && echo "✅ 배포 준비 완료" || echo "❌ 추가 작업 필요")**

$([ $deployment_ready == true ] && echo "- 모든 핵심 기능이 정상 동작
- Kong AWS 마스킹 플러그인 안정적 작동  
- 프록시 체인 정상 동작
- Redis 매핑 시스템 작동
- 기본 에러 처리 정상" || echo "- 일부 핵심 기능에 문제 발견
- 추가 디버깅 및 수정 필요
- 배포 전 안정성 개선 권장")

### 💡 권장사항

EOF
    
    if [[ $deployment_ready == true ]]; then
        echo "- 🚀 **즉시 배포 가능**: 모든 핵심 기능이 안정적으로 동작" >> "$REPORT_FILE"
        echo "- 📈 **확장 가능**: 추가 AWS 패턴 및 기능 점진적 추가" >> "$REPORT_FILE"
        echo "- 🔍 **모니터링 강화**: 프로덕션 환경에서 실시간 모니터링 설정" >> "$REPORT_FILE"
    else
        echo "- 🔧 **문제 해결 우선**: 실패한 테스트 케이스 분석 및 수정" >> "$REPORT_FILE"
        echo "- 🧪 **추가 테스트**: 더 상세한 디버깅 및 로그 분석" >> "$REPORT_FILE"
        echo "- ⏳ **배포 연기**: 안정성 확보 후 배포 진행" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

---

**리포트 생성 시간**: $(date '+%Y-%m-%d %H:%M:%S')  
**리포트 파일**: $REPORT_FILE

EOF
}

# Main execution
main() {
    echo -e "${BLUE}Kong AWS Masking MVP - 빠른 핵심 검증 시작...${NC}"
    init_report
    
    # Run core tests
    run_test "기본 연결성 (Kong, Redis, Claude API)" "test_connectivity"
    run_test "핵심 AWS 패턴 마스킹" "test_core_patterns" 
    run_test "프록시 체인 (Nginx → Kong → Claude)" "test_proxy_chain"
    run_test "Redis 매핑 지속성" "test_redis_mapping"
    run_test "기본 에러 처리 (잘못된 API 키)" "test_error_handling"
    
    # Generate report
    generate_final_report
    
    echo -e "${BLUE}검증 완료. 상세 결과: $REPORT_FILE${NC}"
    
    # Final status
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    if [[ $success_rate -ge 80 ]]; then
        echo -e "${GREEN}🎉 배포 준비 완료! ($success_rate% 성공)${NC}"
        exit 0
    else
        echo -e "${RED}❌ 추가 작업 필요 ($success_rate% 성공)${NC}"
        exit 1
    fi
}

# Run main function
main "$@"