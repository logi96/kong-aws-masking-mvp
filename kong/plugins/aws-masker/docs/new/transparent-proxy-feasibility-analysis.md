# Kong 투명 프록시 구현 타당성 분석 보고서

## 📋 Executive Summary

**결론**: "Backend API의 모든 외부 호출을 Kong API Gateway를 통해 투명하게 가로채고 보안 마스킹을 강제"하는 것은 **부분적으로 가능**하지만, 여러 기술적 제약과 보안 위험이 존재합니다.

### 핵심 발견사항
1. **기술적 가능성**: Docker 환경에서 DNS 오버라이드, HTTP 프록시, iptables 리다이렉션 등 여러 방법으로 구현 가능
2. **보안 문제**: SSL/TLS 인증서 검증 우회가 필요하여 중대한 보안 위험 발생
3. **현재 구조의 한계**: Backend가 Kong을 우회하여 직접 Claude API를 호출하는 구조
4. **권장 방안**: 투명 프록시보다는 명시적 프록시 패턴이 더 안전하고 실용적

## 🔍 현재 아키텍처 분석

### 1. 현재 구조
```
Backend API (3000) → 직접 호출 → api.anthropic.com
     ↓
  Kong (8000) ← 우회됨 (사용되지 않음)
```

### 2. 발견된 문제점
- **Backend의 직접 호출**: `claudeService.js`에서 `https://api.anthropic.com/v1/messages`를 직접 호출
- **Kong 우회**: Kong에 `anthropic-transparent` 라우트가 정의되어 있으나 사용되지 않음
- **마스킹 미적용**: aws-masker 플러그인이 transparent 라우트에 적용되지 않음

## 🛠️ 투명 프록시 구현 방법 분석

### 방법 1: DNS Override (권장도: ⭐⭐⭐)

#### 구현 방식
```yaml
# docker-compose.yml
services:
  backend:
    extra_hosts:
      - "api.anthropic.com:kong"
    environment:
      NODE_TLS_REJECT_UNAUTHORIZED: "0"  # 보안 위험!
```

#### 장점
- 구현이 간단함
- Backend 코드 수정 불필요
- Docker 네이티브 기능 활용

#### 단점
- **치명적 보안 위험**: SSL 인증서 검증 비활성화 필요
- Docker 네트워크 내에서만 작동
- Production 환경에서 사용 불가

### 방법 2: HTTP(S) Proxy (권장도: ⭐⭐)

#### 구현 방식
```yaml
# docker-compose.yml
services:
  backend:
    environment:
      HTTPS_PROXY: http://kong:8000
```

#### 장점
- 표준 프록시 메커니즘
- 대부분의 HTTP 클라이언트 지원

#### 단점
- HTTPS 터널링으로 인해 데이터 검사 불가
- CONNECT 메서드 처리의 복잡성
- Kong stream 모듈 설정 필요

### 방법 3: iptables Redirect (권장도: ⭐)

#### 구현 방식
```bash
iptables -t nat -A OUTPUT -p tcp -d api.anthropic.com --dport 443 \
  -j DNAT --to-destination ${KONG_IP}:8443
```

#### 장점
- 진정한 투명 프록시
- 애플리케이션 수정 불필요

#### 단점
- **보안 위험**: NET_ADMIN 권한 필요
- Linux 전용
- 컨테이너 보안 정책 위반
- 설정 복잡도 높음

## 🔐 보안 및 기술적 제약사항

### 1. SSL/TLS 문제
- **근본적 문제**: HTTPS 트래픽은 종단간 암호화되어 있어 중간에서 검사/수정 불가
- **해결책의 위험성**: SSL 인증서 검증 우회는 MITM 공격에 취약

### 2. 컨테이너 보안
- iptables 방식은 NET_ADMIN 권한 필요
- Production 환경에서 보안 정책 위반
- 컨테이너 격리 원칙 훼손

### 3. 운영 복잡도
- 투명 프록시는 디버깅과 트러블슈팅이 어려움
- 네트워크 문제 발생 시 원인 파악 복잡
- 모니터링 및 로깅 구현 어려움

## 💡 권장 솔루션: 명시적 프록시 패턴

### 1. Backend 환경변수 기반 라우팅
```javascript
// claudeService.js 수정
this.claudeApiUrl = process.env.KONG_PROXY_URL || 'https://api.anthropic.com/v1/messages';
```

```yaml
# docker-compose.yml
services:
  backend:
    environment:
      KONG_PROXY_URL: "http://kong:8000/claude-proxy/v1/messages"
```

### 2. 장점
- **보안**: SSL 인증서 검증 유지
- **명확성**: 트래픽 흐름이 명시적
- **유연성**: 환경별 설정 가능
- **디버깅**: 문제 추적 용이

### 3. 구현 단계
1. Backend 코드에서 환경변수 기반 URL 설정
2. Kong에 이미 정의된 `/claude-proxy` 라우트 활용
3. aws-masker 플러그인은 이미 적용되어 있음
4. 테스트 및 검증

## 📊 비교 분석

| 방식 | 보안성 | 구현 복잡도 | 운영 안정성 | Production 적합성 |
|------|--------|-------------|-------------|------------------|
| 투명 프록시 (DNS) | ⚠️ 낮음 | 낮음 | 중간 | ❌ 부적합 |
| 투명 프록시 (iptables) | ⚠️ 매우 낮음 | 높음 | 낮음 | ❌ 부적합 |
| 명시적 프록시 | ✅ 높음 | 낮음 | 높음 | ✅ 적합 |

## 🎯 최종 권고사항

### 1. 단기 (즉시 구현 가능)
- **명시적 프록시 패턴 채택**
- Backend 환경변수로 Kong 프록시 URL 설정
- 기존 Kong 라우트와 플러그인 활용

### 2. 중기 (선택적 개선)
- Service Mesh 패턴 검토 (Istio, Linkerd)
- mTLS를 통한 서비스 간 통신 보안 강화
- 중앙화된 트래픽 관리 및 모니터링

### 3. 장기 (아키텍처 진화)
- Zero Trust 네트워크 아키텍처
- Policy-based 트래픽 제어
- 완전한 observability 구현

## 📝 결론

투명 프록시를 통한 "모든 외부 호출 가로채기"는 기술적으로 가능하지만, 보안 위험과 운영 복잡도를 고려할 때 **권장하지 않습니다**. 

대신 **명시적 프록시 패턴**을 통해:
- ✅ 보안성 유지
- ✅ 구현 단순성
- ✅ 운영 안정성
- ✅ Production 준비성

을 모두 달성할 수 있습니다.

---
*작성일: 2025-07-26*  
*작성자: Infrastructure Analysis Team*