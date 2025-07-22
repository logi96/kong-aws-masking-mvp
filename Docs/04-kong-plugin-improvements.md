# Kong DB-less AWS Multi-Resource Masking MVP - Kong 플러그인 간소화 가이드

## 요약
MVP에서는 작동하는 최소한의 마스킹 플러그인만 구현합니다. 복잡한 기능은 모두 제거합니다.

## 1. MVP 플러그인 구조 (최소화)

### 1.1 디렉토리 구조
```
kong/plugins/aws-masker/
├── handler.lua    # 핵심 로직만
└── schema.lua     # 기본 설정만
```

### 1.2 schema.lua (간단 버전)
```lua
return {
  name = "aws-masker",
  fields = {
    { config = {
        type = "record",
        fields = {
          { enabled = { type = "boolean", default = true } },
        },
    } },
  },
}
```

### 1.3 handler.lua (MVP 버전)
```lua
local BasePlugin = require "kong.plugins.base_plugin"

local AwsMaskerHandler = BasePlugin:extend()

AwsMaskerHandler.PRIORITY = 900
AwsMaskerHandler.VERSION = "0.1.0"

-- 단순 패턴 (정규식 최소화)
local patterns = {
  -- EC2 인스턴스 ID
  { pattern = "i%-[0-9a-f]+", prefix = "EC2_" },
  -- Private IP
  { pattern = "10%.%d+%.%d+%.%d+", prefix = "PRIVATE_IP_" },
  -- S3 버킷 (간단 패턴)
  { pattern = "[a-z0-9%-]+%-bucket", prefix = "BUCKET_" },
  -- RDS 인스턴스
  { pattern = "[a-z]+-mysql-[0-9]+", prefix = "RDS_" }
}

function AwsMaskerHandler:new()
  AwsMaskerHandler.super.new(self, "aws-masker")
end

function AwsMaskerHandler:access(conf)
  AwsMaskerHandler.super.access(self)
  
  -- 요청 본문 읽기
  local body = kong.request.get_raw_body()
  if not body then
    return
  end
  
  -- 마스킹 매핑 초기화
  ngx.ctx.mask_map = {}
  local counter = {}
  
  -- 단순 문자열 치환
  for _, p in ipairs(patterns) do
    counter[p.prefix] = counter[p.prefix] or 0
    
    body = body:gsub(p.pattern, function(match)
      -- 이미 마스킹된 값인지 확인
      if ngx.ctx.mask_map[match] then
        return ngx.ctx.mask_map[match]
      end
      
      -- 새 마스킹 값 생성
      counter[p.prefix] = counter[p.prefix] + 1
      local masked = p.prefix .. string.format("%03d", counter[p.prefix])
      
      -- 매핑 저장
      ngx.ctx.mask_map[match] = masked
      ngx.ctx.mask_map[masked] = match  -- 역방향도 저장
      
      kong.log.debug("Masked: ", match, " -> ", masked)
      return masked
    end)
  end
  
  -- 마스킹된 본문 설정
  kong.service.request.set_raw_body(body)
end

function AwsMaskerHandler:body_filter(conf)
  AwsMaskerHandler.super.body_filter(self)
  
  -- 응답 청크 처리
  local chunk = ngx.arg[1]
  local eof = ngx.arg[2]
  
  -- 버퍼링
  ngx.ctx.response_buffer = (ngx.ctx.response_buffer or "") .. (chunk or "")
  
  if eof then
    -- 마스킹 복원
    local body = ngx.ctx.response_buffer
    
    if ngx.ctx.mask_map then
      -- 역방향 치환 (마스킹 -> 원본)
      for masked, original in pairs(ngx.ctx.mask_map) do
        -- 마스킹된 값만 복원 (PREFIX_숫자 형식)
        if masked:match("^[A-Z_]+_%d+$") then
          body = body:gsub(masked, original)
        end
      end
    end
    
    ngx.arg[1] = body
  else
    -- 청크 모드에서는 nil 반환
    ngx.arg[1] = nil
  end
end

return AwsMaskerHandler
```

## 2. Kong 설정 (최소화)

### 2.1 kong.yml
```yaml
_format_version: "3.0"

services:
  - name: claude-service
    url: https://api.anthropic.com
    routes:
      - name: analyze-route
        paths:
          - /analyze-aws

plugins:
  - name: aws-masker
    service: claude-service
    config:
      enabled: true
```

### 2.2 Dockerfile (필요시)
```dockerfile
FROM kong:3.9.0.1

# 플러그인 복사
COPY ./plugins /usr/local/share/lua/5.1/kong/plugins

# 플러그인 활성화
ENV KONG_PLUGINS="bundled,aws-masker"
```

## 3. 테스트 방법

### 3.1 단위 테스트 (선택사항)
```lua
-- test.lua
local handler = require "kong.plugins.aws-masker.handler"

-- 테스트 데이터
local test_data = [[
{
  "instance": "i-0a1b2c3d4e5f",
  "ip": "10.0.1.100",
  "bucket": "my-data-bucket",
  "db": "prod-mysql-01"
}
]]

-- 마스킹 테스트
print("Original:", test_data)
-- 실제 테스트는 Kong 환경에서 실행
```

### 3.2 통합 테스트
```bash
# 1. Kong 시작
docker-compose up -d kong

# 2. 플러그인 확인
curl http://localhost:8001/plugins

# 3. 테스트 요청
curl -X POST http://localhost:8000/analyze-aws \
  -H "Content-Type: application/json" \
  -d '{
    "instance": "i-1234567890",
    "ip": "10.0.1.100"
  }'
```

## 4. 일반적인 문제 해결

### 플러그인이 로드되지 않음
```bash
# Kong 로그 확인
docker-compose logs kong | grep aws-masker

# 플러그인 경로 확인
docker exec kong ls /usr/local/share/lua/5.1/kong/plugins/
```

### 마스킹이 작동하지 않음
1. 패턴이 너무 복잡하지 않은지 확인
2. 로그 레벨을 debug로 설정
3. `kong.log.debug()` 출력 확인

## 5. MVP에서 제외된 기능

### ❌ 제거된 복잡성
- 재귀적 JSON 파싱
- 복잡한 에러 처리
- 동시성 제어
- 성능 최적화
- Trie 구조
- 메모리 관리

### ✅ MVP 포커스
- 단순 문자열 치환
- 기본 매핑 저장
- 간단한 복원

## 6. 성능 기대치

- **처리 속도**: 요청당 10-50ms
- **메모리 사용**: 요청당 < 1MB
- **동시 처리**: 100 req/s 가능

## 7. 다음 단계 (MVP 이후)

MVP 검증 후 필요시:
1. JSON 파싱 추가
2. 에러 처리 강화
3. 패턴 확장

## 8. 결론

MVP 플러그인은:
- **100줄 이하 코드**: 이해하기 쉬움
- **기본 기능만**: 마스킹과 복원
- **빠른 개발**: 1일 이내 구현 가능

이 구현으로 기본적인 AWS 리소스 마스킹이 가능하며, MVP 검증에 충분합니다.

---
*원칙: 최소 기능으로 최대 가치 검증*
