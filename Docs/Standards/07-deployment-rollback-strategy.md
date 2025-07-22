# Kong AWS Masking MVP - Simple Deployment Guide

## Overview
A straightforward deployment and rollback guide for MVP phase using Docker Compose.

## 1. Deployment Strategy

### 1.1 MVP Deployment Principles
- **Simplicity**: Easy to understand and execute
- **Reliability**: Basic health checks and verification
- **Quick Rollback**: Simple version switching
- **Manual Control**: Clear, deliberate deployment steps

### 1.2 Deployment Flow
```
Backup → Stop Services → Deploy New Version → Health Check → Verify
                            ↓ (if failed)
                        Rollback to Previous
```

## 2. Pre-Deployment Checklist

### 2.1 Manual Checklist
Before deploying, ensure:
- [ ] All tests pass locally
- [ ] Environment variables are set correctly
- [ ] AWS credentials are configured
- [ ] Docker images build successfully
- [ ] Current version is backed up

### 2.2 Pre-deployment Script
```bash
#!/bin/bash
# scripts/pre-deploy.sh

echo "🔍 Pre-deployment Checklist"

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found"
    exit 1
fi

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running"
    exit 1
fi

# Check current containers
echo "Current running containers:"
docker-compose ps

# Confirm deployment
read -p "Continue with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo "✅ Ready to deploy!"
```

## 3. Deployment Process

### 3.1 Simple Deployment Steps
```bash
#!/bin/bash
# scripts/deploy.sh

echo "🚀 Starting deployment..."

# 1. Create backup tag of current version
echo "Creating backup..."
docker tag kong-aws-masking:latest kong-aws-masking:backup

# 2. Pull or build new images
echo "Building new version..."
docker-compose build

# 3. Stop current services
echo "Stopping services..."
docker-compose down

# 4. Start new services
echo "Starting new services..."
docker-compose up -d

# 5. Wait for services to be ready
echo "Waiting for services..."
sleep 10

# 6. Health check
echo "Running health check..."
if curl -f http://localhost:3000/health && curl -f http://localhost:8001/status; then
    echo "✅ Deployment successful!"
else
    echo "❌ Health check failed, rolling back..."
    ./scripts/rollback.sh
    exit 1
fi
```

### 3.2 Deployment Verification
```bash
#!/bin/bash
# scripts/verify-deployment.sh

echo "🔍 Verifying deployment..."

# Check backend API
echo -n "Backend API: "
curl -s http://localhost:3000/health | jq -r '.status' || echo "FAILED"

# Check Kong Gateway
echo -n "Kong Gateway: "
curl -s http://localhost:8001/status | jq -r '.database.reachable' || echo "FAILED"

# Test masking functionality
echo -n "Masking test: "
response=$(curl -s -X POST http://localhost:3000/analyze \
    -H "Content-Type: application/json" \
    -d '{"test": "i-1234567890abcdef0"}')
    
if echo "$response" | grep -q "EC2_"; then
    echo "WORKING"
else
    echo "FAILED"
fi

echo "✅ Verification complete!"
```

## 4. Rollback Procedure

### 4.1 Quick Rollback
```bash
#!/bin/bash
# scripts/rollback.sh

echo "🔄 Starting rollback..."

# 1. Stop current services
docker-compose down

# 2. Restore backup version
docker tag kong-aws-masking:backup kong-aws-masking:latest

# 3. Start services with backup version
docker-compose up -d

# 4. Verify rollback
sleep 10
if curl -f http://localhost:3000/health; then
    echo "✅ Rollback successful!"
else
    echo "❌ Rollback failed! Manual intervention required."
    exit 1
fi
```

### 4.2 Manual Rollback Steps
If automated rollback fails:

1. **Stop all containers**:
   ```bash
   docker-compose down
   docker stop $(docker ps -q)
   ```

2. **Check available images**:
   ```bash
   docker images | grep kong-aws-masking
   ```

3. **Manually start previous version**:
   ```bash
   docker run -d -p 3000:3000 --env-file .env kong-aws-masking:backup
   ```

## 5. Backup Strategy

