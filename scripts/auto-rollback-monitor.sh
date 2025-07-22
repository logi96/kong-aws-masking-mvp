#!/bin/bash
# auto-rollback-monitor.sh - 자동 롤백 모니터링

# 임계값 정의
ERROR_RATE_THRESHOLD=0.01  # 1%
LATENCY_THRESHOLD=100      # 100ms
MEMORY_THRESHOLD=95        # 95%

while true; do
    # 에러율 확인
    ERROR_RATE=$(curl -s http://localhost:9090/metrics | grep aws_masking_errors | awk '{print $2}')
    if (( $(echo "$ERROR_RATE > $ERROR_RATE_THRESHOLD" | bc -l) )); then
        ./scripts/emergency-rollback.sh "High error rate: $ERROR_RATE"
        break
    fi
    
    # 지연시간 확인
    LATENCY=$(curl -s http://localhost:9090/metrics | grep aws_masking_latency_p95 | awk '{print $2}')
    if (( $(echo "$LATENCY > $LATENCY_THRESHOLD" | bc -l) )); then
        ./scripts/emergency-rollback.sh "High latency: $LATENCY ms"
        break
    fi
    
    sleep 10
done
