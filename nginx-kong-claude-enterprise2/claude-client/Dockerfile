# Claude API Client for Testing
# Multi-stage build for optimized image size
FROM node:20-alpine AS base

# Install essential tools and AWS CLI v2
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    httpie \
    python3 \
    py3-pip \
    groff \
    less \
    mailcap \
    aws-cli \
    && rm -rf /var/cache/apk/*

# Install additional testing tools
RUN apk add --no-cache \
    netcat-openbsd \
    bind-tools \
    postgresql-client \
    mysql-client \
    redis

# Create app directory with proper permissions
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 testuser && \
    adduser -D -u 1001 -G testuser testuser

# Install Node.js dependencies
COPY --chown=testuser:testuser package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Create directories for logs, test scenarios, and results
RUN mkdir -p /app/logs /app/test-scenarios /app/scripts /app/test-results /app/test-data && \
    chown -R testuser:testuser /app

# Copy test client scripts with proper ownership
COPY --chown=testuser:testuser test-client.js ./
COPY --chown=testuser:testuser test-scenarios/ ./test-scenarios/
COPY --chown=testuser:testuser scripts/ ./scripts/

# Create a comprehensive health check script
RUN echo '#!/bin/sh' > /usr/local/bin/healthcheck.sh && \
    echo 'set -e' >> /usr/local/bin/healthcheck.sh && \
    echo '# Check if node is running' >> /usr/local/bin/healthcheck.sh && \
    echo 'pgrep -f "node" > /dev/null || exit 1' >> /usr/local/bin/healthcheck.sh && \
    echo '# Check if logs directory is writable' >> /usr/local/bin/healthcheck.sh && \
    echo 'touch /app/logs/healthcheck.tmp && rm /app/logs/healthcheck.tmp || exit 1' >> /usr/local/bin/healthcheck.sh && \
    echo 'exit 0' >> /usr/local/bin/healthcheck.sh && \
    chmod +x /usr/local/bin/healthcheck.sh

# Set environment variables for testing
ENV NODE_ENV=test \
    LOG_LEVEL=info \
    TEST_TIMEOUT=60000 \
    AWS_DEFAULT_REGION=ap-northeast-2

# Health check with more aggressive settings for testing
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Switch to non-root user
USER testuser

# Default command - run test client in watch mode
CMD ["node", "test-client.js"]