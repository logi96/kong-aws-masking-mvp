# 6. 테스트 전략

## 6.1 테스트 전략 개요

### 6.1.1 테스트 피라미드

```
         E2E Tests (10%)
        /            \
    Integration Tests (30%)
   /                    \
  Unit Tests (60%)
```

### 6.1.2 테스트 원칙

1. **실용성**: 오버 테스팅 방지, 핵심 기능 집중
2. **자동화**: CI/CD 파이프라인 통합
3. **격리성**: 각 테스트 독립 실행 가능
4. **재현성**: 동일 조건에서 일관된 결과

## 6.2 단위 테스트

### 6.2.1 Kong Plugin 단위 테스트

**파일: `kong/plugins/dynamic-router/spec/handler_spec.lua`**

```lua
local helpers = require "spec.helpers"
local DynamicRouter = require "kong.plugins.dynamic-router.handler"

describe("Dynamic Router Plugin", function()
  
  describe("access phase", function()
    it("routes to correct upstream when host is allowed", function()
      -- Given
      local conf = {
        allowed_hosts = {
          ["api.anthropic.com"] = "https://api.anthropic.com"
        }
      }
      
      -- Mock Kong functions
      local kong_mock = {
        request = {
          get_header = function(name)
            if name == "x-original-host" then
              return "api.anthropic.com"
            end
          end
        },
        service = {
          set_upstream = spy.new(function() end),
          request = {
            set_header = spy.new(function() end)
          }
        },
        log = {
          info = spy.new(function() end)
        }
      }
      
      -- When
      _G.kong = kong_mock
      DynamicRouter:access(conf)
      
      -- Then
      assert.spy(kong_mock.service.set_upstream).was_called_with("https://api.anthropic.com")
      assert.spy(kong_mock.service.request.set_header).was_called()
    end)
    
    it("returns 403 when host is not allowed", function()
      -- Given
      local conf = {
        allowed_hosts = {}
      }
      
      local response_exit_called = false
      local response_code, response_body
      
      local kong_mock = {
        request = {
          get_header = function() return "malicious.com" end
        },
        response = {
          exit = function(code, body)
            response_exit_called = true
            response_code = code
            response_body = body
          end
        },
        log = {
          warn = spy.new(function() end)
        }
      }
      
      -- When
      _G.kong = kong_mock
      DynamicRouter:access(conf)
      
      -- Then
      assert.is_true(response_exit_called)
      assert.equals(403, response_code)
      assert.equals("Unauthorized external API", response_body.message)
    end)
    
    it("returns 400 when x-original-host header is missing", function()
      -- Test implementation
    end)
  end)
end)
```

### 6.2.2 Backend Service 단위 테스트

**파일: `backend/tests/unit/services/claudeService.test.js`**

```javascript
const ClaudeService = require('../../../src/services/claudeService');
const axios = require('axios');

jest.mock('axios');

describe('ClaudeService', () => {
  let service;
  
  beforeEach(() => {
    service = new ClaudeService();
    jest.clearAllMocks();
  });
  
  describe('sendClaudeRequest', () => {
    it('should call external API directly without Kong URL', async () => {
      // Given
      const mockResponse = { data: { content: 'AI response' } };
      axios.post.mockResolvedValue(mockResponse);
      
      const request = {
        messages: [{ content: 'Test message' }]
      };
      
      // When
      const result = await service.sendClaudeRequest(request);
      
      // Then
      expect(axios.post).toHaveBeenCalledWith(
        'https://api.anthropic.com/v1/messages',
        request,
        expect.objectContaining({
          headers: expect.objectContaining({
            'x-api-key': expect.any(String)
          })
        })
      );
      expect(result).toEqual(mockResponse.data);
    });
    
    it('should handle API errors properly', async () => {
      // Given
      const mockError = new Error('API Error');
      mockError.response = { status: 429, data: { error: 'Rate limited' } };
      axios.post.mockRejectedValue(mockError);
      
      // When/Then
      await expect(service.sendClaudeRequest({}))
        .rejects.toThrow('API Error');
    });
  });
});
```

### 6.2.3 테스트 커버리지 목표

```bash
# Jest 설정 (package.json)
{
  "jest": {
    "collectCoverageFrom": [
      "src/**/*.js",
      "!src/tests/**"
    ],
    "coverageThreshold": {
      "global": {
        "branches": 80,
        "functions": 80,
        "lines": 80,
        "statements": 80
      }
    }
  }
}
```

