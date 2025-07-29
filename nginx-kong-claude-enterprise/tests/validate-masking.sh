#!/bin/bash

# Masking Validation Script
# Validates that AWS resources are properly masked and unmasked

set -euo pipefail

# Configuration
PROXY_URL="http://localhost:8082"
API_KEY="${ANTHROPIC_API_KEY:-test-key}"
REPORT_DIR="test-report"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
VALIDATION_REPORT="${REPORT_DIR}/masking-validation_${TIMESTAMP}.md"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test data
declare -A TEST_RESOURCES=(
    ["ec2"]="i-1234567890abcdef0"
    ["s3"]="my-test-bucket-2024"
    ["rds"]="mysql-prod-instance"
    ["private_ip"]="10.0.1.100"
    ["vpc"]="vpc-1234567890abcdef0"
    ["sg"]="sg-1234567890abcdef0"
    ["iam_role"]="arn:aws:iam::123456789012:role/my-test-role"
)

# Initialize report
init_report() {
    mkdir -p "$REPORT_DIR"
    cat > "$VALIDATION_REPORT" << EOF
# AWS Resource Masking Validation Report
**Generated**: $(date)
**Environment**: nginx-kong-claude-enterprise

## Test Summary
This report validates the masking and unmasking functionality for AWS resources.

## Test Cases

EOF
}

# Helper function to extract masked values from response
extract_masked_values() {
    local response="$1"
    # Extract X-AWS-Masked-Resources header or parse response body
    echo "$response" | grep -oE '(EC2|S3|RDS|VPC|SG|IAM|PRIVATE_IP)_[0-9]+' | sort -u
}

# Test single resource masking
test_resource_masking() {
    local resource_type="$1"
    local resource_value="$2"
    local test_name="Masking Test: $resource_type"
    
    echo -e "\n${YELLOW}Testing $resource_type masking...${NC}"
    
    # Create request with the resource
    local request_body=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "Analyze this AWS resource: $resource_value"
    }],
    "max_tokens": 100
}
EOF
)
    
    # Send request and capture response
    local response_file="/tmp/masking_test_${resource_type}_${TIMESTAMP}.txt"
    local http_code=$(curl -s -w "%{http_code}" -X POST "$PROXY_URL/" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -d "$request_body" \
        -o "$response_file")
    
    # Analyze response
    echo "### $test_name" >> "$VALIDATION_REPORT"
    echo "- **Resource Type**: $resource_type" >> "$VALIDATION_REPORT"
    echo "- **Original Value**: \`$resource_value\`" >> "$VALIDATION_REPORT"
    echo "- **HTTP Status**: $http_code" >> "$VALIDATION_REPORT"
    
    if [ "$http_code" = "200" ]; then
        # Check if resource was masked in response
        if grep -q "$resource_value" "$response_file"; then
            echo -e "${RED}✗ FAILED${NC}: Original resource found in response"
            echo "- **Result**: ❌ Original resource leaked in response" >> "$VALIDATION_REPORT"
        else
            # Look for masked pattern
            local masked_values=$(extract_masked_values "$(cat $response_file)")
            if [ -n "$masked_values" ]; then
                echo -e "${GREEN}✓ PASSED${NC}: Resource properly masked"
                echo "- **Result**: ✅ Resource masked successfully" >> "$VALIDATION_REPORT"
                echo "- **Masked Values**: $masked_values" >> "$VALIDATION_REPORT"
            else
                echo -e "${YELLOW}⚠ WARNING${NC}: No masked pattern found"
                echo "- **Result**: ⚠️ No clear masking pattern detected" >> "$VALIDATION_REPORT"
            fi
        fi
    else
        echo -e "${RED}✗ ERROR${NC}: Request failed with status $http_code"
        echo "- **Result**: ❌ Request failed" >> "$VALIDATION_REPORT"
    fi
    
    echo "" >> "$VALIDATION_REPORT"
}

