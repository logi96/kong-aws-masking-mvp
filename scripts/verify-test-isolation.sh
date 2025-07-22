#!/bin/bash
# verify-test-isolation.sh - 테스트 환경 격리 검증 스크립트
# 보안 최우선: 프로덕션 환경과의 완전한 격리 확인

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "🔒 Kong AWS Masking - 테스트 환경 격리 검증"
echo "=========================================="

# 검증 실패 카운터
FAILURES=0

# 1. Docker 네트워크 격리 확인
echo -e "\n[1/6] Docker 네트워크 격리 확인..."
if docker network ls | grep -q "kong-test-network"; then
    echo -e "${GREEN}✓ 테스트 전용 네트워크 확인됨${NC}"
    
    # 프로덕션 네트워크와 연결 확인
    if docker network inspect kong-test-network | grep -q "production"; then
        echo -e "${RED}✗ 경고: 프로덕션 네트워크와 연결 감지!${NC}"
        ((FAILURES++))
    else
        echo -e "${GREEN}✓ 프로덕션 네트워크와 격리됨${NC}"
    fi
else
    echo -e "${YELLOW}! 테스트 네트워크 생성 필요${NC}"
    docker network create --driver bridge kong-test-network
    echo -e "${GREEN}✓ 테스트 네트워크 생성 완료${NC}"
fi

# 2. 환경 변수 확인
echo -e "\n[2/6] 환경 변수 격리 확인..."
if [[ "${ENVIRONMENT:-}" == "test" || "${ENVIRONMENT:-}" == "" ]]; then
    echo -e "${GREEN}✓ 테스트 환경 변수 확인됨${NC}"
else
    echo -e "${RED}✗ 경고: ENVIRONMENT가 'test'가 아님: ${ENVIRONMENT}${NC}"
    ((FAILURES++))
fi

# AWS 자격 증명 격리 확인
if [[ -f .env.test ]]; then
    if grep -q "PROD" .env.test; then
        echo -e "${RED}✗ 경고: 테스트 환경에 프로덕션 자격 증명 감지!${NC}"
        ((FAILURES++))
    else
        echo -e "${GREEN}✓ 테스트 전용 자격 증명 확인됨${NC}"
    fi
else
    echo -e "${YELLOW}! .env.test 파일 생성 필요${NC}"
    cat > .env.test << EOF
# Test environment only - DO NOT USE IN PRODUCTION
ENVIRONMENT=test
ANTHROPIC_API_KEY=sk-ant-test-key-only
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test-only-key
AWS_SECRET_ACCESS_KEY=test-only-secret
ENABLE_SECURITY_AUDIT=true
AUDIT_LOG_PATH=/secure/logs/test-aws-masking-audit.log
EOF
    echo -e "${GREEN}✓ 테스트 환경 파일 생성 완료${NC}"
fi

# 3. 포트 격리 확인
echo -e "\n[3/6] 포트 격리 확인..."
TEST_PORTS=(8100 8101 3100)  # 테스트 전용 포트
PROD_PORTS=(8000 8001 3000)  # 프로덕션 포트

for port in "${TEST_PORTS[@]}"; do
    if lsof -i :$port > /dev/null 2>&1; then
        echo -e "${YELLOW}! 포트 $port 이미 사용 중${NC}"
    else
        echo -e "${GREEN}✓ 테스트 포트 $port 사용 가능${NC}"
    fi
done

for port in "${PROD_PORTS[@]}"; do
    if lsof -i :$port > /dev/null 2>&1; then
        echo -e "${YELLOW}! 주의: 프로덕션 포트 $port 사용 중${NC}"
    fi
done

# 4. 데이터 격리 확인
echo -e "\n[4/6] 데이터 격리 확인..."
if [[ -d ./test-data ]]; then
    echo -e "${GREEN}✓ 테스트 데이터 디렉토리 확인됨${NC}"
else
    mkdir -p ./test-data/logs ./test-data/mappings ./test-data/audit
    chmod 700 ./test-data
    echo -e "${GREEN}✓ 테스트 데이터 디렉토리 생성 완료${NC}"
fi

# 5. Kong 설정 격리 확인
echo -e "\n[5/6] Kong 설정 격리 확인..."
if [[ -f ./kong/kong-test.yml ]]; then
    echo -e "${GREEN}✓ 테스트 Kong 설정 확인됨${NC}"
else
    cp ./kong/kong.yml ./kong/kong-test.yml
    sed -i.bak 's/8000/8100/g; s/8001/8101/g' ./kong/kong-test.yml
    echo -e "${GREEN}✓ 테스트 Kong 설정 생성 완료${NC}"
fi

# 6. 보안 감사 로그 설정
echo -e "\n[6/6] 보안 감사 로그 설정..."
AUDIT_DIR="/secure/logs"
if [[ -d $AUDIT_DIR ]] || mkdir -p $AUDIT_DIR 2>/dev/null; then
    echo -e "${GREEN}✓ 감사 로그 디렉토리 준비됨${NC}"
else
    echo -e "${YELLOW}! 감사 로그 디렉토리 생성 실패 - sudo 권한 필요할 수 있음${NC}"
    AUDIT_DIR="./test-data/audit"
    mkdir -p $AUDIT_DIR
    echo -e "${GREEN}✓ 대체 감사 로그 디렉토리 사용: $AUDIT_DIR${NC}"
fi

# 최종 결과
echo -e "\n=========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}✅ 테스트 환경 격리 검증 완료!${NC}"
    echo -e "${GREEN}   프로덕션과 완전히 격리된 환경입니다.${NC}"
    
    # 격리 증명서 생성
    cat > ./test-isolation-certificate.txt << EOF
테스트 환경 격리 증명서
생성일시: $(date)
검증결과: PASS
네트워크: kong-test-network (격리됨)
포트: 8100, 8101, 3100 (테스트 전용)
데이터: ./test-data (격리됨)
환경: test
EOF
    echo -e "\n${GREEN}격리 증명서가 생성되었습니다: ./test-isolation-certificate.txt${NC}"
else
    echo -e "${RED}❌ 테스트 환경 격리 실패!${NC}"
    echo -e "${RED}   $FAILURES 개의 보안 위험이 발견되었습니다.${NC}"
    echo -e "${RED}   위험을 해결한 후 다시 실행하세요.${NC}"
    exit 1
fi

echo "=========================================="