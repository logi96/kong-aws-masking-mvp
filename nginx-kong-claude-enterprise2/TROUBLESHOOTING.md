# Kong AWS Masking MVP - Troubleshooting Guide

**Version**: 1.0.0  
**Generated**: 2025-07-29  
**Coverage**: Production Issues  
**Update Frequency**: Weekly  

## 🎯 Quick Reference

### Emergency Commands
```bash
# System status check
docker-compose ps && docker stats --no-stream

# Health check
./deploy/post-deploy-verify.sh production

# Service restart
docker-compose restart [service-name]

# Emergency rollback
./deploy/rollback.sh production

# View logs
docker-compose logs -f [service-name]
```

### Common Issue Resolution Times
- **Service restart**: 30-60 seconds
- **Configuration fix**: 2-5 minutes
- **Network issue**: 1-3 minutes
- **Full rollback**: 2-5 minutes

---

## 🔍 Diagnostic Tools & Commands

### System Health Assessment
```bash
# Overall system health
./deploy/post-deploy-verify.sh production --quick

# Individual service health
docker inspect --format='{{.State.Health.Status}}' claude-redis
docker inspect --format='{{.State.Health.Status}}' claude-kong
docker inspect --format='{{.State.Health.Status}}' claude-nginx

# Resource usage
docker stats --no-stream | grep claude-

# Network connectivity
docker exec claude-nginx ping -c 3 kong
docker exec claude-kong ping -c 3 redis
```

### Log Analysis
```bash
# Real-time logs (all services)
docker-compose logs -f

# Service-specific logs
docker logs claude-kong --tail 100
docker logs claude-redis --tail 100
docker logs claude-nginx --tail 100

# Error log filtering
docker-compose logs | grep -i error
docker-compose logs | grep -i "fail\|error\|exception"

# Access logs
tail -f logs/nginx/access.log
tail -f logs/kong/access.log
```

### Configuration Validation
```bash
# Validate current configuration
./config/validate-config.sh production

# Check Kong configuration
docker exec claude-kong kong config -c /usr/local/kong/declarative/kong.yml

# Check Nginx configuration
docker exec claude-nginx nginx -t
```

---

## 🚨 Common Issues & Solutions

### 1. Service Startup Issues

#### Issue: Container Keeps Restarting
**Symptoms:**
- Container status shows "Restarting"
- Service appears unhealthy
- Repeated restart cycles

**Diagnosis:**
```bash
# Check container logs
docker logs claude-[service] --tail 50

# Check restart count
docker inspect claude-[service] | grep RestartCount

# Check exit codes
docker inspect claude-[service] | grep ExitCode
```

**Common Causes & Solutions:**

##### Memory Issues
```bash
# Check memory usage
docker stats claude-[service] --no-stream

# Solution: Increase memory limits
# Edit config/production.env:
KONG_MEMORY_LIMIT=4G
REDIS_MEMORY_LIMIT=1G

# Restart with new limits
docker-compose up -d
```

##### Port Conflicts
```bash
# Check port usage
ss -tln | grep -E ":(6379|8000|8001|8082|8085)"

# Solution: Stop conflicting services or change ports
sudo lsof -i :8000  # Find what's using the port
sudo kill -9 [PID]  # Stop conflicting process
```

##### Configuration Errors
```bash
# Validate configuration
./config/validate-config.sh production

# Common fixes:
# - Fix ANTHROPIC_API_KEY format
# - Correct REDIS_PASSWORD
# - Update port mappings
```

#### Issue: Services Start But Fail Health Checks
**Symptoms:**
- Containers running but marked unhealthy
- Health check endpoints return errors
- Services appear started but don't respond

**Diagnosis:**
```bash
# Test health endpoints manually
curl http://localhost:8085/health  # Nginx
curl http://localhost:8001/status  # Kong
docker exec claude-redis redis-cli ping  # Redis

# Check health check configuration
docker inspect claude-[service] | grep -A 10 Healthcheck
```

**Solutions:**
```bash
# Restart specific service
docker-compose restart [service]

# Check service dependencies
docker-compose ps  # Ensure dependencies are healthy first

# Increase health check timeout
# Edit docker-compose.yml:
# healthcheck:
#   timeout: 30s  # Increase from default
```

### 2. Network Connectivity Issues

#### Issue: Services Cannot Communicate
**Symptoms:**
- Kong cannot reach Redis
- Nginx cannot proxy to Kong
- External API calls failing

**Diagnosis:**
```bash
# Check network connectivity
docker exec claude-nginx ping kong
docker exec claude-kong ping redis

# Check network configuration
docker network ls | grep claude
docker network inspect claude-enterprise

# Check DNS resolution
docker exec claude-nginx nslookup kong
docker exec claude-kong nslookup redis
```

