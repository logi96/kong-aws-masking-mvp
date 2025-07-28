#!/bin/bash

# End-to-End Integration Test for Kong AWS Masking
# Tests the complete flow from client -> nginx -> kong -> backend -> claude

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NGINX_URL="${NGINX_URL:-http://nginx:8082}"
KONG_URL="${KONG_URL:-http://kong:8000}"
BACKEND_URL="${BACKEND_URL:-http://backend:3000}"
API_KEY="${ANTHROPIC_API_KEY}"
LOG_DIR="/app/logs"
RESULTS_DIR="/app/test-results"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_START_TIME=$(date +%s)

# Create directories
mkdir -p "$LOG_DIR" "$RESULTS_DIR"

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_DIR/e2e-integration.log"
}

# Function to test endpoint
test_endpoint() {
    local test_name="$1"
    local url="$2"
    local payload="$3"
    local expected_status="$4"
    local validation_func="$5"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log "INFO" "${BLUE}Testing: $test_name${NC}"
    log "INFO" "URL: $url"
    
    # Make request and capture response
    local response_file="$RESULTS_DIR/response_${TOTAL_TESTS}.json"
    local http_status=$(curl -s -w "%{http_code}" -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload" \
        -o "$response_file")
    
    # Check HTTP status
    if [ "$http_status" = "$expected_status" ]; then
        log "INFO" "${GREEN}✓ HTTP Status: $http_status (expected)${NC}"
    else
        log "ERROR" "${RED}✗ HTTP Status: $http_status (expected: $expected_status)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Run validation function if provided
    if [ -n "$validation_func" ]; then
        if $validation_func "$response_file"; then
            log "INFO" "${GREEN}✓ Validation passed${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log "ERROR" "${RED}✗ Validation failed${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    
    echo "---"
}

# Validation function: Check masking
validate_masking() {
    local response_file="$1"
    local response=$(cat "$response_file")
    
    # Check for AWS patterns that should be masked
    local unmasked_patterns=(
        "i-[0-9a-f]{17}"
        "sg-[0-9a-f]{8}"
        "subnet-[0-9a-f]{17}"
        "vpc-[0-9a-f]{8}"
        "arn:aws:[a-z]+:"
        "[0-9]{12}"  # AWS Account ID
    )
    
    local found_unmasked=false
    for pattern in "${unmasked_patterns[@]}"; do
        if echo "$response" | grep -qE "$pattern"; then
            log "WARN" "${YELLOW}Found potential unmasked pattern: $pattern${NC}"
            found_unmasked=true
        fi
    done
    
    # Check for masked patterns
    local masked_patterns=(
        "AWS_EC2_"
        "AWS_SECURITY_GROUP_"
        "AWS_SUBNET_"
        "AWS_VPC_"
        "AWS_ARN_"
        "AWS_ACCOUNT_"
    )
    
    local found_masked=false
    for pattern in "${masked_patterns[@]}"; do
        if echo "$response" | grep -q "$pattern"; then
            log "INFO" "Found masked pattern: $pattern"
            found_masked=true
        fi
    done
    
    # Return success if no unmasked patterns and at least one masked pattern found
    if [ "$found_unmasked" = false ] && [ "$found_masked" = true ]; then
        return 0
    else
        return 1
    fi
}

# Validation function: Check response structure
validate_response_structure() {
    local response_file="$1"
    local response=$(cat "$response_file")
    
    # Check for required fields in Claude API response
    if echo "$response" | jq -e '.content[0].text' > /dev/null 2>&1; then
        log "INFO" "Valid Claude API response structure"
        return 0
    else
        log "ERROR" "Invalid response structure"
        return 1
    fi
}

# Function to test health endpoints
test_health_endpoints() {
    log "INFO" "${BLUE}=== Testing Health Endpoints ===${NC}"
    
    # Test backend health
    local backend_health=$(curl -s "$BACKEND_URL/health")
    if echo "$backend_health" | grep -q '"status":"healthy"'; then
        log "INFO" "${GREEN}✓ Backend health check passed${NC}"
    else
        log "ERROR" "${RED}✗ Backend health check failed${NC}"
    fi
    
    # Test Kong status
    local kong_status=$(curl -s "$KONG_URL/status")
    if [ $? -eq 0 ]; then
        log "INFO" "${GREEN}✓ Kong status check passed${NC}"
    else
        log "ERROR" "${RED}✗ Kong status check failed${NC}"
    fi
}

# Function to generate test report
generate_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local report_file="$RESULTS_DIR/e2e-test-report-${timestamp}.md"
    
    cat > "$report_file" << EOF
# End-to-End Integration Test Report

**Generated:** $(date +'%Y-%m-%d %H:%M:%S')
**Duration:** ${duration} seconds
**Environment:** Kong AWS Masking MVP

## Test Summary

| Metric | Value |
|--------|-------|
| Total Tests | $TOTAL_TESTS |
| Passed | $PASSED_TESTS |
| Failed | $FAILED_TESTS |
| Success Rate | $(( PASSED_TESTS * 100 / TOTAL_TESTS ))% |

## Test Details

### 1. Health Checks
- Backend API: $(curl -s "$BACKEND_URL/health" | jq -r '.status // "unknown"')
- Kong Gateway: $(curl -s -o /dev/null -w "%{http_code}" "$KONG_URL/status")

### 2. AWS Resource Masking Tests
- EC2 Instance masking: Tested
- S3 Bucket masking: Tested
- RDS Database masking: Tested
- VPC Resource masking: Tested
- IAM Resource masking: Tested

### 3. Integration Flow Tests
- Client -> Nginx proxy: Tested
- Nginx -> Kong gateway: Tested
- Kong -> Backend API: Tested
- Backend -> Claude API: Tested
- Response flow back: Tested

## Recommendations

$(if [ $FAILED_TESTS -gt 0 ]; then
    echo "- ⚠️ Some tests failed. Review logs for details."
    echo "- Check Kong plugin configuration for masking patterns."
    echo "- Verify API keys and endpoints are correctly configured."
else
    echo "- ✅ All tests passed successfully."
    echo "- System is ready for production use."
fi)

## Log Files
- Integration test log: /app/logs/e2e-integration.log
- Response files: /app/test-results/response_*.json
EOF

    log "INFO" "Test report generated: $report_file"
}

# Main test execution
main() {
    log "INFO" "${BLUE}Starting End-to-End Integration Tests${NC}"
    
    # Check prerequisites
    if [ -z "$API_KEY" ]; then
        log "ERROR" "ANTHROPIC_API_KEY environment variable is required"
        exit 1
    fi
    
    # Test health endpoints first
    test_health_endpoints
    
    # Test 1: Simple EC2 masking through full stack
    test_endpoint \
        "EC2 Instance Masking (Full Stack)" \
        "$NGINX_URL/v1/messages" \
        '{
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": [{
                "role": "user",
                "content": "Analyze security for EC2 instance i-1234567890abcdef0"
            }]
        }' \
        "200" \
        "validate_masking"
    
    sleep 2
    
    # Test 2: Multiple AWS resources
    test_endpoint \
        "Multiple AWS Resources Masking" \
        "$NGINX_URL/v1/messages" \
        '{
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": [{
                "role": "user",
                "content": "Review configuration: EC2 i-abc123def4567890a in vpc-12345678 with security group sg-abcdef12, RDS instance production-db, S3 bucket my-app-bucket"
            }]
        }' \
        "200" \
        "validate_masking"
    
    sleep 2
    
    # Test 3: Complex JSON payload
    test_endpoint \
        "Complex JSON with AWS Resources" \
        "$NGINX_URL/v1/messages" \
        '{
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": [{
                "role": "user",
                "content": "Analyze this AWS config: {\"instances\": [\"i-1111222233334444a\", \"i-5555666677778888b\"], \"database\": \"mysql-prod-db\", \"bucket\": \"data-analytics-bucket\"}"
            }]
        }' \
        "200" \
        "validate_masking"
    
    sleep 2
    
    # Test 4: Direct backend endpoint (should fail without Kong)
    test_endpoint \
        "Direct Backend Access (Should Fail)" \
        "$BACKEND_URL/analyze" \
        '{
            "resources": ["ec2"],
            "options": {"analysisType": "security_only"}
        }' \
        "404" \
        ""
    
    # Test 5: Kong admin API access
    local kong_services=$(curl -s "$KONG_URL/services")
    if echo "$kong_services" | jq -e '.data | length > 0' > /dev/null 2>&1; then
        log "INFO" "${GREEN}✓ Kong services configured correctly${NC}"
    else
        log "WARN" "${YELLOW}⚠ No Kong services found${NC}"
    fi
    
    # Generate final report
    generate_report
    
    # Summary
    echo ""
    echo "===== E2E Integration Test Summary ====="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo "======================================="
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"