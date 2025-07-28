# Claude Client Test Suite

Comprehensive testing framework for Kong AWS Masking integration with Claude API.

## Overview

This test suite provides multiple levels of testing to ensure AWS resource masking works correctly throughout the entire request/response flow.

## Architecture

```
Test Client Container
├── Test Scenarios (JSON)     # Declarative test cases
├── Automation Scripts        # Test runners and validators
├── Pattern Validation        # AWS pattern regex testing
└── E2E Integration Tests     # Full stack validation
```

## Test Categories

### 1. Pattern Validation (`aws-pattern-validation.js`)
- Validates AWS resource regex patterns
- Tests masking transformations
- Ensures pattern coverage

### 2. Scenario Testing (`run-test-scenarios.js`)
- Executes JSON-defined test scenarios
- Tests specific AWS resource types:
  - EC2 instances
  - S3 buckets
  - RDS databases
  - VPC resources
  - IAM credentials
  - Mixed resource combinations

### 3. Masking Validation (`validate-masking.sh`)
- Quick smoke tests for core functionality
- Validates masking is active
- Checks for data leaks

### 4. E2E Integration (`e2e-integration-test.sh`)
- Tests complete request flow
- Validates all components:
  - Nginx proxy
  - Kong gateway
  - Backend API
  - Claude API integration

## Running Tests

### Prerequisites
```bash
# Ensure containers are running
docker-compose up -d

# Set environment variable
export ANTHROPIC_API_KEY=your-api-key
```

### Individual Test Suites

```bash
# Pattern validation
docker exec claude-client npm run test:patterns

# Scenario tests
docker exec claude-client npm run test:scenarios

# Quick validation
docker exec claude-client npm run test:validate

# E2E integration
docker exec claude-client npm run test:e2e

# Run all tests
docker exec claude-client npm run test:all
```

### Comprehensive Test Run

```bash
# Run all tests with consolidated reporting
docker exec claude-client /app/scripts/run-all-tests.sh
```

## Test Scenarios

### EC2 Test Scenarios
- Single instance masking
- Multiple instances
- Instance with associated resources
- Complex EC2 configurations

### S3 Test Scenarios
- Simple bucket names
- Log buckets
- Bucket ARNs
- S3 CLI output

### RDS Test Scenarios
- Database instance names
- Connection endpoints
- Cluster configurations
- Multi-region setups

### VPC Test Scenarios
- VPC IDs
- Subnet configurations
- Security group rules
- Network ACLs

### IAM Test Scenarios
- Role ARNs
- User policies
- Access keys
- Cross-account trusts

### Mixed Resource Scenarios
- Full application stacks
- Lambda integrations
- Disaster recovery setups
- Kubernetes on AWS

## Test Results

Results are stored in `/app/test-results/`:
- `pattern-validation-*.json` - Pattern test results
- `test-results-*.json` - Scenario execution results
- `e2e-test-report-*.md` - Integration test reports
- `test-summary-*.md` - Consolidated test summary

## Interpreting Results

### Pattern Validation
- ✅ All patterns match their examples
- ❌ Pattern regex needs adjustment

### Scenario Tests
- Check masking validation results
- Verify response structure
- Ensure no data leaks

### E2E Tests
- Confirm all services are connected
- Validate end-to-end masking
- Check performance metrics

## Troubleshooting

### Common Issues

1. **API Key Issues**
   ```bash
   # Check if API key is set
   echo $ANTHROPIC_API_KEY
   ```

2. **Service Connectivity**
   ```bash
   # Check service health
   curl http://localhost:3000/health
   curl http://localhost:8001/status
   ```

3. **Masking Not Working**
   - Check Kong plugin is loaded
   - Verify pattern configurations
   - Review Kong logs

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug
docker exec claude-client npm run test:scenarios
```

### Viewing Logs

```bash
# Test client logs
docker exec claude-client tail -f /app/logs/test-client.log

# Pattern validation logs
docker exec claude-client tail -f /app/logs/pattern-validation.log

# E2E test logs
docker exec claude-client tail -f /app/logs/e2e-integration.log
```

## Performance Benchmarks

Expected performance metrics:
- Pattern matching: < 1ms per pattern
- API response time: < 5 seconds
- Masking overhead: < 100ms

## Security Considerations

- All AWS credentials are masked before external API calls
- No sensitive data is logged
- Test data uses example/dummy values only

## Extending Tests

### Adding New Scenarios

1. Create new JSON file in `/test-scenarios/`
2. Follow the existing schema
3. Include validation rules

### Adding New Patterns

1. Update `AWS_PATTERNS` in `aws-pattern-validation.js`
2. Add test examples
3. Update Kong plugin patterns if needed

## CI/CD Integration

```yaml
# Example GitHub Actions workflow
- name: Run AWS Masking Tests
  run: |
    docker-compose up -d
    sleep 10
    docker exec claude-client /app/scripts/run-all-tests.sh
```

## Support

For issues or questions:
1. Check test logs in `/app/logs/`
2. Review test reports in `/app/test-results/`
3. Verify service configurations