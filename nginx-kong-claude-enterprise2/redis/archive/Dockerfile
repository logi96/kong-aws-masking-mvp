# Redis for AWS Masking Mapping Storage
FROM redis:7-alpine

# Install additional tools for health checks and debugging
RUN apk add --no-cache \
    curl \
    jq

# Create necessary directories
RUN mkdir -p /var/log/redis && \
    chown redis:redis /var/log/redis

# Copy custom entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/custom-entrypoint.sh

# Make entrypoint executable
RUN chmod +x /usr/local/bin/custom-entrypoint.sh

# Ensure proper permissions for data directory
RUN mkdir -p /data && chown redis:redis /data

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
    CMD redis-cli ping | grep -q PONG || exit 1

# Expose Redis port
EXPOSE 6379

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]