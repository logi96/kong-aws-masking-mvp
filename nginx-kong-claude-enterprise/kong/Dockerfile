# Kong 3.7 버전 사용 (메인 프로젝트와 동일)
FROM kong:3.7

USER root

# 필요한 패키지 설치
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Kong 환경 변수 설정
ENV KONG_DATABASE=off \
    KONG_DECLARATIVE_CONFIG=/opt/kong/kong.yml \
    KONG_PROXY_ACCESS_LOG=/dev/stdout \
    KONG_ADMIN_ACCESS_LOG=/dev/stdout \
    KONG_PROXY_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_LISTEN="0.0.0.0:8001" \
    KONG_PROXY_LISTEN="0.0.0.0:8000" \
    KONG_PLUGINS="bundled,aws-masker"

# 디렉토리 생성
RUN mkdir -p /opt/kong \
    && mkdir -p /usr/local/share/lua/5.1/kong/plugins/aws-masker \
    && chown -R kong:kong /opt/kong

# aws-masker 플러그인 복사
COPY --chown=kong:kong plugins/aws-masker/ /usr/local/share/lua/5.1/kong/plugins/aws-masker/

# Kong 설정 파일 복사
COPY --chown=kong:kong kong.yml /opt/kong/kong.yml

# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD kong health || exit 1

# Kong 사용자로 전환
USER kong

# 포트 노출
EXPOSE 8000 8001

# Kong 시작
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["kong", "docker-start"]