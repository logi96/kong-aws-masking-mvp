# 7. 개발 지침

## 7.1 필수 준수사항 (DO's)

### 7.1.1 보안 관련 DO's

✅ **모든 외부 API URL은 직접 사용**
```javascript
// GOOD: Envoy가 자동으로 가로챔
const apiUrl = 'https://api.anthropic.com/v1/messages';
```

✅ **민감한 정보는 로그에서 제외**
```javascript
// GOOD: 민감한 정보 마스킹
logger.info('Processing request', {
  accountId: maskAccountId(accountId),
  region: region
});
```

✅ **에러 메시지에 상세 정보 포함 금지**
```javascript
// GOOD: 일반적인 에러 메시지
throw new Error('External API request failed');
```

### 7.1.2 코드 품질 DO's

✅ **JSDoc 타입 주석 필수 작성**
```javascript
/**
 * AWS 리소스 분석 요청
 * @param {Object} request - 분석 요청 객체
 * @param {string[]} request.resources - 분석할 리소스 타입
 * @param {Object} request.options - 분석 옵션
 * @returns {Promise<Object>} 분석 결과
 */
async function analyzeResources(request) {
  // Implementation
}
```

✅ **에러 핸들링 패턴 준수**
```javascript
// GOOD: 구조화된 에러 처리
try {
  const result = await externalApiCall();
  return result;
} catch (error) {
  logger.error('API call failed', {
    error: error.message,
    code: error.response?.status
  });
  throw new ServiceError('External API unavailable', 503);
}
```

✅ **비동기 처리 일관성**
```javascript
// GOOD: async/await 사용
async function processRequest(data) {
  const validated = await validateData(data);
  const result = await sendToAPI(validated);
  return result;
}
```

### 7.1.3 Kong 플러그인 DO's

✅ **우선순위 명시적 설정**
```lua
-- GOOD: 명확한 우선순위
local DynamicRouter = {
  PRIORITY = 2000,  -- AWS Masker(1000)보다 먼저 실행
  VERSION = "1.0.0"
}
```

✅ **적절한 로그 레벨 사용**
```lua
-- GOOD: 레벨별 로깅
kong.log.debug("Processing request to ", host)
kong.log.info("Routing to upstream ", upstream_url)
kong.log.warn("Unauthorized access attempt to ", host)
kong.log.err("Missing required header: x-original-host")
```

✅ **에러 응답 표준화**
```lua
-- GOOD: 일관된 에러 응답
return kong.response.exit(403, {
  message = "Unauthorized external API",
  code = "UNAUTHORIZED_HOST",
  details = { attempted_host = original_host }
})
```

### 7.1.4 Docker/환경 설정 DO's

✅ **환경별 설정 분리**
```yaml
# GOOD: 환경별 compose 파일
docker-compose.yml          # 기본 설정
docker-compose.dev.yml      # 개발 환경
docker-compose.prod.yml     # 운영 환경
docker-compose.test.yml     # 테스트 환경
```

✅ **헬스체크 필수 구현**
```yaml
# GOOD: 모든 서비스에 헬스체크
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/status"]
  interval: 30s
  timeout: 3s
  retries: 3
```

## 7.2 금지사항 (DON'Ts)

### 7.2.1 보안 관련 DON'Ts

❌ **환경변수로 API URL 설정 금지**
```javascript
// BAD: Kong 우회 가능
const apiUrl = process.env.CLAUDE_API_URL || 'https://api.anthropic.com';
```

❌ **민감한 정보 하드코딩 금지**
```javascript
// BAD: AWS 계정 정보 노출
const accountId = '123456789012';
```

❌ **인증 정보 로깅 금지**
```javascript
// BAD: API 키 로깅
logger.debug('Request headers:', headers); // x-api-key 포함
```

### 7.2.2 코드 품질 DON'Ts

❌ **동기 I/O 사용 금지**
```javascript
// BAD: 동기 파일 읽기
const data = fs.readFileSync('config.json');
```

❌ **전역 변수 사용 금지**
```javascript
// BAD: 전역 상태
global.apiClient = new ApiClient();
```

❌ **console.log 사용 금지**
```javascript
// BAD: console 직접 사용
console.log('Debug info:', data);
```

### 7.2.3 Kong 플러그인 DON'Ts

❌ **블로킹 연산 금지**
```lua
-- BAD: 동기 sleep
os.execute("sleep 1")
```

❌ **글로벌 변수 오염 금지**
```lua
-- BAD: 글로벌 변수
upstream_url = "https://api.example.com"
```

❌ **무한 재시도 금지**
```lua
-- BAD: 무한 루프 가능성
while not success do
  success = try_operation()
end
```

### 7.2.4 인프라 DON'Ts

❌ **latest 태그 사용 금지**
```yaml
# BAD: 버전 불확실성
image: envoyproxy/envoy:latest
```

❌ **하드코딩된 포트 금지**
```yaml
# BAD: 환경별 충돌 가능
ports:
  - "3000:3000"  # 환경변수 사용 필요
```

## 7.3 베스트 프랙티스

### 7.3.1 성능 최적화

**커넥션 재사용**
```javascript
// axios 인스턴스 재사용
const apiClient = axios.create({
  timeout: 30000,
  httpAgent: new http.Agent({ keepAlive: true }),
  httpsAgent: new https.Agent({ keepAlive: true })
});
```

**비동기 병렬 처리**
```javascript
// 병렬 API 호출
const [ec2Data, s3Data] = await Promise.all([
  fetchEC2Instances(),
  fetchS3Buckets()
]);
```

### 7.3.2 에러 처리 패턴

