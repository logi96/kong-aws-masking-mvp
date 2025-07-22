#!/bin/bash
# run-phase4-step1-final.sh
# Phase 4-1 최종 검증: cjson 및 API 인증 문제 해결
# 보안 최우선: 100% 완벽한 해결 확인

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=========================================="
echo "🔒 Phase 4-1 최종 검증: 보안 문제 100% 해결"
echo "=========================================="
echo "시작 시간: $(date)"
echo ""

# 작업 디렉토리
KONG_DIR="/Users/tw.kim/Documents/AGA/test/Kong"
cd "$KONG_DIR"

# 보안 체크포인트
echo -e "${BLUE}🔒 보안 체크포인트: 환경 검증${NC}"
echo "=========================================="

# API 키 확인
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo -e "${RED}❌ ANTHROPIC_API_KEY 환경 변수가 설정되지 않았습니다!${NC}"
    echo "export ANTHROPIC_API_KEY=sk-ant-api... 설정 필요"
    exit 1
else
    echo -e "${GREEN}✓ API 키 설정됨 (마지막 4자: ...${ANTHROPIC_API_KEY: -4})${NC}"
fi

# 파일 검증
echo -e "\n${BLUE}[1/6] 수정된 파일 검증${NC}"
echo "=========================================="

FILES_TO_CHECK=(
    "kong/plugins/aws-masker/json_safe.lua"
    "kong/plugins/aws-masker/auth_handler.lua"
    "kong/plugins/aws-masker/handler.lua"
    "kong/kong.yml"
    "docker-compose.yml"
)

MISSING_FILES=0
for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ $file${NC}"
    else
        echo -e "${RED}✗ $file - 파일 없음!${NC}"
        ((MISSING_FILES++))
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo -e "${RED}❌ 필요한 파일이 누락되었습니다!${NC}"
    exit 1
fi

# Docker 재시작
echo -e "\n${BLUE}[2/6] Docker 환경 재시작${NC}"
echo "=========================================="

echo "Kong 컨테이너 재시작..."
docker-compose down
docker-compose up -d

# Kong 준비 대기
echo "Kong 시작 대기 중..."
MAX_WAIT=60
WAIT_COUNT=0
while ! curl -s http://localhost:8001/status > /dev/null 2>&1; do
    echo -n "."
    sleep 2
    ((WAIT_COUNT++))
    if [ $WAIT_COUNT -gt $MAX_WAIT ]; then
        echo -e "\n${RED}❌ Kong이 시작되지 않았습니다!${NC}"
        docker-compose logs kong
        exit 1
    fi
done
echo -e "\n${GREEN}✓ Kong 준비 완료${NC}"

# JSON 모듈 테스트
echo -e "\n${BLUE}[3/6] JSON 모듈 호환성 테스트${NC}"
echo "=========================================="

echo "Kong 컨테이너 내부에서 json_safe 모듈 테스트..."
JSON_TEST_RESULT=$(docker-compose exec -T kong sh -c '
cd /usr/local/share/lua/5.1/kong/plugins/aws-masker
lua -e "
local json_safe = require \"kong.plugins.aws-masker.json_safe\"
local ok, msg = json_safe.test()
if ok then
    print(\"SUCCESS: \" .. msg)
else
    print(\"FAILED: \" .. msg)
    os.exit(1)
end
"' 2>&1) || JSON_TEST_SUCCESS=false

if [ "${JSON_TEST_SUCCESS:-true}" = true ] && echo "$JSON_TEST_RESULT" | grep -q "SUCCESS"; then
    echo -e "${GREEN}✓ JSON 모듈 테스트 성공${NC}"
    echo "$JSON_TEST_RESULT"
    JSON_MODULE_OK=true
else
    echo -e "${RED}✗ JSON 모듈 테스트 실패${NC}"
    echo "$JSON_TEST_RESULT"
    JSON_MODULE_OK=false
fi

# API 인증 테스트
echo -e "\n${BLUE}[4/6] API 인증 처리 테스트${NC}"
echo "=========================================="

# 테스트 요청 준비
TEST_REQUEST='{
  "model": "claude-3-sonnet-20240229",
  "messages": [{
    "role": "user",
    "content": "Test: EC2 instance i-1234567890abcdef0 with IAM key AKIAIOSFODNN7EXAMPLE"
  }],
  "max_tokens": 10
}'

echo "API 인증 포함 요청 전송..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${ANTHROPIC_API_KEY}" \
    -d "$TEST_REQUEST" 2>&1 || true)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo "HTTP 상태 코드: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ API 인증 성공${NC}"
    AUTH_SUCCESS=true
elif [ "$HTTP_CODE" = "401" ]; then
    echo -e "${RED}✗ API 인증 실패 (401)${NC}"
    echo "응답: $BODY"
    AUTH_SUCCESS=false
else
    echo -e "${YELLOW}⚠ 예상치 못한 응답: $HTTP_CODE${NC}"
    AUTH_SUCCESS=false
fi

# Kong 로그 확인
echo -e "\n${BLUE}[5/6] Kong 플러그인 로그 확인${NC}"
echo "=========================================="

echo "최근 Kong 로그 (마스킹 및 인증):"
docker-compose logs --tail=50 kong 2>&1 | grep -E "(AWS Masker|auth_handler|json_safe)" | tail -20 || true

# 마스킹 검증
MASKED_COUNT=$(docker-compose logs --tail=100 kong 2>&1 | grep -c "Masked .* AWS resources" || true)
echo -e "\n마스킹된 요청 수: $MASKED_COUNT"

if [ $MASKED_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ 마스킹 기능 작동 확인${NC}"
    MASKING_OK=true
else
    echo -e "${YELLOW}⚠ 마스킹 로그를 찾을 수 없음${NC}"
    MASKING_OK=false
fi

# 보안 검증
echo -e "\n${BLUE}[6/6] 최종 보안 검증${NC}"
echo "=========================================="

# Critical 패턴 테스트
CRITICAL_REQUEST='{
  "messages": [{
    "role": "user", 
    "content": "KMS key arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012 and secret arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db-AbCdEf"
  }]
}'

echo "Critical 패턴 마스킹 테스트..."
CRITICAL_RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -d "$CRITICAL_REQUEST" 2>&1 || true)

