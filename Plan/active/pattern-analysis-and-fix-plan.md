# Kong AWS Masker 패턴 분석 및 수정 계획

## 🔍 상세 분석 결과

### 1. 패턴 시스템 구조
현재 시스템은 3단계 구조로 되어 있습니다:

1. **patterns.lua** - 기본 패턴 정의 (50개)
   - 단순한 10자리 API Gateway 패턴 포함 (문제의 원인)
   ```lua
   api_gateway = {
     pattern = "[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]",
     replacement = "API_GW_%03d"
   }
   ```

2. **patterns_extension.lua** - 확장 패턴 정의 (40개 추가)
   - 더 구체적인 API Gateway 패턴 포함
   ```lua
   api_gateway_id = {
     pattern = "([a-z0-9]{10})%.execute%-api%.([^%.]+)%.amazonaws%.com",
     replacement = "APIGW_%03d.execute-api.$2.amazonaws.com"
   }
   ```

3. **pattern_integrator.lua** - 패턴 통합 및 우선순위 관리
   - 충돌 검사
   - 우선순위 재조정

### 2. 현재 문제점

#### 2.1 패턴 통합 미사용
- `masker_ngx_re.lua`가 `patterns.lua`만 사용
- `pattern_integrator.lua`가 실제로 호출되지 않음
- 확장 패턴들이 적용되지 않음

#### 2.2 API Gateway 패턴 과도한 매칭
- 10자리 소문자/숫자 조합을 모두 매칭
- 일반 텍스트까지 마스킹되어 컨텍스트 손실

#### 2.3 패턴 초기화 로직
```lua
-- masker_ngx_re.lua:194
function _M.init_patterns()
  for name, pattern_def in pairs(patterns.patterns) do
    -- patterns.lua만 사용 중
  end
end
```

### 3. spec 폴더 분석 결과

테스트 파일 구조:
- `unit/` - 단위 테스트
  - `handler_spec.lua` - 핸들러 테스트
  - `masker_spec.lua` - 마스킹 로직 테스트
  - `patterns_spec.lua` - 패턴 테스트
  - `schema_spec.lua` - 스키마 검증
- `integration/` - 통합 테스트
- `mock_data.lua` - 테스트용 모의 데이터
- `mock_kong.lua` - Kong API 모의 객체

## 🎯 구체적 수정 계획

### Phase 1: 즉시 수정 (긴급)

#### 1.1 API Gateway 패턴 수정
```lua
-- patterns.lua 수정
api_gateway = {
  -- 기존: "[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]"
  -- 수정: API Gateway ID는 execute-api URL에서만 찾도록 변경
  pattern = "([a-z0-9]{10})(?=%.execute%-api%.)",
  replacement = "API_GW_%03d",
  type = "apigateway",
  description = "API Gateway ID (in execute-api URLs only)"
}
```

#### 1.2 패턴 통합 활성화
```lua
-- masker_ngx_re.lua 수정
local patterns = require "kong.plugins.aws-masker.patterns"
local pattern_integrator = require "kong.plugins.aws-masker.pattern_integrator"  -- 추가

function _M.init_patterns()
  -- 기존 패턴과 확장 패턴 통합
  local integrated_patterns = pattern_integrator.integrate_patterns(patterns.patterns)
  
  for _, pattern_def in ipairs(integrated_patterns) do
    -- 패턴 초기화 로직
  end
end
```

### Phase 2: 검증 및 테스트

#### 2.1 단일 패턴 테스트
- EC2 인스턴스 ID 마스킹 확인
- API Gateway 패턴이 과도하게 매칭되지 않는지 확인
- 각 AWS 리소스 타입별 검증

#### 2.2 50개 패턴 재실행
- 수정된 패턴으로 전체 테스트
- 보안 검증 (Claude가 원본을 볼 수 없는지)
- 성능 측정

### Phase 3: 최적화 및 정리

#### 3.1 불필요한 코드 제거
- 중복 패턴 제거
- 사용하지 않는 테스트 파일 정리
- 주석 처리된 코드 제거

#### 3.2 문서화
- 패턴 통합 프로세스 문서화
- API Gateway 패턴 수정 사유 기록
- 테스트 결과 보고서 작성

## 🚨 보안 고려사항

1. **패턴 우선순위**
   - 더 구체적인 패턴이 먼저 매칭되도록 우선순위 조정
   - 과도한 매칭 방지

2. **Fail-Secure**
   - 패턴 매칭 실패 시 요청 차단
   - 에러 발생 시 원본 노출 방지

3. **성능 영향**
   - 패턴 수 증가로 인한 성능 영향 최소화
   - Redis 캐싱 활용

## 📋 실행 순서

1. **백업** - 현재 patterns.lua 백업
2. **수정** - API Gateway 패턴 수정
3. **통합** - pattern_integrator 활성화
4. **재시작** - Kong 재시작
5. **테스트** - 단일 패턴 테스트
6. **검증** - 50개 패턴 전체 테스트
7. **보고** - 결과 보고서 작성

## ⏱️ 예상 소요 시간

- Phase 1: 30분 (코드 수정 및 재시작)
- Phase 2: 1시간 (테스트 실행 및 검증)
- Phase 3: 30분 (최적화 및 문서화)

총 예상 시간: 2시간

## 🎯 성공 기준

1. API Gateway 패턴이 의도한 대로만 매칭
2. 50개 패턴 모두 정상 작동
3. Claude가 마스킹된 데이터만 수신
4. 성능 저하 없음 (< 5초 응답)