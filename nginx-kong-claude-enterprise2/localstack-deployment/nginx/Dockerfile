FROM nginx:1.27-alpine

RUN apk add --no-cache curl

# Remove default nginx configuration
RUN rm -rf /etc/nginx/conf.d/*

# Copy our configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/claude-proxy.conf /etc/nginx/conf.d/claude-proxy.conf

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s \
    CMD curl -f http://localhost:8082/health || exit 1

EXPOSE 8082