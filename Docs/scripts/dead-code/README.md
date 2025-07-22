# 🔍 AIDA Dead Code Detection Tool

**목적**: AIDA 프로젝트의 사용되지 않는 코드를 체계적으로 검출하고 제거하여 코드베이스를 깨끗하게 유지합니다.

---

## ⚡ 빠른 시작 (Quick Start)

프로젝트 루트 디렉토리에서 다음 명령어를 실행하세요:

```bash
# 전체 dead code 분석 실행 (권장)
./Docs/scripts/dead-code/run-analysis.sh
```

이 명령어 하나로:
- ✅ 백업 파일(.bak) 자동 삭제
- ✅ 필요한 의존성 자동 설치
- ✅ 전체 코드베이스 분석
- ✅ 상세 보고서 생성

---

## 📊 분석 결과 확인

분석이 완료되면 보고서가 생성됩니다:

```bash
# 최신 보고서 확인
cat Docs/scripts/dead-code/report/dead-code-analysis-*.md

# 종합 분석 보고서 확인 (있는 경우)
cat Docs/scripts/dead-code/report/dead-code-comprehensive-analysis.md

# ts-prune 상세 결과 확인
cat Docs/scripts/dead-code/report/ts-prune-output.txt
```

---

## 🎯 상세 사용법

### 1. 전체 분석 (권장)
```bash
./Docs/scripts/dead-code/run-analysis.sh
```

이 스크립트는:
- 백업 파일 정리
- TypeScript dead code 검출
- 주석 처리된 코드 블록 감지
- 사용되지 않는 exports 검출
- 종합 보고서 생성

### 2. 백업 파일만 정리
```bash
./Docs/scripts/dead-code/clean-backup-files.sh
```

.bak, .backup, .old 등의 백업 파일을 즉시 삭제합니다.

### 3. 간단한 분석 실행
```bash
node Docs/scripts/dead-code/run-simple-analysis.cjs
```

TypeScript 컴파일 없이 빠른 분석을 수행합니다.

---

## 📈 보고서 해석

### 보고서 구조
```markdown
# 🔍 AIDA Dead Code Analysis Report

## 📊 Summary
- Empty Files: 0          # 빈 파일 개수
- Duplicate Files: 0      # 중복 파일 개수
- Commented Code: 253     # 주석 처리된 코드 블록
- Unused Exports: 928     # 사용되지 않는 exports

## Health Score: 87%      # 전체 건강도 점수
```

### 주요 지표 설명

#### 1. **Unused Exports** (사용되지 않는 exports)
- `(used in module)`: 같은 파일 내에서만 사용됨
- 표시 없음: 어디서도 사용되지 않음

#### 2. **Commented Code Blocks** (주석 처리된 코드)
- 100자 이상의 주석 블록 중 코드 패턴을 포함한 것
- Git 히스토리로 대체 가능한 오래된 코드

#### 3. **Health Score** (건강도 점수)
```
Health Score = (1 - 문제있는파일수 / 전체파일수) × 100
```
- 85% 이상: 좋음
- 70-85%: 개선 필요
- 70% 미만: 즉시 정리 필요

---

## 🛠️ 설정 커스터마이징

`config.json`을 수정하여 동작을 변경할 수 있습니다:

```json
{
  "deadCodeDetection": {
    "sourcePath": "src",              // 분석할 소스 디렉토리
    "includeTestFiles": true,         // 테스트 파일 포함 여부
    "minCommentedBlockSize": 3,       // 최소 주석 블록 크기
    "excludePatterns": [              // 제외할 패턴
      "node_modules",
      "dist"
    ]
  }
}
```

---

## 🚨 문제 해결 (Troubleshooting)

### 1. "ts-node를 찾을 수 없습니다" 오류
```bash
npm install -g ts-node
# 또는
npm install --save-dev ts-node
```

### 2. 권한 거부 오류
```bash
chmod +x Docs/scripts/dead-code/*.sh
```

### 3. 메모리 부족 오류
```bash
export NODE_OPTIONS="--max-old-space-size=4096"
./Docs/scripts/dead-code/run-analysis.sh
```

### 4. ts-prune 실행 실패
```bash
npm install --save-dev ts-prune
```

---

## 🎯 베스트 프랙티스

### 1. 정기 실행
- **권장 주기**: 월 1회 (매월 첫째 주)
- **목표**: Health Score 85% 이상 유지

### 2. 단계적 정리
```bash
# Step 1: 백업 파일 삭제 (안전)
./Docs/scripts/dead-code/clean-backup-files.sh

# Step 2: 보고서 검토
cat Docs/scripts/dead-code/report/dead-code-analysis-*.md

# Step 3: 선택적 정리
# 보고서를 보고 신중하게 결정
```

### 3. Git 백업
```bash
# 정리 전 현재 상태 저장
git add -A && git commit -m "Before dead code cleanup"

# Dead code 정리 후
git add -A && git commit -m "Remove dead code based on analysis"
```

---

## 📊 예상 효과

정기적인 dead code 제거 시:

- **번들 크기**: 15-20% 감소
- **빌드 시간**: 10-15% 단축  
- **메모리 사용**: 5-10% 감소
- **코드 가독성**: 30% 향상
- **유지보수성**: 크게 개선

---

## 📁 디렉토리 구조

```
Docs/scripts/dead-code/
├── README.md                 # 이 파일
├── detect-dead-code.ts       # 메인 검출 엔진
├── clean-backup-files.sh     # 백업 파일 정리
├── run-analysis.sh           # 통합 실행 스크립트
├── run-simple-analysis.cjs   # 간단한 분석
├── config.json              # 설정 파일
├── tsconfig.json            # TypeScript 설정
├── docs/
│   └── detection-plan.md    # 상세 기술 문서
└── report/                  # 분석 보고서 저장
    ├── dead-code-analysis-YYYY-MM-DD.md
    ├── dead-code-comprehensive-analysis.md
    └── ts-prune-output.txt
```

---

## 🔧 고급 사용법

### TypeScript AST 분석만 실행
```bash
cd /path/to/project
ts-node Docs/scripts/dead-code/detect-dead-code.ts
```

### ts-prune만 실행
```bash
npx ts-prune --project tsconfig.json > Docs/scripts/dead-code/report/ts-prune-output.txt
```

### 특정 디렉토리만 분석
```bash
# config.json 수정 후
{
  "sourcePath": "src/agents"  // 특정 디렉토리만
}
```

---

## 📝 추가 문서

- [상세 기술 문서](docs/detection-plan.md)
- [AIDA 프로젝트 문서](../../README.md)

---

**버전**: 1.0.0  
**최종 업데이트**: 2025-07-15  
**유지보수**: AIDA 개발팀