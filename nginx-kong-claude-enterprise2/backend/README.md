# nginx-kong-claude-enterprise2 Backend Service

## Overview

This backend service provides comprehensive health monitoring and API management for the nginx-kong-claude-enterprise2 project. It includes:

- **Health Check API**: Monitor Kong, Redis, and Claude API connectivity
- **Resource Analysis**: AWS resource analysis through Kong Gateway
- **Monitoring Dashboard**: Real-time metrics and observability
- **High Availability**: Built-in resilience and error handling

## Features

### 🏥 Health Check Endpoints

- `/health` - Basic health status
- `/health/detailed` - Comprehensive system health with all dependencies
- `/health/live` - Kubernetes liveness probe
- `/health/ready` - Kubernetes readiness probe
- `/health/dependencies/:name` - Check specific dependency (kong, redis, claude)
- `/health/metrics` - Service performance metrics

### 📊 Monitoring & Observability

- Real-time system metrics collection
- Prometheus-compatible metrics export
- Event tracking and alerting
- Request tracing and performance monitoring
- SSE-based log streaming

### 🔐 Security Features

- Helmet.js for security headers
- Rate limiting protection
- CORS configuration
- Input validation and sanitization
- Secure error handling

## Quick Start

### Prerequisites

- Node.js >= 20.0.0
- npm >= 10.0.0
- Redis server
- Kong Gateway
- AWS CLI configured
- Claude API key

### Installation

```bash
# Install dependencies
npm install

# Copy environment configuration
cp .env.example .env

# Edit .env with your configuration
vim .env
```

### Environment Configuration

Key environment variables:

```env
# Node Environment
NODE_ENV=development
PORT=3000

# AWS Configuration
AWS_REGION=ap-northeast-2

# Claude API
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE

# Kong Gateway
KONG_ADMIN_URL=http://kong:8001
KONG_PROXY_URL=http://kong:8000

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your-password
```

### Running the Service

```bash
# Development mode with hot reload
npm run dev

# Production mode
npm run start:prod

# Test mode
npm run start:test

# Using the start script
./scripts/start.sh dev
```

## API Documentation

### Health Check API

#### Basic Health Check
```bash
GET /health

Response:
{
  "status": "healthy",
  "timestamp": "2024-01-28T10:00:00.000Z",
  "service": {
    "name": "nginx-kong-claude-enterprise2-backend",
    "version": "1.0.0",
    "environment": "development"
  },
  "uptime": 3600
}
```

#### Detailed Health Check
```bash
GET /health/detailed

Response:
{
  "status": "healthy|degraded|unhealthy",
  "timestamp": "2024-01-28T10:00:00.000Z",
  "dependencies": [
    {
      "name": "kong",
      "status": "healthy",
      "responseTime": 45,
      "details": {
        "admin": { "status": "healthy" },
        "proxy": { "status": "healthy" }
      }
    },
    {
      "name": "redis",
      "status": "healthy",
      "responseTime": 10,
      "details": {
        "ping": "PONG",
        "version": "7.0.5"
      }
    },
    {
      "name": "claude",
      "status": "healthy",
      "responseTime": 200,
      "details": {
        "apiKeyConfigured": true
      }
    }
  ],
  "system": {
    "memory": { "usagePercent": "45.00" },
    "cpu": { "loadAverage": [0.5, 0.7, 0.8] }
  }
}
```

### Testing

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test suite
npm run test:unit
npm run test:integration

# Test health endpoints
./scripts/test-health.sh
```

### Code Quality

```bash
# Lint code
npm run lint

# Fix linting issues
npm run lint:fix

# Type checking
npm run type-check

# Full quality check
npm run quality:check
```

## Project Structure

```
backend/
├── src/
│   ├── app.js              # Express application setup
│   ├── server.js           # Server entry point
│   ├── routes/
│   │   ├── health.js       # Health check endpoints
│   │   ├── analyze.js      # Analysis endpoints
│   │   └── monitoring.js   # Monitoring endpoints
│   ├── services/
│   │   ├── health/         # Health check service
│   │   ├── monitoring/     # Monitoring service
│   │   ├── aws/           # AWS service integration
│   │   ├── claude/        # Claude API integration
│   │   └── redis/         # Redis service
│   ├── middlewares/
│   │   └── errorHandler.js # Error handling middleware
│   └── utils/
│       └── logger.js       # Winston logger configuration
├── tests/
│   ├── unit/              # Unit tests
│   └── integration/       # Integration tests
├── scripts/
│   ├── start.sh          # Startup script
│   └── test-health.sh    # Health check test script
└── package.json
```

## Monitoring Integration

The service provides multiple monitoring integration points:

1. **Prometheus Metrics**: `/monitoring/prometheus`
2. **Custom Metrics**: `/monitoring/metrics`
3. **Event Tracking**: `/monitoring/events`
4. **Log Streaming**: `/monitoring/logs` (SSE)

## Deployment

### Docker

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "src/server.js"]
```

### Kubernetes

The service is designed to work with Kubernetes health probes:

```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5
```

## Troubleshooting

### Common Issues

1. **Redis Connection Failed**
   - Check Redis host and port in .env
   - Ensure Redis password is correct
   - Verify Redis is running

2. **Kong Gateway Unreachable**
   - Check Kong URLs in .env
   - Ensure Kong is running
   - Verify network connectivity

3. **Claude API Errors**
   - Verify API key is valid
   - Check API rate limits
   - Ensure network access to Claude API

### Debug Mode

Enable debug logging:
```bash
LOG_LEVEL=debug npm run dev
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Run tests: `npm test`
4. Ensure code quality: `npm run quality:check`
5. Commit your changes
6. Push to the branch
7. Create a Pull Request

## License

MIT License - See LICENSE file for details