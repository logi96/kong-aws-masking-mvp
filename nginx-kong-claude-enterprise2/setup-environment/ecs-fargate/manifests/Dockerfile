# Kong Gateway + AWS Masker ElastiCache Plugin
# ECS Fargate Production Image
# Phase 1 Success Version with ElastiCache Integration

FROM kong:3.9-ubuntu

# Set maintainer and labels
LABEL maintainer="Kong AWS Masking Enterprise Team"
LABEL version="2.0.0-elasticache-ecs"
LABEL description="Kong Gateway with ElastiCache-enabled AWS masking plugin for ECS Fargate"

# Switch to root to install dependencies
USER root

# Install lua-resty-redis if not already present
RUN apt-get update && \
    apt-get install -y curl && \
    luarocks install lua-resty-redis && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create plugin directory structure
RUN mkdir -p /usr/local/share/lua/5.1/kong/plugins/aws-masker

# Copy plugin files (will be added via COPY commands below)
COPY kong-plugins/aws-masker/ /usr/local/share/lua/5.1/kong/plugins/aws-masker/

# Set proper permissions
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/aws-masker && \
    chmod -R 644 /usr/local/share/lua/5.1/kong/plugins/aws-masker/*.lua

# Switch back to kong user for security
USER kong

# Default Kong configuration environment variables
ENV KONG_DATABASE=off \
    KONG_PROXY_LISTEN="0.0.0.0:8000" \
    KONG_ADMIN_LISTEN="0.0.0.0:8001" \
    KONG_STATUS_LISTEN="0.0.0.0:8100" \
    KONG_PLUGINS="aws-masker" \
    KONG_LOG_LEVEL="info"

# ElastiCache connection defaults
ENV ELASTICACHE_ENDPOINT="localhost.localstack.cloud" \
    ELASTICACHE_PORT="4510" \
    ELASTICACHE_SSL_ENABLED="false" \
    ELASTICACHE_DATABASE="0"

# Performance and reliability settings
ENV KONG_WORKER_PROCESSES="auto" \
    KONG_WORKER_CONNECTIONS="4096" \
    KONG_PROXY_ACCESS_LOG="/dev/stdout" \
    KONG_ADMIN_ACCESS_LOG="/dev/stdout" \
    KONG_PROXY_ERROR_LOG="/dev/stderr" \
    KONG_ADMIN_ERROR_LOG="/dev/stderr"

# Expose ports
EXPOSE 8000 8001 8100

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8100/status || exit 1

# Entry point
CMD ["kong", "docker-start"]