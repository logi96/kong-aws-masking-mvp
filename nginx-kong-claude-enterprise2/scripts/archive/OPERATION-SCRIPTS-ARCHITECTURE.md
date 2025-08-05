# Kong AWS Masker 운영 스크립트 아키텍처

## 스크립트 구조 설계

### 1. 시작/종료 스크립트
```
scripts/
├── start.sh              # 전체 시스템 시작
├── stop.sh               # 전체 시스템 종료
├── restart.sh            # 재시작 (stop + start)
└── graceful-restart.sh   # 무중단 재시작
```

### 2. 헬스체크 스크립트
```
scripts/
├── health-check.sh       # 통합 헬스체크
├── health-check-kong.sh  # Kong 전용 헬스체크
├── health-check-redis.sh # Redis 전용 헬스체크
└── health-check-nginx.sh # Nginx 전용 헬스체크
```

### 3. 모니터링 및 로깅
```
scripts/
├── monitor-realtime.sh   # 실시간 모니터링
├── log-collector.sh      # 로그 수집/압축
└── metrics-exporter.sh   # 메트릭 내보내기
```

### 4. 백업 및 복구
```
scripts/
├── backup-all.sh         # 전체 백업
├── restore-all.sh        # 전체 복구
└── validate-backup.sh    # 백업 검증
```

## 운영 스크립트 요구사항

### 시작 스크립트 (start.sh)
1. **사전 검증**
   - Docker/Docker Compose 설치 확인
   - 필수 환경변수 검증
   - 포트 충돌 검사
   - 디스크 공간 확인

2. **시작 순서**
   - Redis 시작 (데이터 저장소)
   - Kong 시작 (API Gateway)
   - Nginx 시작 (프록시)
   - Backend 시작 (애플리케이션)

3. **시작 후 검증**
   - 각 서비스 헬스체크
   - 네트워크 연결 테스트
   - 플러그인 로드 확인

### 종료 스크립트 (stop.sh)
1. **graceful shutdown**
   - 진행 중인 요청 완료 대기
   - 연결 드레이닝
   - 데이터 플러시

2. **종료 순서**
   - Backend 종료
   - Nginx 종료
   - Kong 종료
   - Redis 종료 (데이터 저장 확인)

### 헬스체크 스크립트 (health-check.sh)
1. **서비스 레벨 체크**
   - 프로세스 상태
   - 포트 리스닝 상태
   - API 응답 테스트

2. **통합 테스트**
   - End-to-end 플로우 테스트
   - 마스킹/언마스킹 동작 확인
   - 응답시간 측정

3. **리소스 모니터링**
   - CPU/메모리 사용량
   - 디스크 I/O
   - 네트워크 대역폭

## 스크립트 공통 기능

### 로깅 표준
```bash
# 로그 레벨
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# 로그 함수
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
```

### 에러 처리
```bash
# 에러 발생 시 즉시 종료
set -euo pipefail

# 에러 트랩
trap 'log_error "Script failed at line $LINENO"' ERR
```

### 환경변수 관리
```bash
# 환경변수 파일 로드
load_env() {
    if [ -f .env ]; then
        export $(cat .env | grep -v '^#' | xargs)
    fi
}
```

## 메트릭 정의

### 핵심 메트릭
1. **가용성 메트릭**
   - Uptime percentage
   - Service availability
   - Health check success rate

2. **성능 메트릭**
   - Request latency (p50, p95, p99)
   - Throughput (req/sec)
   - Error rate

3. **리소스 메트릭**
   - CPU utilization
   - Memory usage
   - Network I/O
   - Disk usage

### 비즈니스 메트릭
1. **마스킹 성능**
   - Masking success rate
   - Pattern match accuracy
   - Processing time per pattern

2. **보안 메트릭**
   - Failed authentication attempts
   - Masked data volume
   - Security incident count

## 자동화 및 알림

### 자동 복구
```bash
# 서비스 다운 감지 시 자동 재시작
auto_recover() {
    local service=$1
    if ! health_check_$service; then
        log_warn "Service $service is down, attempting restart"
        restart_service $service
    fi
}
```

### 알림 시스템
- 서비스 다운 알림
- 성능 임계값 초과 알림
- 보안 이벤트 알림
- 리소스 부족 알림

## 스크립트 테스트 전략

### 단위 테스트
- 개별 함수 테스트
- 에러 케이스 처리 검증
- 환경변수 파싱 테스트

### 통합 테스트
- 전체 시작/종료 시나리오
- 장애 복구 시나리오
- 무중단 재시작 검증

### 부하 테스트
- 동시 요청 처리
- 리소스 한계 테스트
- 장시간 안정성 테스트