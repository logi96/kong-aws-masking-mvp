# Kong DB-less AWS Multi-Resource Masking MVP - 간소화된 PRD

## 1. 프로젝트 개요

### 1.1 목적
AWS CLI로 수집한 EC2, S3, RDS 정보를 Kong DB-less 모드를 통해 안전하게 마스킹하여 Claude API로 전송하고, 기본적인 보안 분석을 수행하는 MVP 구축

### 1.2 MVP 범위 (축소됨)
- **핵심 기능만 구현**: 단순 마스킹/복원
- **기본 리소스만 지원**: EC2, S3, RDS
- **단순 분석만 수행**: 보안 취약점 기본 검사

### 1.3 성공 기준 (간소화)
- [ ] 주요 AWS 리소스 ID 마스킹/복원 작동
- [ ] Claude가 마스킹된 데이터로 기본 분석 수행
- [ ] Docker Compose로 원클릭 실행
- [ ] 기본적인 에러 없이 작동

## 2. 시스템 아키텍처 (단순화)

```
┌─────────────────┬─────────────────┬─────────────────┐
│  Backend API    │  Kong Gateway   │   Claude API    │
│  (Port 3000)    │  (Port 8000)    │   (External)    │
│                 │                 │                 │
│ AWS CLI 실행 ───▶ 마스킹 처리 ────▶ 분석 수행      │
│ 결과 반환 ◀───── 복원 처리 ◀────── 응답 반환      │
└─────────────────┴─────────────────┴─────────────────┘
```

## 3. 기술 스택 (2025년 최신)

| 컴포넌트 | 기술 | 버전 | 비고 |
|----------|------|------|------|
| API Gateway | Kong | 3.9.0.1 | DB-less 모드 |
| Backend | Node.js | 20.x LTS | JavaScript + JSDoc |
| AI API | Claude | 3.5 Sonnet | 80% 비용 절감 |
| 컨테이너 | Docker Compose | 3.8 | |
| AWS CLI | AWS CLI v2 | latest | 공식 Docker 이미지 |

## 4. 간소화된 마스킹 규칙

| 리소스 타입 | 원본 예시 | 마스킹 후 |
|------------|----------|----------|
| EC2 Instance | i-0a1b2c3d4e5f | EC2_001 |
| Private IP | 10.0.1.123 | PRIVATE_IP_001 |
| S3 Bucket | my-bucket-2024 | BUCKET_001 |
| RDS Instance | prod-mysql-01 | RDS_001 |

## 5. 구현 컴포넌트 (MVP 버전)

### 5.1 디렉토리 구조 (간소화)
```
kong-aws-masking-mvp/
├── docker-compose.yml
├── .env
├── kong/
│   ├── kong.yml          # 선언적 설정
│   └── plugins/
│       └── aws-masker/
│           ├── handler.lua    # 핵심 로직만
│           └── schema.lua     # 기본 스키마
├── backend/
│   ├── package.json
│   └── server.js         # 단순 구현
└── README.md
```

### 5.2 Docker Compose 설정 (보안 강화)
```yaml
version: '3.8'

services:
  kong:
    image: kong:3.9.0.1
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: "/kong/kong.yml"
      KONG_PROXY_ACCESS_LOG: "/dev/stdout"
      KONG_PROXY_ERROR_LOG: "/dev/stderr"
    ports:
      - "8000:8000"
      - "8001:8001"
    volumes:
      - ./kong/kong.yml:/kong/kong.yml:ro
      - ./kong/plugins:/usr/local/share/lua/5.1/kong/plugins:ro
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 5

  backend:
    build: ./backend
    environment:
      KONG_PROXY_URL: "http://kong:8000"
      ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
      AWS_REGION: "${AWS_REGION:-us-east-1}"
    ports:
      - "3000:3000"
    volumes:
      - ~/.aws:/root/.aws:ro  # 읽기 전용으로 마운트
    depends_on:
      kong:
        condition: service_healthy
```

## 6. Kong 플러그인 간소화

