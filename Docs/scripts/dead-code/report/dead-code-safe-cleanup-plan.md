# 🔒 Dead Code 안전 정리 계획

**생성일**: 2025-07-15  
**목적**: AIDA 프로젝트의 dead code를 안전하고 체계적으로 정리

---

## 🎯 핵심 원칙

1. **No Breaking Changes**: 기능에 영향 없는 정리만 수행
2. **Evidence-Based**: 모든 삭제는 증거 기반으로 결정
3. **Gradual Cleanup**: 단계적이고 점진적인 정리
4. **Full Documentation**: 모든 변경사항 문서화

---

## 📊 Phase 1: 종합 분석 (Analysis)

### 1.1 전체 Dead Code 스캔
```bash
# 1. 전체 분석 실행
./Docs/scripts/dead-code/run-analysis.sh

# 2. 상세 보고서 확인
cat Docs/scripts/dead-code/report/dead-code-comprehensive-analysis.md
```

### 1.2 현재 상태 (2025-07-15)
- **총 TypeScript 파일**: 365개
- **사용되지 않는 Exports**: 928개
- **주석 처리된 코드**: 253개 블록
- **백업 파일**: 0개 (이미 삭제됨)
- **이미 삭제된 파일**:
  - `src/core/analysis/alert-analyzer.ts`
  - `src/core/analysis/analysis-builder.ts`
  - `src/core/analysis/analysis-builder.test.ts`

---

## 🏷️ Phase 2: 분류 및 우선순위

### 2.1 위험도 분류

#### 🟢 LOW RISK (안전)
- 백업 파일 (.bak, .backup)
- 빈 파일
- 중복 파일
- 테스트 전용 Mock/Stub

#### 🟡 MEDIUM RISK (주의)
- 사용되지 않는 인터페이스
- 사용되지 않는 타입 정의
- 내부에서만 사용되는 exports
- 주석 처리된 코드 블록

#### 🔴 HIGH RISK (위험)
- Public API exports
- Strategy/Factory 패턴 구현체
- DI 컨테이너 등록 클래스
- 동적으로 로드되는 모듈

### 2.2 영향도 매트릭스

| 카테고리 | 개수 | 위험도 | 조치 |
|---------|------|--------|------|
| Core Interfaces | 15+ | HIGH | 상세 검증 필요 |
| Strategy Classes | 20+ | HIGH | 런타임 확인 필요 |
| Test Utilities | 50+ | LOW | 안전하게 제거 가능 |
| Type Definitions | 189 | MEDIUM | 사용처 확인 필요 |
| Internal Functions | 142 | MEDIUM | 개별 검증 필요 |

---

## 🔍 Phase 3: 상세 검증 프로세스

### 3.1 의존성 검증 스크립트
```bash
#!/bin/bash
# check-dependencies.sh

TARGET_FILE=$1
echo "Checking dependencies for: $TARGET_FILE"

# 1. Direct imports 확인
echo "=== Direct Imports ==="
grep -r "from.*$TARGET_FILE" src/ test/

# 2. Dynamic imports 확인
echo "=== Dynamic Imports ==="
grep -r "import.*$TARGET_FILE" src/ test/

# 3. DI Container 등록 확인
echo "=== DI Container ==="
grep -r "register.*$TARGET_FILE" src/

# 4. Test 사용 확인
echo "=== Test Usage ==="
grep -r "$TARGET_FILE" test/
```

### 3.2 런타임 사용 확인
```typescript
// runtime-usage-checker.ts
import { execSync } from 'child_process';

export function checkRuntimeUsage(className: string): boolean {
  // 1. Production logs 확인
  const prodLogs = execSync(`grep -r "${className}" logs/`);
  
  // 2. Dynamic loading 패턴 확인
  const dynamicLoad = execSync(`grep -r "require.*${className}" src/`);
  
  // 3. Reflection 사용 확인
  const reflection = execSync(`grep -r "getClass.*${className}" src/`);
  
  return !!(prodLogs || dynamicLoad || reflection);
}
```

### 3.3 테스트 영향 분석
```bash
# 1. 삭제 전 테스트 실행
npm test > before-deletion.log

# 2. 파일 삭제

# 3. 삭제 후 테스트 실행
npm test > after-deletion.log

# 4. 차이 분석
diff before-deletion.log after-deletion.log
```

---

## 🛠️ Phase 4: 단계적 정리 실행

### 4.1 안전 항목 정리 (Week 1)
```bash
# 1. 사용되지 않는 test utilities
- test/test-doubles/test-factory.ts:createMockExpressApp
- test/mocks/redis-mock.ts:mockRedisModule

# 2. 완전히 고립된 타입 정의
- 어디서도 import되지 않는 interface/type

# 3. 빈 파일 및 중복 파일
```

### 4.2 중간 위험 항목 (Week 2)
```bash
# 1. 각 항목별 상세 검증
for file in medium-risk-files.txt; do
  ./check-dependencies.sh $file
  # Manual review
  # Create PR for each batch
done
```

### 4.3 고위험 항목 (Week 3+)
- 팀 리뷰 필요
- Production 로그 분석
- 점진적 Deprecation

---

## 📝 Phase 5: 문서화 및 추적

### 5.1 삭제 기록 문서
```markdown
## Dead Code Removal Log

### 2025-07-15
- **Removed**: src/core/analysis/alert-analyzer.ts
- **Reason**: Duplicate of src/agents/smart-investigator/src/modules/alert-analyzer.ts
- **Impact**: None - using smart-investigator version
- **Verified**: All imports updated, tests passing

### [Date]
- **File**: 
- **Reason**: 
- **Impact**: 
- **Verified**: 
```

### 5.2 진행 상황 대시보드
```markdown
## Dead Code Cleanup Progress

| Date | Total Files | Dead Exports | Removed | Health Score |
|------|------------|--------------|---------|--------------|
| 2025-07-15 | 365 | 928 | 3 | 75% |
| Target | 320 | <100 | - | 95% |
```

---

## ⚠️ 주의사항

### DO NOT DELETE
1. **Strategy Pattern 구현체** - 동적 로딩 가능성
2. **DI Token 정의** - 런타임 의존성
3. **Public API Exports** - 외부 사용 가능성
4. **Event Handlers** - 이벤트 기반 호출

### SAFE TO DELETE
1. **Duplicate 구현체** - 다른 위치에 동일 코드 존재
2. **Obsolete Mocks** - 더 이상 사용하지 않는 테스트 모의객체
3. **Commented Code** - 6개월 이상 된 주석 코드
4. **Empty Files** - 내용이 없는 파일

---

## 🚀 실행 명령어

```bash
# 1. 분석 실행
./Docs/scripts/dead-code/run-analysis.sh

# 2. 안전 항목 정리
./scripts/cleanup-safe-items.sh

# 3. 검증 실행
npm run validate:all

# 4. 커밋
git add -A && git commit -m "chore: remove dead code - [category]"
```

---

## 📊 예상 결과

### 정리 후 메트릭
- **코드베이스 크기**: -20%
- **빌드 시간**: -15%
- **테스트 실행 시간**: -10%
- **번들 크기**: -25%

### 품질 개선
- **코드 가독성**: +30%
- **유지보수성**: +40%
- **신규 개발자 온보딩**: -2일

---

**다음 단계**: Phase 1 전체 분석 실행 후 상세 계획 수립