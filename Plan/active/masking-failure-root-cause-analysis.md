# Kong AWS Masking 실패 근본 원인 분석 보고서

## 🔍 깊이 있는 분석 결과

### 1. 코드 변경 이력 분석

#### Git 커밋 분석
- 총 3개 커밋만 존재 (히스토리가 짧음)
- 4229e72 커밋: "feat: Complete Kong AWS masking MVP implementation"

#### 파일 구조 변화
**이전 (4229e72 커밋)**:
- `masker.lua` - 단순한 Lua 패턴 기반 마스킹
- `handler.lua` - masker.lua 사용
- `text_masker_v2.lua` - 복합 텍스트 처리용 (계획됨)

**현재**:
- `masker_ngx_re.lua` - ngx.re 기반 고급 마스킹 (새로 추가)
- `handler.lua` - masker_ngx_re.lua로 변경됨
- `masker.lua` - 여전히 존재하지만 사용되지 않음

### 2. 핵심 문제점 발견

#### 2.1 마스킹 로직 변경
**이전 masker.lua** (작동했던 버전):
```lua
for pattern_name, pattern_def in pairs(patterns.patterns) do
  -- 모든 패턴을 직접 순회하며 처리
  for match in string.gmatch(text, pattern_def.pattern) do
    -- 매칭된 모든 항목 마스킹
  end
end
```

**현재 masker_ngx_re.lua** (문제 있는 버전):
```lua
for pattern_name, pattern_info in pairs(pattern_config) do
  -- pattern_config만 순회 (초기화 문제 가능성)
  if pattern_info.use_ngx_re and ngx and ngx.re then
    -- ngx.re 사용 (일부 패턴만)
  else
    -- Lua 패턴 사용 (하지만 로직이 다름)
  end
end
```

#### 2.2 패턴 통합 시스템의 복잡성
1. `patterns.lua` - 기본 패턴 (테이블 구조)
2. `patterns_extension.lua` - 확장 패턴 (배열 구조)
3. `pattern_integrator.lua` - 통합 로직
4. `masker_ngx_re.lua` - pattern_config 사용

이 복잡한 구조로 인해:
- 패턴이 제대로 초기화되지 않음
- 일부 패턴만 작동
- 500 에러 발생 (undefined 응답)

#### 2.3 Phase별 처리의 문제
masker_ngx_re.lua는 3단계 처리를 시도:
1. Phase 1: Redis 후보 추출
2. Phase 2: Redis 매핑 처리
3. Phase 3: 실제 마스킹 적용

하지만 Phase 3에서 pattern_config 순회 시 모든 패턴이 포함되지 않음.

### 3. 왜 이전에는 작동했는가?

#### 완료된 계획 문서 분석
`phase3-aws-masking-expansion-plan-completed.md`에 따르면:
- text_masker_v2.lua가 계획되었음
- 복합 텍스트 처리를 위한 설계
- 하지만 실제 구현은 masker_ngx_re.lua로 변경됨

#### 가능한 시나리오
1. 초기에는 masker.lua로 테스트 (성공)
2. 성능 개선을 위해 masker_ngx_re.lua 도입
3. 하지만 모든 패턴이 제대로 이전되지 않음
4. 테스트가 부분적으로만 수행됨

### 4. 해결 방안

#### Option 1: 이전 방식으로 복원 (빠른 해결)
```bash
# handler.lua 수정
local masker = require "kong.plugins.aws-masker.masker"  # masker_ngx_re 대신
```

#### Option 2: masker_ngx_re.lua 수정 (권장)
```lua
-- mask_data 함수 수정
-- pattern_config 대신 직접 패턴 사용
for pattern_name, pattern_def in pairs(patterns.patterns) do
  -- 기존 masker.lua의 로직 적용
end
```

#### Option 3: 하이브리드 접근
- 간단한 패턴: Lua string 패턴 사용
- 복잡한 패턴 (ARN 등): ngx.re 사용
- 하지만 모든 패턴이 처리되도록 보장

### 5. 즉시 실행 가능한 조치

1. **백업 생성**
   ```bash
   cp handler.lua handler.lua.backup
   cp masker_ngx_re.lua masker_ngx_re.lua.backup2
   ```

2. **Option 1 테스트** (가장 빠름)
   - handler.lua에서 masker.lua 사용으로 변경
   - 50개 패턴 테스트 재실행

3. **성공 시**: 
   - masker_ngx_re.lua의 문제점 상세 분석
   - 단계적 마이그레이션 계획 수립

4. **실패 시**:
   - Option 2로 진행
   - mask_data 함수 재구현

### 6. 권장사항

**즉시**: Option 1 (이전 작동 버전으로 복원)
- 리스크 최소화
- 빠른 문제 해결
- 보안 우선

**장기적**: masker_ngx_re.lua 개선
- 성능 이점 활용
- 하지만 모든 패턴 지원 보장

### 7. 교훈

1. **복잡성의 함정**: 단순한 해결책이 더 안정적일 수 있음
2. **테스트 커버리지**: 모든 패턴에 대한 개별 테스트 필요
3. **점진적 마이그레이션**: 한 번에 모든 것을 바꾸지 말 것
4. **문서화**: 왜 변경했는지 기록 필요