# Kong AWS Masking - 상세 마이그레이션 계획

**계획 수립일**: 2025년 7월 23일  
**예상 소요 시간**: 5-7일  
**위험도**: HIGH (전체 아키텍처 변경)  
**롤백 가능성**: YES (각 단계별 롤백 포인트 설정)

---

## 🎯 **마이그레이션 목표**

### **FROM**: Kong을 별도 서비스로 사용하는 잘못된 구조
```javascript
axios.post(`${kongUrl}/analyze-claude`, request)  // ❌
```

### **TO**: Kong을 투명한 API Gateway로 사용하는 올바른 구조  
```javascript
axios.post('https://api.anthropic.com/v1/messages', request)  // ✅
```

---

## 📋 **단계별 상세 계획**

### 🔥 **Phase 0: 사전 준비 및 백업 (1일)**

#### 0.1 현재 상태 완전 백업
```bash
# 모든 설정 파일 백업
cp -r kong/ kong.backup.$(date +%Y%m%d)
cp -r backend/ backend.backup.$(date +%Y%m%d)
cp docker-compose.yml docker-compose.backup.yml

# Git 브랜치 생성
git checkout -b feature/api-gateway-migration
git add .
git commit -m "backup: Save current architecture before migration"
```

#### 0.2 환경 검증 및 테스트 데이터 준비
```bash
# 현재 시스템 상태 확인
curl -s http://localhost:8001/routes | jq '.' > current-routes.json
curl -s http://localhost:8001/services | jq '.' > current-services.json
curl -s http://localhost:8001/plugins | jq '.' > current-plugins.json

# 테스트 데이터 준비
cat > test-data.json << EOF
{
  "resources": ["ec2"],
  "options": {"analysisType": "security_only"}
}
EOF

# 현재 시스템 기능 테스트
curl -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d @test-data.json > baseline-test-result.json
```

#### 0.3 의존성 및 영향도 분석
- [ ] 현재 Kong 라우트 사용 현황 조사
- [ ] Backend 코드에서 Kong URL 사용처 모두 식별
- [ ] 환경변수 의존성 맵핑
- [ ] 테스트 코드 영향도 분석

**완료 기준**: 모든 백업 완료 + 현재 상태 문서화 완료

---

### 🔥 **Phase 1: Kong 설정 완전 재설계 (1-2일)**

#### 1.1 새로운 kong.yml 작성

```yaml
# kong/kong.yml - 완전 새로 작성
_format_version: "3.0"
_transform: true

# 글로벌 프록시 설정
_globals:
  proxy_request_buffering: true    # 요청 버퍼링 활성화
  proxy_response_buffering: true   # 응답 버퍼링 활성화

# Claude API 서비스 정의 (실제 외부 API)
services:
  - name: claude-api-service
    url: https://api.anthropic.com
    protocol: https
    host: api.anthropic.com
    port: 443
    connect_timeout: 5000
    write_timeout: 30000
    read_timeout: 30000
    retries: 3
    tags:
      - external-api
      - claude

# 도메인 기반 자동 intercept 설정
routes:
  - name: claude-api-intercept
    service: claude-api-service
    hosts:
      - api.anthropic.com           # 이 도메인 호출을 자동 intercept
    paths:
      - /v1/messages               # Claude API 경로
    methods:
      - POST
    strip_path: false              # 경로 유지
    preserve_host: true            # 호스트 헤더 유지
    request_buffering: true        # 요청 버퍼링
    response_buffering: true       # 응답 버퍼링
    tags:
      - claude-route
      - masking-required

# AWS Masker 플러그인 적용 (새로운 라우트에)
plugins:
  - name: aws-masker
    route: claude-api-intercept
    config:
      use_redis: true
      proxy_request_buffering: true
      change_request_body: true
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
      mask_private_ips: true
      preserve_structure: true
      log_masked_requests: false   # 프로덕션에서는 false
    tags:
      - security
      - aws-masking

# 기존 Backend 라우트는 일시적으로 유지 (마이그레이션 완료 후 제거)
  - name: backend-api-temp
    service: backend-api
    paths:
      - /analyze
    methods:
      - POST
    strip_path: false
    tags:
      - temporary
      - migration
```

#### 1.2 Kong 컨테이너 설정 업데이트

