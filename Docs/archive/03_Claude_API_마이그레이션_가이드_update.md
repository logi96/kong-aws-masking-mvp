# Kong DB-less AWS Multi-Resource Masking MVP - Claude API 빠른 전환 가이드

## 요약
Claude 3.5 Sonnet으로 변경하여 80% 비용 절감. 코드 1줄만 수정하면 됩니다.

## 1. 즉시 적용 사항

### 1.1 모델 변경 (1분 작업)
```javascript
// backend/server.js
// const CLAUDE_MODEL = 'claude-3-opus-20240229';  // 제거
const CLAUDE_MODEL = 'claude-3-5-sonnet-20241022';  // 추가
```

### 1.2 비용 비교
| 항목 | Opus (기존) | Sonnet (신규) | 절감 |
|------|------------|---------------|------|
| 입력 | $15/1M 토큰 | $3/1M 토큰 | 80% |
| 출력 | $75/1M 토큰 | $15/1M 토큰 | 80% |
| 월 예상 | $8,250 | $1,650 | $6,600 |

## 2. MVP용 간단한 구현

### 2.1 기본 Claude 클라이언트
```javascript
// backend/claude-client.js (MVP 버전)
const axios = require('axios');

/**
 * Claude API 클라이언트
 * @class
 */
class ClaudeClient {
  /**
   * @param {string} apiKey - Anthropic API 키
   */
  constructor(apiKey) {
    /** @type {string} */
    this.apiKey = apiKey;
    /** @type {string} */
    this.model = 'claude-3-5-sonnet-20241022';
    /** @type {string} */
    this.baseURL = 'https://api.anthropic.com/v1/messages';
  }

  /**
   * AWS 데이터를 분석합니다
   * @param {Object} awsData - 분석할 AWS 데이터
   * @returns {Promise<Object>} Claude API 응답
   * @throws {Error} API 호출 실패 시
   */
  async analyze(awsData) {
    const response = await axios.post(
      this.baseURL,
      {
        model: this.model,
        max_tokens: 2000,  // MVP에는 충분
        messages: [{
          role: 'user',
          content: `Analyze AWS infrastructure:\n${JSON.stringify(awsData)}`
        }]
      },
      {
        headers: {
          'X-API-Key': this.apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json'
        }
      }
    );
    
    return response.data;
  }
}

module.exports = ClaudeClient;
```

### 2.2 에러 처리 (기본만)
```javascript
try {
  const result = await claudeClient.analyze(data);
  return result;
} catch (error) {
  if (error.response?.status === 429) {
    console.log('Rate limit hit, waiting 60s...');
    await new Promise(resolve => setTimeout(resolve, 60000));
    return claudeClient.analyze(data);  // 재시도
  }
  throw error;
}
```

## 3. MVP에서 제외할 사항

### ❌ 과도한 최적화
- 복잡한 토큰 계산
- 캐싱 전략
- 배치 처리
- 스트리밍 응답

### ✅ MVP 포커스
- 기본 API 호출
- 간단한 재시도
- 기본 에러 처리

## 4. 테스트 방법

### 4.1 API 키 확인
```bash
# .env 파일
ANTHROPIC_API_KEY=sk-ant-api03-xxxxx

# 테스트
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "test"}]
  }'
```

### 4.2 통합 테스트
```bash
# 전체 플로우 테스트
curl -X POST http://localhost:3000/analyze
```

## 5. 비용 모니터링 (선택사항)

### 5.1 간단한 사용량 추적
```javascript
/**
 * API 사용량을 로깅합니다
 * @param {{data: {usage: {total_tokens: number}}}} response - Claude API 응답
 */
function logUsage(response) {
  console.log(`API Call - Tokens: ${response.data.usage.total_tokens}`);
  console.log(`Estimated cost: $${response.data.usage.total_tokens * 0.000015}`);
}
```

### 5.2 일일 한도 설정
```javascript
/** @type {number} 일일 비용 한도 (달러) */
const DAILY_LIMIT = 50;  // $50/day
/** @type {number} 현재까지 사용한 일일 비용 */
let dailyCost = 0;

/**
 * 일일 한도를 체크합니다
 * @param {number} estimatedCost - 예상 비용
 * @throws {Error} 일일 한도 초과 시
 */
function checkDailyLimit(estimatedCost) {
  if (dailyCost + estimatedCost > DAILY_LIMIT) {
    throw new Error('Daily limit exceeded');
  }
}
```

## 6. 일반적인 문제 해결

### Rate Limit (429 에러)
- 해결: 60초 대기 후 재시도
- 예방: 요청 간 1초 간격

### 타임아웃
- 해결: timeout 30초로 설정
- 예방: max_tokens 줄이기

### 응답 품질
- Sonnet은 Opus와 동등한 품질
- 더 빠른 응답 속도

## 7. 마이그레이션 체크리스트

- [x] 모델명 변경
- [x] API 키 확인
- [x] 기본 에러 처리
- [ ] 첫 테스트 실행
- [ ] 비용 확인

## 8. 결론

MVP에서는:
1. **모델만 변경**: 1줄 수정으로 80% 비용 절감
2. **복잡한 기능 제외**: 기본 API 호출만
3. **빠른 검증**: 즉시 테스트 가능

예상 작업 시간: 10분

---
*핵심: 모델명만 바꾸면 즉시 80% 비용 절감*
