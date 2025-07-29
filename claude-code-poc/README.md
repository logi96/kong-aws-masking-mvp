# Claude Code Kong Masking Proxy POC

## 🎯 목적
Claude Code가 Kong Gateway를 통과하도록 하여 AWS 리소스를 자동으로 마스킹하는 POC

## 🔍 핵심 발견: HTTPS 문제 해결

### 문제
- Claude Code는 api.anthropic.com으로 HTTPS 요청을 보냄
- HTTPS는 end-to-end 암호화로 중간에서 내용을 볼 수 없음
- Kong이 HTTPS 트래픽을 복호화하려면 정식 SSL 인증서 필요

### 해결책: HTTP 로컬 프록시
```
Claude Code → HTTP → Local Proxy (포트 8082) → Kong → HTTPS → api.anthropic.com
```

**핵심**: `ANTHROPIC_BASE_URL=http://localhost:8082` 설정으로 Claude Code가 HTTP를 사용하도록 함

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Network (poc-net)                  │
│                                                              │
│  ┌─────────────────┐    ┌──────────────────┐               │
│  │  claude-test    │    │  masking-proxy   │               │
│  │                 │    │                   │               │
│  │ - Claude Code   │───▶│ - HTTP Server    │               │
│  │ - Test Scripts  │HTTP│ - AWS Masking    │               │
│  │ - Isolated Env  │    │ - Port 8082      │               │
│  └─────────────────┘    └────────┬─────────┘               │
│                                   │                          │
│                                   │ HTTP                     │
│                                   ▼                          │
│                         ┌─────────────────┐                 │
│                         │      kong       │                 │
│                         │                 │                 │
│                         │ - Gateway       │─────────────────┼───▶ api.anthropic.com
│                         │ - Routing       │      HTTPS      │
│                         │ - Logging       │                 │
│                         └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 사용 방법

### 1. 환경 설정
```bash
# API 키 설정 (선택사항 - 실제 API 호출시 필요)
export ANTHROPIC_API_KEY=sk-ant-api03-xxxxx
```

### 2. POC 실행
```bash
# 전체 환경 시작 및 테스트
./run-poc.sh
```

### 3. 대화형 테스트
```bash
# Claude Code 테스트 컨테이너 접속
docker-compose exec claude-test /bin/bash

# 테스트 실행
./test-claude-code.sh
```

### 4. 로그 확인
```bash
# 마스킹 프록시 로그 (마스킹된 요청 확인)
docker-compose logs -f masking-proxy

# Kong 로그
docker-compose logs -f kong
```

## 📁 프로젝트 구조

```
claude-code-poc/
├── docker-compose.yml          # 전체 환경 구성
├── run-poc.sh                  # 실행 스크립트
│
├── kong-masking-proxy/         # HTTP 마스킹 프록시
│   ├── Dockerfile
│   ├── kong-masking-proxy.py  # 마스킹 로직 구현
│   ├── test-http-proxy.py     # HTTP 연결 테스트
│   └── requirements.txt
│
├── claude-code-test/           # 격리된 테스트 환경
│   ├── Dockerfile
│   └── test-claude-code.sh    # 테스트 스크립트
│
├── kong.yml                    # Kong 설정
└── example/                    # 참고 프로젝트
    └── claude-code-litellm/    # 원본 아이디어 소스
```

## 🎭 마스킹 예시

### 요청 (원본)
```json
{
  "messages": [{
    "role": "user",
    "content": "Analyze EC2 instance i-1234567890abcdef0 in bucket my-data-bucket"
  }]
}
```

### 요청 (마스킹됨)
```json
{
  "messages": [{
    "role": "user",
    "content": "Analyze EC2 instance EC2_INSTANCE_001 in bucket S3_BUCKET_001"
  }]
}
```

## ✅ 검증된 사항

1. **HTTP BASE_URL 지원**: Claude Code는 HTTP 로컬 프록시 연결 가능
2. **요청 인터셉션**: 프록시에서 요청 내용 확인 및 수정 가능
3. **마스킹 적용**: AWS 리소스 패턴 인식 및 마스킹 성공
4. **Kong 통합**: 마스킹된 요청을 Kong으로 전달 가능

## 🚨 주의사항

- 이는 POC이며, 프로덕션 사용시 추가 보안 고려 필요
- 실제 API 호출시 유효한 ANTHROPIC_API_KEY 필요
- 로컬 HTTP 프록시는 개발/테스트 환경에서만 사용 권장

## 🔄 정리

```bash
# 모든 컨테이너 중지 및 제거
docker-compose down

# 볼륨까지 완전 제거
docker-compose down -v
```