```yaml
# docker-compose.yml에서 Kong 섹션 수정
kong:
  build:
    context: .
    dockerfile: docker/kong/Dockerfile
  environment:
    KONG_DATABASE: "off"
    KONG_DECLARATIVE_CONFIG: "/opt/kong/kong.yml"
    KONG_PROXY_ACCESS_LOG: /dev/stdout
    KONG_ADMIN_ACCESS_LOG: /dev/stdout
    KONG_PROXY_ERROR_LOG: /dev/stderr
    KONG_ADMIN_ERROR_LOG: /dev/stderr
    KONG_ADMIN_LISTEN: '0.0.0.0:8001'
    KONG_PROXY_LISTEN: '0.0.0.0:8000'
    KONG_LOG_LEVEL: ${KONG_LOG_LEVEL:-info}
    KONG_PLUGINS: "aws-masker"
    
    # Forward Proxy 설정 추가
    KONG_PROXY_REQUEST_BUFFERING: "on"     # 핵심 설정
    KONG_CHANGE_REQUEST_BODY: "true"       # 핵심 설정
    
    # Redis 설정
    REDIS_HOST: ${REDIS_HOST:-redis}
    REDIS_PORT: ${REDIS_PORT:-6379}
    REDIS_PASSWORD: ${REDIS_PASSWORD:-}
```

#### 1.3 Kong 설정 검증 스크립트

```bash
#!/bin/bash
# scripts/verify-kong-config.sh

echo "=== Kong 설정 검증 ==="

# Kong 컨테이너 재시작
docker-compose restart kong

# Kong 시작 대기
sleep 10

# Admin API 접근 가능 여부 확인
if curl -f -s http://localhost:8001/status > /dev/null; then
    echo "✅ Kong Admin API 접근 가능"
else
    echo "❌ Kong Admin API 접근 불가"
    exit 1
fi

# 새로운 라우트 확인
echo "새로운 라우트 확인:"
curl -s http://localhost:8001/routes | jq '.data[] | select(.name == "claude-api-intercept")'

# 새로운 서비스 확인
echo "새로운 서비스 확인:"
curl -s http://localhost:8001/services | jq '.data[] | select(.name == "claude-api-service")'

# AWS Masker 플러그인 확인
echo "AWS Masker 플러그인 확인:"
curl -s http://localhost:8001/plugins | jq '.data[] | select(.name == "aws-masker")'

echo "✅ Kong 설정 검증 완료"
```

**Phase 1 완료 기준**: 새로운 Kong 설정이 정상 동작하며 Admin API로 확인 가능

---

### 🔥 **Phase 2: Backend 코드 완전 수정 (1일)**

#### 2.1 claudeService.js 핵심 변경

```javascript
// backend/src/services/claude/claudeService.js - 대대적 수정

/**
 * @fileoverview Claude API service - API Gateway 패턴으로 완전 재작성
 * @description Kong을 투명한 프록시로 사용, 실제 Claude API 직접 호출
 */

'use strict';

require('dotenv').config();

const axios = require('axios');
const logger = require('../../../utils/logger');
const { sanitizeString } = require('../../../utils/validation');

class ClaudeService {
  constructor() {
    // Kong 관련 설정 모두 제거
    // this.kongUrl = process.env.KONG_PROXY_URL;  // ❌ 완전 제거
    
    // 실제 외부 API 설정만 유지
    this.apiUrl = 'https://api.anthropic.com';  // ✅ 실제 Claude API
    this.apiKey = process.env.ANTHROPIC_API_KEY;
    this.model = process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-20241022';
    this.timeout = parseInt(process.env.REQUEST_TIMEOUT, 10) || 30000;
    this.maxRetries = parseInt(process.env.MAX_RETRIES, 10) || 3;
    this.retryDelay = parseInt(process.env.RETRY_DELAY, 10) || 1000;
    
    this.validateConfiguration();
  }
  
  validateConfiguration() {
    if (!this.apiKey) {
      throw new Error('ANTHROPIC_API_KEY environment variable is required');
    }
    
    if (process.env.NODE_ENV === 'test' && this.apiKey.includes('test')) {
      return;
    }
    
    if (!this.apiKey.startsWith('sk-ant-api03-')) {
      throw new Error('Invalid Anthropic API key format');
    }
  }
  
  /**
   * Claude API 요청 전송 (Kong이 투명하게 intercept)
   * @param {Object} request - Claude API 요청 객체
   * @returns {Promise<Object>} Claude API 응답
   */
  async sendClaudeRequest(request) {
    let lastError;
    
    for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
      try {
        logger.debug(`Claude API request attempt ${attempt}/${this.maxRetries}`);
        
        // 실제 Claude API 직접 호출 (Kong이 자동으로 intercept)
        const response = await axios.post(
          `${this.apiUrl}/v1/messages`,  // ✅ 실제 Claude API 엔드포인트
          request,
          {
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': this.apiKey,           // 실제 API 키
              'anthropic-version': '2023-06-01'
            },
            timeout: this.timeout
          }
        );
        
        logger.info('Claude API request successful', {
          attempt,
          status: response.status,
          tokensUsed: response.data.usage?.total_tokens || 0
        });
        
        return response.data;
        
      } catch (error) {
        lastError = error;
        
        logger.warn(`Claude API request attempt ${attempt} failed`, {
          error: error.message,
          status: error.response?.status
        });
        
        // 인증/인가 오류는 재시도 안함
        if (error.response?.status === 401 || error.response?.status === 403) {
          throw error;
        }
        
        // 잘못된 요청도 재시도 안함
        if (error.response?.status === 400) {
          throw error;
        }
        
        // 재시도 대기
        if (attempt < this.maxRetries) {
          const delay = this.retryDelay * Math.pow(2, attempt - 1);
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    }
    
    throw lastError;
  }
  
  // 기존 메서드들 유지 (analyzeAwsData, buildAnalysisPrompt, etc.)
  // Kong URL 관련 코드만 제거
}

module.exports = new ClaudeService();
```

