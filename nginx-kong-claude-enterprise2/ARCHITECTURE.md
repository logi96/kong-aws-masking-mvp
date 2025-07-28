# Kong AWS Masker Infrastructure Architecture

## Overview

This document describes the complete infrastructure architecture for the Kong AWS Masker plugin integration with Claude API.

## Architecture Components

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Claude Client  │────▶│   Nginx Proxy   │────▶│  Kong Gateway   │
│   (Port 3000)   │     │  (Port 8082)    │     │  (Port 8000)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                          │
                                                          ▼
                                                 ┌─────────────────┐
                                                 │   AWS Masker    │
                                                 │    Plugin       │
                                                 └─────────────────┘
                                                          │
                                ┌─────────────────────────┴─────────┐
                                │                                   │
                                ▼                                   ▼
                        ┌─────────────────┐                ┌─────────────────┐
                        │     Redis       │                │   Claude API    │
                        │ (Mapping Store) │                │  (Anthropic)    │
                        └─────────────────┘                └─────────────────┘
```

## Component Details

### 1. Kong Gateway (Port 8000/8001)
- **Image**: `kong:3.9.0-ubuntu`
- **Mode**: DB-less (declarative configuration)
- **Purpose**: API Gateway with AWS resource masking
- **Features**:
  - AWS Masker plugin for sensitive data protection
  - Rate limiting and security policies
  - Request/response transformation
  - Health checks and monitoring

### 2. Redis (Port 6379)
- **Image**: `redis:7-alpine`
- **Purpose**: High-performance mapping storage
- **Features**:
  - Bidirectional mapping storage (original ↔ masked)
  - TTL-based automatic cleanup
  - Performance optimization with pipelining
  - Persistence with AOF and RDB

### 3. Nginx (Port 8082)
- **Image**: `nginx:1.27-alpine`
- **Purpose**: Enterprise proxy layer
- **Features**:
  - Load balancing
  - SSL termination (if configured)
  - Request routing
  - Additional security layer

### 4. Claude Client
- **Image**: `node:20-alpine`
- **Purpose**: Test client for integration testing
- **Features**:
  - Automated testing scenarios
  - Performance benchmarking
  - Integration validation

## Docker Network Architecture

```yaml
networks:
  claude-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

## Environment Configuration

### Required Environment Variables
```bash
# API Keys
ANTHROPIC_API_KEY=sk-ant-api03-xxx

# Redis Security
REDIS_PASSWORD=<secure-password>

# AWS Configuration
AWS_REGION=ap-northeast-2
AWS_ACCESS_KEY_ID=<your-key>
AWS_SECRET_ACCESS_KEY=<your-secret>
```

## Kong Plugin Architecture

### AWS Masker Plugin Structure
```
kong/plugins/aws-masker/
├── handler.lua              # Main request/response handler
├── schema.lua               # Configuration schema
├── masker_ngx_re.lua       # Optimized regex masking engine
├── patterns.lua             # AWS resource patterns
├── redis_integration.lua    # Redis connection management
├── monitoring.lua           # Metrics and monitoring
├── event_publisher.lua      # Event publishing for audit
└── health_check.lua         # Health check endpoints
```

### Plugin Flow
1. **Request Phase**:
   - Intercept incoming requests
   - Extract AWS resource identifiers
   - Generate masked values
   - Store mappings in Redis
   - Replace sensitive data with masked values

2. **Response Phase**:
   - Intercept Claude API responses
   - Retrieve original values from Redis
   - Replace masked values with originals
   - Update monitoring metrics

## Redis Data Structure

### Mapping Storage
```
# Forward mapping (original → masked)
aws:mask:i-1234567890abcdef0 → EC2_001
aws:mask:arn:aws:iam::123456789012:role/MyRole → IAM_ROLE_001

# Reverse mapping (masked → original)
aws:unmask:EC2_001 → i-1234567890abcdef0
aws:unmask:IAM_ROLE_001 → arn:aws:iam::123456789012:role/MyRole

# Statistics
aws:stats:counts → {total_mappings: 1000, ...}
aws:stats:counts:20250728 → {daily_mappings: 100, ...}
```

## Security Considerations

### 1. Network Security
- All services run in isolated Docker network
- No direct external access to Redis
- Kong Admin API protected (consider adding authentication)

### 2. Data Security
- AWS resources masked before external API calls
- Redis password protection
- Sensitive commands disabled in Redis
- TLS/SSL support ready for production

### 3. Access Control
- Rate limiting on API endpoints
- Bot detection enabled
- IP restriction capabilities
- Request size limiting

## Performance Optimization

### 1. Kong Optimizations
- Connection pooling for Redis
- Pattern caching for regex operations
- Worker process tuning
- Memory cache configuration

### 2. Redis Optimizations
- Pipeline operations for batch processing
- Connection pooling with keepalive
- Optimized data structures
- Memory limits and eviction policies

### 3. Nginx Optimizations
- Worker process auto-tuning
- Keep-alive connections
- Buffer size optimization
- Gzip compression

## Monitoring and Observability

### 1. Health Checks
- Kong: `http://localhost:8001/status`
- Nginx: `http://localhost:8082/health`
- Redis: `redis-cli ping`

### 2. Metrics
- Request/response times
- Masking operation counts
- Cache hit rates
- Error rates

### 3. Logging
- Centralized logging to `/logs` directory
- Structured JSON logging
- Log rotation configured
- Debug mode available

## Deployment

### Quick Start
```bash
# Clone and setup
cp .env.example .env
# Edit .env with your values

# Deploy
./deploy.sh

# Check status
./deploy.sh status

# View logs
./deploy.sh logs kong
```

### Production Considerations
1. Use environment-specific configurations
2. Enable SSL/TLS for all endpoints
3. Configure proper resource limits
4. Set up monitoring and alerting
5. Implement backup strategies for Redis
6. Use secrets management for sensitive data

## Troubleshooting

### Common Issues
1. **Redis Connection Failed**
   - Check Redis password in .env
   - Verify Redis container is running
   - Check network connectivity

2. **Kong Plugin Not Loading**
   - Verify plugin files are mounted correctly
   - Check Kong logs for Lua errors
   - Validate plugin configuration

3. **Claude API Errors**
   - Verify ANTHROPIC_API_KEY
   - Check rate limits
   - Review request/response logs

### Debug Commands
```bash
# Check Kong plugins
curl http://localhost:8001/plugins

# Test Redis connection
docker exec claude-redis redis-cli ping

# View Kong configuration
docker exec claude-kong kong config db_less

# Check service logs
docker-compose logs -f --tail=100
```