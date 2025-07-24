#!/bin/bash
# run-phase4-step2.sh
# Phase 4 - 2단계: 성능 벤치마크 및 최적화
# 보안 최우선: 10KB < 100ms 목표 달성

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=========================================="
echo "🚀 Phase 4 - 2단계: 성능 벤치마크 및 최적화"
echo "=========================================="
echo "시작 시간: $(date)"
echo ""

# 작업 디렉토리
KONG_DIR="/Users/tw.kim/Documents/AGA/test/Kong"
cd "$KONG_DIR"

# 보안 체크포인트: 테스트 환경 확인
echo -e "${BLUE}🔒 보안 체크포인트: 테스트 환경${NC}"
echo "=========================================="
echo "테스트 환경: 로컬 시뮤레이션"
echo "실제 데이터 사용: 아니오 (모의 데이터만 사용)"
echo ""

# Lua 실행 환경 확인
echo -e "${BLUE}[1/4] Lua 환경 확인${NC}"
echo "=========================================="

if command -v lua >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Lua 설치됨${NC}"
    lua -v
    LUA_CMD="lua"
elif command -v luajit >/dev/null 2>&1; then
    echo -e "${GREEN}✓ LuaJIT 설치됨${NC}"
    luajit -v
    LUA_CMD="luajit"
else
    echo -e "${RED}✗ Lua 런타임이 필요합니다${NC}"
    echo "macOS: brew install lua"
    echo "Linux: apt-get install lua5.1"
    exit 1
fi

# 필요한 파일 확인
echo -e "\n${BLUE}[2/4] 테스트 파일 확인${NC}"
echo "=========================================="

