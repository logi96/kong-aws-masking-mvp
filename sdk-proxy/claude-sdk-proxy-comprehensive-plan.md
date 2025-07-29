# Claude SDK 프록시 검증 종합 계획 (Agent 기반)

## 프로젝트 목표
현재 Kong 프로젝트와 완전히 독립된 환경에서 Claude SDK(@anthropic-ai/sdk)의 프록시 지원을 검증하고, Kong Gateway를 통한 민감정보 마스킹 가능성을 확인

## 기술 검증 목표
1. Claude Code SDK가 프록시를 통해 API 호출을 할 수 있는지 확인
2. ANTHROPIC_BASE_URL, HTTP_PROXY/HTTPS_PROXY 환경변수 지원 여부 검증
3. Kong Gateway와의 통합 가능성 평가
4. 프록시 레벨에서의 마스킹 적용 가능성 확인

## 상세 설계 및 Agent 할당

### Phase 1: 아키텍처 설계 및 계획 수립

#### 담당 Agent: `systems-architect`
**임무**: 전체 시스템 아키텍처 설계 및 컴포넌트 정의

**상세 설계 (제공)**:
```
sdk-proxy/                     # 완전 독립 테스트 프로젝트
├── docker-compose.yml         # Docker 환경 구성
├── Dockerfile                 # Node.js 테스트 환경
├── package.json              # 최소 의존성
├── src/
│   ├── test-sdk-proxy.js     # SDK 프록시 테스트
│   ├── simple-masker.js      # 간단한 마스킹 로직
│   └── test-scenarios.js     # 테스트 시나리오
├── kong-minimal/
│   ├── kong.yml              # 최소 Kong 설정
│   └── simple-logger.lua     # 요청 로깅 플러그인
├── nginx-proxy/
│   └── nginx.conf            # 간단한 프록시
├── results/                  # 테스트 결과
└── README.md                 # 실행 가이드
```

**Agent 지침**:
```
systems-architect agent가 위의 기본 구조를 검토하고,
컴포넌트 간 통신 흐름을 정의하고,
현재 Kong 프로젝트와의 완전한 격리를 보장하는 아키텍처를 확정해줘
```

### Phase 2: 인프라 환경 구성

#### 담당 Agent: `infrastructure-engineer`
**임무**: Docker 기반 격리 환경 구축

**상세 설계 (제공)**:

**docker-compose.yml**:
```yaml
version: '3.8'

services:
  # 간단한 프록시 서버 (nginx로 시작)
  nginx-proxy:
    image: nginx:alpine
    container_name: sdk-test-proxy
    ports:
      - "8888:80"
    volumes:
      - ./nginx-proxy/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./results/logs:/var/log/nginx
    networks:
      - sdk-test-net
    
  # Kong 프록시 (선택사항)
  kong-minimal:
    image: kong:3.9.0.1-alpine
    container_name: sdk-test-kong
    environment:
      - KONG_DATABASE=off
      - KONG_DECLARATIVE_CONFIG=/kong.yml
      - KONG_PROXY_ACCESS_LOG=/dev/stdout
    ports:
      - "8000:8000"
    volumes:
      - ./kong-minimal/kong.yml:/kong.yml
    networks:
      - sdk-test-net
      
  # SDK 테스트 컨테이너
  sdk-tester:
    build: .
    container_name: sdk-tester
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - PROXY_URL=http://nginx-proxy:80
      - KONG_URL=http://kong-minimal:8000
    volumes:
      - ./src:/app/src
      - ./results:/app/results
    depends_on:
      - nginx-proxy
      - kong-minimal
    networks:
      - sdk-test-net
    # 네트워크 격리
    extra_hosts:
      - "api.anthropic.com:127.0.0.1"
    command: node src/test-sdk-proxy.js

networks:
  sdk-test-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
```

**Dockerfile**:
```dockerfile
FROM node:20-alpine

WORKDIR /app

# 네트워크 디버깅 도구
RUN apk add --no-cache curl tcpdump

# 패키지 설치
COPY package.json .
RUN npm install

# 소스 복사
COPY src/ ./src/

CMD ["node", "src/test-sdk-proxy.js"]
```

**Agent 지침**:
```
infrastructure-engineer agent가 위의 Docker 구성을 구현하고,
네트워크 격리가 제대로 작동하는지 확인하고,
컨테이너 간 통신이 원활한지 검증해줘
```

### Phase 3: SDK 테스트 구현

#### 담당 Agent: `backend-engineer`
**임무**: Claude SDK 프록시 테스트 코드 개발