**Solutions:**
```bash
# Recreate network
docker-compose down
docker network prune
docker-compose up -d

# Check firewall/iptables
sudo iptables -L | grep docker
sudo ufw status  # If using UFW

# Verify service names in configuration
grep -r "kong\|redis\|nginx" config/
```

#### Issue: External API Access Blocked
**Symptoms:**
- Cannot reach api.anthropic.com
- Proxy requests timeout
- DNS resolution failures

**Diagnosis:**
```bash
# Test external connectivity from host
curl -I https://api.anthropic.com/health

# Test from containers
docker exec claude-kong curl -I https://api.anthropic.com/health
docker exec claude-nginx curl -I https://api.anthropic.com/health

# Check DNS
nslookup api.anthropic.com
```

**Solutions:**
```bash
# Configure proxy if behind corporate firewall
# Add to docker-compose.yml:
# environment:
#   - HTTP_PROXY=http://proxy:port
#   - HTTPS_PROXY=http://proxy:port

# Update DNS settings
# Edit /etc/docker/daemon.json:
# {
#   "dns": ["8.8.8.8", "1.1.1.1"]
# }
# sudo systemctl restart docker
```

### 3. Kong-Specific Issues

#### Issue: Kong Admin API Not Responding
**Symptoms:**
- `curl http://localhost:8001/status` fails
- Kong configuration changes not applying
- Plugin management not working

**Diagnosis:**
```bash
# Check Kong process
docker exec claude-kong ps aux | grep kong

# Check Kong logs
docker logs claude-kong --tail 100

# Verify Kong configuration
docker exec claude-kong kong config -c /usr/local/kong/declarative/kong.yml

# Check plugin loading
curl http://localhost:8001/plugins
```

**Solutions:**
```bash
# Restart Kong service
docker-compose restart kong

# Validate Kong configuration file
docker exec claude-kong kong config -c /usr/local/kong/declarative/kong.yml

# Reset Kong configuration
docker exec claude-kong kong reload -c /usr/local/kong/declarative/kong.yml

# Check for plugin issues
docker exec claude-kong ls -la /usr/local/kong/plugins/aws-masker/
```

#### Issue: AWS Masker Plugin Not Working
**Symptoms:**
- AWS resources not being masked
- Plugin not showing in Kong admin
- Masking/unmasking failures

**Diagnosis:**
```bash
# Check plugin status
curl http://localhost:8001/plugins | jq '.data[] | select(.name=="aws-masker")'

# Check plugin files
docker exec claude-kong ls -la /usr/local/kong/plugins/aws-masker/

# Test Redis connectivity from Kong
docker exec claude-kong redis-cli -h redis -p 6379 -a "$REDIS_PASSWORD" ping

# Check for Lua errors
docker logs claude-kong | grep -i "lua\|error"
```

**Solutions:**
```bash
# Restart Kong to reload plugins
docker-compose restart kong

# Verify plugin file syntax
docker exec claude-kong luac -p /usr/local/kong/plugins/aws-masker/handler.lua

# Check Redis connection
docker exec claude-kong redis-cli -h redis -p 6379 -a "$REDIS_PASSWORD" ping

# Clear Redis cache if needed
docker exec claude-redis redis-cli -a "$REDIS_PASSWORD" FLUSHDB
```

### 4. Redis Issues

#### Issue: Redis Connection Refused
**Symptoms:**
- Kong cannot connect to Redis
- Redis operations timeout
- Authentication failures

**Diagnosis:**
```bash
# Test Redis connectivity
docker exec claude-redis redis-cli ping
docker exec claude-redis redis-cli -a "$REDIS_PASSWORD" ping

# Check Redis configuration
docker exec claude-redis redis-cli config get "*"

# Check Redis logs
docker logs claude-redis --tail 100

# Test from other containers
docker exec claude-kong redis-cli -h redis -p 6379 -a "$REDIS_PASSWORD" ping
```

**Solutions:**
```bash
# Restart Redis
docker-compose restart redis

# Check Redis password
echo $REDIS_PASSWORD  # Verify environment variable
grep REDIS_PASSWORD config/production.env

# Reset Redis data if corrupted
docker-compose stop redis
docker volume rm $(docker volume ls -q | grep redis)
docker-compose up -d redis

# Check Redis memory usage
docker exec claude-redis redis-cli info memory
```

#### Issue: Redis Memory Issues
**Symptoms:**
- High memory usage
- Out of memory errors
- Slow Redis operations

**Diagnosis:**
```bash
# Check Redis memory usage
docker exec claude-redis redis-cli info memory
docker exec claude-redis redis-cli memory usage [key]

# Check key distribution
docker exec claude-redis redis-cli keys "*" | wc -l
docker exec claude-redis redis-cli keys "aws_masker:*" | wc -l
```

