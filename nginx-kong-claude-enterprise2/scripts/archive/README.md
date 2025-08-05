# Day 2: Essential Test Automation - Usage Guide

**Kong AWS Masking MVP - Continuous Quality Assurance System**

## 🎯 Overview

This Day 2 automation system maintains the **95% success rate achieved in Day 1** through continuous validation and automated testing. The system provides rapid deployment validation and ongoing monitoring to ensure system stability.

### Key Achievement
- **Day 1 Baseline**: 95% overall success rate with 100% success on core AWS patterns
- **Day 2 Goal**: Maintain this performance through automated validation

## 📁 Script Inventory

| Script | Purpose | Execution Time | When to Use |
|--------|---------|----------------|-------------|
| `day2-health-check.sh` | System health validation | ~30 seconds | Before any deployment |
| `day2-smoke-test.sh` | Core functionality validation | ~60 seconds | Post-deployment verification |
| `day2-regression-test.sh` | Protect Day 1 achievements | ~3 minutes | After code changes |
| `day2-system-monitor.sh` | Continuous monitoring | ~10 seconds | Production monitoring |
| `day2-run-all-tests.sh` | Orchestrated test execution | 2-7 minutes | Comprehensive validation |
| `test-config.env` | Centralized configuration | N/A | Configuration management |

## 🚀 Quick Start

### Basic Usage

```bash
# Quick deployment validation (2 minutes)
./scripts/day2-run-all-tests.sh quick

# Standard pre-deployment testing (5 minutes)  
./scripts/day2-run-all-tests.sh standard

# Complete validation suite (7 minutes)
./scripts/day2-run-all-tests.sh full

# Continuous monitoring mode
./scripts/day2-run-all-tests.sh monitor
```

### Individual Script Usage

```bash
# Health check only
./scripts/day2-health-check.sh

# Smoke test only
./scripts/day2-smoke-test.sh

# Regression test only
./scripts/day2-regression-test.sh

# Single monitoring check
./scripts/day2-system-monitor.sh

# Silent monitoring (for cron jobs)
./scripts/day2-system-monitor.sh --silent
```

## 📋 Test Modes Explained

### Quick Mode (`quick`)
**Purpose**: Rapid deployment readiness check  
**Duration**: ~2 minutes  
**Tests**: Health check + Core smoke test  
**Use Case**: Pre-deployment validation, CI/CD pipeline integration

```bash
./scripts/day2-run-all-tests.sh quick
```

**Success Criteria**:
- All critical services responding
- Core AWS patterns functional (EC2, VPC, Security Groups, AMI, Subnet)
- System resources within normal ranges

### Standard Mode (`standard`)
**Purpose**: Comprehensive pre-deployment validation  
**Duration**: ~5 minutes  
**Tests**: Health + Smoke + Regression tests  
**Use Case**: Regular deployment validation, post-maintenance verification

```bash
./scripts/day2-run-all-tests.sh standard
```

**Success Criteria**:
- All quick mode criteria
- No regression from Day 1 baseline (95% success rate maintained)
- Extended AWS pattern coverage
- Proxy chain stability confirmed

### Full Mode (`full`)
**Purpose**: Complete system validation with monitoring  
**Duration**: ~7 minutes  
**Tests**: All tests + System monitoring  
**Use Case**: Major deployment validation, weekly quality assurance

```bash
./scripts/day2-run-all-tests.sh full
```

**Success Criteria**:
- All standard mode criteria
- System monitoring shows healthy metrics
- Resource usage within thresholds
- Error pattern analysis completed

### Monitor Mode (`monitor`)
**Purpose**: Continuous system monitoring  
**Duration**: Continuous (checks every 5 minutes)  
**Tests**: System monitoring only  
**Use Case**: Production monitoring, background health checks

```bash
./scripts/day2-run-all-tests.sh monitor
```

**Features**:
- Runs indefinitely until stopped (Ctrl+C)
- Configurable check intervals
- Automatic alert detection and logging
- Resource usage monitoring

## ⚙️ Configuration

### Environment Configuration (`test-config.env`)

The centralized configuration file contains all settings:

```bash
# Source configuration
source scripts/test-config.env

# Override specific settings
export KONG_ADMIN_URL="http://custom-host:8001"
export MAX_CPU_USAGE=70  # Lower threshold
export MONITOR_INTERVAL=300  # 5 minutes
```