### 5.1 Creating Backups
```bash
#!/bin/bash
# scripts/backup.sh

BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

echo "📦 Creating backup in $BACKUP_DIR..."

# Backup configurations
cp -r kong/ $BACKUP_DIR/
cp docker-compose.yml $BACKUP_DIR/
cp .env $BACKUP_DIR/.env.backup

# Save current image info
docker images | grep kong-aws-masking > $BACKUP_DIR/docker-images.txt

# Create tarball
tar -czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_DIR" .
rm -rf $BACKUP_DIR

echo "✅ Backup created: $BACKUP_DIR.tar.gz"
```

### 5.2 Restoring from Backup
```bash
#!/bin/bash
# scripts/restore-backup.sh

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    exit 1
fi

echo "📦 Restoring from $BACKUP_FILE..."

# Extract backup
mkdir -p restore_tmp
tar -xzf "$BACKUP_FILE" -C restore_tmp/

# Restore files
cp -r restore_tmp/kong/ ./
cp restore_tmp/docker-compose.yml ./
cp restore_tmp/.env.backup ./.env

# Clean up
rm -rf restore_tmp

echo "✅ Backup restored! Run 'docker-compose up -d' to start services."
```

## 6. Monitoring Deployment

### 6.1 Simple Monitoring Script
```bash
#!/bin/bash
# scripts/monitor.sh

echo "📊 Monitoring services..."

while true; do
    clear
    echo "=== Service Status ==="
    echo "Time: $(date)"
    echo
    
    # Check container status
    docker-compose ps
    
    echo -e "\n=== Health Status ==="
    echo -n "Backend: "
    curl -s http://localhost:3000/health | jq -r '.status' 2>/dev/null || echo "DOWN"
    
    echo -n "Kong: "
    curl -s http://localhost:8001/status > /dev/null 2>&1 && echo "UP" || echo "DOWN"
    
    echo -e "\n=== Recent Logs ==="
    docker-compose logs --tail=5 --no-log-prefix
    
    echo -e "\nPress Ctrl+C to exit"
    sleep 5
done
```

## 7. Troubleshooting Deployments

### 7.1 Common Issues

| Issue | Diagnosis | Solution |
|-------|-----------|----------|
| Services won't start | Check logs: `docker-compose logs` | Fix configuration errors |
| Port conflicts | `lsof -i :3000` or `lsof -i :8000` | Change ports or stop conflicting services |
| Health check fails | Check individual service health | Review service logs for errors |
| AWS credential errors | Test AWS CLI: `aws sts get-caller-identity` | Fix AWS configuration |

### 7.2 Debug Commands
```bash
# View all logs
docker-compose logs

# Follow logs in real-time
docker-compose logs -f

# Check specific service
docker-compose logs backend
docker-compose logs kong

# Inspect running containers
docker ps -a

# Check container health
docker inspect backend | jq '.[0].State.Health'

# Test connectivity between containers
docker-compose exec backend ping kong
```

## 8. Emergency Procedures

### 8.1 Complete System Reset
```bash
#!/bin/bash
# scripts/emergency-reset.sh

echo "⚠️  WARNING: This will reset the entire system!"
read -p "Are you sure? (yes/no) " -r
if [[ ! $REPLY == "yes" ]]; then
    exit 1
fi

# Stop everything
docker-compose down -v

# Remove all related images
docker images | grep kong-aws-masking | awk '{print $3}' | xargs docker rmi -f

# Clean build cache
docker system prune -f

# Rebuild from scratch
docker-compose build --no-cache
docker-compose up -d

echo "✅ System reset complete!"
```

## 9. Production Considerations

For production deployment (post-MVP), consider:
- Automated deployment pipelines
- Zero-downtime deployment strategies
- Comprehensive monitoring and alerting
- Automated rollback triggers
- Load balancing and scaling

## 10. Deployment Checklist Summary

### Before Deployment:
- [ ] Backup current version
- [ ] Test new version locally
- [ ] Review configuration changes
- [ ] Notify team of deployment

### During Deployment:
- [ ] Monitor logs actively
- [ ] Verify health endpoints
- [ ] Test core functionality
- [ ] Watch for errors

### After Deployment:
- [ ] Confirm all services are healthy
- [ ] Run smoke tests
- [ ] Monitor for 15-30 minutes
- [ ] Document any issues

## Conclusion

This MVP deployment guide provides:
- Simple, manual deployment process
- Basic health checking and verification
- Quick rollback capability
- Essential monitoring tools

Keep deployments simple and controlled during MVP phase. Automation and advanced strategies can be added post-MVP based on real needs.