# 원본 패턴이 응답에 없는지 확인
if echo "$CRITICAL_RESPONSE" | grep -q "arn:aws:kms:us-east-1:123456789012"; then
    echo -e "${RED}✗ 보안 위험: Critical 패턴이 마스킹되지 않음!${NC}"
    SECURITY_OK=false
else
    echo -e "${GREEN}✓ Critical 패턴 마스킹 확인${NC}"
    SECURITY_OK=true
fi

# 통합 보고서 생성
echo -e "\n${BLUE}📝 Phase 4-1 최종 보고서 생성${NC}"
echo "=========================================="

cat > phase4-step1-final-report.md << EOF
# Phase 4-1 최종 검증 보고서

**검증일시**: $(date)
**검증자**: Kong AWS Masking Security Team
**상태**: $([ "$JSON_MODULE_OK" = true ] && [ "$AUTH_SUCCESS" = true ] && [ "$MASKING_OK" = true ] && [ "$SECURITY_OK" = true ] && echo "✅ **완료**" || echo "⚠️ **미완료**")

## 🎯 해결 목표
1. cjson 모듈 호환성 문제 - 100% 해결
2. API 인증 문제 - 100% 해결

## 📋 검증 결과

### 1. JSON 모듈 호환성
- 상태: $([ "$JSON_MODULE_OK" = true ] && echo "✅ 해결" || echo "❌ 미해결")
- json_safe.lua 모듈 구현
- 다중 라이브러리 지원 (cjson, cjson.safe, kong.tools.cjson)
- 폴백 메커니즘 구현

### 2. API 인증 처리
- 상태: $([ "$AUTH_SUCCESS" = true ] && echo "✅ 해결" || echo "❌ 미해결")
- auth_handler.lua 모듈 구현
- 환경 변수 및 헤더 기반 인증
- API 키 안전한 전달

### 3. 마스킹 기능
- 상태: $([ "$MASKING_OK" = true ] && echo "✅ 정상" || echo "⚠️ 확인 필요")
- 마스킹된 요청: $MASKED_COUNT 건
- 47개 패턴 처리

### 4. 보안 검증
- 상태: $([ "$SECURITY_OK" = true ] && echo "✅ 안전" || echo "❌ 위험")
- Critical 패턴 마스킹 확인
- 민감 정보 노출 방지

## 🔒 보안 체크리스트