#### 2.2 환경변수 정리

```javascript
// backend/.env.example - 업데이트
# Claude API 설정 (실제 외부 API)
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
ANTHROPIC_MODEL=claude-3-5-sonnet-20241022

# AWS 설정
AWS_REGION=ap-northeast-2
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key

# 애플리케이션 설정
NODE_ENV=development
PORT=3000
REQUEST_TIMEOUT=30000
MAX_RETRIES=3
RETRY_DELAY=1000

# Kong 관련 변수들 제거
# KONG_PROXY_URL=http://localhost:8000     # ❌ 제거
# KONG_API_ENDPOINT=/analyze-claude        # ❌ 제거

# Redis 설정 (Kong이 사용)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your-redis-password
```

#### 2.3 Backend 검증 스크립트

```bash
#!/bin/bash
# scripts/verify-backend-changes.sh

echo "=== Backend 코드 변경 검증 ==="

# Kong URL 사용처 확인 (있으면 안됨)
echo "Kong URL 사용처 검색:"
if grep -r "kongUrl\|KONG_PROXY_URL" backend/src/; then
    echo "❌ Kong URL 사용처 발견 - 제거 필요"
    exit 1
else
    echo "✅ Kong URL 사용처 없음"
fi

# 실제 Claude API URL 사용 확인
echo "Claude API URL 사용 확인:"
if grep -r "api.anthropic.com" backend/src/; then
    echo "✅ 실제 Claude API URL 사용 중"
else
    echo "❌ Claude API URL 사용처 없음 - 추가 필요"
    exit 1
fi

# 환경변수 파일 검증
echo "환경변수 파일 검증:"
if grep -q "KONG_PROXY_URL" backend/.env.example; then
    echo "❌ .env.example에 Kong 관련 변수 존재 - 제거 필요"
    exit 1
else
    echo "✅ .env.example 정리 완료"
fi

echo "✅ Backend 코드 변경 검증 완료"
```

**Phase 2 완료 기준**: Backend 코드에서 Kong 관련 코드 완전 제거 + 실제 Claude API 직접 호출

---

### 🔥 **Phase 2.5: 테스트 스크립트 대대적 수정 (2.5일) - CRITICAL 누락사항**

#### ⚠️ **치명적 발견: 43개 테스트 스크립트 영향 분석 누락**

**영향도 분석 결과**:
- **총 43개 테스트 파일** 중 **36개가 Kong 직접 호출** 사용
- **30개 파일이 `/analyze-claude` 라우트** 직접 사용 (API Gateway 변경 후 제거됨)
- **모든 성능/보안 테스트가 영향** 받음

#### 2.5.1 테스트 파일 영향도 카테고리 분석

**🔴 HIGH IMPACT (36개 파일)**: `localhost:8000` 직접 호출
```bash
# 대표적인 영향 받는 파일들
tests/production-comprehensive-test.sh      # 프로덕션 테스트
tests/comprehensive-flow-test.sh           # 전체 플로우 테스트
tests/performance-test.sh                  # 성능 테스트
tests/security-masking-test.sh             # 보안 테스트
# ... 총 36개 파일
```

**🔴 CRITICAL IMPACT (30개 파일)**: `/analyze-claude` 라우트 사용
```bash
# Kong 전용 라우트 직접 호출 (완전 제거 예정)
tests/direct-kong-test.sh                  # Kong 직접 테스트
tests/kong-api-test.sh                     # Kong API 테스트
tests/50-patterns-full-visualization.sh    # 패턴 시각화
# ... 총 30개 파일
```

**🟢 NO IMPACT (6개 파일)**: `localhost:3000` 사용 (이미 올바른 패턴)
```bash
tests/individual-pattern-security-test.sh  # 개별 패턴 테스트
tests/echo-flow-test.sh                    # Echo 플로우 테스트
# ... 총 6개 파일 (수정 불필요)
```

