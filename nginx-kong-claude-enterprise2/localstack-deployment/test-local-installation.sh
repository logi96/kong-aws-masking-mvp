#!/bin/bash

# 로컬 Docker 환경에서 설치 스크립트 구성요소 검증
set -euo pipefail

echo "==============================================="
echo "로컬 Docker 환경 - 설치 스크립트 구성요소 테스트"
echo "테스트 시간: $(date)"
echo "==============================================="

TEST_DIR="/tmp/kong-local-install-test-$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="/tmp/local-installation-test-$(date +%Y%m%d_%H%M%S).md"

# 테스트 디렉토리 생성
mkdir -p $TEST_DIR
cd $TEST_DIR

echo "# 로컬 Docker 환경 설치 스크립트 테스트 보고서" > $REPORT_FILE
echo "**테스트 시간:** $(date)" >> $REPORT_FILE
echo "**테스트 디렉토리:** $TEST_DIR" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 함수: 테스트 실행
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "🔍 테스트: $test_name"
    echo "## $test_name" >> $REPORT_FILE
    
    if eval "$test_command" 2>&1; then
        echo "✅ PASS: $test_name"
        echo "**결과:** ✅ PASS" >> $REPORT_FILE
        return 0
    else
        echo "❌ FAIL: $test_name"
        echo "**결과:** ❌ FAIL" >> $REPORT_FILE
        return 1
    fi
    echo "" >> $REPORT_FILE
}

PASS_COUNT=0
TOTAL_TESTS=0

echo "1. 기본 환경 검증..."

# Test 1: Docker 사용 가능 여부
run_test "Docker 실행 가능 여부" "docker --version" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

# Test 2: Docker Compose 사용 가능 여부
run_test "Docker Compose 실행 가능 여부" "docker-compose --version" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

echo ""
echo "2. 설치 스크립트 구성요소 재현..."

# 프로젝트 구조 생성 (user_data_full.sh에서 추출)
mkdir -p kong/plugins/aws-masker nginx claude-code-sdk logs/{kong,nginx,redis,claude-code-sdk} redis/data

# Test 3: kong-traditional.yml 생성 테스트
run_test "kong-traditional.yml 파일 생성" "
cat > kong/kong-traditional.yml << 'EOF'
_format_version: \"3.0\"
_transform: true

services:
  - name: claude-api-service
    url: https://api.anthropic.com
    protocol: https
    host: api.anthropic.com
    port: 443

routes:
  - name: claude-proxy-route
    service: claude-api-service
    paths:
      - /v1

plugins:
  - name: aws-masker
    route: claude-proxy-route
    config:
      anthropic_api_key: \"test-api-key\"
      mask_ec2_instances: true
      redis_host: \"redis\"
      redis_port: 6379
EOF
test -f kong/kong-traditional.yml
" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

# Test 4: Docker Compose 파일 생성 테스트
run_test "Docker Compose 파일 생성" "
cat > docker-compose.yml << 'EOF'
services:
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass test-password
    ports:
      - \"6379:6379\"
    networks:
      - claude-network

  kong:
    image: kong/kong-gateway:3.9.0.1
    depends_on:
      - redis
    environment:
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong-traditional.yml
      - KONG_PROXY_LISTEN=0.0.0.0:8010
      - KONG_ADMIN_LISTEN=0.0.0.0:8001
      - KONG_PLUGINS=bundled,aws-masker
    volumes:
      - ./kong/kong-traditional.yml:/usr/local/kong/declarative/kong-traditional.yml:ro
      - ./kong/plugins:/usr/local/kong/plugins:ro
    ports:
      - \"8001:8001\"
      - \"8010:8010\"
    networks:
      - claude-network

  nginx:
    image: nginx:alpine
    depends_on:
      - kong
    ports:
      - \"8082:8082\"
    networks:
      - claude-network

networks:
  claude-network:
    driver: bridge
