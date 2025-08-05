# Kong AWS Masking MVP - Test Suite Documentation

**Project**: nginx-kong-claude-enterprise2  
**Purpose**: Comprehensive test suite for Kong AWS masking functionality  
**Last Updated**: 2025-07-30

## 🎯 Overview

This test suite validates the complete Kong AWS masking system including:
- End-to-end proxy chain functionality
- AWS resource pattern masking/unmasking
- Component-specific reliability
- Performance benchmarks
- System integration

## 📁 Test Organization

### **core/** - 핵심 통합 테스트
Essential end-to-end tests for system validation:

| Test Script | Purpose | Execution Time | Priority |
|------------|---------|----------------|----------|
| `e2e-comprehensive-test.sh` | Complete E2E flow verification with performance metrics | ~5 min | 🔴 Critical |
| `proxy-integration-test.sh` | Proxy chain integration with 50+ AWS patterns | ~3 min | 🔴 Critical |
| `proxy-chain-verification.sh` | Proxy chain validation and connectivity | ~2 min | 🟡 High |

### **patterns/** - AWS 패턴 테스트
AWS resource pattern masking validation:

| Test Script | Purpose | Execution Time | Priority |
|------------|---------|----------------|----------|
| `50-patterns-complete-test.sh` | Complete 50+ AWS patterns validation | ~10 min | 🔴 Critical |
| `comprehensive-patterns-validation.sh` | Comprehensive pattern validation | ~6 min | 🟡 High |
| `aws-patterns-integration-test.sh` | AWS pattern integration testing | ~4 min | 🟡 High |
| `50-patterns-simple-test.sh` | Simplified AWS patterns testing | ~3 min | 🟢 Medium |

### **components/** - 컴포넌트별 테스트
Individual component reliability tests:

| Test Script | Purpose | Execution Time | Priority |
|------------|---------|----------------|----------|
| `kong-direct-test.sh` | Direct Kong Gateway testing | ~2 min | 🟡 High |
| `redis-optimization-test.sh` | Redis configuration and optimization | ~3 min | 🟡 High |
| `test-authentication.sh` | API key authentication and rate limiting | ~2 min | 🟡 High |
| `sdk-proxy-test.sh` | Claude Code SDK proxy functionality | ~2 min | 🟢 Medium |

### **performance/** - 성능 및 검증
Performance benchmarks and quick validation:

| Test Script | Purpose | Execution Time | Priority |
|------------|---------|----------------|----------|
| `performance-benchmark.sh` | System performance and resource usage | ~5 min | 🟡 High |
| `quick-core-validation.sh` | Rapid core functionality validation | ~1 min | 🟢 Medium |

### **logging/** - 로깅 테스트
Logging and monitoring validation:

| Test Script | Purpose | Execution Time | Priority |
|------------|---------|----------------|----------|
| `test-comprehensive-logging.sh` | Comprehensive logging system validation | ~3 min | 🟢 Medium |

## 🚀 Quick Start Guide

### **Pre-deployment Validation**
Essential tests before any code changes:
```bash
cd tests/

# 1. Core system validation
./core/e2e-comprehensive-test.sh
./core/proxy-chain-verification.sh

# 2. Pattern functionality
./patterns/comprehensive-patterns-validation.sh

# 3. Performance check
./performance/quick-core-validation.sh
```

### **Full System Validation**
Complete test suite for production readiness:
```bash
cd tests/

# Execute in order for comprehensive validation
./core/e2e-comprehensive-test.sh
./patterns/50-patterns-complete-test.sh
./performance/performance-benchmark.sh
./components/kong-direct-test.sh
./components/redis-optimization-test.sh
```

### **Quick Health Check**
Rapid system health validation:
```bash
cd tests/
./performance/quick-core-validation.sh  # ~1 minute
```

## 📊 Test Reports

All test executions generate timestamped reports in `test-report/`:

```
test-report/
├── e2e-comprehensive-test-YYYYMMDD_HHMMSS.md
├── 50-patterns-complete-test-YYYYMMDD_HHMMSS.md
├── performance-benchmark-YYYYMMDD_HHMMSS.md
├── proxy-integration-test-001.md
└── kong-direct-test-YYYYMMDD_HHMMSS.md
```

**Report Naming Convention:**
- Timestamp format: `YYYYMMDD_HHMMSS`
- Sequential numbering: `001`, `002`, `003` for repeated runs
- Descriptive prefixes matching test script names

## 🎯 Test Execution Strategy

### **By Development Phase**

**1. Pre-commit Validation** (3-5 minutes)
```bash
./performance/quick-core-validation.sh
./core/proxy-chain-verification.sh
```

**2. Feature Development** (10-15 minutes)
```bash
./core/e2e-comprehensive-test.sh
./patterns/comprehensive-patterns-validation.sh
./components/kong-direct-test.sh
```

