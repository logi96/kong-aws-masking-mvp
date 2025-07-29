FROM node:20-alpine

# 필수 도구 설치
RUN apk add --no-cache \
    curl \
    tcpdump \
    bash \
    wget

WORKDIR /app

# package.json 복사 및 의존성 설치
COPY package.json ./
RUN npm install

# 소스 디렉토리는 volume으로 마운트됨
# COPY src/ ./src/

# 실행 권한
USER root

# 기본 명령어
CMD ["node", "src/test-sdk-proxy.js"]