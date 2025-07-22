# Kong AWS Masking MVP - Local Development & Testing Guide

## Overview
This guide focuses on local development, testing, and simple deployment for the MVP phase.

## 1. Local Development Workflow

### 1.1 Development Setup
```bash
# Clone the repository
git clone <repository-url>
cd kong-aws-masking-mvp

# Create environment file
cp .env.example .env
# Edit .env with your API keys

# Install dependencies
cd backend && npm install
```

### 1.2 Running Locally
```bash
# Start all services with Docker Compose
docker-compose up --build

# Run in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## 2. Testing Strategy

### 2.1 Local Testing
```bash
# Run backend tests
cd backend
npm test

# Run linting
npm run lint

# Quick integration test
cd ../tests
node simple-test.js

# System health check
./quick-check.sh
```

### 2.2 Manual Testing Checklist
- [ ] Backend API health endpoint responds
- [ ] Kong Gateway is accessible
- [ ] AWS CLI commands work correctly
- [ ] Data masking functions properly
- [ ] Claude API integration works

## 3. Building & Deployment

### 3.1 Building Docker Images
```bash
# Build all services
docker-compose build

# Build specific service
docker-compose build backend

# Build with no cache
docker-compose build --no-cache
```

### 3.2 Simple Deployment Process
```bash
# For MVP deployment to a single server:

# 1. Copy files to server
scp -r ./* user@server:/opt/kong-aws-masking/

# 2. SSH to server
ssh user@server

# 3. Start services
cd /opt/kong-aws-masking
docker-compose up -d

# 4. Verify deployment
curl http://localhost:3000/health
curl http://localhost:8001/status
```

## 4. Development Scripts

### 4.1 Quick Test Script
```bash
#!/bin/bash
# scripts/test-local.sh

echo "Running local tests..."

# Check if services are running
if ! docker-compose ps | grep -q "Up"; then
    echo "Services not running. Starting..."
    docker-compose up -d
    sleep 10
fi

# Run health checks
echo "Checking Backend API..."
curl -f http://localhost:3000/health || exit 1

echo "Checking Kong Gateway..."
curl -f http://localhost:8001/status || exit 1

echo "All tests passed!"
```

### 4.2 Development Helper
```bash
#!/bin/bash
# scripts/dev.sh

case "$1" in
    start)
        docker-compose up -d
        docker-compose logs -f
        ;;
    stop)
        docker-compose down
        ;;
    restart)
        docker-compose restart
        ;;
    logs)
        docker-compose logs -f ${2:-}
        ;;
    test)
        cd tests && node simple-test.js
        ;;
    *)
        echo "Usage: ./dev.sh {start|stop|restart|logs|test}"
        exit 1
        ;;
esac
```

## 5. Environment Configuration

### 5.1 Required Environment Variables
```bash
# .env file
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
AWS_REGION=us-east-1
NODE_ENV=development
PORT=3000
```

### 5.2 Docker Compose Configuration
The `docker-compose.yml` file handles:
- Service dependencies
- Network configuration
- Volume mounts for AWS credentials
- Health checks

## 6. Troubleshooting

### 6.1 Common Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| Port already in use | Another service on port | Change port in docker-compose.yml |
| AWS credentials error | Missing ~/.aws config | Configure AWS CLI locally |
| Kong not starting | Configuration error | Check kong/kong.yml syntax |
| API timeout | Slow Claude response | Increase timeout in backend |

### 6.2 Debug Commands
```bash
# Check container status
docker-compose ps

# View specific service logs
docker-compose logs backend
docker-compose logs kong

# Execute commands in container
docker-compose exec backend sh
docker-compose exec kong sh

# Check network connectivity
docker-compose exec backend ping kong
```

## 7. Code Quality

### 7.1 Pre-commit Checks
```bash
# Run before committing
npm run lint
npm test

# Format code
npm run format
```

### 7.2 JSDoc Standards
All JavaScript code should include JSDoc comments:
```javascript
/**
 * Analyzes AWS resources using Claude API
 * @param {Object} awsData - AWS resource data
 * @returns {Promise<Object>} Analysis results
 */
async function analyzeResources(awsData) {
    // Implementation
}
```

## 8. Security Considerations

### 8.1 Local Security
- Never commit `.env` files
- Keep AWS credentials in `~/.aws` only
- Use read-only mounts for sensitive data
- Regular dependency updates with `npm audit`

### 8.2 Basic Security Checks
```bash
# Check for known vulnerabilities
npm audit

# Update dependencies
npm update

# Check for secrets in code
grep -r "sk-ant" --exclude-dir=node_modules .
grep -r "aws_secret" --exclude-dir=node_modules .
```

## 9. Performance Tips

### 9.1 Docker Optimization
- Use `.dockerignore` to exclude unnecessary files
- Leverage build cache with proper Dockerfile structure
- Limit container resources in docker-compose.yml

### 9.2 Development Speed
- Use `nodemon` for auto-reload during development
- Mount source code as volumes for instant updates
- Use `docker-compose up` without `--build` when code hasn't changed

## 10. MVP Deployment Checklist

Before deploying the MVP:
- [ ] All tests pass locally
- [ ] Environment variables are set
- [ ] AWS credentials are configured
- [ ] Docker images build successfully
- [ ] Health endpoints respond correctly
- [ ] Masking functionality verified
- [ ] Basic security checks completed

## Conclusion

This guide provides a simple, effective workflow for MVP development without complex CI/CD pipelines. Focus on:
- Local development and testing
- Simple Docker-based deployment
- Manual verification steps
- Basic security practices

For production deployment, additional automation and security measures should be implemented post-MVP.