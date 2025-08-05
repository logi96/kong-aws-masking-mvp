# Kong AWS Masking MVP - Rollback Guide

**Version**: 1.0.0  
**Generated**: 2025-07-29  
**Target**: Production Recovery  
**RTO**: 2 minutes  

## 🚨 Emergency Rollback (30 seconds)

### Quick Rollback Command
```bash
# Emergency rollback to last known good state
./deploy/rollback.sh production

# Expected completion: 60-120 seconds
```

### Emergency Contact Information
- **System Admin**: On-call rotation
- **Dev Team Lead**: Primary escalation
- **Business Owner**: For production decisions

---

## 📋 Rollback Decision Matrix

### When to Rollback

#### Immediate Rollback Required ❌
- **API completely unavailable** (HTTP 5xx for >5 minutes)
- **Data corruption detected** in Redis
- **Security breach** or compromise
- **Critical functionality broken** (AWS masking fails)
- **Memory/CPU exhaustion** causing system instability

#### Consider Rollback ⚠️
- **Performance degradation** (>50% slower)
- **Intermittent errors** affecting <10% of requests
- **Non-critical features** not working
- **Warning-level issues** in logs

#### No Rollback Needed ✅
- **Minor UI issues** not affecting functionality
- **Documentation inconsistencies**
- **Cosmetic log messages**
- **Performance within acceptable range**

---

## 🔄 Rollback Procedures

### Automated Rollback (Recommended)

#### 1. Standard Rollback
```bash
# Rollback to most recent deployment backup
./deploy/rollback.sh production

# Process:
# ✅ Detect latest backup automatically
# ✅ Validate backup integrity
# ✅ Stop current services gracefully
# ✅ Restore previous configuration
# ✅ Start services with restored config
# ✅ Verify rollback success
```

#### 2. Targeted Rollback
```bash
# Rollback to specific deployment
./deploy/rollback.sh production deploy-20250729-120000

# Use when:
# - You know the exact deployment to restore
# - Multiple deployments failed in sequence
# - Specific version required
```

#### 3. Force Rollback
```bash
# Skip safety checks and force rollback
FORCE_ROLLBACK=true ./deploy/rollback.sh production

# Use when:
# - System is completely unresponsive
# - Safety checks are failing due to system state
# - Emergency recovery needed
```

### Manual Rollback (Emergency Only)

#### Step 1: Stop All Services
```bash
# Force stop all containers
docker stop $(docker ps -q --filter name=claude-)
docker rm $(docker ps -aq --filter name=claude-)

# Clean up networks
docker network rm claude-enterprise 2>/dev/null || true
```

#### Step 2: Restore Configuration
```bash
# Find latest backup
ls -la backups/pre-deploy/

# Restore configuration
cp backups/pre-deploy/deploy-YYYYMMDD-HHMMSS/config.env config/production.env
```

#### Step 3: Restart Services
```bash
# Start with restored configuration
docker-compose up -d

# Verify services
docker-compose ps
```

---

## 📊 Rollback Verification

### Automatic Verification
```bash
# Comprehensive rollback verification
./deploy/post-deploy-verify.sh production

# Expected Results:
✅ All containers healthy
✅ Network connectivity restored  
✅ Service endpoints responding
✅ AWS masking functionality working
✅ Performance within normal range
```

### Manual Verification Checklist

#### Infrastructure Health
- [ ] All containers running and healthy
- [ ] Network connectivity between services
- [ ] All required ports accessible
- [ ] Resource usage normal

#### Service Functionality
- [ ] Redis: `docker exec claude-redis redis-cli ping` → PONG
- [ ] Kong Admin: `curl http://localhost:8001/status` → JSON response
- [ ] Kong Proxy: `curl -I http://localhost:8000/` → HTTP response
- [ ] Nginx: `curl http://localhost:8085/health` → {"status":"healthy"}

#### End-to-End Testing
- [ ] Submit test request through proxy chain
- [ ] Verify AWS resource masking works
- [ ] Check Redis mapping storage
- [ ] Confirm response unmasks correctly

### Success Criteria
```
✅ RTO Target: <2 minutes (Recovery Time Objective)
✅ RPO Target: <5 minutes (Recovery Point Objective)  
✅ Service Availability: >99.9%
✅ Data Integrity: 100%
✅ Functional Completeness: 100%
```

---

## 🗄️ Backup Management