## 6.3 통합 테스트

### 6.3.1 Envoy + Kong 통합 테스트

**파일: `tests/integration/envoy-kong.test.js`**

```javascript
const { exec } = require('child_process');
const axios = require('axios');
const { promisify } = require('util');

const execAsync = promisify(exec);

describe('Envoy + Kong Integration', () => {
  beforeAll(async () => {
    // Docker Compose로 테스트 환경 시작
    await execAsync('docker-compose -f docker-compose.test.yml up -d');
    
    // 서비스 준비 대기
    await waitForServices();
  });
  
  afterAll(async () => {
    await execAsync('docker-compose -f docker-compose.test.yml down');
  });
  
  test('Backend API calls should be intercepted by Envoy', async () => {
    // Given: Backend 컨테이너에서 직접 외부 API 호출
    const command = `docker exec backend-api curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com/v1/messages`;
    
    // When
    const { stdout } = await execAsync(command);
    
    // Then: Kong을 거쳐 403 응답 (미인증)
    expect(stdout.trim()).toBe('403');
  });
  
  test('iptables should redirect traffic to Envoy', async () => {
    // Given: iptables 규칙 확인
    const command = 'docker exec backend-api iptables -t nat -L OUTPUT -n';
    
    // When
    const { stdout } = await execAsync(command);
    
    // Then
    expect(stdout).toContain('REDIRECT');
    expect(stdout).toContain('15001');
  });
  
  test('Kong should receive x-original-host header', async () => {
    // Test implementation
  });
});

async function waitForServices() {
  const maxRetries = 30;
  const services = [
    { name: 'Backend', url: 'http://localhost:3000/health' },
    { name: 'Kong', url: 'http://localhost:8001/status' }
  ];
  
  for (const service of services) {
    let retries = 0;
    while (retries < maxRetries) {
      try {
        await axios.get(service.url);
        console.log(`${service.name} is ready`);
        break;
      } catch (error) {
        retries++;
        if (retries === maxRetries) {
          throw new Error(`${service.name} failed to start`);
        }
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  }
}
```

### 6.3.2 AWS Masker 통합 테스트

**파일: `tests/integration/aws-masker-flow.test.js`**

```javascript
describe('AWS Masker End-to-End Flow', () => {
  test('AWS resources should be masked and unmasked correctly', async () => {
    // Given
    const testPayload = {
      resources: ['ec2'],
      options: {
        analysisType: 'security_only'
      }
    };
    
    // When: Backend API 호출
    const response = await axios.post('http://localhost:3000/analyze', testPayload);
    
    // Then: 마스킹된 데이터가 Claude API로 전송되고 언마스킹되어 반환
    expect(response.status).toBe(200);
    expect(response.data).toHaveProperty('analysis');
    
    // Kong 로그 확인으로 마스킹 검증
    const logs = await getKongLogs();
    expect(logs).toContain('AWS_EC2_');
  });
});
```

## 6.4 부하 테스트

### 6.4.1 성능 벤치마크 설정

**파일: `tests/load/k6-script.js`**

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp up
    { duration: '5m', target: 100 },  // Stay at 100 users
    { duration: '2m', target: 200 },  // Spike
    { duration: '5m', target: 200 },  // Stay at 200 users
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'], // 95% 요청이 3초 이내
    http_req_failed: ['rate<0.05'],    // 에러율 5% 미만
  },
};

export default function () {
  const payload = JSON.stringify({
    resources: ['ec2', 's3'],
    options: {
      analysisType: 'comprehensive'
    }
  });
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  const res = http.post('http://localhost:3000/analyze', payload, params);
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 3s': (r) => r.timings.duration < 3000,
    'has analysis result': (r) => JSON.parse(r.body).analysis !== undefined,
  });
  
  sleep(1);
}
```

### 6.4.2 부하 테스트 시나리오

```bash
# 기본 부하 테스트
k6 run tests/load/k6-script.js

# 스트레스 테스트
k6 run --vus 500 --duration 10m tests/load/k6-script.js

# 스파이크 테스트
k6 run tests/load/spike-test.js

# 지속성 테스트
k6 run --vus 100 --duration 2h tests/load/soak-test.js
```

## 6.5 장애 주입 테스트

### 6.5.1 네트워크 장애 시뮬레이션

```bash
# Envoy 네트워크 지연 주입
docker exec envoy-sidecar tc qdisc add dev eth0 root netem delay 1000ms

