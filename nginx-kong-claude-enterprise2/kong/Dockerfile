# Kong Gateway with AWS Masker Plugin
ARG KONG_VERSION=3.8.0
FROM kong:${KONG_VERSION}-ubuntu

# Install dependencies for the aws-masker plugin
USER root

# Optimize package installation and add memory optimization tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    lua5.1-cjson \
    lua5.1-socket \
    lua5.1-lpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create plugin directory structure
RUN mkdir -p /usr/local/share/lua/5.1/kong/plugins/aws-masker
RUN mkdir -p /usr/local/kong/declarative

# Copy the AWS masker plugin files
COPY plugins/aws-masker/*.lua /usr/local/share/lua/5.1/kong/plugins/aws-masker/

# Copy minimal Kong configuration
COPY kong-minimal.yml /usr/local/kong/declarative/kong.yml

# Set proper permissions
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/aws-masker
RUN chown -R kong:kong /usr/local/kong/declarative

# Switch back to kong user
USER kong

# Set Kong environment variables for better memory management
ENV KONG_DATABASE=off
ENV KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml
ENV KONG_PLUGINS=bundled,aws-masker
ENV KONG_LUA_PACKAGE_PATH=/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/kong/plugins/?.lua;/usr/local/kong/plugins/?/init.lua;;

# Memory optimization settings
ENV KONG_NGINX_WORKER_PROCESSES=auto
ENV KONG_NGINX_WORKER_CONNECTIONS=8192
ENV KONG_MEM_CACHE_SIZE=2048m
ENV KONG_DB_CACHE_TTL=3600
ENV KONG_DB_CACHE_NEG_TTL=300
ENV KONG_NGINX_HTTP2_MAX_FIELD_SIZE=8k
ENV KONG_NGINX_HTTP2_MAX_HEADER_SIZE=16k
ENV KONG_CLIENT_BODY_BUFFER_SIZE=8m

# Enhanced health check with memory monitoring
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD kong health || exit 1

# Expose Kong ports
EXPOSE 8000 8443 8001 8444

# Start Kong
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["kong", "docker-start"]