**3. Pre-production** (25-30 minutes)
```bash
# Full validation suite
./core/e2e-comprehensive-test.sh
./patterns/50-patterns-complete-test.sh
./performance/performance-benchmark.sh
./components/redis-optimization-test.sh
./components/test-authentication.sh
./logging/test-comprehensive-logging.sh
```

### **By Modification Type**

**Kong Plugin Changes:**
```bash
./patterns/50-patterns-complete-test.sh  # Pattern validation
./core/proxy-integration-test.sh         # Integration check
./components/kong-direct-test.sh         # Direct Kong test
```

**Redis Configuration:**
```bash
./components/redis-optimization-test.sh  # Redis-specific
./core/e2e-comprehensive-test.sh         # Integration impact
```

**Nginx Proxy Changes:**
```bash
./core/proxy-chain-verification.sh       # Proxy validation
./core/e2e-comprehensive-test.sh         # End-to-end check
```

**Performance Optimization:**
```bash
./performance/performance-benchmark.sh   # Before/after comparison
./performance/quick-core-validation.sh   # Quick verification
```

## 🔧 Test Environment Requirements

### **System Prerequisites**
- Docker Compose running with all services healthy
- Redis accessible on configured port with authentication
- Kong Gateway with aws-masker plugin enabled
- Nginx proxy configured and running
- Valid ANTHROPIC_API_KEY in environment

### **Port Configuration**
```bash
# Default test endpoints
NGINX_PROXY=http://localhost:8085
KONG_GATEWAY=http://localhost:8000
KONG_ADMIN=http://localhost:8001
REDIS_HOST=localhost:6379
```

### **Environment Variables**
```bash
# Required for test execution
export ANTHROPIC_API_KEY="sk-ant-api03-..."
export REDIS_PASSWORD="your-redis-password"
```

## 🚨 Critical Test Rules

### **MUST Rules**
1. **Report Generation**: Every test MUST generate a timestamped report
2. **Pre-change Testing**: Run core tests before ANY code modifications
3. **Sequential Execution**: Do not run tests in parallel (Redis conflicts)
4. **Clean Environment**: Ensure clean Redis state between test runs
5. **Error Handling**: All test failures must be investigated before proceeding

### **Best Practices**
- Archive old test reports regularly
- Review test reports for performance regressions
- Update tests when adding new AWS patterns
- Maintain consistent test report format
- Document any test modifications

## 📚 Troubleshooting

### **Common Test Failures**

**Connection Errors:**
```bash
# Check service health
docker-compose ps
docker-compose logs kong
```

**Redis Authentication:**
```bash
# Verify Redis password
docker exec claude-redis redis-cli -a "$REDIS_PASSWORD" ping
```

**Kong Plugin Issues:**
```bash
# Check plugin status
curl http://localhost:8001/plugins
```

**API Key Problems:**
```bash
# Validate API key format
echo $ANTHROPIC_API_KEY | grep -E "^sk-ant-api03-"
```

### **Test Report Analysis**

**Performance Regression Detection:**
- Compare response times across reports
- Monitor Redis operation latency
- Track masking pattern success rates

**Pattern Validation Issues:**
- Check Kong logs for pattern matching failures
- Verify Redis mapping storage
- Validate unmask operations

## 🗂️ Archive Management

### **Archive Structure**
```
archive/
├── day1-core-validation.sh      # Legacy development validation
├── integration-test.sh          # Generic integration test (replaced)
└── simple-integration-test.sh   # Basic integration test (replaced)
```

**Archive Policy:**
- Legacy development tests moved to `archive/`
- Duplicate functionality tests archived
- Historical test reports preserved in `test-report/`

## 📈 Test Metrics

### **Success Criteria**
- **Core Tests**: 100% pass rate required
- **Pattern Tests**: 95%+ AWS pattern success rate
- **Performance**: <5 second response times
- **Redis**: <1ms operation latency
- **Integration**: End-to-end flow 100% functional

### **Coverage Goals**
- All 50+ AWS resource patterns tested
- Complete proxy chain validation
- Authentication and rate limiting coverage
- Performance baseline establishment
- Error scenario validation

## 🔄 Continuous Improvement

### **Test Maintenance**
- Review and update tests monthly
- Add tests for new AWS patterns
- Performance baseline updates
- Documentation synchronization

### **Feedback Integration**
- Incorporate production issue findings
- Update based on user feedback  
- Enhance based on monitoring insights
- Adapt to infrastructure changes

---

## 📞 Support

For test-related issues:
1. Check test reports in `test-report/`
2. Review Docker logs: `docker-compose logs`
3. Validate environment configuration
4. Consult troubleshooting section above
5. Check CLAUDE.md for operational guidance

**Test Suite Version**: v1.0  
**Compatible with**: Kong Gateway 3.9.0.1, Redis 7-alpine, Nginx latest