**Solutions:**
```bash
# Clear old mappings
docker exec claude-redis redis-cli eval "
  for i, key in ipairs(redis.call('keys', 'aws_masker:*')) do
    if redis.call('ttl', key) == -1 then
      redis.call('expire', key, 86400)
    end
  end
" 0

# Increase Redis memory limit
# Edit config/production.env:
REDIS_MEMORY_LIMIT=2G

# Restart with new limits
docker-compose up -d redis
```

### 5. Nginx Proxy Issues

#### Issue: Nginx Not Proxying Requests
**Symptoms:**
- 502 Bad Gateway errors
- Requests not reaching Kong
- Nginx health check fails

**Diagnosis:**
```bash
# Check Nginx configuration
docker exec claude-nginx nginx -t

# Test upstream connectivity
docker exec claude-nginx nc -z kong 8010

# Check Nginx logs
docker logs claude-nginx --tail 100

# Test proxy configuration
curl -v http://localhost:8085/health
```

**Solutions:**
```bash
# Restart Nginx
docker-compose restart nginx

# Check upstream configuration
docker exec claude-nginx cat /etc/nginx/conf.d/claude-proxy.conf

# Test Kong connectivity from Nginx
docker exec claude-nginx curl -I http://kong:8010/

# Reload Nginx configuration
docker exec claude-nginx nginx -s reload
```

#### Issue: Header Transformation Not Working
**Symptoms:**
- API key not being passed correctly
- Authentication failures
- Header missing in downstream

**Diagnosis:**
```bash
# Check request headers
curl -v -H "Authorization: Bearer test" http://localhost:8085/v1/messages

# Check Nginx configuration
docker exec claude-nginx cat /etc/nginx/conf.d/claude-proxy.conf | grep proxy_set_header

# Enable Nginx debug logging
# Edit nginx.conf: error_log /var/log/nginx/error.log debug;
```

**Solutions:**
```bash
# Verify Nginx proxy configuration
docker exec claude-nginx nginx -T | grep -A 10 -B 10 proxy_set_header

# Test header transformation
curl -H "Authorization: Bearer test" \
     -H "X-Debug: true" \
     http://localhost:8085/v1/messages \
     -v

# Update Nginx configuration if needed
# Edit nginx/conf.d/claude-proxy.conf
docker-compose restart nginx
```

---

## 🛠️ Advanced Troubleshooting

### Performance Issues

#### High CPU Usage
**Diagnosis:**
```bash
# Monitor CPU usage
docker stats --no-stream | sort -k3 -hr

# Check processes inside containers
docker exec claude-kong top
docker exec claude-nginx top

# System-level monitoring
top -p $(docker inspect -f '{{.State.Pid}}' claude-kong)
```

**Solutions:**
```bash
# Adjust worker processes
# Kong: KONG_WORKER_PROCESSES=2
# Nginx: NGINX_WORKER_PROCESSES=2

# Review configuration for inefficiencies
# Check for infinite loops in Lua code
# Optimize regex patterns in AWS masker

# Scale horizontally if needed
# Add more Kong instances
```

#### High Memory Usage
**Diagnosis:**
```bash
# Check container memory usage
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Check memory leaks
docker exec claude-kong ps aux --sort=-%mem
docker exec claude-redis redis-cli info memory
```

**Solutions:**
```bash
# Increase memory limits
# Edit config/production.env
KONG_MEMORY_LIMIT=6G
REDIS_MEMORY_LIMIT=2G

# Optimize Kong cache settings
KONG_MEM_CACHE_SIZE=2048m

# Clear Redis if too many keys
docker exec claude-redis redis-cli FLUSHDB
```

#### Slow Response Times
**Diagnosis:**
```bash
# Test response times
curl -w "@curl-format.txt" -s http://localhost:8085/health

# Check each component
time curl -s http://localhost:8085/health  # Full chain
time curl -s http://localhost:8001/status  # Kong direct
time docker exec claude-redis redis-cli ping  # Redis direct
```

**Solutions:**
```bash
# Optimize Kong configuration
# Increase worker connections
KONG_NGINX_WORKER_CONNECTIONS=4096

# Optimize Redis
# Check slow queries
docker exec claude-redis redis-cli slowlog get 10

# Optimize Nginx
# Enable keepalive connections
# Adjust buffer sizes
```

### SSL/TLS Issues

#### Certificate Problems
**Diagnosis:**
```bash
# Check certificate validity
openssl x509 -in nginx/ssl/cert.pem -text -noout

# Test SSL connection
openssl s_client -connect localhost:443 -servername localhost

# Check certificate in Nginx
docker exec claude-nginx nginx -T | grep ssl_certificate
```

