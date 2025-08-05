# Claude Code SDK Docker Container
# Base image: Node.js 20 LTS on Alpine Linux for minimal size
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install system dependencies that might be needed
RUN apk add --no-cache \
    bash \
    curl \
    git \
    ca-certificates

# Install Claude Code SDK globally
RUN npm install -g @anthropic-ai/claude-code

# Verify installation
RUN claude --version

# Create a startup script to handle API key (as root)
RUN echo '#!/bin/sh' > /usr/local/bin/claude-start.sh && \
    echo 'if [ -n "$ANTHROPIC_API_KEY" ]; then' >> /usr/local/bin/claude-start.sh && \
    echo '  export ANTHROPIC_API_KEY' >> /usr/local/bin/claude-start.sh && \
    echo 'fi' >> /usr/local/bin/claude-start.sh && \
    echo 'exec "$@"' >> /usr/local/bin/claude-start.sh && \
    chmod +x /usr/local/bin/claude-start.sh

# Create a non-root user for security
RUN addgroup -g 1001 claude && \
    adduser -D -u 1001 -G claude claude

# Switch to non-root user
USER claude

# Set working directory for claude user
WORKDIR /home/claude

# Default command - use startup script
ENTRYPOINT ["/usr/local/bin/claude-start.sh"]
CMD ["sh"]