### Backup Structure
```
backups/
├── pre-deploy/
│   ├── deploy-20250729-143022/
│   │   ├── config.env              # Environment configuration
│   │   ├── services-state.json     # Docker service state
│   │   └── redis-backup.rdb        # Redis data snapshot
│   └── deploy-20250729-120000/
└── rollback-state/
    ├── rollback-20250729-150000/   # Pre-rollback state
    └── ...
```

### Backup Validation
```bash
# List available deployment backups
ls -lat backups/pre-deploy/

# Validate specific backup
./deploy/rollback.sh production deploy-YYYYMMDD-HHMMSS --dry-run

# Check backup integrity
find backups/pre-deploy/deploy-YYYYMMDD-HHMMSS -name "*.env" -exec head -1 {} \;
```

### Backup Retention Policy
- **Production**: 7 days (168 hours)
- **Staging**: 3 days (72 hours)  
- **Development**: 1 day (24 hours)
- **Critical backups**: 30 days (marked separately)

---

## ⚡ Rollback Scenarios & Solutions

### Scenario 1: Kong Configuration Error

#### Symptoms
- Kong admin API returns 500 errors
- Kong proxy not responding
- Configuration validation failures

#### Rollback Process
```bash
# Quick Kong-specific rollback
./deploy/rollback.sh production

# Verify Kong configuration
docker exec claude-kong kong config -c /usr/local/kong/declarative/kong.yml
```

#### Post-Rollback Actions
1. Review Kong configuration changes
2. Test configuration in staging
3. Update deployment procedures

### Scenario 2: Redis Data Corruption

#### Symptoms
- Redis operations failing
- AWS masking mappings lost
- Memory usage abnormally high

#### Rollback Process
```bash
# Rollback with data preservation disabled (fresh start)
PRESERVE_DATA=false ./deploy/rollback.sh production

# Alternative: Restore specific Redis backup
docker exec claude-redis redis-cli --rdb /data/restore.rdb
```

#### Post-Rollback Actions
1. Investigate Redis corruption cause
2. Implement additional data validation
3. Consider Redis clustering for resilience

### Scenario 3: Network Connectivity Issues

#### Symptoms
- Services cannot communicate
- External API calls failing
- DNS resolution problems

#### Rollback Process
```bash
# Force rollback to clean network state
FORCE_ROLLBACK=true ./deploy/rollback.sh production

# Manually clean networks if needed
docker network prune -f
```

#### Post-Rollback Actions
1. Check network configuration changes
2. Validate DNS settings
3. Test network connectivity

### Scenario 4: Memory/Resource Exhaustion

#### Symptoms
- Containers getting killed (OOMKilled)
- High CPU usage
- Slow response times

#### Rollback Process
```bash
# Quick rollback to restore resource limits
./deploy/rollback.sh production

# Check resource usage after rollback
docker stats --no-stream
```

#### Post-Rollback Actions
1. Review resource allocation changes
2. Implement better resource monitoring
3. Consider scaling up infrastructure

---

## 🛡️ Data Protection During Rollback

### Data Preservation Options

#### Default Behavior (PRESERVE_DATA=true)
- Redis data backed up before rollback
- Configuration files preserved
- Logs retained for analysis
- Previous state saved for re-rollback

#### Fresh Start (PRESERVE_DATA=false)
```bash
# Start with clean slate
PRESERVE_DATA=false ./deploy/rollback.sh production

# Use when:
# - Data corruption suspected
# - Clean environment needed
# - Testing rollback procedures
```

### Data Recovery
```bash
# Recover data from backup after rollback
docker cp backups/pre-deploy/deploy-YYYYMMDD-HHMMSS/redis-backup.rdb claude-redis:/data/
docker-compose restart redis

# Verify data recovery
docker exec claude-redis redis-cli keys "aws_masker:*" | wc -l
```

---

## 📈 Rollback Performance Metrics

### Target Performance
- **Detection to Decision**: <2 minutes
- **Rollback Execution**: 60-120 seconds
- **Service Recovery**: <30 seconds
- **Validation Complete**: <60 seconds
- **Total RTO**: <5 minutes

### Monitoring Rollback Success
```bash
# Monitor rollback progress
tail -f logs/rollbacks/rollback-YYYYMMDD-HHMMSS.log

# Check service startup
watch docker-compose ps

# Monitor health checks
watch 'curl -s http://localhost:8085/health'
```

### Performance Benchmarks
```
Average Rollback Times:
├── Configuration Only: 45 seconds
├── Configuration + Data: 90 seconds  
├── Full System Rollback: 120 seconds
└── Emergency Force Rollback: 60 seconds

Success Rates:
├── Automated Rollback: 98%
├── Manual Rollback: 95%
└── Force Rollback: 90%
```

