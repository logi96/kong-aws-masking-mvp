# HTTPS 이슈 분석 - Claude Code 프록시의 핵심 문제

## 🔒 문제의 핵심

### 우리가 직면한 문제
1. **Claude Code → api.anthropic.com (HTTPS)**
   - End-to-end 암호화로 중간에서 내용을 볼 수 없음
   - Kong이 HTTPS 트래픽을 복호화하려면 api.anthropic.com의 정식 SSL 인증서 필요
   - 정식 인증서가 없으므로 MITM(Man-in-the-Middle) 불가능

2. **이전 시도의 실패 원인**
   - nginx proxy: SSL handshake 실패 (SNI 문제)
   - Kong transparent proxy: HTTPS 내용을 볼 수 없음
   - 자체 서명 인증서: Claude Code가 거부

## 🎯 claude-code-litellm의 해결 방법 분석

### 핵심 발견
```bash
# README.md에서
ANTHROPIC_BASE_URL=http://localhost:8082 claude
```

**중요**: `http://` (not `https://`)를 사용!

### 가능한 시나리오들

#### 시나리오 1: HTTP 로컬 프록시
- Claude Code가 HTTP로 로컬 프록시에 연결
- 로컬 프록시가 HTTPS로 실제 API 호출
- 장점: SSL 문제 회피
- 단점: Claude Code가 HTTP를 허용해야 함

#### 시나리오 2: 로컬 HTTPS with 자체 인증서
- 로컬 프록시가 자체 서명 인증서 사용
- Claude Code가 인증서 검증을 무시하도록 설정
- 또는 시스템 신뢰 저장소에 인증서 추가

## 🔍 검증해야 할 사항

1. **claude-code-litellm 서버가 HTTP/HTTPS 중 무엇을 사용하는가?**
2. **Claude Code가 실제로 HTTP 연결을 허용하는가?**
3. **HTTPS를 사용한다면 인증서는 어떻게 처리하는가?**

## 🚀 다음 단계

1. claude-code-litellm 서버 코드에서 HTTP/HTTPS 설정 확인
2. 실제로 Claude Code가 HTTP BASE_URL을 수락하는지 테스트
3. Kong에 동일한 방식 적용 가능성 검토