# Test multiple resources in single request
test_multiple_resources() {
    local test_name="Multiple Resources Masking"
    
    echo -e "\n${YELLOW}Testing multiple resources masking...${NC}"
    
    # Create request with multiple resources
    local content="I have EC2 instance ${TEST_RESOURCES[ec2]} in VPC ${TEST_RESOURCES[vpc]} "
    content+="with security group ${TEST_RESOURCES[sg]} and private IP ${TEST_RESOURCES[private_ip]}. "
    content+="Data is stored in S3 bucket ${TEST_RESOURCES[s3]} and RDS instance ${TEST_RESOURCES[rds]}."
    
    local request_body=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "$content"
    }],
    "max_tokens": 200
}
EOF
)
    
    # Send request
    local response_file="/tmp/masking_test_multiple_${TIMESTAMP}.txt"
    local http_code=$(curl -s -w "%{http_code}" -X POST "$PROXY_URL/" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -d "$request_body" \
        -o "$response_file")
    
    echo "### $test_name" >> "$VALIDATION_REPORT"
    echo "- **Resources Count**: ${#TEST_RESOURCES[@]}" >> "$VALIDATION_REPORT"
    echo "- **HTTP Status**: $http_code" >> "$VALIDATION_REPORT"
    
    if [ "$http_code" = "200" ]; then
        local leaked_resources=()
        local masked_count=0
        
        # Check each resource
        for resource_type in "${!TEST_RESOURCES[@]}"; do
            if grep -q "${TEST_RESOURCES[$resource_type]}" "$response_file"; then
                leaked_resources+=("$resource_type: ${TEST_RESOURCES[$resource_type]}")
            else
                ((masked_count++))
            fi
        done
        
        if [ ${#leaked_resources[@]} -eq 0 ]; then
            echo -e "${GREEN}✓ PASSED${NC}: All resources masked"
            echo "- **Result**: ✅ All ${#TEST_RESOURCES[@]} resources masked successfully" >> "$VALIDATION_REPORT"
        else
            echo -e "${RED}✗ FAILED${NC}: ${#leaked_resources[@]} resources leaked"
            echo "- **Result**: ❌ Resources leaked: ${#leaked_resources[@]}/${#TEST_RESOURCES[@]}" >> "$VALIDATION_REPORT"
            echo "- **Leaked Resources**:" >> "$VALIDATION_REPORT"
            for leaked in "${leaked_resources[@]}"; do
                echo "  - $leaked" >> "$VALIDATION_REPORT"
            done
        fi
    else
        echo -e "${RED}✗ ERROR${NC}: Request failed"
        echo "- **Result**: ❌ Request failed" >> "$VALIDATION_REPORT"
    fi
    
    echo "" >> "$VALIDATION_REPORT"
}

# Test edge cases
test_edge_cases() {
    local test_name="Edge Cases"
    
    echo -e "\n${YELLOW}Testing edge cases...${NC}"
    
    echo "### $test_name" >> "$VALIDATION_REPORT"
    
    # Test 1: Empty resource ID
    test_edge_case "Empty EC2 ID" "i-"
    
    # Test 2: Very long S3 bucket name
    local long_bucket="my-very-long-bucket-name-that-reaches-the-maximum-allowed-63-chars"
    test_edge_case "Max length S3 bucket" "$long_bucket"
    
    # Test 3: Special characters in bucket name
    test_edge_case "S3 bucket with dots" "my.bucket.with.dots"
    
    # Test 4: IP at boundary
    test_edge_case "Boundary private IP" "10.0.0.0"
    test_edge_case "Boundary private IP" "10.255.255.255"
    
    # Test 5: Malformed resources
    test_edge_case "Malformed EC2 ID" "i-xyz123"
    test_edge_case "Invalid IP" "256.256.256.256"
}

test_edge_case() {
    local case_name="$1"
    local resource="$2"
    
    echo "  Testing: $case_name" >> "$VALIDATION_REPORT"
    
    local request_body=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "Check resource: $resource"
    }],
    "max_tokens": 50
}
EOF
)
    
    local response=$(curl -s -X POST "$PROXY_URL/" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -d "$request_body")
    
    if echo "$response" | grep -q "$resource"; then
        echo "    - ⚠️ Resource not masked (might be invalid format)" >> "$VALIDATION_REPORT"
    else
        echo "    - ✅ Resource masked or handled correctly" >> "$VALIDATION_REPORT"
    fi
}

