# Integration Test Report
**Generated**: 2025년 7월 28일 월요일 22시 55분 21초 KST
**Test Environment**: nginx-kong-claude-enterprise

## Executive Summary
This report contains the results of integration testing for the Kong AWS masking plugin.

## Test Environment
- **Nginx URL**: http://localhost:8083
- **Kong Admin URL**: http://localhost:8081
- **Redis Port**: 6380

## Test Results

### Test 1: Service Health Checks

- ✅ Nginx health check: HTTP 200
- ✅ Kong admin API: HTTP 200
- ✅ Redis connection: Available

### Test 2: AWS Resource Masking

- Response Code: 401
- Response Time: 1.225771s
- ⚠️ EC2 instance masking: Not detected
- ⚠️ S3 bucket masking: Not detected

### Test 3: Redis Mapping Storage

- ⚠️ No mappings found in Redis

### Test 4: Performance Benchmark

- Running 5 performance tests...
  - Test 1: 1.0s
  - Test 2: 0s
  - Test 3: 0s
  - Test 4: 1.0s
  - Test 5: 0s
- Average response time: .400s
- ⚠️ Performance target: Not met (> 100ms)

### Test 5: Fail-Secure Mode (Circuit Breaker)

- ❌ Fail-secure mode: Not working (HTTP 401)


## Summary
- Tests Passed: 3
- Tests Failed: 1
- Warnings: 4

## Recommendations
1. Fix failed tests before deployment
2. Investigate warning conditions
3. Monitor Redis availability in production
4. Consider implementing request queuing for better performance
