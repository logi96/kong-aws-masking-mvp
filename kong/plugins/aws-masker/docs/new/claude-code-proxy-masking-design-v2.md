# Claude Code 프록시 기반 민감정보 마스킹 시스템 설계문서 v2.0

## 1. 개요

### 1.1 배경
Claude Code는 Anthropic의 공식 CLI 도구로, 개발자들이 AI 어시스턴트와 상호작용하며 코드를 작성할 수 있게 해줍니다. 하지만 기업 환경에서는 내부 인프라 정보(IP 주소, AWS 리소스 ID 등)가 외부 API로 전송되는 것을 방지해야 합니다.

### 1.2 목적
- Claude Code가 Anthropic API로 전송하는 민감정보를 자동으로 마스킹
- 기존 Kong Gateway 인프라의 aws-masker 플러그인 활용
- Claude Code 공식 프록시 지원 기능을 통한 투명한 통합

### 1.3 핵심 원칙
- **단순성**: 복잡한 wrapper 없이 환경변수만으로 구현
- **공식 지원**: Claude Code의 공식 프록시 기능 활용
- **기존 인프라 재사용**: 이미 구현된 Kong aws-masker 플러그인 활용
- **무중단 적용**: Claude Code 사용자 경험 변화 없음

## 2. 아키텍처

### 2.1 시스템 구성도

```mermaid
graph LR
    subgraph "Developer Environment"
        CC[Claude Code CLI]
        ENV[Environment Variables]
    end
    
    subgraph "Kong Gateway (Port 8000)"
        KG[Kong Gateway]
        AM[aws-masker Plugin]
        RD[(Redis Cache)]
    end
    
    subgraph "External"
        API[Anthropic API<br/>api.anthropic.com]
    end
    
    CC -->|1. HTTPS Request| KG
    ENV -.->|ANTHROPIC_BASE_URL| CC
    KG -->|2. Apply Masking| AM
    AM <-->|3. Store Mappings| RD
    KG -->|4. HTTPS with Masked Data| API
    API -->|5. Response| KG
    KG -->|6. Unmask Response| CC
```

### 2.2 데이터 플로우

1. **요청 단계**:
   - Claude Code가 API 호출 시도
   - `ANTHROPIC_BASE_URL` 설정으로 Kong Gateway로 라우팅
   - Kong의 aws-masker 플러그인이 민감정보 마스킹
   - 마스킹된 요청을 Anthropic API로 전달

2. **응답 단계**:
   - Anthropic API 응답 수신
   - Kong이 마스킹된 ID를 원본으로 복원 (언마스킹)
   - 원본 데이터로 Claude Code에 응답

### 2.3 마스킹 대상

| 리소스 타입 | 패턴 예시 | 마스킹 결과 |
|------------|---------|------------|
| EC2 Instance | i-1234567890abcdef0 | AWS_EC2_001 |
| S3 Bucket | my-company-data-bucket | AWS_S3_BUCKET_001 |
| RDS Instance | prod-mysql-instance | AWS_RDS_001 |
| VPC | vpc-0123456789abcdef | AWS_VPC_001 |
| 내부 IP* | 10.0.1.100 | PRIVATE_IP_001 |

*내부 IP 마스킹은 현재 비활성화 상태 (필요시 활성화 가능)

## 3. 구현 방법

### 3.1 사전 요구사항

- Kong Gateway 3.x 이상 (현재: 3.7)
- aws-masker 플러그인 설치 완료
- Redis 7.x (마스킹 매핑 저장용)
- Claude Code 최신 버전

### 3.2 Kong Gateway 설정

#### 3.2.1 현재 Kong 라우트 구성
```yaml
# kong.yml (이미 구현됨)
routes:
  # Transparent proxy for api.anthropic.com
  - name: anthropic-transparent
    service: claude-api-service
    hosts:
      - api.anthropic.com
    paths:
      - /v1/messages
    methods:
      - POST
    strip_path: false
    preserve_host: false
    
plugins:
  # AWS Masker는 이미 적용됨
  - name: aws-masker
    route: anthropic-transparent
    config:
      use_redis: true
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
```

#### 3.2.2 추가 설정 (필요시)
```yaml
# LLM Gateway 모드를 위한 추가 라우트
routes:
  - name: claude-llm-gateway
    service: claude-api-service
    paths:
      - /v1/messages
    methods:
      - POST
    strip_path: false
```

### 3.3 Claude Code 설정

#### 3.3.1 방법 1: ANTHROPIC_BASE_URL 사용 (권장)

**Linux/macOS**:
```bash
# ~/.bashrc 또는 ~/.zshrc에 추가
export ANTHROPIC_BASE_URL=http://kong:8000

# Docker 환경
export ANTHROPIC_BASE_URL=http://host.docker.internal:8000

# 외부 접근
export ANTHROPIC_BASE_URL=https://your-kong-domain.com:8000
```

**Windows**:
```powershell
# 시스템 환경변수 설정
[System.Environment]::SetEnvironmentVariable(
    "ANTHROPIC_BASE_URL", 
    "http://kong:8000", 
    "User"
)
```

