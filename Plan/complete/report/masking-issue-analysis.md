# Kong AWS Masking 문제 분석 보고서

## 🔍 현재 상황

### 1. 설정 확인 완료
- ✅ Kong 라우트 설정: `/analyze-claude`, `/claude-proxy/v1/messages`
- ✅ Backend CLAUDE_API_URL: `http://kong:8000/claude-proxy/v1/messages`
- ✅ AWS Masker 플러그인: 두 라우트 모두에 적용

### 2. 마스킹 작동 확인
Kong 로그에서 마스킹이 실제로 작동함을 확인:
```
[MASKING] Mask count: 24
[UNMASK] Applying unmask map: EC2_002=>i-1234567890abcdef0
```

### 3. 발견된 문제점

#### 3.1 API Gateway 패턴 문제
```lua
api_gateway = {
  pattern = "[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]",
  replacement = "API_GW_%03d"
}
```
- 이 패턴은 10자리 소문자/숫자 조합을 모두 매칭
- 너무 광범위하여 과도한 마스킹 발생
- "Pattern api_gateway matched 24 times" - 의도하지 않은 텍스트까지 마스킹

#### 3.2 Claude 응답 문제
- Claude가 EC2 인스턴스 정보 대신 API Gateway 분석 결과를 반환
- 이는 마스킹이 너무 과도하게 적용되어 원본 컨텍스트가 손실되었을 가능성

#### 3.3 50개 패턴 테스트 실패 원인
테스트가 실패한 이유:
1. 과도한 마스킹으로 인한 컨텍스트 손실
2. Claude가 마스킹된 텍스트를 제대로 해석하지 못함
3. systemPrompt가 제대로 전달되지 않았을 가능성

## 🎯 해결 방안

### 1. API Gateway 패턴 수정 (긴급)
```lua
-- 현재 (문제)
pattern = "[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]"

-- 수정안 (더 구체적으로)
pattern = "[a-z0-9]{10}\\b"  -- 단어 경계 추가
-- 또는 더 구체적인 패턴 사용
```

### 2. 테스트 방법 개선
```javascript
// test-masking endpoint 수정 필요
// systemPrompt를 더 명확하게 전달
const response = await claudeService.analyzeAwsData(
  { testData: testText },
  {
    systemPrompt: `You are a test echo service. Return EXACTLY: "${testText}"`,
    maxTokens: 100,
    analysisType: 'test_echo'  // 새로운 타입 추가
  }
);
```

### 3. 디버깅 개선
- Kong 로그에서 실제 마스킹된 요청 본문 확인 필요
- Claude로 전송되는 실제 데이터 검증

## 📋 즉시 수행할 작업

1. **API Gateway 패턴 비활성화 (임시)**
   - 과도한 마스킹 방지
   - 다른 패턴들의 정상 작동 확인

2. **단순한 에코 테스트 구현**
   - Claude가 단순히 입력을 반복하도록 설정
   - 마스킹/언마스킹 플로우 검증

3. **패턴별 개별 테스트**
   - 각 AWS 리소스 패턴을 개별적으로 테스트
   - 어떤 패턴이 문제를 일으키는지 식별

## 🚨 보안 검증

현재 설정은 기본적으로 안전합니다:
- Kong이 AWS 리소스를 마스킹하고 있음
- Claude는 마스킹된 데이터만 수신
- 언마스킹은 응답 시에만 수행

단, 과도한 마스킹으로 인해 기능이 제대로 작동하지 않는 상태입니다.