### 6.1 기본 마스킹 로직만 구현
```lua
-- handler.lua (간소화)
local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson"

local AwsMaskerHandler = BasePlugin:extend()

-- 단순 패턴 정의
local patterns = {
  {pattern = "i%-[a-f0-9]+", prefix = "EC2_"},
  {pattern = "10%.%d+%.%d+%.%d+", prefix = "PRIVATE_IP_"},
  {pattern = "[a-z0-9%-]+%-bucket", prefix = "BUCKET_"},
  {pattern = "prod%-[a-z]+%-[0-9]+", prefix = "RDS_"}
}

function AwsMaskerHandler:access(conf)
  local body = kong.request.get_raw_body()
  if not body then return end
  
  -- 단순 마스킹
  local counter = {}
  for _, p in ipairs(patterns) do
    counter[p.prefix] = 0
    body = body:gsub(p.pattern, function(match)
      counter[p.prefix] = counter[p.prefix] + 1
      local masked = p.prefix .. string.format("%03d", counter[p.prefix])
      -- 매핑 저장 (단순 구현)
      ngx.ctx.mappings = ngx.ctx.mappings or {}
      ngx.ctx.mappings[masked] = match
      return masked
    end)
  end
  
  kong.service.request.set_raw_body(body)
end

function AwsMaskerHandler:body_filter(conf)
  local chunk = ngx.arg[1]
  if chunk and ngx.ctx.mappings then
    -- 단순 복원
    for masked, original in pairs(ngx.ctx.mappings) do
      chunk = chunk:gsub(masked, original)
    end
    ngx.arg[1] = chunk
  end
end

return AwsMaskerHandler
```

### 6.2 Kong 설정 (간소화)
```yaml
# kong.yml
_format_version: "3.0"
_comment: "Kong Gateway 3.9.0.1 - MVP Configuration"

services:
  - name: claude-api
    url: https://api.anthropic.com
    routes:
      - name: analyze-route
        paths:
          - /analyze-aws

plugins:
  - name: aws-masker
    service: claude-api
    config:
      enabled: true
```

## 7. Backend API (간소화)

```javascript
// server.js (MVP 버전)
const express = require('express');
const axios = require('axios');
const { exec } = require('child_process');
const util = require('util');

const app = express();
app.use(express.json());

const execAsync = util.promisify(exec);
const CLAUDE_MODEL = 'claude-3-5-sonnet-20241022'; // 비용 효율적

/**
 * AWS 리소스를 수집합니다
 * @returns {Promise<{ec2: Array, s3: Array, rds: Array}>} AWS 리소스 정보
 */
async function collectAWSResources() {
  const resources = {};
  
  try {
    // EC2
    const { stdout: ec2Data } = await execAsync(
      'aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]" --output json'
    );
    resources.ec2 = JSON.parse(ec2Data);
    
    // S3
    const { stdout: s3Data } = await execAsync(
      'aws s3api list-buckets --query "Buckets[*].Name" --output json'
    );
    resources.s3 = JSON.parse(s3Data);
    
    // RDS
    const { stdout: rdsData } = await execAsync(
      'aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output json'
    );
    resources.rds = JSON.parse(rdsData);
  } catch (error) {
    console.error('AWS CLI Error:', error);
  }
  
  return resources;
}

/**
 * AWS 리소스 분석 엔드포인트
 * @param {import('express').Request} req - Express 요청 객체
 * @param {import('express').Response} res - Express 응답 객체
 */
app.post('/analyze', async (req, res) => {
  try {
    // AWS 데이터 수집
    const awsData = await collectAWSResources();
    
    // Kong 프록시를 통해 Claude API 호출
    const response = await axios.post(
      'http://kong:8000/analyze-aws/v1/messages',
      {
        model: CLAUDE_MODEL,
        max_tokens: 2000,
        messages: [{
          role: 'user',
          content: `Analyze this AWS infrastructure for basic security issues:\n${JSON.stringify(awsData, null, 2)}`
        }]
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': process.env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01'
        }
      }
    );
    
    res.json({
      status: 'success',
      analysis: response.data
    });
  } catch (error) {
    console.error('Error:', error.message);
    res.status(500).json({ error: 'Analysis failed' });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

## 8. 빠른 시작 가이드

### 8.1 환경 설정
```bash
# 1. 프로젝트 클론
git clone <repository>
cd kong-aws-masking-mvp

# 2. 환경변수 설정
cat > .env << EOF
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
AWS_REGION=us-east-1
EOF

# 3. AWS 자격증명 확인
aws sts get-caller-identity
```

### 8.2 실행
```bash
# 빌드 및 실행
docker-compose up --build

# 헬스체크
curl http://localhost:3000/health

# 분석 실행
curl -X POST http://localhost:3000/analyze
```

## 9. MVP 테스트 계획

### 9.1 기본 테스트만
- [ ] 마스킹 작동 확인
- [ ] Claude API 응답 확인
- [ ] 복원 작동 확인

### 9.2 성공 지표
- 에러 없이 실행
- 마스킹된 데이터로 분석 가능
- 5초 이내 응답

## 10. 다음 단계 (MVP 이후)

MVP 검증 성공 후:
1. 메모리 관리 개선
2. 에러 처리 강화
3. 패턴 매칭 최적화
4. 모니터링 추가

---

**예상 구현 시간**: 2-3일 (복잡한 기능 제외로 대폭 단축)
