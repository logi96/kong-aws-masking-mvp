# 50개 패턴 마스킹 실패 원인 분석 및 해결 계획

## 🔍 현재 상황 분석

### 1. 아키텍처 구성
- **Kong Route**: `/analyze-claude` → `https://api.anthropic.com/v1/messages`
- **AWS Masker Plugin**: route `analyze-claude`에 적용됨
- **Backend**: claudeService.js가 Claude API를 직접 호출

### 2. 문제점 식별

#### 2.1 API Gateway 패턴 미적용
현재 Backend가 Claude API를 직접 호출하고 있어 Kong을 우회합니다:
```javascript
// claudeService.js (line 265-276)
const response = await axios.post(
  this.claudeApiUrl,  // https://api.anthropic.com/v1/messages
  request,
  {
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': this.apiKey,
      'anthropic-version': '2023-06-01'
    },
    timeout: this.timeout
  }
);
```

#### 2.2 Docker 네트워크 프록시 미작동
- `HTTP_PROXY` 환경변수가 설정되어 있지만 Node.js axios가 이를 자동으로 사용하지 않음
- `docker-compose.yml`의 프록시 설정이 실제로 적용되지 않음

#### 2.3 테스트 엔드포인트 구조 문제
- `/test-masking` 엔드포인트가 claudeService를 사용하여 직접 Claude API 호출
- `/test-masking/batch` 역시 같은 문제

## 🎯 해결 방안

### 방안 1: Backend가 Kong 엔드포인트 호출 (권장)
Backend의 CLAUDE_API_URL을 Kong의 `/analyze-claude`로 변경

**장점**:
- 명확한 API Gateway 패턴
- 쉬운 구현
- 디버깅 용이

**단점**:
- URL 변경 필요

### 방안 2: HTTP Proxy 강제 적용
axios에 HTTP proxy agent 설정

**장점**:
- 투명한 프록시
- URL 변경 불필요

**단점**:
- 복잡한 구현
- 디버깅 어려움

## 📋 상세 구현 계획

### Phase 1: Backend 설정 수정
1. **claudeService.js 수정**
   - CLAUDE_API_URL을 Kong endpoint로 변경
   - 또는 axios에 proxy 설정 추가

2. **환경변수 정리**
   - `CLAUDE_API_URL` 기본값 변경
   - 불필요한 proxy 설정 제거

### Phase 2: Kong 라우트 추가 (필요 시)
1. **claude-proxy 라우트 추가**
   - Path: `/claude-proxy/v1/messages`
   - Service: claude-api-service
   - Plugin: aws-masker

### Phase 3: 테스트 검증
1. **단일 패턴 테스트**
   - EC2, VPC, IP 패턴 개별 검증
   - 마스킹/언마스킹 플로우 확인

2. **50개 패턴 일괄 테스트**
   - 모든 AWS 리소스 패턴 검증
   - 보안 취약점 확인

### Phase 4: 문서화
1. **아키텍처 다이어그램 업데이트**
2. **API 플로우 문서화**
3. **보안 검증 보고서 작성**

## 🚨 보안 고려사항

1. **Fail-Secure 원칙**
   - 마스킹 실패 시 요청 차단
   - 에러 발생 시 원본 데이터 노출 방지

2. **로깅 및 모니터링**
   - 마스킹 성공/실패 추적
   - 보안 이벤트 기록

3. **성능 영향**
   - 추가 홉으로 인한 지연 최소화
   - 5초 응답 시간 목표 준수

## 🔧 즉시 실행 가능한 수정사항

### Option 1: CLAUDE_API_URL 변경 (간단)
```javascript
// claudeService.js
this.claudeApiUrl = process.env.CLAUDE_API_URL || 'http://kong:8000/analyze-claude';
```

### Option 2: Proxy Agent 추가 (복잡)
```javascript
const HttpsProxyAgent = require('https-proxy-agent');
const proxyUrl = process.env.HTTP_PROXY;
const agent = proxyUrl ? new HttpsProxyAgent(proxyUrl) : undefined;

const response = await axios.post(url, data, {
  httpsAgent: agent,
  proxy: false // axios 내장 proxy 비활성화
});
```

## 📊 예상 결과

수정 후:
1. Backend → Kong (`/analyze-claude`) → Claude API
2. Kong이 요청 마스킹 수행
3. Claude는 마스킹된 데이터만 수신
4. Kong이 응답 언마스킹
5. Backend가 원본 데이터 수신

## 🎯 추천 접근 방법

**즉시 적용**: Option 1 (CLAUDE_API_URL 변경)
- 가장 간단하고 명확한 해결책
- API Gateway 패턴에 부합
- 즉시 테스트 가능

**장기적**: 
- 프록시 패턴 연구 및 최적화
- 성능 벤치마크
- 프로덕션 준비