**상세 설계 (제공)**:

**package.json**:
```json
{
  "name": "claude-sdk-proxy-test",
  "version": "1.0.0",
  "dependencies": {
    "@anthropic-ai/sdk": "^0.14.1",
    "undici": "^5.28.0",
    "https-proxy-agent": "^7.0.2"
  },
  "scripts": {
    "test": "node src/test-sdk-proxy.js",
    "test:all": "node src/test-sdk-proxy.js && node src/test-scenarios.js"
  }
}
```

**src/test-sdk-proxy.js**:
```javascript
const Anthropic = require('@anthropic-ai/sdk');
const { ProxyAgent } = require('undici');
const fs = require('fs');

// 결과 저장 객체
const results = {
  timestamp: new Date().toISOString(),
  environment: {
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY ? 'Set' : 'Not set',
    PROXY_URL: process.env.PROXY_URL,
    ANTHROPIC_BASE_URL: process.env.ANTHROPIC_BASE_URL
  },
  tests: {}
};

// Test 1: 직접 연결 (차단되어야 함)
async function testDirectConnection() {
  console.log('\n=== Test 1: Direct Connection (Should Fail) ===');
  try {
    const client = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY
    });
    
    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 10,
      messages: [{ role: 'user', content: 'test' }]
    });
    
    results.tests.directConnection = {
      success: false,
      message: 'Direct connection succeeded (should have been blocked)'
    };
    console.log('❌ Direct connection not blocked');
  } catch (error) {
    results.tests.directConnection = {
      success: true,
      message: 'Direct connection blocked as expected',
      error: error.code || error.message
    };
    console.log('✅ Direct connection blocked:', error.code);
  }
}

// Test 2: ProxyAgent를 통한 연결
async function testProxyAgent() {
  console.log('\n=== Test 2: ProxyAgent Connection ===');
  try {
    const proxyUrl = process.env.PROXY_URL || 'http://nginx-proxy:80';
    const proxyAgent = new ProxyAgent(proxyUrl);
    
    const client = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY,
      fetchOptions: {
        dispatcher: proxyAgent,
        headers: {
          'Accept-Encoding': 'identity' // Kong unmasking 지원
        }
      }
    });
    
    console.log(`Using proxy: ${proxyUrl}`);
    
    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 50,
      messages: [{ 
        role: 'user', 
        content: 'Analyze EC2 instance i-1234567890abcdef0 and S3 bucket my-data-bucket' 
      }]
    });
    
    const responseText = response.content[0].text;
    results.tests.proxyAgent = {
      success: true,
      proxyUrl: proxyUrl,
      responsePreview: responseText.substring(0, 100),
      containsOriginalIds: {
        ec2: responseText.includes('i-1234567890abcdef0'),
        s3: responseText.includes('my-data-bucket')
      }
    };
    
    console.log('✅ Proxy connection successful');
    console.log('Response preview:', responseText.substring(0, 100));
    
  } catch (error) {
    results.tests.proxyAgent = {
      success: false,
      error: error.message,
      stack: error.stack
    };
    console.log('❌ Proxy connection failed:', error.message);
  }
}

// Test 3: 환경변수 테스트
async function testEnvironmentVariables() {
  console.log('\n=== Test 3: Environment Variables ===');
  
  // ANTHROPIC_BASE_URL 설정
  const originalBaseUrl = process.env.ANTHROPIC_BASE_URL;
  process.env.ANTHROPIC_BASE_URL = process.env.PROXY_URL || 'http://nginx-proxy:80';
  
  try {
    const client = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY
    });
    
    console.log(`ANTHROPIC_BASE_URL set to: ${process.env.ANTHROPIC_BASE_URL}`);
    
    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 10,
      messages: [{ role: 'user', content: 'env test' }]
    });
    
    results.tests.environmentVariable = {
      success: true,
      baseUrl: process.env.ANTHROPIC_BASE_URL,
      message: 'ANTHROPIC_BASE_URL is respected'
    };
    console.log('✅ Environment variable works');
    
  } catch (error) {
    results.tests.environmentVariable = {
      success: false,
      baseUrl: process.env.ANTHROPIC_BASE_URL,
      error: error.message,
      note: 'ANTHROPIC_BASE_URL may not be supported by SDK'
    };
    console.log('❌ Environment variable not supported:', error.message);
  } finally {
    process.env.ANTHROPIC_BASE_URL = originalBaseUrl;
  }
}

// Test 4: Custom fetch 구현
async function testCustomFetch() {
  console.log('\n=== Test 4: Custom Fetch Implementation ===');
  try {
    const client = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY,
      fetch: async (url, init) => {
        // Kong으로 리다이렉트
        const kongUrl = url.toString().replace(
          'https://api.anthropic.com',
          process.env.KONG_URL || 'http://kong-minimal:8000'
        );
        console.log('Redirecting:', url, '->', kongUrl);
        
        const fetch = require('node-fetch');
        return fetch(kongUrl, init);
      }
    });
    
    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 20,
      messages: [{ role: 'user', content: 'custom fetch test' }]
    });
    
    results.tests.customFetch = {
      success: true,
      message: 'Custom fetch implementation works'
    };
    console.log('✅ Custom fetch successful');
    
  } catch (error) {
    results.tests.customFetch = {
      success: false,
      error: error.message
    };
    console.log('❌ Custom fetch failed:', error.message);
  }
}

// 메인 실행 함수
async function runAllTests() {
  console.log('Starting Claude SDK Proxy Tests...');
  console.log('Environment:', JSON.stringify(results.environment, null, 2));
  
  await testDirectConnection();
  await testProxyAgent();
  await testEnvironmentVariables();
  await testCustomFetch();
  
  // 결과 저장
  const resultPath = '/app/results/test-results.json';
  fs.writeFileSync(resultPath, JSON.stringify(results, null, 2));
  
  console.log('\n=== Test Summary ===');
  console.log(JSON.stringify(results.tests, null, 2));
  console.log(`\nResults saved to: ${resultPath}`);
  
  // 성공한 테스트 수 계산
  const successCount = Object.values(results.tests)
    .filter(test => test.success).length;
  console.log(`\nSuccess rate: ${successCount}/${Object.keys(results.tests).length}`);
}

// 실행
runAllTests().catch(console.error);
```