**Solutions:**
```bash
# Generate new certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem \
  -out nginx/ssl/cert.pem

# Update Nginx configuration
# Enable SSL in nginx.conf
# Restart Nginx
docker-compose restart nginx
```

### Data Consistency Issues

#### Redis Data Corruption
**Diagnosis:**
```bash
# Check Redis data integrity
docker exec claude-redis redis-cli debug object [key]
docker exec claude-redis redis-cli memory doctor

# Verify AWS masking mappings
docker exec claude-redis redis-cli keys "aws_masker:*" | head -10
docker exec claude-redis redis-cli get "aws_masker:map:AWS_EC2_001"
```

**Solutions:**
```bash
# Backup current data
docker exec claude-redis redis-cli save

# Restore from backup if available
docker cp backups/redis/dump.rdb claude-redis:/data/
docker-compose restart redis

# Clear corrupted data
docker exec claude-redis redis-cli flushdb
# Will lose mappings but system will recreate them
```

---

## 📊 Monitoring & Alerting

### Health Check Automation
```bash
# Setup continuous monitoring
./deploy/day2-integration.sh production start

# Check monitoring status
./deploy/day2-integration.sh production status

# View monitoring logs
tail -f logs/monitoring/health-monitoring.log
```

### Custom Health Checks
```bash
# Create custom health check script
cat > custom-health-check.sh << 'EOF'
#!/bin/bash
# Test critical functionality
if ! curl -s http://localhost:8085/health | grep -q healthy; then
  echo "CRITICAL: Nginx proxy down"
  exit 1
fi

if ! docker exec claude-redis redis-cli ping | grep -q PONG; then
  echo "CRITICAL: Redis down"
  exit 1
fi

echo "OK: All services healthy"
EOF

chmod +x custom-health-check.sh
```

### Log Analysis Automation
```bash
# Setup log monitoring
tail -f logs/nginx/error.log | grep -E "error|crit|alert|emerg" &
tail -f logs/kong/error.log | grep -E "error|crit|alert|emerg" &

# Error pattern detection
grep -r "OutOfMemory\|Connection refused\|Timeout" logs/
```

---

## 🎯 Prevention & Best Practices

### Proactive Monitoring
1. **Regular Health Checks**: Every 60 seconds
2. **Resource Monitoring**: CPU, memory, disk usage
3. **Log Analysis**: Error pattern detection
4. **Performance Baselines**: Response time tracking

### Configuration Management
1. **Version Control**: All configuration in Git
2. **Testing**: Validate config before deployment
3. **Documentation**: Keep troubleshooting guide updated
4. **Backups**: Regular configuration backups

### Incident Response
1. **Runbooks**: Step-by-step procedures
2. **Communication**: Clear escalation paths
3. **Documentation**: Record all incidents
4. **Post-Mortems**: Learn from failures

---

## 📞 Support Escalation

### Level 1: Self-Service (0-15 minutes)
- Check this troubleshooting guide
- Run automated diagnostics
- Review recent logs
- Attempt service restart

### Level 2: Team Support (15-30 minutes)
- Engage on-call engineer
- Share diagnostic information
- Document current state
- Consider rollback if critical

### Level 3: Expert Support (30+ minutes)
- Senior technical lead involvement
- Deep system analysis
- Custom solution development
- Long-term fix planning

### Information to Collect
```bash
# System state
docker-compose ps > system-state.txt
docker stats --no-stream > resource-usage.txt

# Logs
docker-compose logs > all-services.log
docker logs claude-kong --tail 100 > kong-recent.log

# Configuration
cp config/production.env config-snapshot.env
docker exec claude-kong kong config > kong-config.txt

# Diagnostics
./deploy/post-deploy-verify.sh production > diagnostics.log
```

---

## ✅ Troubleshooting Checklist

### Initial Assessment
- [ ] Identify affected services
- [ ] Determine impact scope  
- [ ] Check recent changes
- [ ] Review monitoring alerts

### Diagnostic Steps
- [ ] Run health checks
- [ ] Check container status
- [ ] Review logs for errors
- [ ] Test network connectivity
- [ ] Validate configuration

### Resolution Actions
- [ ] Apply appropriate fix
- [ ] Verify resolution
- [ ] Monitor for stability
- [ ] Document solution
- [ ] Update procedures

### Post-Resolution
- [ ] Notify stakeholders
- [ ] Schedule post-mortem
- [ ] Update documentation
- [ ] Implement prevention measures

---

**🎯 Remember**: Most issues can be resolved quickly with systematic diagnosis. When in doubt, check logs first and don't hesitate to rollback if the issue is impacting production.

For additional support:
- [Deployment Guide](DEPLOYMENT.md)
- [Rollback Procedures](ROLLBACK.md)
- [System Architecture](docs/architecture/ARCHITECTURE.md)