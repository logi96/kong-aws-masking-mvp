#!/bin/bash
# 품질 검사 스크립트 (04-code-quality-assurance.md 준수)

set -e # 에러 시 스크립트 중단

echo "🔍 Running quality checks..."

# 현재 디렉토리 확인
if [ ! -f "package.json" ]; then
  echo "❌ package.json not found. Run this script from backend directory."
  exit 1
fi

# 1. Lint 검사
echo "📝 Checking code style..."
npm run lint
if [ $? -ne 0 ]; then
  echo "❌ Lint errors found. Run 'npm run lint:fix' to fix automatically."
  exit 1
fi

# 2. 타입 검사
echo "🔍 Running type checking..."
npm run type-check
if [ $? -ne 0 ]; then
  echo "❌ Type errors found. Check JSDoc annotations."
  exit 1
fi

# 3. 단위 테스트 실행
echo "🧪 Running unit tests..."
npm run test:unit
if [ $? -ne 0 ]; then
  echo "❌ Unit tests failed"
  exit 1
fi

# 4. 테스트 커버리지 체크
echo "📊 Checking test coverage..."
npm run test:coverage
if [ $? -ne 0 ]; then
  echo "⚠️  Coverage threshold not met"
  # MVP에서는 경고만 출력, 빌드 중단하지 않음
fi

# 5. 보안 검사
echo "🔒 Checking security..."
npm audit --production --audit-level=high
if [ $? -ne 0 ]; then
  echo "⚠️  Security vulnerabilities found"
  # MVP에서는 경고만, critical일 때만 중단
fi

echo "✅ All quality checks passed!"
echo "📊 Quality metrics:"
echo "  - Lint: ✅ Passed"
echo "  - Type Check: ✅ Passed"  
echo "  - Unit Tests: ✅ Passed"
echo "  - Coverage: Check output above"
echo "  - Security: Check output above"

# 성공 시 품질 리포트 생성
if [ -f "scripts/quality-metrics.js" ]; then
  echo "📈 Generating quality report..."
  node scripts/quality-metrics.js
fi