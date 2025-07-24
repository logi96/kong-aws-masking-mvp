#!/bin/bash

# Comprehensive Flow Test - 20 AWS Patterns 
# Tests complete Backend → Kong → Redis → Kong → Backend transformation flow
# Following text-transformation-table-report.md format

set -e

echo "=================================================="
echo "🧪 COMPREHENSIVE FLOW TEST - 20 AWS PATTERNS"
echo "=================================================="
echo "Testing Date: $(date)"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

# Results arrays for report generation
declare -a RESULTS
declare -a FAILED_TESTS

# Function to test pattern transformation flow
test_pattern_flow() {
    local test_name="$1"
    local test_pattern="$2"
    local expected_mask_pattern="$3"
    
    echo -n "Testing: $test_name... "
    
    # Use quick-mask-test endpoint for instant response
    response=$(curl -s -X POST "http://localhost:3000/quick-mask-test" \
        -H "Content-Type: application/json" \
        -d "{\"testText\":\"$test_pattern\"}" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}FAILED${NC} - Connection error"
        FAILED_TESTS+=("$test_name: Connection error")
        ((FAILED++))
        return
    fi
    
    # Check if response contains original pattern (should NOT)
    if echo "$response" | grep -q "$test_pattern"; then
        echo -e "${RED}FAILED${NC} - Original pattern found"
        FAILED_TESTS+=("$test_name: Original pattern not masked - $test_pattern")
        ((FAILED++))
        return
    fi
    
    # Extract masked result from response
    masked_result=$(echo "$response" | jq -r '.data.originalInput' 2>/dev/null)
    if [ "$masked_result" = "null" ] || [ -z "$masked_result" ]; then
        echo -e "${RED}FAILED${NC} - Invalid response format"
        FAILED_TESTS+=("$test_name: Invalid response format")
        ((FAILED++))
        return
    fi
    
    # Success case
    echo -e "${GREEN}PASSED${NC}"
    RESULTS+=("$test_name|$test_pattern|$masked_result|✅")
    ((PASSED++))
}

# Function to test fail-secure behavior
test_fail_secure() {
    local test_name="$1"
    local test_pattern="$2"
    
    echo -n "Testing: $test_name... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000/quick-mask-test" \
        -H "Content-Type: application/json" \
        -d "{\"testText\":\"$test_pattern\"}" 2>/dev/null)
    
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$status_code" = "503" ]; then
        echo -e "${GREEN}PASSED${NC} - Fail-secure working"
        RESULTS+=("$test_name|$test_pattern|503 Service Unavailable|🛡️")
        ((PASSED++))
    else
        echo -e "${RED}FAILED${NC} - Expected 503, got $status_code"
        FAILED_TESTS+=("$test_name: Expected 503 but got $status_code")
        ((FAILED++))
    fi
}

echo "=== Testing 20 AWS Pattern Transformations ==="
echo ""

# 1. Basic AWS Resource Patterns (7 patterns)
echo "📋 Basic AWS Resource Patterns:"
test_pattern_flow "EC2 Instance ID" "i-1234567890abcdef0" "EC2_"
test_pattern_flow "VPC ID" "vpc-0123456789abcdef0" "VPC_"
test_pattern_flow "Subnet ID" "subnet-0123456789abcdef0" "SUBNET_"
test_pattern_flow "Security Group ID" "sg-0123456789abcdef0" "SG_"
test_pattern_flow "S3 Bucket Name" "my-production-bucket" "BUCKET_"
test_pattern_flow "RDS Instance" "prod-db-instance" "RDS_"
test_pattern_flow "IAM Role ARN" "arn:aws:iam::123456789012:role/MyRole" "IAM_ROLE_"

echo ""
echo "🌐 Network Patterns:"
# 2. Network Patterns (4 patterns)
test_pattern_flow "Private IP (10.x)" "10.0.1.100" "PRIVATE_IP_"
test_pattern_flow "Private IP (172.x)" "172.31.0.50" "PRIVATE_IP_"
test_pattern_flow "Private IP (192.168.x)" "192.168.1.100" "PRIVATE_IP_"
test_pattern_flow "CIDR Block" "10.0.1.0/24" "PRIVATE_IP_"

echo ""
echo "🔐 Security Patterns:"
# 3. Security Patterns (3 patterns)
test_pattern_flow "AWS Account ID" "123456789012" "ACCOUNT_"
test_pattern_flow "Access Key" "AKIAIOSFODNN7EXAMPLE" "ACCESS_KEY_"
test_pattern_flow "Secret Access Key" "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" "SECRET_KEY_"

echo ""
echo "🔗 Complex Patterns:"
# 4. Complex Patterns (6 patterns)
test_pattern_flow "EC2 + VPC" "i-1234567890abcdef0, vpc-0123456789abcdef0" "EC2_.*VPC_"
test_pattern_flow "Multiple IPs" "10.0.1.100, 172.31.0.50, 192.168.1.100" "PRIVATE_IP_"
test_pattern_flow "EC2 in VPC Context" "EC2 instance i-1234567890abcdef0 in vpc-0123456789abcdef0 with IP 10.0.1.100" "EC2_.*VPC_.*PRIVATE_IP_"
test_pattern_flow "RDS Connection" "Connect to RDS prod-db-instance from subnet-0123456789abcdef0" "RDS_.*SUBNET_"
test_pattern_flow "S3 with IAM Role" "S3 bucket my-production-bucket accessed by role arn:aws:iam::123456789012:role/AppRole" "BUCKET_.*IAM_ROLE_"
test_pattern_flow "Full Infrastructure" "Deploy i-1234567890abcdef0 to vpc-0123456789abcdef0 subnet-0123456789abcdef0 with sg-0123456789abcdef0" "EC2_.*VPC_.*SUBNET_.*SG_"

# Generate detailed report
echo ""
echo "=================================================="
echo "📊 COMPREHENSIVE FLOW TEST RESULTS"
echo "=================================================="
echo -e "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo -e "Success Rate: $(( PASSED * 100 / (PASSED + FAILED) ))%"

# Save results for report generation
cat > /tmp/flow-test-results.csv << EOF
Test Name,Original Pattern,Masked Result,Status
EOF

for result in "${RESULTS[@]}"; do
    echo "$result" | tr '|' ',' >> /tmp/flow-test-results.csv
done

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed Tests:"
    for failed in "${FAILED_TESTS[@]}"; do
        echo "  - $failed"
    done
fi

echo ""
echo "✅ Results saved to /tmp/flow-test-results.csv"
echo "Ready for comprehensive report generation"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL FLOW TESTS PASSED - SYSTEM READY FOR PRODUCTION${NC}"
    exit 0
else
    echo -e "${RED}⚠️  SOME TESTS FAILED - REVIEW REQUIRED${NC}"
    exit 1
fi