#### 2.5.2 테스트 수정 전략

**기존 잘못된 패턴**:
```bash
# Kong 직접 호출 (API Gateway 패턴 무시)
curl -X POST http://localhost:8000/analyze-claude \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model":"claude-3-5-sonnet-20241022","messages":[...]}'
```

**새로운 올바른 패턴**:
```bash
# Backend API 호출 (Kong이 투명하게 intercept)
curl -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}'

# Kong intercept 검증 (간접 방식)
docker logs kong-gateway --since=1m | grep "api.anthropic.com"
docker exec redis-cache redis-cli KEYS "*" | head -5
```

#### 2.5.3 단계별 테스트 수정 계획

**Step A: 긴급 프로덕션 테스트 수정 (0.5일)**
```bash
#!/bin/bash
# scripts/fix-production-tests.sh

echo "=== 프로덕션 테스트 파일 긴급 수정 ==="

# 최우선 수정 대상
CRITICAL_TESTS=(
  "tests/production-comprehensive-test.sh"
  "tests/production-security-test.sh" 
  "tests/comprehensive-flow-test.sh"
  "tests/final-integration-test.sh"
)

for test_file in "${CRITICAL_TESTS[@]}"; do
  echo "수정 중: $test_file"
  
  # localhost:8000/analyze → localhost:3000/analyze 변경
  sed -i 's|localhost:8000/analyze|localhost:3000/analyze|g' "$test_file"
  
  # Kong intercept 검증 코드 추가
  echo '# Kong intercept 검증' >> "$test_file"
  echo 'docker logs kong-gateway --since=1m | grep "api.anthropic.com" || echo "No Kong intercept"' >> "$test_file"
done

echo "✅ 프로덕션 테스트 긴급 수정 완료"
```

**Step B: Kong 직접 호출 테스트 재작성 (1일)**
```bash
#!/bin/bash
# scripts/rewrite-kong-direct-tests.sh

echo "=== Kong 직접 호출 테스트 재작성 ==="

# analyze-claude 사용하는 모든 테스트 식별
KONG_DIRECT_TESTS=$(grep -l "analyze-claude" tests/*.sh)

for test_file in $KONG_DIRECT_TESTS; do
  echo "재작성 중: $test_file"
  
  # 기존 파일 백업
  cp "$test_file" "${test_file}.backup"
  
  # 새로운 간접 검증 방식으로 재작성
  cat > "$test_file" << 'EOF'
#!/bin/bash
# Rewritten for correct API Gateway pattern

echo "=== Kong AWS Masking Test (Indirect Verification) ==="

# Backend API 호출 (Kong이 투명하게 intercept)
response=$(curl -s -X POST "http://localhost:3000/analyze" \
    -H "Content-Type: application/json" \
    -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}')

# 응답 검증
if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✅ Backend API 테스트 통과"
    
    # Kong intercept 간접 검증
    echo "Kong intercept 검증:"
    KONG_LOGS=$(docker logs kong-gateway --since=1m | grep "api.anthropic.com" | wc -l)
    if [ "$KONG_LOGS" -gt 0 ]; then
        echo "✅ Kong intercept 확인됨 ($KONG_LOGS 건)"
    else
        echo "⚠️ Kong intercept 로그 없음 (정상일 수도 있음)"
    fi
    
    # Redis 마스킹 패턴 확인
    echo "Redis 마스킹 패턴:"
    REDIS_PATTERNS=$(docker exec redis-cache redis-cli KEYS "*" | wc -l)
    echo "✅ Redis에 $REDIS_PATTERNS 개 패턴 저장됨"
    
else
    echo "❌ 테스트 실패"
    echo "응답: $response"
fi
EOF

  chmod +x "$test_file"
done

echo "✅ Kong 직접 호출 테스트 재작성 완료"
```

**Step C: 성능 테스트 수정 (0.5일)**
```bash
#!/bin/bash
# scripts/fix-performance-tests.sh

echo "=== 성능 테스트 수정 ==="

PERFORMANCE_TESTS=(
  "tests/performance-test.sh"
  "tests/performance-test-simple.sh"
  "tests/redis-performance-test.sh"
)

for test_file in "${PERFORMANCE_TESTS[@]}"; do
  echo "수정 중: $test_file"
  
  # 동시 호출 부분을 Backend API로 변경
  sed -i 's|localhost:8000/analyze-claude|localhost:3000/analyze|g' "$test_file"
  sed -i 's|localhost:8000/analyze|localhost:3000/analyze|g' "$test_file"
  
  # 헤더 수정 (x-api-key 제거, Content-Type 추가)
  sed -i 's|-H "x-api-key: \$ANTHROPIC_API_KEY"|-H "Content-Type: application/json"|g' "$test_file"
  
  # 요청 본문 수정 (Claude API 포맷 → Backend 포맷)
  sed -i 's|{"model":"claude-3-5-sonnet-20241022","messages":\[.*\]}|{"resources":["ec2"],"options":{"analysisType":"security_only"}}|g' "$test_file"
done

echo "✅ 성능 테스트 수정 완료"
```

