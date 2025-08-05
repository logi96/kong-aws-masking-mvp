#!/bin/bash

# Kong 실제 설치 모니터링 스크립트
set -euo pipefail

INSTANCE_ID="i-fa2980469c3b0f536"
INSTANCE_IP="10.0.1.6"
REPORT_FILE="/tmp/kong-actual-install-monitor-$(date +%Y%m%d_%H%M%S).md"

echo "==============================================="
echo "Kong 실제 설치 모니터링 시작"
echo "Instance ID: $INSTANCE_ID"
echo "Instance IP: $INSTANCE_IP"
echo "모니터링 시간: $(date)"
echo "==============================================="

# 모니터링 보고서 초기화
echo "# Kong 실제 설치 모니터링 보고서" > $REPORT_FILE
echo "**모니터링 시간:** $(date)" >> $REPORT_FILE
echo "**Instance ID:** $INSTANCE_ID" >> $REPORT_FILE
echo "**Instance IP:** $INSTANCE_IP" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 함수: 포트 체크
check_port() {
    local port=$1
    local service_name=$2
    echo "🔍 $service_name 포트 $port 체크 중..."
    
    if timeout 10 bash -c "</dev/tcp/$INSTANCE_IP/$port" 2>/dev/null; then
        echo "✅ $service_name (포트 $port): 응답"
        echo "- ✅ **$service_name (포트 $port)**: 응답" >> $REPORT_FILE
        return 0
    else
        echo "❌ $service_name (포트 $port): 무응답"
        echo "- ❌ **$service_name (포트 $port)**: 무응답" >> $REPORT_FILE
        return 1
    fi
}

# 함수: HTTP 헬스체크
check_http() {
    local url=$1
    local service_name=$2
    echo "🔍 $service_name HTTP 헬스체크 중..."
    
    if curl -f -s --connect-timeout 10 "$url" > /dev/null 2>&1; then
        echo "✅ $service_name HTTP: 정상"
        echo "- ✅ **$service_name HTTP**: 정상" >> $REPORT_FILE
        return 0
    else
        echo "❌ $service_name HTTP: 실패"
        echo "- ❌ **$service_name HTTP**: 실패" >> $REPORT_FILE
        return 1
    fi
}

echo ""
echo "## 설치 후 서비스 상태 체크" >> $REPORT_FILE
echo ""

echo "1. 핵심 서비스 포트 체크 시작..."
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Kong Admin API (8001)
check_port 8001 "Kong Admin API" && ((PASSED_CHECKS++)) || true
((TOTAL_CHECKS++))

# Kong Proxy (8010)  
check_port 8010 "Kong Proxy" && ((PASSED_CHECKS++)) || true
((TOTAL_CHECKS++))

# Nginx Proxy (8082)
check_port 8082 "Nginx Proxy" && ((PASSED_CHECKS++)) || true
((TOTAL_CHECKS++))

# Redis (6379)
check_port 6379 "Redis" && ((PASSED_CHECKS++)) || true
((TOTAL_CHECKS++))

echo ""
echo "2. HTTP 헬스체크 시작..."

# Kong Admin API 헬스체크
check_http "http://$INSTANCE_IP:8001/status" "Kong Admin API" && ((PASSED_CHECKS++)) || true
((TOTAL_CHECKS++))

# Nginx 헬스체크
check_http "http://$INSTANCE_IP:8082/health" "Nginx Proxy" && ((PASSED_CHECKS++)) || true
((TOTAL_CHECKS++))

echo ""
echo "==============================================="
echo "설치 모니터링 결과 요약"
echo "==============================================="
echo "✅ 성공: $PASSED_CHECKS/$TOTAL_CHECKS"
echo "❌ 실패: $((TOTAL_CHECKS - PASSED_CHECKS))/$TOTAL_CHECKS"

# 결과를 보고서에 추가
echo "" >> $REPORT_FILE
echo "## 모니터링 결과 요약" >> $REPORT_FILE
echo "- **총 체크:** $TOTAL_CHECKS" >> $REPORT_FILE
echo "- **성공:** $PASSED_CHECKS" >> $REPORT_FILE
echo "- **실패:** $((TOTAL_CHECKS - PASSED_CHECKS))" >> $REPORT_FILE
echo "- **성공률:** $(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%" >> $REPORT_FILE

if [[ $PASSED_CHECKS -eq $TOTAL_CHECKS ]]; then
    echo ""
    echo "🎉 모든 서비스가 정상적으로 설치되고 실행 중입니다!"
    echo "📋 상세 보고서: $REPORT_FILE"
    echo "**최종 판정:** ✅ **실제 설치 스크립트 완전 성공**" >> $REPORT_FILE
    exit 0
elif [[ $PASSED_CHECKS -gt $((TOTAL_CHECKS / 2)) ]]; then
    echo ""
    echo "⚠️  일부 서비스는 실행 중이지만 완전하지 않습니다."
    echo "📋 상세 보고서: $REPORT_FILE"
    echo "**최종 판정:** ⚠️ **부분 성공 - 추가 검증 필요**" >> $REPORT_FILE
    exit 1
else
    echo ""
    echo "❌ 설치가 실패했거나 아직 진행 중일 수 있습니다."
    echo "📋 상세 보고서: $REPORT_FILE"  
    echo "**최종 판정:** ❌ **설치 실패 또는 진행 중**" >> $REPORT_FILE
    exit 2
fi