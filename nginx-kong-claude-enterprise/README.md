# Nginx-Kong-Claude Enterprise Integration

엔터프라이즈 수준의 Claude Code 통합 솔루션으로, Nginx 프록시와 Kong Gateway를 통해 AWS 리소스를 안전하게 마스킹합니다.

## 🏗️ 아키텍처

```
Claude Code → Nginx(:8082) → Kong(+aws-masker) → Claude API
                                     ↓
                                   Redis
```

## 🚀 빠른 시작

### 필수 요구사항
- Docker & Docker Compose
- Claude API Key

### 환경 설정
```bash
cp .env.example .env
# .env 파일에서 ANTHROPIC_API_KEY 설정
```

### 실행
```bash
./scripts/start.sh
```

### 테스트
```bash
# 헬스 체크
./scripts/health-check.sh

# End-to-End 테스트
./scripts/test-e2e.sh
```

## 📋 주요 기능

- **고성능 프록시**: Nginx를 통한 엔터프라이즈급 HTTP 프록시
- **AWS 리소스 마스킹**: Kong aws-masker 플러그인으로 자동 마스킹/언마스킹
- **데이터 영속성**: Redis를 통한 마스킹 매핑 저장
- **완전한 격리**: Docker 컨테이너 기반 독립 실행

## 📚 문서

- [프로젝트 계획](PROJECT-PLAN.md) - 상세 아키텍처 및 구현 계획
- [API 문서](docs/API.md) - API 엔드포인트 및 사용법
- [운영 가이드](docs/OPERATIONS.md) - 배포 및 운영 가이드

## 🔧 설정

### Nginx
- 포트: 8082
- 설정: `nginx/nginx.conf`

### Kong
- Admin 포트: 8001
- 설정: `kong/kong.yml`
- 플러그인: `kong/plugins/aws-masker/`

### Redis
- 포트: 6379
- 설정: `redis/redis.conf`

## 📊 모니터링

- Nginx 로그: `logs/nginx/`
- Kong 로그: `logs/kong/`
- Redis 로그: `logs/redis/`
- 헬스 대시보드: `monitoring/health-dashboard.html`

## 🤝 기여

이슈와 PR을 환영합니다. 기여 전 [CONTRIBUTING.md](CONTRIBUTING.md)를 참조해주세요.

## 📝 라이선스

MIT License