**Step D: 시각화 및 디버그 테스트 수정 (0.5일)**
```bash
#!/bin/bash
# scripts/fix-debug-tests.sh

echo "=== 디버그 및 시각화 테스트 수정 ==="

DEBUG_TESTS=$(find tests/ -name "*debug*" -o -name "*visualization*" -o -name "*flow*" | grep "\.sh$")

for test_file in $DEBUG_TESTS; do
  if grep -q "localhost:8000" "$test_file"; then
    echo "수정 중: $test_file"
    
    # 기본 URL 변경
    sed -i 's|localhost:8000/analyze|localhost:3000/analyze|g' "$test_file"
    
    # analyze-claude 사용하는 경우 완전 재작성 필요 표시
    if grep -q "analyze-claude" "$test_file"; then
      echo "# ⚠️ 이 파일은 analyze-claude를 사용하므로 수동 재작성 필요" >> "$test_file"
      echo "# 참고: TEST-SCRIPTS-IMPACT-ANALYSIS.md" >> "$test_file"
    fi
  fi
done

echo "✅ 디버그 테스트 수정 완료"
```

#### 2.5.4 테스트 검증 스크립트

```bash
#!/bin/bash
# scripts/validate-all-tests.sh

echo "=== 모든 테스트 파일 검증 ==="

# 잘못된 패턴 사용 확인
echo "1. 잘못된 패턴 검사:"
BAD_PATTERNS=$(grep -r "localhost:8000/analyze-claude" tests/ | wc -l)
if [ "$BAD_PATTERNS" -eq 0 ]; then
    echo "✅ analyze-claude 패턴 모두 제거됨"
else
    echo "❌ analyze-claude 패턴 $BAD_PATTERNS 개 남아있음"
    grep -r "localhost:8000/analyze-claude" tests/
fi

# Kong 직접 호출 확인
KONG_DIRECT=$(grep -r "localhost:8000" tests/ | grep -v "# Kong intercept" | wc -l)
echo "2. Kong 직접 호출: $KONG_DIRECT 개 (최소화 목표)"

# Backend 호출 확인
BACKEND_CALLS=$(grep -r "localhost:3000" tests/ | wc -l)
echo "3. Backend API 호출: $BACKEND_CALLS 개 (증가 목표)"

# 테스트 실행 가능성 확인
echo "4. 테스트 실행 검증:"
FAILED_TESTS=0
for test_file in tests/*.sh; do
    if ! bash -n "$test_file" 2>/dev/null; then
        echo "❌ 문법 오류: $test_file"
        ((FAILED_TESTS++))
    fi
done

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo "✅ 모든 테스트 파일 문법 검증 통과"
else
    echo "❌ $FAILED_TESTS 개 파일에 문법 오류"
fi

echo "✅ 테스트 검증 완료"
```

**Phase 2.5 완료 기준**: 
- 43개 테스트 파일 중 36개 수정 완료
- Kong 직접 호출 패턴 완전 제거
- 모든 테스트가 올바른 API Gateway 패턴 사용
- 테스트 실행 검증 통과

---

### 🔥 **Phase 3: Docker 네트워킹 설정 (2일)**

#### 3.1 HTTP Proxy 방식 구현 (권장)

```yaml
# docker-compose.yml - Backend 섹션 수정
backend:
  build:
    context: .
    dockerfile: docker/backend/Dockerfile
  environment:
    # 실제 API 설정
    ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    ANTHROPIC_MODEL: ${ANTHROPIC_MODEL:-claude-3-5-sonnet-20241022}
    AWS_REGION: ${AWS_REGION:-ap-northeast-2}
    NODE_ENV: ${NODE_ENV:-development}
    PORT: 3000
    
    # HTTP Proxy 설정 (핵심!)
    HTTP_PROXY: http://kong:8000       # 모든 HTTP 요청을 Kong으로
    HTTPS_PROXY: http://kong:8000      # 모든 HTTPS 요청을 Kong으로
    NO_PROXY: localhost,127.0.0.1,redis,backend,kong  # 내부 서비스 제외
    
    # 기타 설정
    REQUEST_TIMEOUT: ${REQUEST_TIMEOUT:-30000}
    MAX_RETRIES: ${MAX_RETRIES:-3}
  ports:
    - "3000:3000"
  volumes:
    - ./backend:/app:delegated
    - backend-modules:/app/node_modules
    - ./logs/backend:/app/logs
  networks:
    - backend
  depends_on:
    kong:
      condition: service_healthy
```

