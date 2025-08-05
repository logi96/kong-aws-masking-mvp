# Phase 3 계획: Claude Code SDK와 Kong Gateway 프록시 통합

**작성일**: 2025-01-29  
**프로젝트**: nginx-kong-claude-enterprise2  
**단계**: Phase 3 - 프록시 체인 구성 및 테스트

## 🎯 목표

Claude Code SDK가 Nginx와 Kong을 거쳐 Claude API와 통신하도록 구성하고, AWS 리소스 마스킹/언마스킹이 정상 작동하는지 검증

## 📐 아키텍처

```
Claude Code SDK Container
    ↓ [HTTP_PROXY=http://nginx:8082]
    ↓ [ANTHROPIC_BASE_URL=http://nginx:8082/v1]
Nginx (port 8082)
    ↓ [/v1/* → Kong으로 라우팅]
Kong Gateway (port 8010)
    ↓ [AWS 리소스 마스킹 처리]
    ↓ [마스킹된 데이터]
Claude API (https://api.anthropic.com)
```

## 📋 작업 계획

### Phase 3 Step 7: 프록시 환경 변수 추가
**담당**: infrastructure-engineer

#### 작업 내용:
1. **Claude Code SDK 환경 변수 설정**
   ```yaml
   environment:
     - HTTP_PROXY=http://nginx:8082
     - ANTHROPIC_BASE_URL=http://nginx:8082/v1
     - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
   ```

2. **Nginx 프록시 설정 수정**
   - `/v1/*` 경로를 Kong으로 라우팅
   - 적절한 헤더 설정 (Host: api.anthropic.com)

3. **Kong 서비스 정의**
   - Upstream: https://api.anthropic.com
   - AWS Masker 플러그인 활성화

4. **Docker 네트워크 검증**
   - 모든 서비스가 같은 네트워크에 있는지 확인
   - 서비스 간 통신 테스트

### Phase 3 Step 8: 프록시 통합 테스트
**담당**: kong-integration-validator

#### 테스트 시나리오:
1. **기본 연결 테스트**
   - Claude Code SDK → Nginx → Kong → Claude API 연결 확인
   - 응답 시간 측정

2. **AWS 리소스 마스킹 테스트**
   - EC2 인스턴스 ID 마스킹
   - S3 버킷 이름 마스킹
   - RDS 인스턴스 마스킹
   - 기타 50개 패턴 테스트

3. **언마스킹 검증**
   - 마스킹된 리소스가 올바르게 복원되는지 확인
   - Redis 저장/조회 확인

4. **에러 처리 테스트**
   - 잘못된 요청 처리
   - 네트워크 오류 시나리오
   - 타임아웃 처리

## 🔑 주요 설정 파일

### 1. docker-compose.yml (claude-code-sdk 서비스)
```yaml
claude-code-sdk:
  environment:
    - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    - HTTP_PROXY=http://nginx:8082
    - ANTHROPIC_BASE_URL=http://nginx:8082/v1
    - NO_PROXY=localhost,127.0.0.1
```

### 2. nginx/conf.d/claude-proxy.conf
```nginx
server {
    listen 8082;
    
    location /v1/ {
        proxy_pass http://kong:8010/;
        proxy_set_header Host api.anthropic.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

### 3. kong/kong.yml
```yaml
services:
  - name: claude-api
    url: https://api.anthropic.com
    routes:
      - name: claude-route
        paths:
          - /
    plugins:
      - name: aws-masker
        config:
          enable_masking: true
          enable_unmasking: true
```

## ✅ 성공 기준

1. **프록시 체인 작동**
   - Claude Code SDK의 요청이 Nginx를 거쳐 Kong으로 전달
   - Kong이 Claude API로 요청 전달 및 응답 수신

2. **마스킹 기능 검증**
   - 50개 AWS 리소스 패턴 모두 마스킹됨
   - 응답에서 마스킹된 리소스가 올바르게 복원됨

3. **성능 요구사항**
   - 추가 지연시간 < 100ms
   - 에러율 < 1%

4. **로깅 및 모니터링**
   - 모든 요청/응답 로깅
   - 마스킹 이벤트 추적
   - 에러 로그 수집

## 📊 테스트 보고서 요구사항

- 위치: `/tests/test-report/proxy-integration-test-001.md`
- 포함 내용:
  - 프록시 체인 연결 테스트 결과
  - 50개 AWS 패턴 마스킹 테스트 결과
  - 성능 메트릭
  - 발견된 이슈 및 해결 방안

## 🚀 예상 일정

- Step 7: 2-3시간 (인프라 설정)
- Step 8: 3-4시간 (통합 테스트)
- 전체: 5-7시간

---

**상태**: 계획 수립 완료  
**다음 단계**: Phase 3 Step 7 실행