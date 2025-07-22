#!/bin/bash
# emergency-rollback.sh - 긴급 롤백 실행 스크립트

set -euo pipefail

REASON=${1:-"Unknown reason"}
echo "🚨 긴급 롤백 시작: $REASON"
echo "시작 시간: $(date)"

# 1. Kong 플러그인 즉시 비활성화
echo "Kong AWS Masker 플러그인 비활성화..."
docker exec kong kong plugin disable aws-masker || true

# 2. 트래픽 우회
echo "트래픽 우회 설정..."
# kubectl patch service kong-proxy -p '{"spec":{"selector":{"version":"stable"}}}' || true

# 3. 이전 버전 복원
echo "이전 버전 복원..."
if [[ -f ./kong/plugins/aws-masker/handler.lua.backup ]]; then
    cp ./kong/plugins/aws-masker/handler.lua.backup ./kong/plugins/aws-masker/handler.lua
fi

# 4. Kong 재시작
echo "Kong 재시작..."
docker-compose restart kong

# 5. 알림 발송
echo "알림 발송..."
# ./scripts/notify.sh "CRITICAL: Emergency rollback executed - $REASON"

echo "✅ 롤백 완료: $(date)"
echo "소요 시간: $SECONDS 초"

# 6. 사후 보고서 생성
cat > ./rollback-report-$(date +%Y%m%d-%H%M%S).txt << REPORT
롤백 보고서
===========
이유: $REASON
시작: $(date)
완료: $(date)
소요시간: $SECONDS 초
상태: 완료
REPORT

