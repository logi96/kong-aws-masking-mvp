# Claude SDK Proxy Test

독립적인 환경에서 Claude SDK(@anthropic-ai/sdk)의 프록시 지원을 검증하는 테스트 프로젝트입니다.

## 🎯 목적

- Claude SDK가 프록시를 통해 API 호출이 가능한지 검증
- Kong Gateway와의 통합 가능성 평가
- AWS 리소스 마스킹 적용 가능성 확인

## 🏗️ 프로젝트 구조

```
sdk-proxy/
├── docker-compose.yml              # Docker 환경 구성
├── Dockerfile                      # 테스트 컨테이너 이미지
├── package.json                    # Node.js 의존성
├── architecture.md                 # 시스템 아키텍처 문서
├── src/
│   ├── test-sdk-proxy.js          # SDK 프록시 테스트
│   ├── simple-masker.js           # 마스킹 로직
│   ├── network-analyzer.js        # 네트워크 분석
│   └── test-monitor.js            # 결과 수집 및 보고서
├── kong-minimal/
│   ├── kong.yml                   # Kong 설정
│   └── plugins/                   # Kong 플러그인
├── nginx-proxy/
│   └── nginx.conf                 # Nginx 프록시 설정
└── results/                       # 테스트 결과
```

## 🚀 빠른 시작

### 사전 요구사항

- Docker & Docker Compose
- Anthropic API Key

### 실행 방법

```bash
# 1. 환경변수 설정
export ANTHROPIC_API_KEY=sk-ant-api03-xxxxx

# 2. 전체 테스트 실행
docker-compose up --build

# 3. 결과 확인
cat results/final-report.md
```

## 🧪 테스트 시나리오

### 1. 직접 연결 테스트
- **목적**: 네트워크 격리 확인
- **기대**: 연결 차단됨

### 2. ProxyAgent 테스트
- **목적**: SDK 프록시 지원 확인
- **방법**: undici ProxyAgent 사용

### 3. 환경변수 테스트
- **목적**: ANTHROPIC_BASE_URL 지원 확인
- **방법**: 환경변수 설정

### 4. Custom Fetch 테스트
- **목적**: 요청 인터셉션 가능성 확인
- **방법**: fetch 함수 오버라이드

## 📊 결과 분석

테스트 완료 후 다음 파일들이 생성됩니다:

- `results/test-results.json` - 테스트 실행 결과
- `results/traffic-analysis.txt` - 네트워크 트래픽 분석
- `results/final-report.md` - 종합 보고서

## 🔧 개별 컴포넌트 실행

### Nginx 프록시만 실행
```bash
docker-compose up nginx-proxy
```

### Kong만 실행
```bash
docker-compose up kong-minimal
```

### 테스트만 실행
```bash
npm install
npm test
```

## 🏢 Kong 통합

### Kong 설정 적용
```bash
# Kong 컨테이너 접속
docker exec -it sdk-test-kong sh

# 설정 확인
kong config db_export
```

### 로그 확인
```bash
# Kong 로그
docker logs sdk-test-kong

# 프록시 로그
docker logs sdk-test-proxy
```

## 🐛 문제 해결

### 연결 실패
```bash
# 네트워크 확인
docker network ls
docker network inspect sdk-proxy_sdk-test-net

# 컨테이너 상태 확인
docker ps -a
```

### 프록시 설정 무시
```bash
# 트래픽 분석 실행
node src/network-analyzer.js

# 결과 확인
cat results/traffic-analysis.txt
```

## 📈 성능 고려사항

- 프록시 추가로 인한 레이턴시 증가 (5-10ms)
- Kong 플러그인 처리 시간 고려
- 네트워크 홉 추가로 인한 영향

## 🔒 보안 고려사항

- API 키는 환경변수로 관리
- 네트워크 격리로 외부 접근 차단
- 로그에 민감정보 노출 방지

## 📚 참고 문서

- [아키텍처 설계](./architecture.md)
- [Kong 플러그인 문서](./kong-minimal/plugins/simple-logger/README.md)
- [Claude SDK 공식 문서](https://github.com/anthropics/anthropic-sdk-typescript)

## 🤝 기여

이 프로젝트는 테스트 목적으로 생성되었습니다. 현재 Kong 프로젝트와 완전히 독립적으로 운영됩니다.

---
*Created: 2025-07-27*  
*Purpose: Claude SDK Proxy Support Validation*