# Test masking consistency
test_consistency() {
    local test_name="Masking Consistency"
    
    echo -e "\n${YELLOW}Testing masking consistency...${NC}"
    
    echo "### $test_name" >> "$VALIDATION_REPORT"
    
    # Send same resource multiple times
    local test_resource="${TEST_RESOURCES[ec2]}"
    local masked_values=()
    
    for i in {1..3}; do
        local request_body=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "Instance $test_resource needs analysis"
    }],
    "max_tokens": 50
}
EOF
)
        
        local response=$(curl -s -X POST "$PROXY_URL/" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $API_KEY" \
            -d "$request_body")
        
        # Extract masked value (this is simplified - real implementation would parse properly)
        local masked=$(echo "$response" | grep -oE 'EC2_[0-9]+' | head -1)
        if [ -n "$masked" ]; then
            masked_values+=("$masked")
        fi
    done
    
    # Check if all masked values are the same
    if [ ${#masked_values[@]} -eq 3 ] && [ "${masked_values[0]}" = "${masked_values[1]}" ] && [ "${masked_values[1]}" = "${masked_values[2]}" ]; then
        echo -e "${GREEN}✓ PASSED${NC}: Consistent masking"
        echo "- **Result**: ✅ Same resource consistently mapped to: ${masked_values[0]}" >> "$VALIDATION_REPORT"
    else
        echo -e "${RED}✗ FAILED${NC}: Inconsistent masking"
        echo "- **Result**: ❌ Inconsistent masking detected" >> "$VALIDATION_REPORT"
        echo "- **Masked Values**: ${masked_values[*]}" >> "$VALIDATION_REPORT"
    fi
    
    echo "" >> "$VALIDATION_REPORT"
}

# Performance test
test_performance() {
    local test_name="Performance Test"
    
    echo -e "\n${YELLOW}Testing performance with large payload...${NC}"
    
    echo "### $test_name" >> "$VALIDATION_REPORT"
    
    # Generate large payload with many resources
    local resources=""
    for i in {1..100}; do
        resources+="EC2 instance i-$(printf '%016x' $i) with IP 10.0.$((i/256)).$((i%256)) "
    done
    
    local request_body=$(cat <<EOF
{
    "model": "claude-3-sonnet-20240229",
    "messages": [{
        "role": "user",
        "content": "$resources"
    }],
    "max_tokens": 100
}
EOF
)
    
    # Measure time
    local start_time=$(date +%s.%N)
    
    local http_code=$(curl -s -w "%{http_code}" -X POST "$PROXY_URL/" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -d "$request_body" \
        -o /dev/null)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo "- **Resources Count**: 200 (100 EC2 + 100 IPs)" >> "$VALIDATION_REPORT"
    echo "- **Processing Time**: ${duration}s" >> "$VALIDATION_REPORT"
    
    if (( $(echo "$duration < 5" | bc -l) )); then
        echo -e "${GREEN}✓ PASSED${NC}: Performance within target (<5s)"
        echo "- **Result**: ✅ Performance target met" >> "$VALIDATION_REPORT"
    else
        echo -e "${RED}✗ FAILED${NC}: Performance exceeded target (>5s)"
        echo "- **Result**: ❌ Performance target missed" >> "$VALIDATION_REPORT"
    fi
    
    echo "" >> "$VALIDATION_REPORT"
}

# Generate summary
generate_summary() {
    echo "## Summary" >> "$VALIDATION_REPORT"
    
    local total_tests=$(grep -c "###" "$VALIDATION_REPORT")
    local passed=$(grep -c "✅" "$VALIDATION_REPORT")
    local failed=$(grep -c "❌" "$VALIDATION_REPORT")
    local warnings=$(grep -c "⚠️" "$VALIDATION_REPORT")
    
    echo "- **Total Tests**: $total_tests" >> "$VALIDATION_REPORT"
    echo "- **Passed**: $passed" >> "$VALIDATION_REPORT"
    echo "- **Failed**: $failed" >> "$VALIDATION_REPORT"
    echo "- **Warnings**: $warnings" >> "$VALIDATION_REPORT"
    
    echo "" >> "$VALIDATION_REPORT"
    echo "## Recommendations" >> "$VALIDATION_REPORT"
    
    if [ $failed -gt 0 ]; then
        echo "1. **Critical**: Fix masking failures to prevent data leakage" >> "$VALIDATION_REPORT"
    fi
    
    if [ $warnings -gt 0 ]; then
        echo "2. Review edge cases with warnings for potential improvements" >> "$VALIDATION_REPORT"
    fi
    
    echo "3. Monitor Redis connection stability for consistent masking" >> "$VALIDATION_REPORT"
    echo "4. Implement automated masking validation in CI/CD pipeline" >> "$VALIDATION_REPORT"
}

# Main execution
main() {
    echo -e "${YELLOW}Starting AWS Resource Masking Validation${NC}\n"
    
    init_report
    
    # Run individual resource tests
    for resource_type in "${!TEST_RESOURCES[@]}"; do
        test_resource_masking "$resource_type" "${TEST_RESOURCES[$resource_type]}"
    done
    
    # Run combined tests
    test_multiple_resources
    test_edge_cases
    test_consistency
    test_performance
    
    # Generate summary
    generate_summary
    
    echo -e "\n${GREEN}Validation complete!${NC}"
    echo "Report saved to: $VALIDATION_REPORT"
    
    # Display summary
    echo -e "\n${YELLOW}Summary:${NC}"
    tail -n 15 "$VALIDATION_REPORT" | grep -E "(Total|Passed|Failed|Warning)"
}

# Check if services are running
if ! curl -s -o /dev/null -w "%{http_code}" "$PROXY_URL/health" | grep -q "200"; then
    echo -e "${RED}Error: Services not accessible at $PROXY_URL${NC}"
    echo "Please ensure docker-compose services are running"
    exit 1
fi

# Execute main
main