#### 3.2 대안 방식: DNS Override (백업 옵션)

```yaml
# docker-compose.yml - 대안 방식
backend:
  # ... 기존 설정 ...
  extra_hosts:
    - "api.anthropic.com:kong"        # Claude API 호출을 Kong으로 리다이렉트
  environment:
    # HTTP_PROXY 대신 DNS override 사용
    ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    # ... 기타 설정
```

#### 3.3 네트워킹 검증 스크립트

```bash
#!/bin/bash
# scripts/verify-networking.sh

echo "=== Docker 네트워킹 검증 ==="

# 컨테이너 재시작
docker-compose down
docker-compose up -d

# 서비스 시작 대기
sleep 30

# Backend 컨테이너에서 HTTP_PROXY 확인
echo "HTTP_PROXY 설정 확인:"
docker exec backend-api env | grep -i proxy

# Backend에서 Claude API 호출 테스트 (Kong을 거쳐야 함)
echo "Backend에서 Claude API 호출 테스트:"
docker exec backend-api curl -v -X POST https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"test"}]}' \
  2>&1 | grep -E "(Connected to|Via:|Proxy-)"

# Kong 로그에서 intercept 확인
echo "Kong intercept 로그 확인:"
docker logs kong-gateway --since=1m | grep -i "api.anthropic.com"

echo "✅ Docker 네트워킹 검증 완료"
```

**Phase 3 완료 기준**: Backend의 외부 API 호출이 Kong을 경유하여 처리됨

---

### 🔥 **Phase 4: 통합 테스트 및 검증 (1일)**

#### 4.1 단계별 기능 테스트

```bash
#!/bin/bash
# scripts/integration-test.sh

echo "=== 통합 테스트 시작 ==="

# 1. Kong Admin API 상태 확인
echo "1. Kong Admin API 상태 확인"
curl -f http://localhost:8001/status || exit 1

# 2. Backend API 상태 확인  
echo "2. Backend API 상태 확인"
curl -f http://localhost:3000/health || exit 1

# 3. Redis 연결 확인
echo "3. Redis 연결 확인"
docker exec redis-cache redis-cli ping || exit 1

# 4. 전체 플로우 테스트
echo "4. 전체 플로우 테스트"
RESPONSE=$(curl -s -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "resources": ["ec2"],
    "options": {"analysisType": "security_only"}
  }')

# 응답 검증
if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
    echo "✅ 전체 플로우 테스트 성공"
else
    echo "❌ 전체 플로우 테스트 실패"
    echo "$RESPONSE"
    exit 1
fi

# 5. AWS 마스킹 검증
echo "5. AWS 마스킹 검증"
# Redis에서 마스킹 패턴 확인
MASKED_PATTERNS=$(docker exec redis-cache redis-cli KEYS "*")
if [ -n "$MASKED_PATTERNS" ]; then
    echo "✅ AWS 패턴 마스킹 확인됨"
else
    echo "❌ AWS 패턴 마스킹 미확인"
    exit 1
fi

# 6. 성능 테스트
echo "6. 성능 테스트"
time curl -s -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' > /dev/null

echo "✅ 통합 테스트 완료"
```

#### 4.2 보안 검증 테스트

```bash
#!/bin/bash
# scripts/security-verification.sh

echo "=== 보안 검증 테스트 ==="

# 실제 AWS 패턴으로 테스트
TEST_INSTANCES=(
    "i-1234567890abcdef0"
    "i-0987654321fedcba0"
    "10.0.0.1"
    "172.16.0.10"
)

for instance in "${TEST_INSTANCES[@]}"; do
    echo "테스트 인스턴스: $instance"
    
    # Backend API 호출 (실제 AWS 패턴 포함)
    RESPONSE=$(curl -s -X POST http://localhost:3000/test-masking \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"Check instance $instance status\"}")
    
    # 응답에 원본 패턴이 없는지 확인 (보안 검증)
    if echo "$RESPONSE" | grep -q "$instance"; then
        echo "❌ 보안 위반: 원본 패턴 노출 - $instance"
        exit 1
    else
        echo "✅ 보안 확인: 패턴 마스킹됨 - $instance"
    fi
done

echo "✅ 보안 검증 완료"
```

#### 4.3 성능 벤치마크