**Claude Code settings.json**:
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://kong:8000"
  }
}
```

#### 3.3.2 방법 2: HTTP_PROXY 사용 (대안)

```bash
# 프록시 설정
export HTTP_PROXY=http://kong:8000
export HTTPS_PROXY=http://kong:8000

# 인증이 필요한 경우
export HTTPS_PROXY=http://username:password@kong:8000
```

### 3.4 SSL/TLS 인증서 처리

#### 3.4.1 자체 서명 인증서 사용 시
```bash
# Kong의 인증서를 신뢰하도록 설정
export NODE_EXTRA_CA_CERTS=/path/to/kong-ca.crt
export SSL_CERT_FILE=/path/to/kong-ca.crt
```

#### 3.4.2 개발 환경에서 인증서 검증 비활성화
```bash
# 주의: 개발 환경에서만 사용
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

## 4. 운영 가이드

### 4.1 설정 검증

```bash
# 1. 환경변수 확인
echo $ANTHROPIC_BASE_URL

# 2. Kong 연결 테스트
curl -I http://kong:8000/v1/messages

# 3. Claude Code 테스트
claude "테스트 메시지"

# 4. 마스킹 동작 확인
docker logs kong | grep "aws-masker"
```

### 4.2 문제 해결

#### 문제: Claude Code가 Kong을 거치지 않음
```bash
# 해결방법 1: 환경변수 재설정
unset ANTHROPIC_API_KEY  # 기존 직접 연결 방지
export ANTHROPIC_BASE_URL=http://kong:8000

# 해결방법 2: Claude Code 재시작
killall claude
claude
```

#### 문제: SSL 인증서 오류
```bash
# 개발 환경 임시 해결
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Production 해결
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/kong-ca.crt
```

#### 문제: 마스킹이 작동하지 않음
```bash
# Kong 플러그인 상태 확인
curl http://kong:8001/plugins | jq '.data[] | select(.name=="aws-masker")'

# Redis 연결 확인
docker exec redis redis-cli ping
```

### 4.3 모니터링

```bash
# 마스킹 통계 확인
curl http://kong:8001/plugins/aws-masker/stats

# Redis 메모리 사용량
docker exec redis redis-cli info memory | grep used_memory_human

# Kong 로그 모니터링
tail -f /var/log/kong/access.log | grep "aws-masker"
```

## 5. 보안 고려사항

### 5.1 네트워크 보안
- Kong Gateway는 private 네트워크에 위치 권장
- 외부 접근 시 HTTPS 필수
- 방화벽에서 Kong 포트(8000) 접근 제어

### 5.2 인증 및 권한
- Kong에 API Key 또는 OAuth 플러그인 추가 고려
- Claude Code 사용자별 접근 제어
- 감사 로그 활성화

### 5.3 데이터 보호
- Redis 비밀번호 설정 필수
- 마스킹 매핑 데이터 주기적 정리 (TTL: 7일)
- 민감한 패턴 추가 시 보안 검토

## 6. 성능 최적화

### 6.1 현재 성능 지표
- 마스킹 처리 시간: < 100ms
- 메모리 사용량: < 256MB (Redis)
- 동시 처리: 100+ requests/sec

### 6.2 최적화 방법
```yaml
# Kong 성능 튜닝
environment:
  KONG_NGINX_WORKER_PROCESSES: 4
  KONG_MEM_CACHE_SIZE: 256m
  
# Redis 최적화
maxmemory-policy: allkeys-lru
maxmemory: 512mb
```

## 7. 마이그레이션 계획

### 7.1 단계별 적용

**Phase 1: 파일럿 (1주)**
- 개발팀 5-10명 대상 테스트
- 피드백 수집 및 문제 해결

**Phase 2: 점진적 확대 (2주)**
- 부서별 순차 적용
- 모니터링 강화

**Phase 3: 전사 적용 (1주)**
- 전체 개발자 대상 적용
- 문서화 완료

### 7.2 롤백 계획
```bash
# 즉시 롤백 방법
unset ANTHROPIC_BASE_URL
export ANTHROPIC_API_KEY=sk-ant-xxx  # 직접 연결로 복귀
```

## 8. FAQ

**Q: 기존 Claude Code 사용에 영향이 있나요?**
A: 없습니다. 환경변수만 설정하면 투명하게 작동합니다.

**Q: 성능 저하가 있나요?**
A: 약 50-100ms 지연이 추가되지만 체감하기 어려운 수준입니다.

**Q: 마스킹된 데이터를 확인할 수 있나요?**
A: Kong 관리자 API를 통해 마스킹 로그를 확인할 수 있습니다.

**Q: Private IP도 마스킹되나요?**
A: 현재는 비활성화되어 있으며, 필요시 patterns.lua에서 활성화 가능합니다.

## 9. 결론

Claude Code의 공식 프록시 지원 기능을 활용하면, 복잡한 wrapper 개발 없이 단순한 환경변수 설정만으로 민감정보 마스킹을 구현할 수 있습니다. 이는 기존 Kong 인프라를 그대로 활용하면서도 보안 요구사항을 충족하는 가장 효율적인 방법입니다.

---
*문서 버전: 2.0*  
*작성일: 2025-07-26*  
*작성자: Infrastructure Security Team*