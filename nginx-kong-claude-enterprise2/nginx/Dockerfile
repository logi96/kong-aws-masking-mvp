# Nginx Reverse Proxy for Kong Gateway
FROM nginx:1.27-alpine

# Install useful tools for debugging
RUN apk add --no-cache \
    curl \
    wget \
    net-tools \
    vim \
    bash

# Create necessary directories
RUN mkdir -p /var/log/nginx /var/cache/nginx \
    && chmod 755 /var/log/nginx /var/cache/nginx

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# Create a custom health check script
RUN echo '#!/bin/sh' > /usr/local/bin/healthcheck.sh && \
    echo 'curl -f http://localhost:8082/health || exit 1' >> /usr/local/bin/healthcheck.sh && \
    chmod +x /usr/local/bin/healthcheck.sh

# Health check configuration
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Expose port 8082
EXPOSE 8082

# Use exec form to ensure nginx receives signals properly
CMD ["nginx", "-g", "daemon off;"]