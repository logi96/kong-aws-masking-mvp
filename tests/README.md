# Kong AWS Masking MVP - Test Scripts Guide

## 📋 Overview

이 디렉토리는 Kong AWS Masking MVP 프로젝트의 활성 테스트 스크립트들을 포함하고 있습니다. 각 스크립트는 시스템의 특정 측면을 검증하기 위해 설계되었습니다.

**중요**: `/analyze-claude` 엔드포인트는 더 이상 존재하지 않습니다. 일부 스크립트에서 이를 참조하는 경우 `/analyze`로 수정이 필요합니다.

## 🏗️ System Architecture

```
Backend API (3000) → Kong Gateway (8000) → Claude API
    ↓                      ↓                    ↓
AWS CLI Execution    Masking/Unmasking    AI Analysis
```

### Available Endpoints
- `/analyze` - 메인 프로덕션 엔드포인트
- `/quick-mask-test` - 빠른 테스트 전용 (Claude API 호출 없음)
- `/health` - 시스템 헬스체크

## 📁 Script Categories

### 1. 🚀 Production Tests

#### **production-comprehensive-test.sh**
- **목적**: 프로덕션 준비 상태 종합 검증
- **사용법**: `./production-comprehensive-test.sh`
- **테스트 항목**: 실제 AWS 분석, 보안 검증, 에러 처리
- **결과**: CSV 파일 생성 및 프로덕션 준비 상태 판정

#### **production-security-test.sh**
- **목적**: 100% 보안 요구사항 충족 검증
- **사용법**: `./production-security-test.sh`
- **테스트 항목**: Redis 실패 시나리오, Circuit Breaker, 부하 테스트
- **결과**: 보안 준수 여부 최종 판정

### 2. 🔒 Security Tests

#### **comprehensive-security-test.sh**
- **목적**: AWS 리소스 마스킹 완전성 검증
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./comprehensive-security-test.sh`
- **주의**: `/analyze-claude` → `/analyze` 수정 필요
- **결과**: `/tmp/security_test_report.txt`

#### **security-masking-test.sh**
- **목적**: 핵심 보안 요구사항 검증
- **사용법**: `./security-masking-test.sh`
- **테스트 항목**: 민감한 AWS 패턴 노출 여부
- **결과**: 보안 문제 발견 시 즉시 종료

#### **quick-security-test.sh**
- **목적**: Claude API 없이 빠른 마스킹 검증
- **사용법**: `./quick-security-test.sh`
- **장점**: 매우 빠른 실행 (API 호출 없음)

### 3. 🔧 Debug Tools

#### **debug-headers.sh**
- **목적**: API 키 헤더 전달 문제 디버깅
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./debug-headers.sh`
- **체크 항목**: 직접 API 호출 vs Kong 경유 호출

#### **debug-iam-role-pattern.sh**
- **목적**: IAM Role ARN 패턴 마스킹 문제 해결
- **사용법**: `./debug-iam-role-pattern.sh`
- **결과**: 패턴 수정 제안

### 4. 📊 Performance Tests

#### **performance-test.sh**
- **목적**: 5초 미만 응답시간 요구사항 검증
- **사용법**: `./performance-test.sh`
- **주의**: API 키가 하드코딩됨 - 환경변수로 수정 권장
- **테스트**: 단일/병렬 요청, Kong 오버헤드 측정

#### **performance-test-simple.sh**
- **목적**: 빠른 성능 검증
- **사용법**: `./performance-test-simple.sh`
- **주의**: API 키가 하드코딩됨 - 환경변수로 수정 권장

### 5. 🗄️ Redis Tests

#### **redis-connection-test.sh**
- **목적**: Redis 연결 및 기본 기능 검증
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./redis-connection-test.sh`
- **테스트**: 연결, TTL, Fallback 메커니즘

#### **redis-performance-test.sh**
- **목적**: Redis 사용 시 성능 영향 측정
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./redis-performance-test.sh`
- **필요**: `bc` 명령어
- **결과**: 상세한 성능 통계

