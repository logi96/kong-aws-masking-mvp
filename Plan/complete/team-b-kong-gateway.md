# Plan: Team B - Kong Gateway Plugin Development

## 팀 개요
**팀명**: Kong Gateway Team  
**역할**: AWS Masker 플러그인 개발 및 Kong 구성 관리  
**독립성**: Mock Backend API를 사용하여 독립적 개발 가능  
**시작 조건**: Infrastructure 팀의 Docker 환경 준비 완료 후

## CLAUDE.md 핵심 준수사항
- [ ] **Testing First**: Lua 테스트 프레임워크로 TDD 적용
- [ ] **No Direct AWS Exposure**: 모든 AWS 리소스 마스킹 보장
- [ ] **Response Time**: 마스킹 처리 < 100ms
- [ ] **Code Standards**: Lua 코딩 표준 엄격 준수

## 목표 (Task Planning Rule)
- **PLAN**: Lua 기반 Kong 커스텀 플러그인으로 AWS 리소스 자동 마스킹
- **GOAL**: 요청/응답의 모든 AWS 식별자를 안전하게 마스킹/언마스킹
- **METRIC**: 정의된 AWS 리소스 패턴 100% 감지 및 마스킹, 처리 시간 < 100ms

## 작업 목록

### Phase 1: 개발 환경 설정 (Day 2 - 4시간)

#### 1.1 Kong 플러그인 개발 환경
```
kong/plugins/aws-masker/
├── handler.lua         # 메인 플러그인 로직
├── schema.lua          # 설정 스키마
├── masker.lua         # 마스킹 유틸리티
├── patterns.lua       # AWS 패턴 정의
└── spec/
    ├── aws-masker_spec.lua
    ├── unit/
    └── integration/
```

**Tasks**:
- [ ] 플러그인 디렉토리 구조 생성
- [ ] Lua 개발 도구 설정 (LuaRocks, busted)
- [ ] Kong 플러그인 템플릿 생성
- [ ] 로컬 테스트 환경 구성

#### 1.2 Mock Backend 설정
**Tasks**:
- [ ] Mock Backend 응답 데이터 준비
- [ ] AWS 리소스 샘플 데이터 생성
- [ ] 테스트용 Claude API Mock 응답

### Phase 2: 플러그인 스키마 개발 (Day 2-3 - 6시간)

#### 2.1 schema.lua 구현
```lua
-- schema.lua
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "aws-masker",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { ttl = { type = "number", default = 300 } },
          { mask_request = { type = "boolean", default = true } },
          { mask_response = { type = "boolean", default = true } },
          { patterns = {
              type = "array",
              elements = { type = "string" },
              default = {}
          }},
        },
    }},
  },
}
```

**Tasks**:
- [ ] 플러그인 설정 스키마 정의
- [ ] 검증 규칙 구현
- [ ] 기본값 설정
- [ ] 스키마 단위 테스트 작성

### Phase 3: AWS 패턴 매칭 엔진 (Day 3-4 - 12시간)

#### 3.1 patterns.lua - AWS 리소스 패턴
```lua
-- patterns.lua
local _M = {}

_M.patterns = {
  ec2_instance = {
    pattern = "i%-[0-9a-f]{8,17}",
    replacement = "EC2_%03d",
    type = "ec2"
  },
  private_ip = {
    pattern = "10%.%d+%.%d+%.%d+",
    replacement = "PRIVATE_IP_%03d",
    type = "ip"
  },
  s3_bucket = {
    pattern = "[a-z0-9][a-z0-9%-]{1,61}[a-z0-9]%.s3",
    replacement = "BUCKET_%03d",
    type = "s3"
  },
  -- ... 추가 패턴
}

return _M
```

**Tasks**:
- [ ] TDD: 패턴 매칭 테스트 작성
- [ ] EC2 인스턴스 ID 패턴 구현
- [ ] Private IP 주소 패턴 구현
- [ ] S3 버킷명 패턴 구현
- [ ] RDS 인스턴스 패턴 구현
- [ ] 패턴 성능 최적화 (pre-compile)

#### 3.2 masker.lua - 마스킹 엔진
```lua
-- masker.lua
local _M = {}
local patterns = require "kong.plugins.aws-masker.patterns"

function _M.mask_data(data, mapping_store)
  -- 마스킹 로직 구현
end

function _M.unmask_data(data, mapping_store)
  -- 언마스킹 로직 구현
end

return _M
```

**Tasks**:
- [ ] TDD: 마스킹/언마스킹 테스트 작성
- [ ] 마스킹 맵 저장소 구현 (TTL 지원)
- [ ] JSON 깊은 탐색 및 마스킹
- [ ] 일관된 마스킹 ID 생성
- [ ] 순환 참조 방지