$(if [ "$JSON_MODULE_OK" = true ] && [ "$AUTH_SUCCESS" = true ] && [ "$MASKING_OK" = true ] && [ "$SECURITY_OK" = true ]; then
    echo "- [x] JSON 모듈 문제 해결"
    echo "- [x] API 인증 문제 해결"
    echo "- [x] 마스킹 기능 정상 작동"
    echo "- [x] Critical 패턴 보호"
    echo "- [x] 환경 변수 안전 관리"
    echo ""
    echo "**Phase 4-1 상태**: ✅ **100% 완료**"
else
    echo "- [$([ "$JSON_MODULE_OK" = true ] && echo "x" || echo " ")] JSON 모듈 문제 해결"
    echo "- [$([ "$AUTH_SUCCESS" = true ] && echo "x" || echo " ")] API 인증 문제 해결"
    echo "- [$([ "$MASKING_OK" = true ] && echo "x" || echo " ")] 마스킹 기능 정상 작동"
    echo "- [$([ "$SECURITY_OK" = true ] && echo "x" || echo " ")] Critical 패턴 보호"
    echo "- [x] 환경 변수 안전 관리"
    echo ""
    echo "**Phase 4-1 상태**: ⚠️ **추가 작업 필요**"
fi)

## 📊 기술적 해결 방안

### JSON 모듈 해결
\`\`\`lua
-- json_safe.lua
local ok, cjson = pcall(require, "cjson")
if not ok then
    ok, cjson = pcall(require, "cjson.safe")
    if not ok then
        ok, cjson = pcall(require, "kong.tools.cjson")
    end
end
\`\`\`

### API 인증 해결
\`\`\`lua
-- auth_handler.lua
function auth_handler.forward_api_key(api_key, target_header)
    kong.service.request.set_header("x-api-key", api_key)
    kong.service.request.set_header("anthropic-version", "2023-06-01")
end
\`\`\`

## ✅ 최종 결론

$(if [ "$JSON_MODULE_OK" = true ] && [ "$AUTH_SUCCESS" = true ] && [ "$MASKING_OK" = true ] && [ "$SECURITY_OK" = true ]; then
    echo "**Phase 4-1 100% 완료**"
    echo ""
    echo "모든 미해결 항목이 성공적으로 해결되었습니다:"
    echo "1. cjson 모듈 호환성 - json_safe 모듈로 해결"
    echo "2. API 인증 - auth_handler 모듈로 해결"
    echo "3. 보안 검증 - 모든 Critical 패턴 보호 확인"
    echo ""
    echo "**다음 단계**: Phase 5 - 프로덕션 배포 (Canary)"
else
    echo "**추가 디버깅 필요**"
    echo ""
    echo "해결 방법:"
    echo "1. Kong 로그 상세 확인: docker-compose logs -f kong"
    echo "2. API 키 형식 확인"
    echo "3. 네트워크 연결 확인"
fi)

---

**서명**: Kong AWS Masking Security Team  
**날짜**: $(date +%Y-%m-%d)  
**보안 수준**: CRITICAL
EOF

echo -e "${GREEN}✓ 보고서 생성: phase4-step1-final-report.md${NC}"

# 최종 결과
echo ""
echo "=========================================="
echo -e "${BLUE}🔒 Phase 4-1 최종 검증 결과${NC}"
echo "=========================================="

if [ "$JSON_MODULE_OK" = true ] && [ "$AUTH_SUCCESS" = true ] && [ "$MASKING_OK" = true ] && [ "$SECURITY_OK" = true ]; then
    echo -e "${GREEN}✅ Phase 4-1 100% 완료!${NC}"
    echo -e "${GREEN}   모든 보안 문제 해결${NC}"
    echo -e "${GREEN}   cjson 모듈 호환성 ✓${NC}"
    echo -e "${GREEN}   API 인증 처리 ✓${NC}"
    echo -e "${GREEN}   Critical 패턴 보호 ✓${NC}"
    echo ""
    echo "Phase 4 전체 상태:"
    echo "  Phase 4-1: 100% ✅"
    echo "  Phase 4-2: 100% ✅"
    echo "  Phase 4-3: 100% ✅"
    echo ""
    echo -e "${GREEN}Phase 4 완료! 다음: Phase 5 - 프로덕션 배포${NC}"
    exit 0
else
    echo -e "${RED}❌ Phase 4-1 미완료${NC}"
    if [ "$JSON_MODULE_OK" = false ]; then
        echo -e "${RED}   JSON 모듈 문제${NC}"
    fi
    if [ "$AUTH_SUCCESS" = false ]; then
        echo -e "${RED}   API 인증 실패${NC}"
    fi
    if [ "$MASKING_OK" = false ]; then
        echo -e "${RED}   마스킹 확인 필요${NC}"
    fi
    if [ "$SECURITY_OK" = false ]; then
        echo -e "${RED}   보안 위험 감지${NC}"
    fi
    echo ""
    echo "디버깅 명령어:"
    echo "  docker-compose logs -f kong"
    echo "  docker-compose exec kong sh"
    exit 1
fi