# Kong 연결 끊기
docker network disconnect kong_frontend kong-gateway

# Redis 장애
docker stop redis-cache
```

### 6.5.2 복구 시나리오 테스트

```javascript
describe('Resilience Tests', () => {
  test('Should handle Envoy failure gracefully', async () => {
    // Given: Envoy 중단
    await execAsync('docker stop envoy-sidecar');
    
    // When: API 호출
    const response = await axios.post('http://localhost:3000/analyze', {}, {
      validateStatus: () => true
    });
    
    // Then: 적절한 에러 응답
    expect(response.status).toBe(503);
    expect(response.data.error).toContain('Service Unavailable');
    
    // Cleanup
    await execAsync('docker start envoy-sidecar');
  });
  
  test('Should recover from Kong restart', async () => {
    // Test implementation
  });
});
```

## 6.6 보안 테스트

### 6.6.1 보안 우회 시도 테스트

```javascript
describe('Security Bypass Prevention', () => {
  test('Direct external API calls should be blocked', async () => {
    // Backend 컨테이너 내부에서 다양한 우회 시도
    const bypassAttempts = [
      'curl https://api.anthropic.com/v1/messages',
      'wget https://api.openai.com/v1/chat/completions',
      'nc -zv api.anthropic.com 443'
    ];
    
    for (const attempt of bypassAttempts) {
      const command = `docker exec backend-api ${attempt}`;
      
      try {
        await execAsync(command);
        fail('Bypass attempt should have failed');
      } catch (error) {
        // 모든 시도가 실패해야 함
        expect(error).toBeDefined();
      }
    }
  });
});
```

### 6.6.2 AWS 데이터 노출 방지 테스트

```javascript
test('AWS sensitive data should never reach external APIs', async () => {
  // Kong 로그를 모니터링하여 마스킹 확인
  const sensitiveData = [
    'i-1234567890abcdef0',
    'arn:aws:iam::123456789012:role/MyRole',
    '10.0.0.1'
  ];
  
  // API 호출
  await axios.post('http://localhost:3000/analyze', {
    resources: ['ec2'],
    rawData: sensitiveData.join(' ')
  });
  
  // Kong 로그 확인
  const logs = await getKongLogs();
  
  for (const data of sensitiveData) {
    expect(logs).not.toContain(data);
  }
});
```

## 6.7 테스트 자동화

### 6.7.1 CI/CD 파이프라인 통합

```yaml
# .github/workflows/test.yml
name: Test Pipeline

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Unit Tests
        run: |
          npm test -- --coverage
          
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        
  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Integration Tests
        run: |
          docker-compose -f docker-compose.test.yml up -d
          npm run test:integration
          docker-compose -f docker-compose.test.yml down
          
  load-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Load Tests
        run: |
          docker-compose up -d
          k6 run tests/load/k6-script.js
          docker-compose down
```

### 6.7.2 테스트 리포트

```javascript
// jest.config.js
module.exports = {
  reporters: [
    'default',
    ['jest-html-reporter', {
      pageTitle: 'Kong AWS Masker Test Report',
      outputPath: 'test-report.html',
      includeFailureMsg: true
    }]
  ]
};
```

## 6.8 테스트 데이터 관리

### 6.8.1 테스트 픽스처

```javascript
// tests/fixtures/aws-resources.js
module.exports = {
  ec2Instances: [
    'i-1234567890abcdef0',
    'i-0987654321fedcba0'
  ],
  s3Buckets: [
    'my-test-bucket-123',
    'backup-prod-2023'
  ],
  validApiHosts: [
    'api.anthropic.com',
    'api.openai.com'
  ],
  invalidApiHosts: [
    'malicious.com',
    'data-exfiltration.io'
  ]
};
```

## 6.9 테스트 모니터링

### 6.9.1 테스트 메트릭 수집

```javascript
// 테스트 실행 시간, 성공률 등 메트릭 수집
const testMetrics = {
  duration: process.hrtime(startTime),
  passed: results.filter(r => r.status === 'passed').length,
  failed: results.filter(r => r.status === 'failed').length,
  skipped: results.filter(r => r.status === 'skipped').length
};

// Prometheus로 전송
await pushMetrics(testMetrics);
```

## 6.10 다음 단계

테스트 전략을 이해했다면 [개발 지침](07-development-guidelines.md)을 참조하여 개발 시 준수사항을 확인하세요.