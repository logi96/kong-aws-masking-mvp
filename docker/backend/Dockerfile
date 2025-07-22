# Multi-stage Dockerfile for Backend API
# Optimized for Node.js development and production

ARG NODE_VERSION=20-alpine

# Stage 1: Dependencies stage
FROM node:${NODE_VERSION} AS deps

WORKDIR /app

# Copy package files
COPY backend/package*.json ./

# Install production dependencies
RUN npm ci --only=production

# Stage 2: Development dependencies
FROM deps AS dev-deps

# Install all dependencies including devDependencies
RUN npm ci

# Stage 3: Build stage (for future TypeScript migration)
FROM dev-deps AS builder

WORKDIR /app

# Copy source code
COPY backend/ ./

# Currently no build step needed for JavaScript
# Future: RUN npm run build

# Stage 4: Runtime stage
FROM node:${NODE_VERSION} AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    curl \
    ca-certificates \
    tzdata \
    aws-cli \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN adduser -D -u 1000 -g 1000 api-user

WORKDIR /app

# Copy production dependencies from deps stage
COPY --from=deps --chown=api-user:api-user /app/node_modules ./node_modules

# Copy application code
COPY --chown=api-user:api-user backend/ ./

# Create necessary directories
RUN mkdir -p /app/logs /app/tmp \
    && chown -R api-user:api-user /app \
    && chmod -R 755 /app

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    NODE_OPTIONS="--max-old-space-size=256"

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Switch to non-root user
USER api-user

# Expose port
EXPOSE 3000

# Stage 5: Development stage
FROM dev-deps AS development

# Install development tools
RUN apk add --no-cache \
    git \
    aws-cli

WORKDIR /app

# Copy all source code
COPY backend/ ./

# Install nodemon globally for development
RUN npm install -g nodemon

# Set development environment
ENV NODE_ENV=development \
    PORT=3000

# Health check for development
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Expose port
EXPOSE 3000

# Use nodemon for hot reload in development
CMD ["nodemon", "--watch", ".", "--ext", "js,json", "--ignore", "node_modules/", "server.js"]

# Default stage is runtime
FROM runtime

# Use exec form for proper signal handling
CMD ["node", "server.js"]