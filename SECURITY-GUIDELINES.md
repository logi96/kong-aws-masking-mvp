# 🚨 Kong AWS Masking MVP - 보안 지침 (CRITICAL)

## 절대 금지 사항

### ❌ Mock 모드 사용 금지
- **절대적 금지**: Mock 모드, 테스트 모드, 가상 데이터 사용 불허
- **이유**: 실제 AWS 리소스와 Claude API가 정상 작동해야 함
- **위반 시**: 즉시 수정 및 전체 시스템 재검증 필요

### ❌ 하드코딩된 테스트 키 사용 금지
- `test-key`, `mock-mode`, `fake-key` 등 모든 형태 금지
- 실제 유효한 API 키만 사용
- 환경별 키 관리 (development/production)

## ✅ 허용되는 사용 사례

### Unit Test에서의 Mock 사용 (제한적 허용)
```javascript
// ✅ 허용: Jest 테스트에서만 콘솔 출력 제한
console.error = jest.fn();

// ❌ 금지: API 응답이나 비즈니스 로직 Mock
// mockClaudeService.analyzeData = jest.fn();
```

### Test Environment 설정 (제한적 허용)
```bash
# ✅ 허용: 테스트 전용 환경 변수
NODE_ENV=test
ANTHROPIC_API_KEY=sk-ant-api03-REAL-TEST-KEY

# ❌ 금지: 가짜 키 사용
ANTHROPIC_API_KEY=test-key-mock-mode
```

## 🔒 보안 요구사항

### API 키 관리
1. **실제 키만 사용**: 모든 환경에서 유효한 API 키 사용
2. **키 보안**: .env 파일을 .gitignore에 포함
3. **키 검증**: 시작 시 API 키 유효성 검증

### AWS 자격증명
1. **실제 AWS CLI 사용**: Mock AWS CLI 도구 사용 금지
2. **권한 검증**: 최소 필요 권한만 부여
3. **자격증명 보안**: AWS 자격증명 파일 보안 관리

### 데이터 마스킹
1. **실제 마스킹**: Kong Gateway를 통한 실제 데이터 마스킹
2. **마스킹 검증**: 모든 민감 데이터가 실제로 마스킹되는지 확인
3. **로그 보안**: 로그에 민감 정보 노출 방지

## 🛡️ 보안 검증 절차

### 시작 전 체크리스트
- [ ] ENABLE_MOCK_MODE=false 확인
- [ ] 실제 ANTHROPIC_API_KEY 설정 확인
- [ ] AWS CLI 실제 자격증명 확인
- [ ] Kong Gateway 마스킹 플러그인 활성화 확인

### 운영 중 모니터링
- [ ] API 호출 성공률 모니터링
- [ ] 마스킹된 데이터 검증
- [ ] 에러 로그에서 민감 정보 누출 체크
- [ ] 성능 지표 < 5초 요구사항 준수

## 🚨 위반 시 대응 절차

### Mock 모드 발견 시
1. **즉시 중단**: 모든 서비스 중단
2. **원인 분석**: Mock 모드 사용 원인 파악
3. **설정 수정**: 실제 환경으로 변경
4. **전체 재테스트**: 모든 기능 재검증
5. **문서 업데이트**: 보안 지침 강화

### 테스트 키 발견 시
1. **키 교체**: 즉시 실제 키로 교체
2. **연결 테스트**: API 연결 상태 확인
3. **기능 검증**: 전체 워크플로우 재실행
4. **보안 감사**: 다른 테스트 키 사용 여부 전체 점검

## 📋 보안 체크리스트

```bash
# 보안 검증 스크립트
#!/bin/bash

echo "🔍 보안 검증 시작..."

# Mock 모드 체크
if grep -r "ENABLE_MOCK_MODE=true" . ; then
    echo "❌ Mock 모드 발견 - 즉시 수정 필요"
    exit 1
fi

# 테스트 키 체크  
if grep -r "test-key\|mock-mode\|fake-key" --exclude-dir=node_modules . ; then
    echo "❌ 테스트 키 발견 - 즉시 교체 필요"
    exit 1
fi

# API 키 형식 체크
if ! grep -q "sk-ant-api03-" .env ; then
    echo "❌ 유효하지 않은 API 키 형식"
    exit 1
fi

echo "✅ 보안 검증 완료"
```

## 📞 보안 이슈 보고

보안 위반 사항 발견 시 즉시 Infrastructure Team에 보고하세요.

---

**⚠️ 이 지침은 절대적으로 준수해야 하며, 어떤 상황에서도 예외 없이 적용됩니다.**