---

## 🔍 Troubleshooting Rollback Issues

### Common Rollback Failures

#### Issue: Backup Not Found
```bash
# Symptom
Error: Deployment backup not found

# Solution
ls -la backups/pre-deploy/
./deploy/rollback.sh production --help  # Check available deployments
```

#### Issue: Services Won't Start
```bash
# Symptom
Services fail to start after rollback

# Diagnosis
docker-compose logs
docker events --since '5m'

# Solution
# Check port conflicts
ss -tln | grep -E ":(6379|8000|8001|8082|8085)"
# Force clean start
docker-compose down --remove-orphans
```

#### Issue: Data Inconsistency
```bash
# Symptom
Redis data doesn't match expectations

# Diagnosis
docker exec claude-redis redis-cli info memory
docker exec claude-redis redis-cli keys "aws_masker:*" | head -10

# Solution
# Restore from specific backup
PRESERVE_DATA=false ./deploy/rollback.sh production
```

### Rollback Verification Failures

#### Failed Health Checks
```bash
# Investigate failed checks
./deploy/post-deploy-verify.sh production > rollback-verification.log

# Common issues:
# - Service startup delays
# - Configuration mismatches  
# - Network connectivity
# - Resource constraints
```

#### Performance Issues Post-Rollback
```bash
# Check resource usage
docker stats --no-stream

# Monitor API response times
curl -w "@curl-format.txt" -s http://localhost:8085/health

# Review configuration
./config/validate-config.sh production
```

---

## 🎯 Rollback Best Practices

### Preparation
1. **Regular Backup Testing**
   ```bash
   # Test rollback in staging weekly
   ./deploy/rollback.sh staging --dry-run
   ```

2. **Monitoring Setup**
   ```bash
   # Ensure monitoring catches issues early
   ./deploy/day2-integration.sh production status
   ```

3. **Documentation Currency**
   - Keep rollback procedures updated
   - Document environment-specific issues
   - Maintain contact information

### Execution
1. **Stay Calm** - Follow procedures systematically
2. **Communicate** - Notify stakeholders immediately  
3. **Document** - Record timeline and decisions
4. **Verify** - Always run post-rollback validation

### Post-Rollback
1. **Root Cause Analysis** - Understand why rollback was needed
2. **Process Improvement** - Update procedures based on learnings
3. **Team Training** - Share knowledge with team
4. **Prevention Planning** - Implement safeguards

---

## 📞 Emergency Contacts & Escalation

### Incident Response Team
- **Primary On-Call**: Technical lead with rollback authority
- **Secondary On-Call**: Senior developer familiar with system
- **Escalation Manager**: Product owner for business decisions
- **Infrastructure Team**: For hardware/network issues

### Communication Channels
- **Immediate**: Phone/SMS for P0 incidents
- **Updates**: Slack/Teams for status updates
- **Documentation**: Incident tracking system

### Escalation Matrix
- **0-5 minutes**: On-call engineer attempts automated rollback
- **5-10 minutes**: Escalate to technical lead if automated fails
- **10-15 minutes**: Engage infrastructure team if systemic issues
- **15+ minutes**: Business stakeholder engagement for decisions

---

## 📊 Rollback Success Metrics

### Key Performance Indicators
- **Mean Time to Detect (MTTD)**: <2 minutes
- **Mean Time to Rollback (MTTR)**: <5 minutes  
- **Rollback Success Rate**: >95%
- **Data Loss Prevention**: 100%
- **False Positive Rate**: <10%

### Reporting
```bash
# Generate rollback report
ls -la logs/rollbacks/ | tail -10

# Analyze rollback patterns
grep -h "Rollback completed" logs/rollbacks/*.log | wc -l
```

---

## ✅ Rollback Checklist

### Pre-Rollback
- [ ] Incident confirmed and rollback decision made
- [ ] Stakeholders notified
- [ ] Backup availability verified
- [ ] Current state documented

### During Rollback
- [ ] Rollback command executed
- [ ] Progress monitored
- [ ] Issues documented
- [ ] Timeline tracked

### Post-Rollback
- [ ] Services verified healthy
- [ ] End-to-end functionality tested
- [ ] Performance validated
- [ ] Stakeholders updated
- [ ] Incident analysis scheduled

---

**🎯 Remember**: A successful rollback is one that quickly restores service with minimal data loss. Speed and accuracy are both critical.

For additional guidance:
- [Deployment Guide](DEPLOYMENT.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Day 2 Operations](docs/day2-operations.md)