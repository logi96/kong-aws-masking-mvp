# Kong DB-less AWS Multi-Resource Masking MVP - 기술 스택 검증 리포트 (간소화)

## 개요
MVP를 위한 최소한의 기술 스택 검증 결과입니다. 복잡한 구성은 제외하고 핵심 컴포넌트만 다룹니다.

## 1. 핵심 기술 스택 확정

| 기술 | 확정 버전 | 선택 이유 |
|------|-----------|-----------|
| **Kong Gateway** | 3.9.0.1 | DB-less 모드 버그 수정 완료 |
| **Claude API** | claude-3-5-sonnet-20241022 | 80% 비용 절감 |
| **Docker Compose** | 3.8 | 안정적, 변경 불필요 |
| **Node.js** | 20.x LTS | 최신 LTS |
| **JavaScript** | ES2022 + JSDoc | MVP 빠른 개발, 타입 안정성 |
| **AWS CLI** | v2 (Docker 이미지) | Python 의존성 없음 |

## 2. 즉시 적용 사항

### 2.1 Claude API 모델 변경
```javascript
// 변경 전
const CLAUDE_MODEL = 'claude-3-opus-20240229';

// 변경 후
const CLAUDE_MODEL = 'claude-3-5-sonnet-20241022';
```

**효과**: 
- 비용: $75/1M 토큰 → $15/1M 토큰 (출력 기준)
- 성능: MVP에 충분한 분석 품질

### 2.2 Kong 버전 명시
```yaml
# docker-compose.yml
services:
  kong:
    image: kong:3.9.0.1  # 명시적 버전 지정
```

### 2.3 AWS CLI Docker 이미지 사용
```yaml
# docker-compose.yml (선택사항)
services:
  aws-cli:
    image: amazon/aws-cli:latest
    volumes:
      - ~/.aws:/root/.aws:ro  # 읽기 전용
```

## 3. MVP에서 제외할 사항

### 3.1 불필요한 최적화
- ❌ 복잡한 캐싱 전략
- ❌ 고급 메모리 관리
- ❌ 성능 최적화
- ✅ 기본 설정만 사용

### 3.2 과도한 모니터링
- ❌ Prometheus/Grafana
- ❌ 상세 메트릭 수집
- ✅ 기본 로깅만

## 4. 보안 필수 사항

```yaml
# docker-compose.yml
volumes:
  - ~/.aws:/root/.aws:ro  # :ro 필수 (읽기 전용)
  - ./kong/plugins:/usr/local/share/lua/5.1/kong/plugins:ro
```

## 5. 환경 설정 체크리스트

```bash
# .env 파일
ANTHROPIC_API_KEY=sk-ant-api03-xxxxx  # Claude 3.5 Sonnet 지원
AWS_REGION=us-east-1
```

## 6. 빠른 검증 명령어

```bash
# Kong 버전 확인
docker run --rm kong:3.9.0.1 kong version

# AWS CLI 작동 확인
aws sts get-caller-identity

# Claude API 테스트 (선택사항)
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## 7. 결론

MVP를 위한 기술 스택은:
1. **최신 안정 버전 사용**: Kong 3.9.0.1, Node.js 20.x
2. **비용 효율적 선택**: Claude 3.5 Sonnet
3. **보안 기본 준수**: 읽기 전용 마운트
4. **복잡성 최소화**: 기본 설정만 사용

이 구성으로 2-3일 내 MVP 구현 가능합니다.
