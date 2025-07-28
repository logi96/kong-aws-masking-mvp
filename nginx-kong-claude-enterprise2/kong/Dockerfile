# Kong Gateway with AWS Masker Plugin
FROM kong:3.9.0-ubuntu

# Install dependencies for the aws-masker plugin
USER root
RUN apt-get update && apt-get install -y \
    lua5.1-cjson \
    lua5.1-socket \
    && rm -rf /var/lib/apt/lists/*

# Create plugin directory structure
RUN mkdir -p /usr/local/share/lua/5.1/kong/plugins/aws-masker

# Copy the AWS masker plugin files
COPY plugins/aws-masker/*.lua /usr/local/share/lua/5.1/kong/plugins/aws-masker/

# Set proper permissions
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/aws-masker

# Switch back to kong user
USER kong

# Set Kong environment variables
ENV KONG_DATABASE=off
ENV KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml
ENV KONG_PLUGINS=bundled,aws-masker
ENV KONG_LUA_PACKAGE_PATH=/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/kong/plugins/?.lua;/usr/local/kong/plugins/?/init.lua;;

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD kong health || exit 1

# Expose Kong ports
EXPOSE 8000 8443 8001 8444

# Start Kong
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["kong", "docker-start"]