# nginx-kong-claude-enterprise2 프로젝트 정리 계획

## 📊 현재 상태 분석

### 다른 프로젝트 참조
- README.md: 하드코딩된 경로 `nginx-kong-claude-enterprise2`
- 테스트 리포트: `claude-code-poc` 컨테이너 참조

### 불필요한 파일들

#### P0 (즉시 삭제 - 안전)
```bash
# 백업 디렉토리들
backup/                     # ~200MB
backups/                    # ~300MB  
nginx-broken-backup/        # ~50MB

# 로그 파일들
logs/                       # ~200MB
backend/logs/               # ~50MB
pids/                       # ~1MB

# Coverage 리포트들
backend/coverage/           # ~50MB

# 임시 파일들
tests/temp-*/               # ~30MB
```

#### P1 (검토 후 삭제)
```bash
# 테스트 결과 (최신 5개만 보존)
tests/test-report/          # 80+ 파일 → 5개만 보존
test-report/                # 중복 리포트

# 개발 의존성
backend/node_modules/       # ~200MB (재생성 가능)

# 중복 설정
docker-compose.*.yml        # 기본 파일만 보존
```

## 🎯 정리 목표
- 파일 수: 2000+ → 1000 미만 (50% 감소)
- 디스크 사용량: ~2GB → ~1.4GB (30% 절약)
- 외부 참조: 완전 제거

## 📋 실행 단계

### 1단계: 안전한 파일 삭제
```bash
#!/bin/bash
cd /Users/tw.kim/Documents/AGA/test/Kong/nginx-kong-claude-enterprise2

# 백업 디렉토리들 삭제
rm -rf backup/
rm -rf backups/
rm -rf nginx-broken-backup/

# 로그 파일들 삭제
rm -rf logs/
rm -rf backend/logs/
rm -rf pids/

# Coverage 리포트 삭제
rm -rf backend/coverage/

# 임시 파일들 삭제
rm -rf tests/temp-*/
```

### 2단계: 테스트 결과 정리
```bash
# 테스트 결과 파일 정리 (최신 5개만 보존)
cd tests/test-report/
ls -t *.md | tail -n +6 | xargs rm -f

cd ../../test-report/
ls -t *.md | tail -n +6 | xargs rm -f
```

### 3단계: 외부 참조 수정
```bash
# README.md 수정
sed -i '' 's/nginx-kong-claude-enterprise2/$(basename $PWD)/g' README.md

# 테스트 스크립트에서 claude-code-poc 참조 제거
find . -name "*.sh" -exec sed -i '' 's/claude-code-poc/nginx-kong-claude-enterprise2/g' {} \;
```

### 4단계: 검증
```bash
# 외부 참조 확인
grep -r "claude-code-poc" . || echo "✅ claude-code-poc 참조 제거 완료"
grep -r "nginx-kong-claude-enterprise[^2]" . || echo "✅ 외부 프로젝트 참조 제거 완료"

# 디스크 사용량 확인
du -sh . 
```

## 🔒 보존할 중요 파일들
- docker-compose.yml (기본 설정)
- backend/src/ (소스 코드)
- kong/plugins/ (플러그인 코드)
- nginx/conf.d/ (설정 파일들)
- scripts/ (운영 스크립트들)
- README.md (문서)
- tests/ (테스트 스크립트들)

## ⚠️ 주의사항
- node_modules는 package.json으로 재생성 가능하므로 삭제 고려
- 테스트 결과는 최신 5개만 보존
- 백업 실행 전 중요 데이터 확인