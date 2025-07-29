FROM nginx:1.25-alpine

# 타임존 설정
RUN apk add --no-cache tzdata

# 헬스체크를 위한 curl 설치
RUN apk add --no-cache curl

# 로그 디렉토리 생성
RUN mkdir -p /var/log/nginx

# 기본 nginx 설정 제거
RUN rm -f /etc/nginx/conf.d/default.conf

# 커스텀 설정 복사
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# 포트 노출
EXPOSE 8082

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8082/health || exit 1

# nginx 실행
CMD ["nginx", "-g", "daemon off;"]