### Phase 4: 핸들러 구현 (Day 4-5 - 12시간)

#### 4.1 handler.lua - 플러그인 메인 로직
```lua
-- handler.lua
local BasePlugin = require "kong.plugins.base_plugin"
local masker = require "kong.plugins.aws-masker.masker"

local AwsMaskerHandler = BasePlugin:extend()
AwsMaskerHandler.VERSION = "1.0.0"
AwsMaskerHandler.PRIORITY = 800

function AwsMaskerHandler:new()
  AwsMaskerHandler.super.new(self, "aws-masker")
end

function AwsMaskerHandler:access(conf)
  AwsMaskerHandler.super.access(self)
  -- 요청 마스킹
end

function AwsMaskerHandler:body_filter(conf)
  AwsMaskerHandler.super.body_filter(self)
  -- 응답 언마스킹
end

return AwsMaskerHandler
```

**Tasks**:
- [ ] TDD: 핸들러 라이프사이클 테스트
- [ ] access 단계: 요청 바디 마스킹
- [ ] body_filter 단계: 응답 언마스킹
- [ ] 에러 핸들링 및 폴백
- [ ] 성능 모니터링 추가

### Phase 5: 통합 및 성능 최적화 (Day 5-6 - 8시간)

#### 5.1 Kong 통합 테스트
**Tasks**:
- [ ] Kong 테스트 하네스 설정
- [ ] 플러그인 로드 테스트
- [ ] End-to-End 마스킹 테스트
- [ ] 에러 시나리오 테스트

#### 5.2 성능 최적화
**Tasks**:
- [ ] 패턴 매칭 벤치마크
- [ ] 메모리 사용량 프로파일링
- [ ] 대용량 페이로드 테스트
- [ ] 동시성 테스트

### Phase 6: 설정 및 문서화 (Day 6 - 4시간)

#### 6.1 Kong 선언적 설정
```yaml
# kong.yml
plugins:
  - name: aws-masker
    service: backend-api
    config:
      ttl: 300
      mask_request: true
      mask_response: true
```

**Tasks**:
- [ ] 플러그인 설정 템플릿 작성
- [ ] 환경별 설정 분리
- [ ] 플러그인 활성화 가이드

#### 6.2 문서화
**Tasks**:
- [ ] 플러그인 사용 가이드
- [ ] API 문서
- [ ] 트러블슈팅 가이드
- [ ] 성능 튜닝 가이드

## Mock 인터페이스 정의

### Backend API Mock (Kong 팀 독립 개발용)
```javascript
// Mock 응답 예시
{
  "instances": [
    { "id": "i-1234567890abcdef0", "ip": "10.0.0.1" }
  ],
  "buckets": ["my-bucket-name.s3.amazonaws.com"]
}
```

### Claude API Mock
```javascript
// Mock Claude 응답
{
  "analysis": "EC2_001 has PRIVATE_IP_001 configuration"
}
```

## 성공 기준

### 기능적 요구사항
- ✅ 모든 AWS 리소스 타입 100% 마스킹
- ✅ 요청/응답 양방향 처리
- ✅ 마스킹 일관성 보장 (같은 리소스 = 같은 마스크)
- ✅ TTL 기반 매핑 정리

### 비기능적 요구사항
- ✅ 마스킹 처리 시간 < 100ms
- ✅ 메모리 사용량 < 50MB
- ✅ 테스트 커버리지 > 80%
- ✅ Lua 코딩 표준 100% 준수

## 산출물

1. **플러그인 코드**
   - handler.lua
   - schema.lua
   - masker.lua
   - patterns.lua

2. **테스트 코드**
   - 단위 테스트
   - 통합 테스트
   - 성능 테스트

3. **설정 파일**
   - kong.yml 템플릿
   - 플러그인 설정 예시

4. **문서**
   - 플러그인 개발 가이드
   - API 레퍼런스
   - 성능 벤치마크 결과

## 일정

- **Day 2**: 환경 설정 및 스키마 개발 시작
- **Day 3-4**: AWS 패턴 매칭 엔진 구현
- **Day 4-5**: 핸들러 구현 및 통합
- **Day 6**: 최적화 및 문서화

## 참조 표준
- [17-kong-plugin-development-guide.md](../../Docs/Standards/17-kong-plugin-development-guide.md)
- [18-aws-resource-masking-patterns.md](../../Docs/Standards/18-aws-resource-masking-patterns.md)
- [02-code-standards-base-rules.md](../../Docs/Standards/02-code-standards-base-rules.md) (Lua 섹션)
- [01-tdd-strategy-guide.md](../../Docs/Standards/01-tdd-strategy-guide.md)

---

**Note**: 이 팀은 Infrastructure 팀이 제공하는 환경에서 Mock을 사용하여 독립적으로 개발합니다.