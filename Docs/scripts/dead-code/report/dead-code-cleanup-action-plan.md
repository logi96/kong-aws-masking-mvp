# 🚀 Dead Code 정리 실행 계획

**작성일**: 2025-07-15  
**기반**: 실행 완료 보고서  
**목표**: 안전하고 체계적인 dead code 제거

---

## 📊 현황 요약

### 분석 결과
- **총 Dead Code**: 902개 항목
- **위험도 분포**:
  - 🔴 HIGH RISK: 611개 (67.7%) - 삭제 금지
  - 🟡 MEDIUM RISK: 79개 (8.8%) - 신중한 검토 필요
  - 🟢 LOW RISK: 212개 (23.5%) - 안전하게 삭제 가능

### 이미 정리된 항목
- ✅ 백업 파일: 348개 (모두 삭제 완료)
- ✅ 중복 파일: 3개 (alert-analyzer, analysis-builder)
- ✅ 사용되지 않는 인터페이스: 2개 (IAlertAnalyzer, IArtifactBuilder)

---

## 🎯 실행 계획

### Phase 1: 즉시 실행 (2025-07-15 ~ 07-17)

#### 1.1 LOW RISK 테스트 유틸리티 정리
```bash
# 대상: 21개 항목
# 예시:
- test/mocks/redis-mock.ts:265 - mockRedisModule
- test/test-doubles/test-factory.ts:597 - createMockExpressApp

# 실행 방법:
1. 의존성 확인
   grep -r "mockRedisModule" src/ test/
   
2. 테스트 실행
   npm test -- test/mocks/
   
3. 안전 확인 후 삭제
   
4. 테스트 재실행
   npm test
```

#### 1.2 "Used in Module" 항목 처리
```bash
# 대상: 180개 항목
# 처리 방법: export 제거, private 변환

# 예시:
export interface CacheEntry { ... }  // Before
interface CacheEntry { ... }         // After

# 자동화 스크립트 필요
```

### Phase 2: 단계적 정리 (2025-07-18 ~ 07-24)

#### 2.1 MEDIUM RISK 검증 및 정리
```bash
# 대상: 79개 항목
# 카테고리별 처리:

1. Golden Command Sets (6개)
   - 사용 여부 확인
   - 대체 구현 확인
   
2. Investigation Commands (5개)
   - 동적 로딩 패턴 확인
   - Strategy 패턴 사용 확인
   
3. Config Interfaces (20개)
   - 실제 설정 파일 확인
   - 런타임 사용 확인
```

#### 2.2 안전성 검증 프로세스
```bash
# 각 항목별 체크리스트
□ Direct import 검색
□ Dynamic require 검색  
□ DI container 등록 확인
□ Test 파일 사용 확인
□ Production 로그 확인
```

### Phase 3: 팀 검토 (2025-07-25 ~ 07-31)

#### 3.1 HIGH RISK 항목 분석
```markdown
# 절대 삭제 금지 항목:
- DI Tokens (150개)
- Strategy/Factory 패턴 (200개)
- Public API exports (100개)
- A2A protocol types (161개)

# 처리 방법:
1. 문서화만 진행
2. Deprecated 마킹
3. 향후 마이그레이션 계획
```

---

## 🛠️ 실행 도구

### CommonJS 기반 스크립트 (권장)
```bash
# 1. 전체 분석 (CommonJS)
node Docs/scripts/dead-code/run-simple-analysis.cjs

# 2. 위험도 평가
node Docs/scripts/dead-code/categorize-dead-code.cjs

# 3. 안전한 정리 (dry run)
./Docs/scripts/dead-code/safe-cleanup.sh

# 4. 보고서 확인
cat Docs/scripts/dead-code/report/dead-code-risk-assessment.md
```

### 자동화 도구 개발 필요
```typescript
// safe-delete-tool.ts → safe-delete-tool.cjs
// AST 기반 안전한 export 제거
// "used in module" 자동 private 변환
// 의존성 자동 확인
```

---

## 📋 일일 체크리스트

### Day 1-2 (LOW RISK)
- [ ] 테스트 유틸리티 21개 검토
- [ ] 각 항목 의존성 확인
- [ ] 삭제 후 테스트 실행
- [ ] 결과 문서화

### Day 3-4 (Used in Module)
- [ ] Export 제거 스크립트 작성
- [ ] 180개 항목 일괄 처리
- [ ] 컴파일 확인
- [ ] 테스트 전체 실행

### Day 5-7 (MEDIUM RISK)
- [ ] 카테고리별 분류
- [ ] 각 항목 상세 분석
- [ ] PR 생성 (10개씩)
- [ ] 코드 리뷰

---

## 📊 성공 지표

### 정량적 지표
- Dead code 감소: 902 → 100 이하
- 빌드 시간: -15%
- 번들 크기: -20%
- 테스트 커버리지: 변화 없음

### 정성적 지표
- 코드 가독성 향상
- 새 개발자 온보딩 시간 단축
- 유지보수 복잡도 감소

---

## ⚠️ 위험 관리

### 위험 요소
1. **런타임 오류**: 동적 로딩 코드 삭제
2. **빌드 실패**: 의존성 누락
3. **테스트 실패**: Mock 객체 삭제

### 대응 방안
1. **단계별 커밋**: 각 배치별 개별 커밋
2. **즉시 롤백**: 문제 발생 시 revert
3. **충분한 테스트**: 각 단계별 전체 테스트
4. **점진적 접근**: 하루 최대 50개 항목

---

## 📝 문서화 템플릿

### 삭제 기록
```markdown
## [날짜] Dead Code 정리

### 삭제된 항목
- File: src/example.ts
- Item: ExampleClass
- Line: 123
- Risk: LOW
- Reason: No imports found, test-only utility
- Tests: All passing
- Commit: abc123
```

---

## 🔄 다음 단계

1. **즉시**: LOW RISK 21개 테스트 유틸리티 정리
2. **Day 2**: "Used in module" 처리 스크립트 작성
3. **Day 3**: MEDIUM RISK 상세 분석 시작
4. **Week 2**: 팀 리뷰 및 HIGH RISK 논의

---

**승인 요청**: 이 계획대로 진행해도 될까요?