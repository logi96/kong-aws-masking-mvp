#!/bin/bash

# Kong AWS Masking Enterprise 2 - 설치 스크립트 Phase 1 성공 버전 검증
# LocalStack Phase 4: 재확인 및 멀티환경 검증

set -euo pipefail

echo "==============================================="
echo "Kong 설치 스크립트 Phase 1 성공 버전 검증"
echo "검증 시간: $(date)"
echo "==============================================="

SCRIPT_PATH="../archive/05-alternative-solutions/terraform/ec2/user_data_full.sh"
VALIDATION_REPORT="/tmp/kong-installation-validation-$(date +%Y%m%d_%H%M%S).md"

# 검증 결과 초기화
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=10

echo "# Kong 설치 스크립트 Phase 1 성공 버전 검증 보고서" > $VALIDATION_REPORT
echo "**검증 시간:** $(date)" >> $VALIDATION_REPORT
echo "**스크립트 경로:** $SCRIPT_PATH" >> $VALIDATION_REPORT
echo "" >> $VALIDATION_REPORT

# 함수: 검증 테스트 실행
run_validation() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo "🔍 검증 중: $test_name"
    echo "## $test_name" >> $VALIDATION_REPORT
    
    if eval "$test_command"; then
        if [[ "$expected_result" == "PASS" ]]; then
            echo "✅ PASS: $test_name"
            echo "**결과:** ✅ PASS" >> $VALIDATION_REPORT
            ((PASS_COUNT++))
        else
            echo "❌ FAIL: $test_name (예상과 다름)"
            echo "**결과:** ❌ FAIL (예상과 다름)" >> $VALIDATION_REPORT
            ((FAIL_COUNT++))
        fi
    else
        if [[ "$expected_result" == "FAIL" ]]; then
            echo "✅ EXPECTED FAIL: $test_name"
            echo "**결과:** ✅ EXPECTED FAIL" >> $VALIDATION_REPORT
            ((PASS_COUNT++))
        else
            echo "❌ FAIL: $test_name"
            echo "**결과:** ❌ FAIL" >> $VALIDATION_REPORT
            ((FAIL_COUNT++))
        fi
    fi
    echo "" >> $VALIDATION_REPORT
}

echo "1. Phase 1 핵심 구성요소 검증 시작..."
echo ""

# Test 1: kong-traditional.yml 생성 확인
run_validation "kong-traditional.yml 생성 스크립트 존재" \
    "grep -q 'kong-traditional.yml' $SCRIPT_PATH" \
    "PASS"

# Test 2: anthropic_api_key 플러그인 설정 확인
run_validation "anthropic_api_key 플러그인 설정" \
    "grep -q 'anthropic_api_key:.*\${anthropic_api_key}' $SCRIPT_PATH" \
    "PASS"

# Test 3: Docker Compose kong-traditional.yml 볼륨 마운트 확인
run_validation "Docker Compose kong-traditional.yml 볼륨 마운트" \
    "grep -q 'kong-traditional.yml:/usr/local/kong/declarative/kong-traditional.yml:ro' $SCRIPT_PATH" \
    "PASS"

# Test 4: Phase 1 성공 handler.lua 포함 확인
run_validation "Phase 1 성공 handler.lua 포함" \
    "grep -q 'Phase 1 성공 버전 handler.lua' $SCRIPT_PATH && grep -q 'Plugin config API key' $SCRIPT_PATH" \
    "PASS"

# Test 5: schema.lua anthropic_api_key 필드 확인
run_validation "schema.lua anthropic_api_key 필드" \
    "grep -q 'anthropic_api_key.*type.*string' $SCRIPT_PATH" \
    "PASS"

# Test 6: 필수 플러그인 모듈 파일들 생성 확인
run_validation "필수 플러그인 모듈 파일들 생성" \
    "grep -q 'masker_ngx_re.lua' $SCRIPT_PATH && grep -q 'json_safe.lua' $SCRIPT_PATH && grep -q 'error_codes.lua' $SCRIPT_PATH" \
    "PASS"

# Test 7: Kong 환경변수 KONG_DECLARATIVE_CONFIG 설정 확인
run_validation "Kong DECLARATIVE_CONFIG 환경변수" \
    "grep -q 'KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong-traditional.yml' $SCRIPT_PATH" \
    "PASS"

# Test 8: 헬스체크 및 검증 로직 포함 확인
run_validation "헬스체크 및 검증 로직" \
    "grep -q '헬스체크 수행' $SCRIPT_PATH && grep -q 'Kong Admin API 확인' $SCRIPT_PATH" \
    "PASS"

# Test 9: 환경변수 처리 확인
run_validation "필수 환경변수 처리" \
    "grep -q 'ANTHROPIC_API_KEY=.*anthropic_api_key' $SCRIPT_PATH && grep -q 'REDIS_PASSWORD=.*redis_password' $SCRIPT_PATH" \
    "PASS"

# Test 10: 이전 kong.yml 참조 제거 확인 (오래된 설정 제거)
run_validation "이전 kong.yml 참조 완전 제거" \
    "! grep -q 'kong.yml:/usr/local/kong/declarative/kong.yml:ro' $SCRIPT_PATH" \
    "PASS"

echo "==============================================="
echo "검증 완료 요약"
echo "==============================================="
echo "✅ PASS: $PASS_COUNT/$TOTAL_TESTS"
echo "❌ FAIL: $FAIL_COUNT/$TOTAL_TESTS"

# 최종 결과를 보고서에 추가
echo "## 검증 요약" >> $VALIDATION_REPORT
echo "- **총 테스트:** $TOTAL_TESTS" >> $VALIDATION_REPORT
echo "- **성공:** $PASS_COUNT" >> $VALIDATION_REPORT
echo "- **실패:** $FAIL_COUNT" >> $VALIDATION_REPORT
echo "- **성공률:** $(( PASS_COUNT * 100 / TOTAL_TESTS ))%" >> $VALIDATION_REPORT

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo ""
    echo "🎉 모든 검증 통과! Phase 1 성공 버전 구성요소가 완벽하게 포함되었습니다."
    echo "📋 상세 보고서: $VALIDATION_REPORT"
    echo "**최종 판정:** ✅ **Phase 1 성공 버전 완전 검증 통과**" >> $VALIDATION_REPORT
    exit 0
else
    echo ""
    echo "⚠️  일부 검증 실패. 상세 내용을 확인하세요."
    echo "📋 상세 보고서: $VALIDATION_REPORT"
    echo "**최종 판정:** ❌ **검증 실패 - 수정 필요**" >> $VALIDATION_REPORT
    exit 1
fi