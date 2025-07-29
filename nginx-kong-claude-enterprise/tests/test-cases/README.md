# Test Cases Documentation

## Overview
This directory contains comprehensive test cases for the nginx-kong-claude-enterprise project, focusing on P0 risks and edge cases.

## Test Categories

### 1. Nginx Proxy Failure Scenarios (TC-NX-*)
- **TC-NX-001**: Nginx Container Crash
- **TC-NX-002**: Nginx Worker Process Exhaustion  
- **TC-NX-003**: Nginx Memory Limit Reached
- **TC-NX-004**: Nginx Upstream (Kong) Connection Failure

### 2. Kong aws-masker Plugin Failures (TC-KM-*)
- **TC-KM-001**: JSON Parsing Failure
- **TC-KM-002**: Pattern Matching Engine Overflow
- **TC-KM-003**: Redis Mapping Store Inconsistency
- **TC-KM-004**: Special AWS Resource Patterns

### 3. Redis Connection Loss (TC-RD-*)
- **TC-RD-001**: Redis Connection Loss (Fail-Secure Mode)
- **TC-RD-002**: Redis Memory Full
- **TC-RD-003**: Redis Cluster Split Brain
- **TC-RD-004**: Redis Response Delay

### 4. Claude API Issues (TC-CL-*)
- **TC-CL-001**: Claude API Response Timeout
- **TC-CL-002**: Claude API 429 Rate Limit
- **TC-CL-003**: Claude API 5xx Server Errors
- **TC-CL-004**: Claude API Response Format Error

### 5. Large Request Processing (TC-LR-*)
- **TC-LR-001**: Large Request Body Processing
- **TC-LR-002**: Mass AWS Resource Masking
- **TC-LR-003**: Streaming Response Handling
- **TC-LR-004**: Concurrent Large Requests

## Test Execution

### Automated Test Suite
```bash
# Run all P0 tests
../run-p0-tests.sh

# Run specific category
../run-p0-tests.sh nginx
../run-p0-tests.sh kong-masker
../run-p0-tests.sh redis
../run-p0-tests.sh claude-api
../run-p0-tests.sh large-request
```

### Masking Validation
```bash
# Validate masking accuracy
../validate-masking.sh
```

### Generate Test Data
```bash
# Generate edge case test data
../test-data-generator.py
```

## Test Data Structure

### Generated Test Data
The `generated/` subdirectory contains:
- `deeply_nested_data.json` - 100-level nested JSON
- `massive_array_data.json` - 10K+ AWS resources
- `mixed_valid_invalid_data.json` - Valid/invalid resource mix
- `unicode_content_data.json` - Unicode and emoji content
- `boundary_values_data.json` - Min/max length values
- `pattern_collision_data.json` - Pattern matching edge cases
- `performance_stress_data.json` - Large payload for stress testing

### Manual Test Cases
- `ec2-test.json` - Basic EC2 instance testing
- `s3-test.json` - S3 bucket masking scenarios
- `multi-resource.json` - Multiple resource types

## Edge Cases Coverage

### Resource ID Boundaries
- Minimum length IDs (e.g., `i-0`, 3-char bucket names)
- Maximum length IDs (63-char bucket names)
- Special characters in names
- Unicode characters
- IP-like bucket names

### Pattern Matching Challenges
- Consecutive patterns without delimiters
- Overlapping text patterns
- Similar but different resource types
- Malformed resource IDs

### Performance Boundaries
- 10,000+ unique resources
- 100MB+ request payloads
- 1000+ concurrent connections
- 60-second timeout scenarios

### Error Conditions
- Malformed JSON (incomplete, invalid syntax)
- Circular references
- Encoding errors
- Network interruptions

## Success Criteria

### Functional Requirements
- ✅ All valid AWS resources must be masked
- ✅ Invalid patterns must not be masked
- ✅ Consistent masking for same resource
- ✅ Proper error handling for edge cases

### Performance Requirements
- ✅ Response time < 5 seconds
- ✅ Memory usage within container limits
- ✅ No memory leaks under stress
- ✅ Graceful degradation under load

### Security Requirements
- ✅ Fail-secure when Redis unavailable
- ✅ No sensitive data leakage
- ✅ Proper authentication handling
- ✅ Rate limiting enforcement

## Test Reports

All test executions generate reports in `/tests/test-report/` with:
- Timestamp-based naming
- Detailed pass/fail status
- Performance metrics
- Error logs and stack traces
- Recommendations for fixes

## Troubleshooting

### Common Issues
1. **Services not running**: Ensure `docker-compose up -d` is executed
2. **Redis connection errors**: Check Redis container health
3. **Timeout failures**: Verify network connectivity
4. **Memory errors**: Monitor container resource usage

### Debug Commands
```bash
# Check service health
docker-compose ps
docker-compose logs nginx
docker-compose logs kong
docker-compose logs redis

# Monitor resource usage
docker stats

# Check network connectivity
docker-compose exec nginx ping kong
docker-compose exec kong redis-cli -h redis ping
```

## Contributing

When adding new test cases:
1. Follow the naming convention: `TC-{CATEGORY}-{NUMBER}`
2. Document edge cases and boundaries
3. Include expected results
4. Update this README
5. Add to automated test suite