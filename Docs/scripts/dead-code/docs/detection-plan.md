# 🔍 AIDA Dead Code Detection Plan

**생성일**: 2025-07-15  
**목적**: src/ 디렉토리의 불필요한 코드(dead code) 체계적 검출 및 제거  
**범위**: TypeScript 소스 코드 전체 (테스트 파일 포함)

---

## 📋 구현 완료 사항

### 1. **스크립트 구조**
```
Docs/scripts/dead-code/
├── detect-dead-code.ts         # 메인 검출 엔진 (TypeScript)
├── clean-backup-files.sh       # 백업 파일 정리 스크립트
├── run-analysis.sh             # 통합 실행 스크립트
├── run-simple-analysis.cjs     # 간단한 분석 스크립트
├── config.json                 # 설정 파일
├── tsconfig.json              # TypeScript 설정
├── docs/
│   └── detection-plan.md      # 이 문서
└── report/                    # 분석 보고서 디렉토리
```

### 2. **검출 가능한 Dead Code 유형**

| 유형 | 자동화 지원 | 구현 상태 |
|------|------------|-----------|
| 🚫 백업 파일 (.bak, .backup) | ✅ 100% | 완료 |
| 📤 사용되지 않는 exports | ✅ 90% | 완료 (ts-prune) |
| 🔒 사용되지 않는 내부 함수/변수 | ✅ 70% | 완료 (AST 분석) |
| 📄 빈 파일 | ✅ 100% | 완료 |
| 👥 중복 파일 | ✅ 100% | 완료 (MD5 해시) |
| 💬 주석 처리된 코드 블록 | ✅ 85% | 완료 (패턴 분석) |
| 🏷️ 사용되지 않는 인터페이스/타입 | ✅ 80% | 완료 (exported only) |

### 3. **핵심 기능**

#### 🧹 백업 파일 자동 삭제
- `.bak`, `.backup`, `.old`, `.orig`, `~` 파일 감지 및 삭제
- 안전한 삭제 프로세스 (확인 후 삭제)

#### 📊 종합 분석 엔진
- **ts-prune** 통합: 사용되지 않는 exports 정확한 감지
- **TypeScript AST 분석**: 내부 dead code 감지
- **MD5 해시 기반**: 중복 파일 감지
- **패턴 매칭**: 주석 처리된 코드 블록 감지

#### 📝 상세 보고서
- Markdown 형식 보고서 자동 생성
- 문제별 분류 및 우선순위
- 실행 가능한 정리 스크립트 포함
- 건강도 점수 계산

---

## 🚀 사용 방법

### 1. **전체 분석 실행** (권장)
```bash
# 프로젝트 루트에서 실행
./Docs/scripts/dead-code/run-analysis.sh
```

이 명령은:
- ✅ 백업 파일 자동 정리
- ✅ 필요한 의존성 설치
- ✅ Dead code 전체 분석
- ✅ 보고서 생성 (Docs/scripts/dead-code/report/)

### 2. **백업 파일만 정리**
```bash
./Docs/scripts/dead-code/clean-backup-files.sh
```

### 3. **Dead code 분석만 실행**
```bash
ts-node Docs/scripts/dead-code/detect-dead-code.ts
```

---

## 📊 예상 결과

### 샘플 보고서 구조
```markdown
# 🔍 AIDA Dead Code Analysis Report

## 📊 Executive Summary
- Total Files: 366
- Files with Issues: 87
- Total Issues: 342
- Health Score: 76%

## 🚫 Backup Files (15)
- src/gateway/webhook.ts.bak
- src/analyzer/core.ts.backup
...

## 📤 Unused Exports (125)
- function: 45 items
- interface: 32 items
- type: 28 items
...

## 💬 Commented Code Blocks (67)
- Large blocks of commented implementation
...
```

### 건강도 점수 계산
```
Health Score = (1 - Files with Issues / Total Files) × 100
```

---

## ⚡ 빠른 정리 가이드

### 1. **즉시 삭제 가능** (위험도: 낮음)
- 🚫 백업 파일 (.bak, .backup)
- 📄 빈 파일
- 💬 오래된 주석 처리 코드

### 2. **검토 후 삭제** (위험도: 중간)
- 📤 사용되지 않는 exports
- 👥 중복 파일 (하나만 유지)

### 3. **신중한 검토 필요** (위험도: 높음)
- 🔒 내부 미사용 코드 (테스트용일 수 있음)
- 🏷️ 타입/인터페이스 (외부 의존성 확인)

---

## 🛡️ 안전 장치

### 1. **단계별 실행**
- Step 1: 백업 파일만 삭제 (안전)
- Step 2: 보고서 검토
- Step 3: 선택적 코드 정리

### 2. **Git 통합**
```bash
# 변경 전 상태 저장
git add -A && git commit -m "Before dead code cleanup"

# Dead code 정리 실행
./scripts/quality/run-dead-code-analysis.sh

# 변경사항 검토
git diff

# 문제 시 복원
git reset --hard HEAD
```

### 3. **제외 패턴 설정**
`Docs/scripts/dead-code/config.json`에서 제외할 패턴 설정 가능

---

## 📈 권장 운영 방안

### 1. **정기 실행**
- **주기**: 월 1회 (월초)
- **담당**: 코드 품질 관리자
- **목표**: Health Score 85% 이상 유지

### 2. **CI/CD 통합**
```yaml
# .github/workflows/dead-code-check.yml
name: Dead Code Check
on:
  schedule:
    - cron: '0 0 1 * *'  # 매월 1일
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: ./Docs/scripts/dead-code/run-analysis.sh
      - uses: actions/upload-artifact@v3
        with:
          name: dead-code-report
          path: Docs/scripts/dead-code/report/
```

### 3. **품질 지표 추적**
| 날짜 | 전체 파일 | 문제 파일 | 건강도 |
|------|----------|----------|--------|
| 2025-07 | 366 | ? | ?% |
| 2025-08 | ? | ? | ?% |

---

## 🎯 기대 효과

### 1. **코드 품질 향상**
- 불필요한 코드 제거로 가독성 향상
- 유지보수 비용 감소
- 빌드 시간 단축

### 2. **보안 강화**
- 주석 처리된 민감 정보 제거
- 오래된 코드의 잠재적 취약점 제거

### 3. **성능 개선**
- 번들 크기 감소
- 메모리 사용량 감소
- 로딩 시간 단축

---

## 🔧 문제 해결

### ts-prune 설치 실패
```bash
npm install --save-dev ts-prune typescript
```

### 권한 오류
```bash
chmod +x Docs/scripts/dead-code/*.sh
```

### 메모리 부족
```bash
export NODE_OPTIONS="--max-old-space-size=4096"
```

---

**다음 단계**: 스크립트 실행 후 생성된 보고서를 검토하고 정리 계획 수립