#### **redis-persistence-test.sh**
- **목적**: 데이터 영속성 검증
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./redis-persistence-test.sh`
- **테스트**: 재시작 후 영속성, TTL 동작

### 6. 🔍 Analysis Tools

#### **ngx-re-analysis.sh**
- **목적**: Nginx 정규식 vs Lua 패턴 성능 분석
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./ngx-re-analysis.sh`
- **결과**: ngx.re 사용 권장사항

#### **ngx-re-final-test.sh**
- **목적**: ngx.re 구현 최종 검증
- **사용법**: `ANTHROPIC_API_KEY=sk-ant-xxx ./ngx-re-final-test.sh`
- **테스트**: 복잡한 패턴 변환 과정 시각화

### 7. 🎯 Quick Tests

#### **quick-check.sh**
- **목적**: 시스템 구성요소 상태 확인
- **사용법**: `./quick-check.sh`
- **체크**: Backend, Kong Gateway, Docker 상태

#### **comprehensive-flow-test.sh**
- **목적**: 전체 마스킹/언마스킹 플로우 테스트
- **사용법**: `./comprehensive-flow-test.sh`
- **결과**: `/tmp/flow-test-results.csv`

## 🛠️ Prerequisites

### Required Environment Variables
```bash
export ANTHROPIC_API_KEY=sk-ant-api03-xxx  # Claude API key
export AWS_REGION=ap-northeast-2           # AWS region
```

### Required Services
- Backend API running on port 3000
- Kong Gateway running on port 8000
- Redis (optional but recommended)
- Docker containers must be running

### System Requirements
- `curl` command
- `jq` for JSON parsing
- `bc` for performance calculations (일부 스크립트)

## 🚨 Known Issues

1. **잘못된 엔드포인트**: 
   - 일부 스크립트가 `/analyze-claude` 사용 (존재하지 않음)
   - `/analyze`로 수정 필요

2. **하드코딩된 API 키**:
   - `performance-test.sh`와 `performance-test-simple.sh`에 API 키 하드코딩
   - 환경변수 사용으로 수정 권장

3. **결과 파일 위치**:
   - 대부분 `/tmp/` 디렉토리 사용
   - 프로젝트 내 `results/` 디렉토리 사용 권장

## 📝 Usage Examples

### Basic System Check
```bash
# 시스템 상태 확인
./quick-check.sh

# 빠른 보안 테스트
./quick-security-test.sh
```

### Full Production Validation
```bash
# 환경변수 설정
export ANTHROPIC_API_KEY=sk-ant-api03-xxx

# 프로덕션 종합 테스트
./production-comprehensive-test.sh

# 프로덕션 보안 테스트
./production-security-test.sh
```

### Performance Testing
```bash
# 성능 테스트 (API 키 수정 필요)
./performance-test.sh

# Redis 성능 영향 측정
ANTHROPIC_API_KEY=sk-ant-xxx ./redis-performance-test.sh
```

### Debugging Issues
```bash
# 헤더 전달 문제
ANTHROPIC_API_KEY=sk-ant-xxx ./debug-headers.sh

# IAM 패턴 문제
./debug-iam-role-pattern.sh
```

## 📊 Test Results

테스트 결과는 주로 다음 위치에 저장됩니다:
- `/tmp/flow-test-results.csv` - 플로우 테스트 결과
- `/tmp/security_test_report.txt` - 보안 테스트 보고서
- 콘솔 출력 - 실시간 테스트 진행 상황

## 🔄 Maintenance

### Adding New Tests
1. 테스트 스크립트 작성 시 환경변수 사용
2. 명확한 목적과 사용법 주석 추가
3. 결과 출력 형식 통일

### Updating Existing Tests
1. `/analyze-claude` → `/analyze` 엔드포인트 수정
2. 하드코딩된 값을 환경변수로 변경
3. 에러 처리 및 로깅 개선

## 📚 Archive

더 이상 사용하지 않는 스크립트들은 `archive/` 디렉토리로 이동되었습니다:
- Phase별 개발 테스트 (run-phase*.sh)
- Echo 테스트 시리즈
- Mock 테스트 (프로젝트 정책 위반)
- 구식 패턴의 테스트들

총 31개의 스크립트가 아카이브되었으며, 16개의 활성 스크립트가 유지되고 있습니다.