**에러 분류 체계**
```javascript
class ServiceError extends Error {
  constructor(message, statusCode, code) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
  }
}

// 사용 예시
throw new ServiceError('Resource not found', 404, 'RESOURCE_NOT_FOUND');
```

**재시도 로직**
```javascript
async function retryableOperation(fn, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      if (!isRetryableError(error)) throw error;
      
      const delay = Math.min(1000 * Math.pow(2, i), 10000);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}
```

### 7.3.3 로깅 표준

**구조화된 로깅**
```javascript
logger.info('Request processed', {
  requestId: req.id,
  method: req.method,
  path: req.path,
  duration: Date.now() - startTime,
  statusCode: res.statusCode
});
```

**로그 레벨 가이드**
- **ERROR**: 즉시 조치 필요
- **WARN**: 주의 필요, 잠재적 문제
- **INFO**: 중요 이벤트, 정상 흐름
- **DEBUG**: 상세 정보, 개발/디버깅용

### 7.3.4 테스트 작성

**테스트 구조**
```javascript
describe('FeatureName', () => {
  describe('methodName', () => {
    it('should handle normal case', async () => {
      // Given
      const input = prepareTestData();
      
      // When
      const result = await methodUnderTest(input);
      
      // Then
      expect(result).toMatchExpectedOutput();
    });
    
    it('should handle error case', async () => {
      // Error case test
    });
  });
});
```

## 7.4 코드 리뷰 체크리스트

### 7.4.1 보안 체크

- [ ] 외부 API URL이 하드코딩되어 있는가?
- [ ] 민감한 정보가 로그에 포함되지 않는가?
- [ ] 에러 메시지가 너무 상세하지 않은가?

### 7.4.2 품질 체크

- [ ] JSDoc 타입 주석이 완성되어 있는가?
- [ ] 에러 처리가 적절한가?
- [ ] 테스트가 충분한가? (커버리지 80% 이상)

### 7.4.3 성능 체크

- [ ] 불필요한 동기 연산이 없는가?
- [ ] 리소스 정리(cleanup)가 적절한가?
- [ ] 타임아웃이 설정되어 있는가?

## 7.5 디버깅 가이드

### 7.5.1 Envoy 디버깅

```bash
# Envoy 액세스 로그 확인
docker logs envoy-sidecar | grep "original-host"

# Envoy 설정 덤프
curl http://localhost:9901/config_dump

# Envoy 통계 확인
curl http://localhost:9901/stats/prometheus | grep http
```

### 7.5.2 Kong 디버깅

```bash
# Kong 에러 로그
docker logs kong-gateway 2>&1 | grep ERROR

# Kong 플러그인 로그
docker logs kong-gateway | grep "dynamic-router"

# Kong Admin API로 설정 확인
curl http://localhost:8001/routes
```

### 7.5.3 트래픽 추적

```bash
# tcpdump로 네트워크 트래픽 확인
docker exec backend-api tcpdump -i any -w capture.pcap

# iptables 패킷 카운트 확인
docker exec backend-api iptables -t nat -L -v -n
```

## 7.6 문제 해결 FAQ

### Q: "Connection refused" 에러 발생
```bash
# A: 서비스 상태 확인
docker ps
docker logs envoy-sidecar
docker logs kong-gateway

# 네트워크 연결 확인
docker exec backend-api ping kong-gateway
```

### Q: 외부 API 호출이 차단되지 않음
```bash
# A: iptables 규칙 확인
docker exec backend-api iptables -t nat -L OUTPUT -n

# Envoy 프로세스 확인
docker exec backend-api ps aux | grep envoy
```

### Q: 성능이 저하됨
```bash
# A: 리소스 사용량 확인
docker stats

# Envoy 메트릭 확인
curl http://localhost:9901/stats/prometheus

# Kong 메트릭 확인
curl http://localhost:8001/metrics
```

## 7.7 마이그레이션 가이드

### 7.7.1 기존 시스템에서 마이그레이션

1. **환경변수 제거**
   ```javascript
   // Before
   const apiUrl = process.env.CLAUDE_API_URL;
   
   // After
   const apiUrl = 'https://api.anthropic.com/v1/messages';
   ```

2. **Kong 설정 업데이트**
   - Dynamic Router 플러그인 추가
   - 기존 라우트 수정

3. **단계적 롤아웃**
   - Canary 배포로 10% 트래픽부터 시작
   - 모니터링 후 점진적 확대

## 7.8 운영 가이드

### 7.8.1 일일 점검 항목

- [ ] 에러율 확인 (< 1%)
- [ ] 응답 시간 확인 (p95 < 3초)
- [ ] 리소스 사용률 확인
- [ ] 로그 이상 패턴 확인

### 7.8.2 정기 유지보수

- **주간**: 성능 리포트 검토
- **월간**: 보안 패치 적용
- **분기**: 의존성 업데이트

## 7.9 팀 온보딩

### 7.9.1 신규 개발자 체크리스트

1. **문서 숙지**
   - [ ] 아키텍처 설계 문서
   - [ ] 개발 지침
   - [ ] 테스트 전략

2. **환경 설정**
   - [ ] Docker 환경 구축
   - [ ] 로컬 테스트 실행
   - [ ] IDE 설정 (JSDoc 지원)

3. **실습**
   - [ ] 간단한 기능 추가
   - [ ] 테스트 작성
   - [ ] 코드 리뷰 참여

## 7.10 결론

이 개발 지침을 준수하여 안전하고 확장 가능한 시스템을 유지하세요. 의문사항이 있으면 팀 리드와 상의하고, 지침 개선사항이 있으면 PR을 통해 제안하세요.