### Key Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KONG_ADMIN_URL` | `http://localhost:8001` | Kong Admin API endpoint |
| `KONG_PROXY_URL` | `http://localhost:8000` | Kong Proxy endpoint |
| `NGINX_URL` | `http://localhost:8085` | Nginx proxy endpoint |
| `REDIS_HOST` | `localhost` | Redis server host |
| `REDIS_PORT` | `6379` | Redis server port |
| `CLAUDE_API_KEY` | (configured) | Claude API authentication key |
| `HEALTH_CHECK_TIMEOUT` | `30` | Health check timeout (seconds) |
| `MAX_CPU_USAGE` | `80` | CPU usage alert threshold (%) |
| `MAX_MEMORY_USAGE` | `80` | Memory usage alert threshold (%) |
| `MIN_PATTERN_SUCCESS_RATE` | `80` | Minimum AWS pattern success rate (%) |

## 📊 Understanding Results

### Exit Codes

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| `0` | All tests passed | ✅ Safe to deploy |
| `1` | Critical failures | ❌ Do not deploy, fix issues |
| `2` | Minor issues | ⚠️ Deploy with caution |
| `3` | Configuration error | 🔧 Fix configuration |

### Report Files

All scripts generate detailed reports in `tests/test-report/`:

```
tests/test-report/
├── day2-health-check-20250730_143022.md
├── day2-smoke-test-20250730_143052.md
├── day2-regression-test-20250730_143125.md
├── day2-comprehensive-test-20250730_143200.md
└── ...
```

### Log Files

System logs are stored in `logs/`:

```
logs/
├── system-monitor-20250730_143022.log
├── system-alerts.log
└── monitoring-summary-20250730_143022.json
```

## 🔄 Automation Workflows

### CI/CD Integration

```bash
# In your CI/CD pipeline
#!/bin/bash
set -e

echo "Running Day 2 validation..."
if ./scripts/day2-run-all-tests.sh quick; then
    echo "✅ Validation passed - proceeding with deployment"
else
    echo "❌ Validation failed - blocking deployment"
    exit 1
fi
```

### Cron Job Setup

```bash
# Add to crontab for production monitoring
# Edit with: crontab -e

# Health check every 15 minutes
*/15 * * * * /path/to/scripts/day2-health-check.sh >/dev/null 2>&1

# System monitoring every 5 minutes
*/5 * * * * /path/to/scripts/day2-system-monitor.sh --silent >/dev/null 2>&1

# Regression test every 2 hours
0 */2 * * * /path/to/scripts/day2-regression-test.sh >/dev/null 2>&1

# Full validation daily at 6 AM
0 6 * * * /path/to/scripts/day2-run-all-tests.sh full >/dev/null 2>&1
```

### Docker Integration

```bash
# Run tests within Docker environment
docker-compose exec backend bash -c "cd /app && ./scripts/day2-run-all-tests.sh quick"

# Health check from outside Docker
./scripts/day2-health-check.sh

# Monitor Docker services
./scripts/day2-system-monitor.sh
```

## 🎯 Core AWS Pattern Coverage

The system validates these **Day 1 proven patterns**:

### Critical Patterns (Must Work - 100% Day 1 Success)
- **EC2 Instance**: `i-1234567890abcdef0` → `AWS_EC2_001`
- **VPC**: `vpc-12345678` → `AWS_VPC_001`
- **Security Group**: `sg-12345678` → `AWS_SECURITY_GROUP_001`
- **AMI**: `ami-12345678` → `AWS_AMI_001`
- **Subnet**: `subnet-1234567890abcdef0` → `AWS_SUBNET_001`

### Extended Patterns (Additional Coverage)
- **EBS Volume**: `vol-1234567890abcdef0` → `AWS_EBS_VOL_001`
- **Lambda ARN**: `arn:aws:lambda:us-east-1:123456789012:function:test` → `AWS_LAMBDA_ARN_001`
- **IAM Role**: `arn:aws:iam::123456789012:role/TestRole` → `AWS_IAM_ROLE_001`
- **S3 Bucket**: `my-test-bucket` → `AWS_S3_BUCKET_001`
- **SNS Topic**: `arn:aws:sns:us-east-1:123456789012:test-topic` → `AWS_SNS_TOPIC_001`

## 🚨 Troubleshooting

### Common Issues

#### Health Check Failures

```bash
# Check system connectivity
curl -sf http://localhost:8001/status  # Kong Admin
curl -sf http://localhost:8000         # Kong Proxy
redis-cli -h localhost -p 6379 -a "password" ping  # Redis

# Check Docker services
docker-compose ps
docker-compose logs kong
```

#### Smoke Test Failures

```bash
# Verify AWS pattern masking
curl -X POST http://localhost:8000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Test: i-1234567890abcdef0"}]}'

# Check Kong logs for masking activity
docker logs claude-kong 2>&1 | grep -i mask
```

