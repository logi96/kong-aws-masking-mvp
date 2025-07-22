# Kong 3.7 DB-less Configuration - Minimal Setup
# Based on search results for Kong 3.7 PostgreSQL connection refused fixes

FROM kong:3.7

USER root

# Set Kong environment variables for DB-less mode
ENV KONG_DATABASE=off \
    KONG_DECLARATIVE_CONFIG=/opt/kong/kong.yml \
    KONG_PROXY_ACCESS_LOG=/dev/stdout \
    KONG_ADMIN_ACCESS_LOG=/dev/stdout \
    KONG_PROXY_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_LISTEN="0.0.0.0:8001" \
    KONG_PROXY_LISTEN="0.0.0.0:8000" \
    KONG_PLUGINS="aws-masker"

# Create necessary directories
RUN mkdir -p /opt/kong \
    && chown -R kong:kong /opt/kong \
    && chmod -R 755 /opt/kong

# Health check with longer timeout for DB-less mode
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD kong health || exit 1

# Switch back to kong user
USER kong

# Expose ports
EXPOSE 8000 8001

# Use exec form to ensure proper signal handling
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["kong", "docker-start"]