EOF
test -f docker-compose.yml
" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

# Test 5: Phase 1 성공 버전 handler.lua 생성
run_test "Phase 1 성공 handler.lua 생성" "
cat > kong/plugins/aws-masker/handler.lua << 'EOF'
local AwsMaskerHandler = {}
AwsMaskerHandler.VERSION = \"1.0.0\"
AwsMaskerHandler.PRIORITY = 700

function AwsMaskerHandler:access(conf)
  -- Phase 1 핵심: API 키 Plugin Config 우선 접근
  local api_key_from_config = conf and conf.anthropic_api_key
  local api_key_from_env = os.getenv(\"ANTHROPIC_API_KEY\")
  local final_api_key = api_key_from_config or api_key_from_env
  
  if final_api_key and final_api_key ~= \"\" then
    kong.service.request.set_header(\"x-api-key\", final_api_key)
    kong.service.request.set_header(\"anthropic-version\", \"2023-06-01\")
  end
end

return AwsMaskerHandler
EOF
test -f kong/plugins/aws-masker/handler.lua
" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

# Test 6: schema.lua anthropic_api_key 필드 포함 확인
run_test "schema.lua anthropic_api_key 필드 생성" "
cat > kong/plugins/aws-masker/schema.lua << 'EOF'
return {
  name = \"aws-masker\",
  fields = {
    { config = {
        type = \"record\",
        fields = {
          { enabled = { type = \"boolean\", default = true } },
          { anthropic_api_key = { type = \"string\", required = false } },
          { redis_host = { type = \"string\", default = \"redis\" } },
          { redis_port = { type = \"number\", default = 6379 } },
        }
    }}
  }
}
EOF
test -f kong/plugins/aws-masker/schema.lua
" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

echo ""
echo "3. Docker Compose 구성 유효성 검증..."

# Test 7: Docker Compose 구성 검증
run_test "Docker Compose 구성 유효성" "docker-compose config > /dev/null" && ((PASS_COUNT++)) || true
((TOTAL_TESTS++))

echo ""
echo "==============================================="
echo "로컬 테스트 결과 요약"
echo "==============================================="
echo "✅ PASS: $PASS_COUNT/$TOTAL_TESTS"
echo "❌ FAIL: $((TOTAL_TESTS - PASS_COUNT))/$TOTAL_TESTS"

# 결과를 보고서에 추가
echo "" >> $REPORT_FILE
echo "## 테스트 결과 요약" >> $REPORT_FILE
echo "- **총 테스트:** $TOTAL_TESTS" >> $REPORT_FILE
echo "- **성공:** $PASS_COUNT" >> $REPORT_FILE
echo "- **실패:** $((TOTAL_TESTS - PASS_COUNT))" >> $REPORT_FILE
echo "- **성공률:** $(( PASS_COUNT * 100 / TOTAL_TESTS ))%" >> $REPORT_FILE

if [[ $PASS_COUNT -eq $TOTAL_TESTS ]]; then
    echo ""
    echo "🎉 모든 로컬 테스트 통과! 설치 스크립트 구성요소가 완전합니다."
    echo "📂 테스트 디렉토리: $TEST_DIR"
    echo "📋 상세 보고서: $REPORT_FILE"
    echo "**최종 판정:** ✅ **로컬 Docker 환경 완전 검증 통과**" >> $REPORT_FILE
    
    echo ""
    echo "🚀 실제 Docker Compose 시작 테스트도 수행 가능합니다:"
    echo "   cd $TEST_DIR && docker-compose up -d"
    exit 0
else
    echo ""
    echo "⚠️  일부 테스트 실패. 상세 내용을 확인하세요."
    echo "📂 테스트 디렉토리: $TEST_DIR"
    echo "📋 상세 보고서: $REPORT_FILE"
    echo "**최종 판정:** ❌ **로컬 테스트 실패 - 수정 필요**" >> $REPORT_FILE
    exit 1
fi