#### Regression Test Issues

```bash
# Compare with Day 1 baseline
cat tests/test-report/day1-core-validation-*.md

# Check for recent code changes
git log --oneline -10

# Verify configuration hasn't changed
diff scripts/test-config.env scripts/test-config.env.backup
```

#### System Monitor Alerts

```bash
# Check system resources
top -bn1 | head -20
free -h
df -h

# Check Docker resource usage
docker stats --no-stream

# Review alert log
tail -f logs/system-alerts.log
```

### Performance Issues

#### Slow Response Times

```bash
# Check system load
uptime

# Monitor Kong performance
curl -s http://localhost:8001/status | jq .

# Check Redis performance
redis-cli -h localhost -p 6379 -a "password" info stats
```

#### High Resource Usage

```bash
# Identify resource-heavy processes
ps aux --sort=-%cpu | head -10
ps aux --sort=-%mem | head -10

# Check Docker container resources
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Monitor system resources continuously
watch -n 5 'free -h && uptime'
```

## 📈 Performance Baselines

### Expected Performance (from Day 1)

| Metric | Day 1 Baseline | Acceptable Range | Alert Threshold |
|--------|----------------|------------------|-----------------|
| AWS Pattern Success Rate | 100% (5/5 core) | ≥ 80% | < 80% |
| Overall Success Rate | 95% | ≥ 90% | < 90% |
| Proxy Chain Success | 100% | 100% | < 100% |
| Redis Mapping Accuracy | 100% | ≥ 95% | < 95% |
| API Response Time | < 3 seconds | < 5 seconds | > 5 seconds |
| Health Check Time | < 30 seconds | < 45 seconds | > 60 seconds |
| Memory Usage | < 1% Redis | < 80% system | > 80% |

### Resource Thresholds

| Resource | Normal | Warning | Critical |
|----------|--------|---------|----------|
| CPU Usage | < 50% | 50-80% | > 80% |
| Memory Usage | < 60% | 60-80% | > 80% |
| Disk Usage | < 70% | 70-85% | > 85% |
| Response Time | < 2s | 2-5s | > 5s |
| Error Rate | < 1% | 1-5% | > 5% |

## 🔒 Security Considerations

### API Key Management

```bash
# Secure API key storage
chmod 600 scripts/test-config.env
export CLAUDE_API_KEY="your-key-here"
unset CLAUDE_API_KEY  # After use
```

### Redis Password Security

```bash
# Verify Redis authentication
redis-cli -h localhost -p 6379 -a "password" ping

# Check Redis security settings
redis-cli -h localhost -p 6379 -a "password" config get "*password*"
```

### Log Security

```bash
# Ensure logs don't contain API keys
grep -r "sk-ant-api" logs/ || echo "No API keys found in logs"

# Rotate logs regularly
find logs/ -name "*.log" -mtime +7 -delete
```

## 📅 Maintenance Schedule

### Daily
- Automated health checks (every 15 minutes)
- System monitoring (every 5 minutes)
- Error log review

### Weekly
- Full validation suite execution
- Performance baseline review
- Resource usage analysis

### Monthly
- Configuration review and updates
- Test suite optimization
- Performance trend analysis

## 🎖️ Success Metrics

### Deployment Readiness Criteria

✅ **Ready for Deployment**:
- Health check: PASS
- Smoke test: PASS (≥ 80% success rate)
- Regression test: PASS (no degradation from Day 1)
- System monitoring: HEALTHY

⚠️ **Deploy with Caution**:
- Minor warnings present
- Success rate 80-95%
- Non-critical issues detected

❌ **Do Not Deploy**:
- Critical system failures
- Success rate < 80%
- Regression from Day 1 baseline

### Continuous Quality Assurance

The system maintains Day 1's **95% success rate** through:
- **Automated validation** of all core patterns
- **Regression prevention** testing
- **Continuous monitoring** with alerting
- **Performance baseline** maintenance

## 📞 Support and Troubleshooting

### Getting Help

1. **Check the logs**: All scripts generate detailed logs
2. **Review reports**: Comprehensive reports explain failures
3. **Run diagnostics**: Use individual scripts to isolate issues
4. **Check configuration**: Verify `test-config.env` settings

### Contact Information

- **System Administrator**: Check Docker logs and system resources
- **Development Team**: Review code changes and regression patterns
- **Operations Team**: Monitor production deployment and performance

---

**Day 2 Automation System**  
**Version**: 2.0.0  
**Last Updated**: 2024-07-30  
**Baseline**: Day 1 achieved 95% success rate  
**Goal**: Maintain quality through continuous automation