```bash
#!/bin/bash
# scripts/performance-benchmark.sh

echo "=== 성능 벤치마크 ==="

# 동시 요청 테스트
echo "동시 요청 테스트 (10개 요청):"
time {
    for i in {1..10}; do
        curl -s -X POST http://localhost:3000/analyze \
          -H "Content-Type: application/json" \
          -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' &
    done
    wait
}

# 연속 요청 테스트  
echo "연속 요청 테스트 (10개 요청):"
time {
    for i in {1..10}; do
        curl -s -X POST http://localhost:3000/analyze \
          -H "Content-Type: application/json" \
          -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' > /dev/null
    done
}

echo "✅ 성능 벤치마크 완료"
```

**Phase 4 완료 기준**: 모든 기능 정상 동작 + 보안 검증 통과 + 성능 기준 만족

---

### 🔥 **Phase 5: 정리 및 최적화 (1일)**

#### 5.1 불필요한 설정 제거

```bash
#!/bin/bash
# scripts/cleanup-legacy.sh

echo "=== 레거시 설정 정리 ==="

# Kong 설정에서 불필요한 라우트 제거
echo "불필요한 Kong 라우트 정리 중..."

# kong.yml에서 임시 라우트들 제거
sed -i '/# 기존 Backend 라우트는 일시적으로 유지/,+10d' kong/kong.yml

# Backend 코드에서 사용하지 않는 환경변수 제거
echo "사용하지 않는 환경변수 제거 중..."
grep -v "KONG_" backend/.env.example > backend/.env.example.tmp
mv backend/.env.example.tmp backend/.env.example

# 불필요한 테스트 파일 정리
echo "불필요한 테스트 파일 정리 중..."
rm -f tests/*quick-mask-test*
rm -f tests/*analyze-claude*

echo "✅ 레거시 설정 정리 완료"
```

#### 5.2 최종 문서 업데이트

```bash
#!/bin/bash
# scripts/update-documentation.sh

echo "=== 문서 업데이트 ==="

# README.md 업데이트
cat > README.md << EOF
# Kong AWS Masking MVP

## 🏗️ Architecture

올바른 API Gateway 패턴을 사용한 Kong AWS Masking 시스템

### Data Flow
1. Backend가 실제 Claude API 직접 호출 (\`https://api.anthropic.com/v1/messages\`)
2. Kong이 자동으로 intercept (Backend는 Kong 존재 모름)
3. AWS Masker 플러그인이 AWS 패턴 마스킹
4. 마스킹된 요청을 Claude API로 전달
5. 응답을 언마스킹하여 Backend로 반환

## 🚀 Quick Start

\`\`\`bash
# 환경변수 설정
cp backend/.env.example backend/.env
# Edit backend/.env with your actual values

# 시스템 시작
docker-compose up --build

# 테스트
curl -X POST http://localhost:3000/analyze \\
  -H "Content-Type: application/json" \\
  -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}'
\`\`\`

## 📋 Key Features

- ✅ 표준 API Gateway 패턴 준수
- ✅ 완전한 AWS 패턴 마스킹/언마스킹
- ✅ Redis 기반 패턴 영속성 (7일)
- ✅ Fail-secure 아키텍처
- ✅ Circuit Breaker 패턴
- ✅ 무한 확장 가능한 구조

EOF

echo "✅ 문서 업데이트 완료"
```

#### 5.3 최종 검증 체크리스트

```bash
#!/bin/bash
# scripts/final-verification.sh

echo "=== 최종 검증 체크리스트 ==="

CHECKS=(
    "Kong Admin API 접근:curl -f http://localhost:8001/status"
    "Backend API 접근:curl -f http://localhost:3000/health"
    "Redis 연결:docker exec redis-cache redis-cli ping"
    "전체 플로우:curl -s -X POST http://localhost:3000/analyze -H 'Content-Type: application/json' -d '{\"resources\":[\"ec2\"]}'"
    "Kong intercept 로그:docker logs kong-gateway --since=1m | grep api.anthropic.com"
)

PASSED=0
TOTAL=${#CHECKS[@]}

for check in "${CHECKS[@]}"; do
    NAME=$(echo "$check" | cut -d: -f1)
    CMD=$(echo "$check" | cut -d: -f2-)
    
    echo -n "검증 중: $NAME... "
    
    if eval "$CMD" > /dev/null 2>&1; then
        echo "✅ 통과"
        ((PASSED++))
    else
        echo "❌ 실패"
    fi
done

echo ""
echo "검증 결과: $PASSED/$TOTAL 통과"

if [ $PASSED -eq $TOTAL ]; then
    echo "🎉 모든 검증 통과 - 마이그레이션 성공!"
    exit 0
else
    echo "🚨 일부 검증 실패 - 추가 조치 필요"
    exit 1
fi
```

