# Production Deployment Guide

## Overview

This guide covers the production deployment of the Nginx-Kong-Claude Enterprise system with emphasis on:
- Resource management and limits
- Logging and monitoring
- Network security
- Volume backup strategies
- Zero-downtime deployments
- Automatic rollback capabilities

## Architecture Improvements

### 1. Resource Management

Each container now has defined resource limits and reservations:

| Service | CPU Limit | CPU Reserve | Memory Limit | Memory Reserve |
|---------|-----------|-------------|--------------|----------------|
| Redis   | 1.0       | 0.5         | 1G           | 512M           |
| Kong    | 2.0       | 1.0         | 2G           | 1G             |
| Nginx   | 1.0       | 0.5         | 1G           | 512M           |

### 2. Logging Strategy

- **Driver**: JSON file with rotation (5 files, 10MB each)
- **Centralized Format**: JSON structured logs for easy parsing
- **Retention**: Configurable via `LOG_RETENTION_DAYS`
- **Performance**: Buffered writes to reduce I/O

### 3. Network Security

- **Isolated Network**: Custom bridge network with defined subnet
- **Service Aliases**: Internal DNS names for service discovery
- **Port Restrictions**: Only necessary ports exposed
- **Metrics Access**: Limited to internal network only

### 4. Volume Management

- **Persistent Volumes**: Redis data with bind mounts
- **Backup Volumes**: Dedicated backup directory structure
- **Log Volumes**: Separate volumes with retention policies
- **Cache Volumes**: Nginx cache with size limits

## Deployment Process

### Prerequisites

1. Docker Engine 20.10+ with Compose v3.8 support
2. Minimum 10GB available disk space
3. 10GB RAM for full stack
4. Valid Anthropic API key

### Step 1: Environment Setup

```bash
# Copy production environment file
cp .env.production .env

# Generate secure Redis password
openssl rand -base64 48 > redis-password.txt
# Update REDIS_PASSWORD in .env

# Create required directories
mkdir -p logs/{nginx,kong,redis}
mkdir -p backups/redis
mkdir -p deployments
```

### Step 2: Initial Deployment

```bash
# Use the production compose file
docker-compose -f docker-compose.prod.yml up -d

# Verify all services are healthy
docker-compose ps
./scripts/health-check-deployment.sh
```

### Step 3: Blue-Green Deployment

For zero-downtime updates:

```bash
# Deploy new version
./scripts/deploy.sh

# The script will:
# 1. Run pre-deployment checks
# 2. Backup current state
# 3. Deploy to inactive color (blue/green)
# 4. Run health checks
# 5. Switch traffic
# 6. Clean up old deployment
```

### Step 4: Monitoring Setup

Enable monitoring profile:

```bash
# Start with monitoring
docker-compose -f docker-compose.prod.yml --profile monitoring up -d

# Access metrics
curl http://localhost:9100/metrics  # Node exporter
curl http://localhost:9113/metrics  # Nginx metrics
```

## Rollback Procedures

### Automatic Rollback

The system includes automatic rollback based on:
- Error rate threshold (default: 5%)
- Response time threshold (default: 5000ms)

Configuration in `.env.production`:
```env
ROLLBACK_THRESHOLD_ERROR_RATE=5
ROLLBACK_THRESHOLD_RESPONSE_TIME=5000
AUTO_ROLLBACK_ENABLED=true
```

### Manual Rollback

```bash
# List recent deployments
ls -la deployments/backups/

# Rollback to specific version
./scripts/rollback.sh <timestamp>

# Emergency rollback to previous
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.yml up -d
```

## Backup Strategy

### Redis Backups

Automated backups run every 6 hours:
- **Local Storage**: 7-day retention
- **Compression**: gzip -9
- **S3 Upload**: Optional with Glacier storage class
- **Verification**: Automatic integrity checks

Manual backup:
```bash
docker-compose exec redis-backup /usr/local/bin/backup.sh
```

### Configuration Backup

Before any changes:
```bash
./scripts/backup-config.sh
```

## Security Hardening

### 1. Network Security
- Internal services use Docker network aliases
- Metrics endpoints restricted to internal network
- Rate limiting on all public endpoints

### 2. Container Security
- Non-root users where possible
- Read-only root filesystems
- Minimal base images
- Regular security updates

### 3. API Security
- API key stored in Kong only
- Request/response size limits
- Security headers on all responses

## Performance Optimization

### 1. Nginx Optimizations
- Worker process auto-scaling
- Connection pooling with Kong
- Response caching for GET requests
- Gzip compression enabled

### 2. Kong Optimizations
- Increased memory cache (2GB)
- Connection pooling to Redis
- Optimized buffer sizes
- Worker process tuning

### 3. Redis Optimizations
- Persistence with AOF + RDB
- Memory limits with eviction policies
- Connection pooling from Kong

## Troubleshooting

### Health Check Failures

```bash
# Check individual services
docker-compose exec kong kong health
docker-compose exec redis redis-cli ping
curl http://localhost:8082/health

# View logs
docker-compose logs -f kong
docker-compose logs -f nginx
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Analyze response times
tail -f logs/nginx/claude-access.log | jq '.request_time'

# Kong performance
curl http://localhost:8001/status
```

### Deployment Failures

```bash
# Check deployment logs
tail -f deployments/deployment-*.log

# Verify blue-green status
docker ps --filter "label=com.claude.deployment.color"

# Force cleanup
docker-compose -f docker-compose.prod.yml down
docker system prune -f
```

## Maintenance

### Log Rotation

Logs rotate automatically, but to force rotation:
```bash
docker-compose exec nginx kill -USR1 1
docker-compose exec kong kill -USR1 1
```

### Certificate Updates (Future)

When SSL is implemented:
```bash
# Place new certificates
cp new-cert.pem nginx/ssl/
cp new-key.pem nginx/ssl/

# Reload without downtime
docker-compose exec nginx nginx -s reload
```

### Scaling

To scale horizontally:
```bash
# Scale Kong instances
docker-compose -f docker-compose.prod.yml up -d --scale kong=3

# Update nginx upstream configuration
# Add new Kong instances to upstream block
```

## Monitoring Metrics

Key metrics to monitor:

### Application Metrics
- Request rate: > 1000 RPS capability
- Error rate: < 1% target
- Response time: < 100ms p95
- Throughput: Monitor bytes/sec

### System Metrics
- CPU usage: < 70% sustained
- Memory usage: < 80% of limits
- Disk I/O: Monitor for bottlenecks
- Network I/O: Check for saturation

### Business Metrics
- API calls per minute
- Masking operations count
- Cache hit ratio
- Successful deployments

## Disaster Recovery

### Backup Restoration

```bash
# Restore Redis from backup
gunzip -c backups/redis/redis_backup_20240101_120000.rdb.gz > restore.rdb
docker-compose exec redis redis-cli --rdb restore.rdb

# Restore configuration
cp deployments/backups/<timestamp>/.env* .
docker-compose -f docker-compose.prod.yml up -d
```

### Full System Recovery

1. Restore environment files
2. Restore Redis data
3. Deploy with production compose
4. Verify all services
5. Run smoke tests

## Contact and Support

For production issues:
1. Check logs first
2. Run health checks
3. Review recent deployments
4. Contact: [Your Support Contact]

---

Last Updated: 2024-01-01
Version: 1.0.0