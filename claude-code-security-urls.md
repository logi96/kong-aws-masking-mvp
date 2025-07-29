# Claude Code 보안 정책을 위한 외부 URL 목록

## 📋 Executive Summary

Claude Code가 정상적으로 작동하기 위해서는 다음 URL들에 대한 접근이 필요합니다. 회사 보안 정책(방화벽, 프록시 등)에서 이 URL들을 허용해야 합니다.

## 🔗 필수 URL 목록

### 1. 핵심 서비스 (필수)
```
https://api.anthropic.com/*
- 주요 엔드포인트: https://api.anthropic.com/v1/messages
- 설명: Claude AI 모델 API 호출
- 포트: 443 (HTTPS)
```

### 2. 텔레메트리 및 모니터링 (필수)
```
https://statsig.anthropic.com/*
- 설명: 사용량 메트릭 및 텔레메트리 데이터
- 포트: 443 (HTTPS)
```

### 3. 에러 리포팅 (필수)
```
https://*.sentry.io/*
- 설명: 에러 추적 및 디버깅
- 포트: 443 (HTTPS)
```

### 4. 문서 및 지원 (권장)
```
https://docs.anthropic.com/*
- 설명: Claude Code 공식 문서
- 포트: 443 (HTTPS)

https://github.com/anthropics/claude-code/*
- 설명: 이슈 리포팅 및 피드백
- 포트: 443 (HTTPS)
```

### 5. 웹 검색 및 콘텐츠 접근 (선택적)
```
웹 검색 기능 사용 시:
- 모든 HTTPS 웹사이트 (*)
- 설명: WebSearch 및 WebFetch 기능
- 참고: 특정 도메인으로 제한 가능
```

## 🔒 보안 설정 권장사항

### 1. 최소 권한 원칙
```yaml
# 필수 도메인만 허용
allowlist:
  - api.anthropic.com
  - statsig.anthropic.com
  - *.sentry.io
```

### 2. 프록시 설정 예시
```bash
# 환경 변수 설정
export HTTPS_PROXY=http://corporate-proxy:8080
export NO_PROXY=localhost,127.0.0.1,internal-services

# Claude Code 특정 도메인 허용
proxy_allowlist="api.anthropic.com,statsig.anthropic.com,sentry.io"
```

### 3. 방화벽 규칙
```
# Outbound HTTPS (443) 허용 필요
ALLOW TCP 443 TO api.anthropic.com
ALLOW TCP 443 TO statsig.anthropic.com
ALLOW TCP 443 TO *.sentry.io
```

## ⚠️ 중요 참고사항

### 1. WebSearch/WebFetch 기능
- 이 기능들을 사용하려면 광범위한 웹 접근이 필요합니다
- 보안이 중요한 환경에서는 비활성화 고려
- 또는 특정 도메인 목록으로 제한

### 2. 지역별 제한
- WebSearch는 미국에서만 사용 가능
- 다른 지역에서는 자동으로 비활성화됨

### 3. 인증 정보
- API 키는 환경 변수로 관리
- 프록시를 통과할 때 헤더 보존 필요

## 📝 검증 방법

### 1. 연결 테스트
```bash
# API 연결 테스트
curl -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'

# 텔레메트리 연결 테스트
curl -I https://statsig.anthropic.com

# 에러 리포팅 연결 테스트
curl -I https://sentry.io
```

### 2. Claude Code 내부 테스트
```bash
# Claude Code 실행 후
claude --test-connection
```

## 🎯 결론

**최소 필수 URL**:
- `https://api.anthropic.com/*`
- `https://statsig.anthropic.com/*`  
- `https://*.sentry.io/*`

이 세 도메인만 허용해도 Claude Code의 핵심 기능은 작동합니다. WebSearch/WebFetch 기능이 필요한 경우 추가적인 웹 접근 권한이 필요합니다.

---
*작성일: 2025-07-26*  
*용도: 기업 보안 정책 설정*