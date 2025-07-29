FROM redis:7-alpine

# 타임존 설정을 위한 패키지 설치
RUN apk add --no-cache tzdata

# 기본 Redis 설정 복사
COPY redis.conf /usr/local/etc/redis/redis.conf

# 데이터 디렉토리 생성
RUN mkdir -p /data && chown redis:redis /data

# 포트 노출
EXPOSE 6379

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD redis-cli --pass ${REDIS_PASSWORD} ping || exit 1

# Redis 사용자로 전환
USER redis

# Redis 서버 시작 (환경 변수를 통한 패스워드 설정)
CMD ["sh", "-c", "redis-server /usr/local/etc/redis/redis.conf --requirepass ${REDIS_PASSWORD}"]