**Agent 지침**:
```
backend-engineer agent가 위의 SDK 테스트 코드를 구현하고,
각 프록시 방법의 동작을 정확히 검증하고,
결과를 명확하게 기록하는 시스템을 구축해줘
```

### Phase 4: 마스킹 로직 구현

#### 담당 Agent: `kong-plugin-developer`
**임무**: 독립적인 마스킹 로직 구현

**상세 설계 (제공)**:

**src/simple-masker.js**:
```javascript
// 현재 프로젝트에서 핵심 패턴만 추출한 독립 마스킹 모듈

const maskingPatterns = {
  // EC2 인스턴스
  ec2_instance: {
    pattern: /\bi-[0-9a-f]{8,17}\b/gi,
    replacement: 'EC2_INSTANCE_MASKED'
  },
  
  // S3 버킷
  s3_bucket: {
    // 간단한 버킷 이름 패턴
    pattern: /\b[a-z0-9][a-z0-9\-\.]{2,62}\b/gi,
    replacement: (match) => {
      // 알려진 버킷 패턴인 경우만 마스킹
      if (match.includes('-bucket') || match.includes('bucket-')) {
        return 'S3_BUCKET_MASKED';
      }
      return match;
    }
  },
  
  // Private IP
  private_ip: {
    pattern: /\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g,
    replacement: 'PRIVATE_IP_MASKED'
  },
  
  // RDS 인스턴스
  rds_instance: {
    pattern: /\b[a-z][a-z0-9\-]{0,62}\.rds\.amazonaws\.com\b/gi,
    replacement: 'RDS_INSTANCE_MASKED'
  }
};

function maskContent(text) {
  let maskedText = text;
  
  for (const [key, config] of Object.entries(maskingPatterns)) {
    if (typeof config.replacement === 'string') {
      maskedText = maskedText.replace(config.pattern, config.replacement);
    } else if (typeof config.replacement === 'function') {
      maskedText = maskedText.replace(config.pattern, config.replacement);
    }
  }
  
  return maskedText;
}

function unmaskContent(maskedText, maskingMap) {
  let unmaskedText = maskedText;
  
  for (const [masked, original] of Object.entries(maskingMap)) {
    unmaskedText = unmaskedText.replace(new RegExp(masked, 'g'), original);
  }
  
  return unmaskedText;
}

module.exports = {
  maskContent,
  unmaskContent,
  patterns: maskingPatterns
};
```

**Agent 지침**:
```
kong-plugin-developer agent가 위의 마스킹 로직을 검토하고,
프록시 레벨에서 적용 가능한 구조로 최적화하고,
테스트 케이스를 추가해줘
```

