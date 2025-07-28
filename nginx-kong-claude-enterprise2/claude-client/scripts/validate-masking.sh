#!/bin/bash

# AWS Masking Validation Script
# Validates that AWS resources are properly masked in API responses

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${ANTHROPIC_BASE_URL:-http://nginx:8082}"
API_KEY="${ANTHROPIC_API_KEY}"
LOG_FILE="/app/logs/masking-validation.log"

# Initialize counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to test masking
test_masking() {
    local test_name="$1"
    local content="$2"
    local patterns_to_check="$3"
    local expected_masks="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log "Testing: $test_name"
    
    # Make API request
    local response=$(curl -s -X POST "$BASE_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-3-5-sonnet-20241022\",
            \"max_tokens\": 1024,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": \"$content\"
            }]
        }" 2>&1)
    
    # Check if request was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to make API request${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Check for original patterns (should NOT be present)
    local all_patterns_masked=true
    for pattern in $patterns_to_check; do
        if echo "$response" | grep -q "$pattern"; then
            echo -e "${RED}✗ Found unmasked pattern: $pattern${NC}"
            all_patterns_masked=false
        fi
    done
    
    # Check for masked patterns (should be present)
    local all_masks_found=true
    for mask in $expected_masks; do
        if ! echo "$response" | grep -q "$mask"; then
            echo -e "${YELLOW}⚠ Expected mask not found: $mask${NC}"
            all_masks_found=false
        fi
    done
    
    if [ "$all_patterns_masked" = true ] && [ "$all_masks_found" = true ]; then
        echo -e "${GREEN}✓ Test passed: All patterns properly masked${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ Test failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo "---"
}

# Main execution
main() {
    log "Starting AWS masking validation tests"
    
    # Check if API key is set
    if [ -z "$API_KEY" ]; then
        log "ERROR: ANTHROPIC_API_KEY environment variable is required"
        exit 1
    fi
    
    # Test 1: EC2 Instance IDs
    test_masking \
        "EC2 Instance ID Masking" \
        "Check these EC2 instances: i-1234567890abcdef0, i-0987654321fedcba0" \
        "i-1234567890abcdef0 i-0987654321fedcba0" \
        "AWS_EC2_"
    
    sleep 1
    
    # Test 2: S3 Bucket Names
    test_masking \
        "S3 Bucket Name Masking" \
        "List files in my-company-bucket and production-logs-backup" \
        "my-company-bucket production-logs-backup" \
        "AWS_S3_BUCKET_ AWS_S3_LOGS_BUCKET_"
    
    sleep 1
    
    # Test 3: RDS Database Names
    test_masking \
        "RDS Database Name Masking" \
        "Connect to production-db and analytics-db-replica" \
        "production-db analytics-db-replica" \
        "AWS_RDS_"
    
    sleep 1
    
    # Test 4: VPC and Security Groups
    test_masking \
        "VPC Resource Masking" \
        "VPC vpc-12345678 has security groups sg-abcdef12 and sg-12345678" \
        "vpc-12345678 sg-abcdef12 sg-12345678" \
        "AWS_VPC_ AWS_SECURITY_GROUP_"
    
    sleep 1
    
    # Test 5: IAM ARNs
    test_masking \
        "IAM ARN Masking" \
        "Role arn:aws:iam::123456789012:role/AdminRole in account 123456789012" \
        "arn:aws:iam::123456789012:role/AdminRole 123456789012" \
        "AWS_ARN_ AWS_ACCOUNT_"
    
    sleep 1
    
    # Test 6: Mixed Resources
    test_masking \
        "Mixed Resource Masking" \
        "Deploy app on i-abc123def4567890a in subnet-11111111111111111 with RDS mysql-prod-db" \
        "i-abc123def4567890a subnet-11111111111111111 mysql-prod-db" \
        "AWS_EC2_ AWS_SUBNET_ AWS_RDS_"
    
    # Generate summary
    echo ""
    echo "===== Test Summary ====="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo "======================="
    
    log "Validation completed. Passed: $PASSED_TESTS/$TOTAL_TESTS"
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"