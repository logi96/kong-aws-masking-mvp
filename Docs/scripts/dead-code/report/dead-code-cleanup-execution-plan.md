# 🚨 Dead Code 정리 실행 계획

**작성자**: Claude  
**날짜**: 2025-07-15  
**상태**: 실행 대기

---

## 🎯 실행 전략

### 1. 즉시 실행 사항

#### 1.1 전체 분석 보고서 생성
```bash
# Dead code 전체 분석
./Docs/scripts/dead-code/run-analysis.sh

# 카테고리별 상세 분석
node -e "
const report = require('./Docs/scripts/dead-code/report/ts-prune-output.txt');
// 카테고리별 분류
const categories = {
  interfaces: [],
  types: [],
  classes: [],
  functions: [],
  testUtils: []
};
// 분류 로직 실행
"
```

#### 1.2 의존성 맵 생성
```typescript
// dependency-map-generator.ts
export async function generateDependencyMap() {
  const unusedExports = await parseUnusedExports();
  const dependencyMap = new Map();
  
  for (const item of unusedExports) {
    const dependencies = await findDependencies(item);
    dependencyMap.set(item, {
      directImports: dependencies.direct,
      dynamicImports: dependencies.dynamic,
      diRegistrations: dependencies.di,
      testUsage: dependencies.tests
    });
  }
  
  return dependencyMap;
}
```

### 2. 검증 체크리스트

#### 각 Dead Code 항목별 확인사항:
- [ ] Direct import 검색 (`grep -r "import.*TargetName"`)
- [ ] Dynamic import 검색 (`grep -r "require.*TargetName"`)
- [ ] DI Container 등록 확인
- [ ] Test 파일에서 사용 확인
- [ ] Strategy/Factory 패턴 확인
- [ ] Event handler 등록 확인
- [ ] Export/Re-export 체인 확인

### 3. 위험도 평가 매트릭스

| 확인 항목 | 가중치 | 설명 |
|----------|--------|------|
| No imports found | +3 | 안전 |
| Test-only usage | +2 | 비교적 안전 |
| Internal module only | +1 | 주의 필요 |
| Re-exported | -1 | 위험 |
| DI registered | -2 | 고위험 |
| Dynamic import | -3 | 매우 위험 |

**안전 점수**: 3점 이상만 삭제 가능

### 4. 실제 정리 프로세스

```bash
#!/bin/bash
# safe-cleanup.sh

# 1. 백업 생성
git stash
git checkout -b dead-code-cleanup-$(date +%Y%m%d)

# 2. 안전 점수 3점 이상 항목만 추출
SAFE_ITEMS=$(node calculate-safety-scores.js | grep "SAFE")

# 3. 각 항목별 개별 처리
for item in $SAFE_ITEMS; do
  echo "Processing: $item"
  
  # 삭제 전 테스트
  npm test
  
  # 파일/코드 제거
  remove-dead-code $item
  
  # 삭제 후 테스트
  npm test
  
  # 실패시 롤백
  if [ $? -ne 0 ]; then
    git checkout -- .
    echo "FAILED: $item - Rolled back"
  else
    git add -A
    git commit -m "chore: remove dead code - $item"
  fi
done
```

### 5. 진행 상황 추적

```markdown
## Dead Code Cleanup Log

### Session: 2025-07-15

| Time | Item | Type | Safety Score | Action | Result |
|------|------|------|--------------|--------|--------|
| 14:30 | alert-analyzer.ts | Duplicate | 5 | Deleted | ✅ Success |
| 14:45 | IAlertAnalyzer | Interface | -1 | Skipped | ⚠️ In use |
| 15:00 | createMockExpressApp | Test util | 4 | Pending | ⏳ Review |
```

---

## 🔄 다음 단계

1. **즉시**: 전체 분석 보고서 재생성
2. **오늘**: 안전 점수 계산 스크립트 작성
3. **내일**: LOW RISK 항목부터 단계적 정리
4. **주말**: 중간 점검 및 다음 주 계획

---

## ⚠️ 교훈

1. **Never Rush**: 성급한 삭제는 위험
2. **Always Verify**: 모든 삭제는 검증 필수
3. **Document Everything**: 왜 삭제했는지 기록
4. **Test Continuously**: 각 단계마다 테스트
5. **Rollback Ready**: 언제든 되돌릴 준비

---

**승인 필요**: 이 계획대로 진행해도 될까요?