**Phase 5 완료 기준**: 모든 최종 검증 통과 + 문서 업데이트 완료

---

## 🚨 **리스크 분석 및 대응 방안**

### **High Risk: Docker 네트워킹 이슈**

**위험**: HTTP_PROXY 설정이 모든 외부 호출에 영향을 미쳐 예상치 못한 부작용 발생

**대응 방안**:
```bash
# 1. NO_PROXY 설정으로 내부 서비스 제외
NO_PROXY: localhost,127.0.0.1,redis,backend,kong

# 2. 대안 방식 준비 (DNS Override)
extra_hosts:
  - "api.anthropic.com:kong"

# 3. 즉시 롤백 가능한 설정 백업
cp docker-compose.yml docker-compose.backup.yml
```

### **Medium Risk: Kong 플러그인 호환성**

**위험**: 새로운 Kong 설정에서 AWS Masker 플러그인 동작 이상

**대응 방안**:
```bash
# 1. 단계별 플러그인 테스트
curl -X POST http://localhost:8000/analyze-claude # 기존 방식 테스트
curl -X POST http://localhost:3000/analyze        # 새로운 방식 테스트

# 2. 플러그인 로그 실시간 모니터링
docker logs kong-gateway -f | grep aws-masker

# 3. Redis 패턴 저장 검증
docker exec redis-cache redis-cli MONITOR
```

### **Low Risk: 성능 저하**

**위험**: 모든 외부 API 호출이 Kong을 경유하여 성능 저하

**대응 방안**:
```bash
# 1. 성능 벤치마크 비교
time curl -X POST http://localhost:3000/analyze  # Before
time curl -X POST http://localhost:3000/analyze  # After

# 2. Kong 설정 최적화
KONG_PROXY_REQUEST_BUFFERING: "on"
KONG_WORKER_PROCESSES: "auto"

# 3. 연결 풀링 최적화
upstream_keepalive: 100
```

---

## 🔄 **롤백 계획**

### **긴급 롤백 (5분 이내)**

```bash
#!/bin/bash
# scripts/emergency-rollback.sh

echo "🚨 긴급 롤백 시작"

# 1. 백업된 설정으로 복구
cp kong.backup.$(date +%Y%m%d)/kong.yml kong/kong.yml
cp docker-compose.backup.yml docker-compose.yml

# 2. 컨테이너 재시작
docker-compose down
docker-compose up -d

# 3. 기본 기능 확인  
sleep 30
curl -f http://localhost:3000/analyze || echo "❌ 롤백 실패"

echo "✅ 긴급 롤백 완료"
```

### **단계별 롤백**

```bash
# Phase별 롤백 포인트
git checkout backup-before-phase-1  # Phase 1 롤백
git checkout backup-before-phase-2  # Phase 2 롤백
git checkout backup-before-phase-3  # Phase 3 롤백
```

---

## 📊 **성공 지표**

### **기술적 지표**
- [ ] Kong Admin API 정상 응답 (< 100ms)
- [ ] Backend API 정상 응답 (< 5초)
- [ ] AWS 패턴 100% 마스킹/언마스킹
- [ ] Redis 패턴 저장 정상 동작
- [ ] 동시 요청 10개 정상 처리

### **비즈니스 지표**  
- [ ] 기존 기능 100% 유지
- [ ] 새로운 외부 API 추가 용이성 확인
- [ ] 개발자 온보딩 시간 단축 (Kong 설정 불필요)
- [ ] 운영 복잡성 감소 (단일 Kong 라우트)

### **보안 지표**
- [ ] Claude API가 원본 AWS 패턴 전혀 수신 안함
- [ ] 모든 AWS 패턴 Redis에 안전 저장
- [ ] Fail-secure 동작 확인 (Redis 실패 시 차단)
- [ ] 보안 로그 정상 기록

---

## 🎯 **최종 목표 달성 확인**

**Before (잘못된 구조)**:
```javascript
// Backend 코드
axios.post(`${kongUrl}/analyze-claude`, request)  // Kong 전용 경로
```

**After (올바른 구조)**:
```javascript
// Backend 코드  
axios.post('https://api.anthropic.com/v1/messages', request)  // 실제 API 직접
```

**핵심 성과**:
- ✅ Backend는 Kong 존재를 완전히 모름
- ✅ Kong이 투명하게 모든 외부 API 호출 intercept
- ✅ 표준 API Gateway 패턴 완벽 구현
- ✅ 무한 확장 가능한 아키텍처
- ✅ 운영 복잡성 대폭 감소

**예상 완료일**: 2025년 7월 30일  
**담당자**: 개발팀 전체  
**승인자**: 아키텍처 리뷰 위원회