### Phase 5: Kong 프록시 구성

#### 담당 Agent: `kong-plugin-architect`
**임무**: 최소 Kong 설정 설계 및 로깅 구현

**상세 설계 (제공)**:

**kong-minimal/kong.yml**:
```yaml
_format_version: "3.0"
_transform: true

services:
  - name: anthropic-proxy-test
    url: https://api.anthropic.com
    protocol: https
    host: api.anthropic.com
    port: 443
    path: /
    
routes:
  - name: test-proxy-route
    service: anthropic-proxy-test
    paths:
      - /
    preserve_host: false
    
plugins:
  # 요청 로깅
  - name: request-transformer
    config:
      add:
        headers:
          - "X-Proxied-By:kong-test"
          - "X-Test-Time:$(date)"
  
  # 간단한 로깅
  - name: tcp-log
    config:
      host: host.docker.internal
      port: 9999
      
  # 응답 헤더 추가
  - name: response-transformer
    config:
      add:
        headers:
          - "X-Kong-Proxy-Test:true"
```

**kong-minimal/simple-logger.lua**:
```lua
-- 간단한 요청/응답 로깅 플러그인
local plugin = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

function plugin:access(conf)
  kong.log.info("Request: ", kong.request.get_method(), " ", kong.request.get_path())
  kong.log.info("Headers: ", kong.request.get_headers())
end

function plugin:body_filter(conf)
  local body = kong.response.get_raw_body()
  if body then
    kong.log.info("Response body preview: ", string.sub(body, 1, 200))
  end
end

return plugin
```

**Agent 지침**:
```
kong-plugin-architect agent가 위의 Kong 설정을 최적화하고,
요청/응답 로깅이 제대로 작동하도록 구성하고,
프록시 동작 확인을 위한 추가 플러그인을 제안해줘
```

### Phase 6: 네트워크 분석

#### 담당 Agent: `root-cause-analyzer`
**임무**: 프록시 연결 실패 원인 분석

**상세 설계 (제공)**:

**src/network-analyzer.js**:
```javascript
const { exec } = require('child_process');
const fs = require('fs');

async function analyzeNetworkTraffic() {
  console.log('=== Network Traffic Analysis ===');
  
  // tcpdump 실행 (Docker 컨테이너 내)
  const tcpdumpCmd = 'timeout 10 tcpdump -i any -n -s 0 -w /app/results/traffic.pcap host api.anthropic.com or host nginx-proxy or host kong-minimal';
  
  exec(tcpdumpCmd, (error, stdout, stderr) => {
    if (error && error.code !== 124) { // 124는 timeout의 정상 종료 코드
      console.error('tcpdump error:', error);
      return;
    }
    
    // 캡처된 패킷 분석
    exec('tcpdump -r /app/results/traffic.pcap -nn', (err, out) => {
      if (!err) {
        fs.writeFileSync('/app/results/traffic-analysis.txt', out);
        console.log('Traffic analysis saved');
        
        // 프록시 연결 확인
        if (out.includes('nginx-proxy') || out.includes('kong-minimal')) {
          console.log('✅ Proxy traffic detected');
        } else if (out.includes('api.anthropic.com')) {
          console.log('❌ Direct connection to Anthropic detected');
        }
      }
    });
  });
}

module.exports = { analyzeNetworkTraffic };
```

**Agent 지침**:
```
root-cause-analyzer agent가 네트워크 트래픽을 분석하고,
프록시 설정이 무시되는 원인을 진단하고,
해결 방안을 제시해줘
```

### Phase 7: 모니터링 및 보고

#### 담당 Agent: `reliability-monitor`
**임무**: 테스트 결과 수집 및 최종 보고서 작성

**상세 설계 (제공)**:

**src/test-monitor.js**:
```javascript
const fs = require('fs');
const path = require('path');

function generateFinalReport() {
  const results = JSON.parse(
    fs.readFileSync('/app/results/test-results.json', 'utf8')
  );
  
  const report = `# Claude SDK Proxy Test Final Report

## Test Date: ${results.timestamp}

## Environment
- API Key: ${results.environment.ANTHROPIC_API_KEY}
- Proxy URL: ${results.environment.PROXY_URL}
- Base URL: ${results.environment.ANTHROPIC_BASE_URL}

## Test Results Summary

### 1. Direct Connection Test
- Expected: Should be blocked
- Result: ${results.tests.directConnection.success ? '✅ PASS' : '❌ FAIL'}
- Details: ${results.tests.directConnection.message}

