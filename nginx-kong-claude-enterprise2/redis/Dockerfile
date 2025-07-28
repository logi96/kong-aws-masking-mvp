# Redis for AWS Masking Mapping Storage
FROM redis:7-alpine

# Install additional tools for health checks and debugging
RUN apk add --no-cache \
    curl \
    jq

# Create necessary directories
RUN mkdir -p /var/log/redis && \
    chown redis:redis /var/log/redis

# Copy custom Redis configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Ensure proper permissions
RUN chown redis:redis /usr/local/etc/redis/redis.conf

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
    CMD redis-cli ping | grep -q PONG || exit 1

# Expose Redis port
EXPOSE 6379

# Run Redis with custom config
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]