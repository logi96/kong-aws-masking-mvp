# 1. 문제 분석 및 솔루션 개요

## 1.1 현재 시스템의 문제점

### 1.1.1 보안 강제의 한계

현재 Kong AWS Masker 시스템은 다음과 같은 구조로 동작합니다:

```javascript
// 현재 상황 (backend/.env)
CLAUDE_API_URL=http://kong:8000/claude-proxy/v1/messages

// Backend 코드 (claudeService.js)
this.claudeApiUrl = process.env.CLAUDE_API_URL || 'https://api.anthropic.com/v1/messages';
```

**문제점:**
1. **개발자 우회 가능**: 환경변수를 무시하고 직접 호출 가능
2. **실수 가능성**: 새로운 외부 API 추가 시 Kong 설정 누락
3. **보안 정책 비강제성**: 코드 리뷰에만 의존

### 1.1.2 확장성 문제

```yaml
# 현재 Kong 설정 (kong.yml)
services:
  - name: claude-api-service
    url: https://api.anthropic.com/v1/messages
    
routes:
  - name: claude-proxy
    service: claude-api-service
    paths:
      - /claude-proxy/v1/messages
```

**문제점:**
1. **수동 설정**: 새 외부 API마다 Kong 설정 추가 필요
2. **Backend 코드 수정**: 각 API별로 환경변수 설정 필요
3. **관리 복잡성**: API 증가에 따른 설정 파일 복잡도 증가

### 1.1.3 실제 보안 위험 시나리오

```javascript
// 개발자가 실수로 또는 의도적으로 작성한 코드
async function fetchDataDirectly() {
  // Kong을 우회하여 직접 호출
  const response = await axios.post('https://api.openai.com/v1/chat/completions', {
    messages: [{
      role: 'user',
      content: `Analyze our AWS infrastructure: ${AWS_ACCOUNT_ID}, ${EC2_INSTANCES}`
    }]
  });
  
  // 민감한 AWS 정보가 마스킹 없이 외부로 유출됨!
}
```

## 1.2 Envoy + Kong 솔루션 개요

### 1.2.1 핵심 아이디어

```
Backend App → [iptables 강제] → Envoy Sidecar → Kong Gateway → External APIs
                                      ↓                ↓
                              트래픽 가로채기    데이터 마스킹
```

### 1.2.2 주요 구성 요소

1. **Envoy Proxy (Sidecar)**
   - 투명한 트래픽 가로채기
   - 원본 호스트 정보 보존
   - Kong으로 라우팅

2. **iptables 규칙**
   - 네트워크 레벨에서 트래픽 리다이렉션
   - 물리적 우회 불가능

3. **Kong Dynamic Router 플러그인**
   - 동적 upstream 라우팅
   - 기존 AWS Masker 통합
   - 중앙화된 보안 정책

## 1.3 기대 효과

### 1.3.1 보안 강화

| 항목 | 현재 | 개선 후 |
|------|------|---------|
| 우회 가능성 | 가능 | 불가능 (물리적 차단) |
| 보안 정책 강제 | 선택적 | 강제적 |
| 민감 정보 유출 위험 | 높음 | 매우 낮음 |

### 1.3.2 운영 효율성

| 항목 | 현재 | 개선 후 |
|------|------|---------|
| 새 API 추가 시간 | 2-3시간 | 5분 (Kong 설정만) |
| Backend 코드 수정 | 필요 | 불필요 |
| 설정 관리 복잡도 | API 수에 비례 | 일정 |

### 1.3.3 ROI 분석

**투자 비용:**
- 개발: 5주 (2명)
- 학습: 1주 (팀 전체)
- 인프라: 추가 비용 없음 (Envoy는 경량)

**예상 이익:**
- 보안 사고 예방: 잠재적 수억원 손실 방지
- 운영 효율: 월 20시간 절감
- 개발 생산성: 새 API 통합 시간 90% 감소

## 1.4 솔루션 선택 근거

### 1.4.1 대안 비교

| 솔루션 | 보안 강제 | 복잡성 | 비용 | 기존 호환성 |
|--------|-----------|--------|------|-------------|
| 현재 방식 | ❌ | ✅ | ✅ | ✅ |
| DNS 스푸핑 | ⚠️ | ⚠️ | ✅ | ❌ |
| Istio | ✅ | ❌ | ❌ | ⚠️ |
| **Envoy + Kong** | ✅ | ✅ | ✅ | ✅ |

### 1.4.2 Envoy + Kong 선택 이유

1. **실용성**: 필요한 기능만 구현
2. **호환성**: 기존 Kong 인프라 100% 재사용
3. **단순성**: Istio 대비 50% 적은 컴포넌트
4. **제어권**: 각 컴포넌트 독립적 관리 가능

## 1.5 구현 범위

### 1.5.1 포함 사항

✅ Envoy Sidecar 패턴 구현
✅ iptables 기반 트래픽 리다이렉션
✅ Kong Dynamic Router 플러그인
✅ 기존 AWS Masker 통합
✅ 모니터링 및 로깅

### 1.5.2 제외 사항 (오버스펙 방지)

❌ Service Mesh 전체 구현
❌ mTLS (1단계에서는 제외)
❌ 복잡한 트래픽 정책
❌ 자동 Sidecar 주입
❌ Control Plane 구현

## 1.6 성공 기준

1. **보안**: 모든 외부 API 호출이 Kong 경유 (100%)
2. **성능**: 추가 레이턴시 < 3ms
3. **안정성**: 99.9% 가용성
4. **운영성**: 새 API 추가 시간 < 10분

## 1.7 리스크 및 완화 방안

| 리스크 | 영향도 | 완화 방안 |
|--------|--------|-----------|
| Envoy 학습 곡선 | 중 | 팀 교육 및 상세 문서 제공 |
| 디버깅 복잡성 증가 | 중 | 로깅 강화 및 추적 도구 구축 |
| 초기 성능 이슈 | 낮 | 부하 테스트 및 최적화 |

## 1.8 다음 단계

이 문서를 읽은 후 [아키텍처 설계](02-architecture-design.md)를 참조하여 상세 기술 구조를 이해하세요.