### 2. ProxyAgent Test
- Expected: Should connect through proxy
- Result: ${results.tests.proxyAgent.success ? '✅ PASS' : '❌ FAIL'}
${results.tests.proxyAgent.success ? 
  `- Proxy URL: ${results.tests.proxyAgent.proxyUrl}
- Response received: Yes` : 
  `- Error: ${results.tests.proxyAgent.error}`}

### 3. Environment Variable Test
- Expected: ANTHROPIC_BASE_URL should be respected
- Result: ${results.tests.environmentVariable.success ? '✅ PASS' : '❌ FAIL'}
- Note: ${results.tests.environmentVariable.note || 'Working as expected'}

### 4. Custom Fetch Test
- Expected: Should redirect to Kong
- Result: ${results.tests.customFetch.success ? '✅ PASS' : '❌ FAIL'}

## Conclusions

### Proxy Support Status
${results.tests.proxyAgent.success ? 
  '✅ Claude SDK supports proxy configuration via ProxyAgent' : 
  '❌ Claude SDK does not support proxy configuration'}

### Recommended Approach
${results.tests.proxyAgent.success ?
  '1. Use ProxyAgent with undici for proxy support\n2. Implement custom fetch for full control\n3. Kong integration is feasible' :
  '1. Continue using Backend API approach\n2. Monitor SDK updates for proxy support\n3. Consider alternative solutions'}

## Next Steps
${results.tests.proxyAgent.success ?
  '- Implement production-ready proxy wrapper\n- Integrate with Kong aws-masker plugin\n- Create migration guide from Backend API' :
  '- Maintain current Backend API architecture\n- Document SDK limitations\n- Explore alternative SDK options'}
`;

  fs.writeFileSync('/app/results/final-report.md', report);
  console.log('Final report generated: /app/results/final-report.md');
}

module.exports = { generateFinalReport };
```

**Agent 지침**:
```
reliability-monitor agent가 모든 테스트 결과를 수집하고,
성공/실패 패턴을 분석하고,
실행 가능한 권고사항과 함께 최종 보고서를 작성해줘
```

### Phase 8: 통합 실행

#### 담당: `pm-agent` 조율하에 다중 Agent 협업

**통합 실행 계획**:

**Step 1 - 환경 준비**:
```
infrastructure-engineer agent가 Docker 환경을 구성하고 시작하고,
systems-architect agent가 컴포넌트 간 연결을 확인해줘
```

**Step 2 - 테스트 실행**:
```
backend-engineer agent가 SDK 프록시 테스트를 실행하고,
root-cause-analyzer agent가 네트워크 트래픽을 모니터링하고,
kong-plugin-architect agent가 Kong 로그를 분석해줘
```

**Step 3 - 결과 분석**:
```
reliability-monitor agent가 모든 테스트 결과를 수집하고,
root-cause-analyzer agent가 실패 원인을 분석하고,
backend-engineer agent가 추가 검증 테스트를 수행해줘
```

**Step 4 - 최종 보고**:
```
reliability-monitor agent가 최종 보고서를 작성하고,
systems-architect agent가 향후 아키텍처 개선 방안을 제안하고,
pm-agent가 전체 결과를 종합해줘
```

## 실행 명령어

```bash
# 1. 프로젝트 디렉토리 생성
mkdir -p sdk-proxy
cd sdk-proxy

# 2. 환경변수 설정
export ANTHROPIC_API_KEY=sk-ant-api03-xxxxx

# 3. 전체 테스트 실행
docker-compose up --build

# 4. 결과 확인
cat results/test-results.json
cat results/final-report.md

# 5. 로그 분석
docker logs sdk-test-proxy
docker logs sdk-test-kong
```

## 성공 기준

1. **ProxyAgent 테스트 성공**: SDK가 프록시를 통해 API 호출 가능
2. **네트워크 격리 확인**: 직접 연결이 차단됨
3. **로깅 동작**: 프록시 서버에서 요청/응답 로그 확인
4. **최종 보고서**: 명확한 결론과 권고사항 도출

## 프로젝트 독립성 보장

- 별도 Docker 네트워크 (172.30.0.0/16)
- 독립적인 포트 사용 (8888, 8000)
- 현재 프로젝트 파일 미참조
- 자체 마스킹 로직 구현
- 격리된 테스트 환경

이 계획은 각 전문가 Agent가 자신의 전문 영역에서 독립적으로 작업하면서도, 전체 프로젝트 목표를 달성할 수 있도록 구성되었습니다.