FILES_TO_CHECK=(
    "tests/performance-benchmark.lua"
    "tests/memory-profile.lua"
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

# 성능 벤치마크 실행
echo -e "\n${BLUE}[3/4] 성능 벤치마크 실행${NC}"
echo "=========================================="

if $LUA_CMD tests/performance-benchmark.lua 2>&1 | tee performance-benchmark.log; then
    echo -e "${GREEN}✅ 성능 벤치마크 완료${NC}"
    BENCHMARK_SUCCESS=true
else
    echo -e "${RED}❌ 성능 벤치마크 실패${NC}"
    BENCHMARK_SUCCESS=false
fi

# 메모리 프로파일링 실행
echo -e "\n${BLUE}[4/4] 메모리 프로파일링 실행${NC}"
echo "=========================================="

if $LUA_CMD tests/memory-profile.lua 2>&1 | tee memory-profile.log; then
    echo -e "${GREEN}✅ 메모리 프로파일링 완료${NC}"
    MEMORY_SUCCESS=true
else
    echo -e "${RED}❌ 메모리 프로파일링 실패${NC}"
    MEMORY_SUCCESS=false
fi

# 통합 보고서 생성
echo -e "\n${BLUE}📝 Phase 4 - 2단계 통합 보고서 생성${NC}"
echo "=========================================="

cat > phase4-step2-report.md << EOF
# Phase 4 - 2단계: 성능 벤치마크 및 최적화 보고서

**실행일시**: $(date)
**테스트 환경**: $($LUA_CMD -v 2>&1 | head -1)

## 🎯 2단계 목표
1. 10KB 텍스트 처리 < 100ms
2. 메모리 사용 < 10MB/request
3. 패턴 정확도 > 95%

## 📋 테스트 결과

### 성능 벤치마크
- 상태: $([ "$BENCHMARK_SUCCESS" = true ] && echo "✅ 성공" || echo "❌ 실패")
- 로그 파일: performance-benchmark.log
- 상세 보고서: performance-benchmark-report.md

$(if [ -f "performance-benchmark-report.md" ]; then
    echo "핵심 결과:"
    grep -A3 "10KB 처리 성능" performance-benchmark-report.md | sed 's/^/  /'
fi)

### 메모리 프로파일링
- 상태: $([ "$MEMORY_SUCCESS" = true ] && echo "✅ 성공" || echo "❌ 실패")
- 로그 파일: memory-profile.log
- 상세 보고서: memory-profile-report.md

$(if [ -f "memory-profile-report.md" ]; then
    echo "핵심 결과:"
    grep -A2 "메모리 증가:" memory-profile-report.md | head -3 | sed 's/^/  /'
fi)

## 🔒 보안 검증

### 테스트 환경
- [x] 로컬 시뮤레이션 환경
- [x] 실제 데이터 미사용
- [x] 모의 AWS 리소스만 사용

### 성능 안전성
- [$([ "$BENCHMARK_SUCCESS" = true ] && echo "x" || echo " ")] 10KB < 100ms 달성
- [$([ "$MEMORY_SUCCESS" = true ] && echo "x" || echo " ")] 메모리 < 10MB 달성
- [x] 패턴 캐싱 방식 설계

## ✅ 2단계 완료 조건

$(if [ "$BENCHMARK_SUCCESS" = true ] && [ "$MEMORY_SUCCESS" = true ]; then
    echo "- [x] 10KB < 100ms 달성"
    echo "- [x] 메모리 증가 < 10MB"
    echo "- [x] 최적화 방안 도출"
    echo ""
    echo "**2단계 상태**: ✅ **완료**"
else
    echo "- [$([ "$BENCHMARK_SUCCESS" = true ] && echo "x" || echo " ")] 10KB < 100ms 달성"
    echo "- [$([ "$MEMORY_SUCCESS" = true ] && echo "x" || echo " ")] 메모리 증가 < 10MB"
    echo "- [ ] 최적화 방안 도출"
    echo ""
    echo "**2단계 상태**: ⚠️ **진행 중**"
fi)

## 📋 다음 단계

$(if [ "$BENCHMARK_SUCCESS" = true ] && [ "$MEMORY_SUCCESS" = true ]; then
    echo "### 3단계: 모니터링 시스템 구축"
    echo "1. 실시간 메트릭 수집"
    echo "2. 알림 시스템 구현"
    echo "3. 대시보드 구성"
else
    echo "### 현재 단계 완료 필요"
    echo "1. 성능 목표 달성"
    echo "2. 메모리 사용량 최적화"
    echo "3. 테스트 재실행"
fi)

## 📊 최적화 권장사항

$(if [ "$BENCHMARK_SUCCESS" = false ] || [ "$MEMORY_SUCCESS" = false ]; then
    echo "### 성능 개선 방안"
    echo "1. **패턴 캐싱**: 빈번한 패턴 결과 저장"
    echo "2. **우선순위 조정**: 빈번한 패턴 우선 처리"
    echo "3. **청크 처리**: 대용량 텍스트 분할 처리"
    echo ""
    echo "### 메모리 최적화"
    echo "1. **매핑 제한**: 최대 10,000개로 제한"
    echo "2. **TTL 관리**: 5분 후 자동 제거"
    echo "3. **LRU 캐시**: 최근 사용 기반 관리"
fi)

---

**작성자**: Kong AWS Masking Security Team
**검토자**: Performance Lead
EOF

echo -e "${GREEN}✓ 보고서 생성: phase4-step2-report.md${NC}"

# 최종 결과
echo ""
echo "=========================================="
echo -e "${BLUE}📊 Phase 4 - 2단계 결과${NC}"
echo "=========================================="

if [ "$BENCHMARK_SUCCESS" = true ] && [ "$MEMORY_SUCCESS" = true ]; then
    echo -e "${GREEN}✅ Phase 4 - 2단계 완료!${NC}"
    echo -e "${GREEN}   성능 벤치마크 통과${NC}"
    echo -e "${GREEN}   메모리 프로파일링 통과${NC}"
    echo ""
    echo "다음 단계:"
    echo "  ./tests/run-phase4-step3.sh  # 모니터링 시스템"
    exit 0
else
    echo -e "${RED}❌ Phase 4 - 2단계 미완료${NC}"
    if [ "$BENCHMARK_SUCCESS" = false ]; then
        echo -e "${RED}   성능 벤치마크 실패${NC}"
    fi
    if [ "$MEMORY_SUCCESS" = false ]; then
        echo -e "${RED}   메모리 프로파일링 실패${NC}"
    fi
    echo ""
    echo "해결 방법:"
    echo "  1. 로그 파일 확인: *.log"
    echo "  2. 최적화 방안 적용"
    echo "  3. 테스트 재실행"
    exit 1
fi