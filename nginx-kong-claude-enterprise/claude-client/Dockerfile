FROM node:20-alpine

# 필요한 패키지 설치
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    python3 \
    py3-pip

# 작업 디렉토리 설정
WORKDIR /app

# Claude Code 설치
RUN npm install -g @anthropic-ai/claude-code

# Node.js 프로젝트 초기화
COPY package.json ./
RUN npm install

# 테스트 스크립트 복사
COPY test-claude.sh ./
RUN chmod +x test-claude.sh

# 테스트 시나리오 디렉토리
COPY test-scenarios/ ./test-scenarios/

# 로그 디렉토리 생성
RUN mkdir -p /app/logs

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD curl -f http://nginx:8082/health || exit 1

# 기본 명령 (컨테이너 유지)
CMD ["tail", "-f", "/dev/null"]