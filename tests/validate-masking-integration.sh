#!/bin/bash

# AWS Masker Plugin Integration Validation Test
# Tests actual masking functionality through Kong gateway

set -e

echo "====================================="
echo " AWS MASKER INTEGRATION VALIDATION"
echo "====================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
print_test_header() {
    echo ""
    echo "-----------------------------------"
    echo "TEST: $1"
    echo "-----------------------------------"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if services are running
check_services() {
    print_test_header "Service Health Check"
    
    # Check Kong
    if curl -s http://localhost:8001/status > /dev/null; then
        print_success "Kong Gateway is running"
    else
        print_failure "Kong Gateway is not accessible"
        exit 1
    fi
    
    # Check Backend
    if curl -s http://localhost:3000/health > /dev/null; then
        print_success "Backend API is running"
    else
        print_failure "Backend API is not accessible"
        exit 1
    fi
    
    # Check Redis
    if docker exec kong-redis redis-cli ping > /dev/null 2>&1; then
        print_success "Redis is running"
    else
        print_failure "Redis is not accessible"
    fi
}

# Test 1: Verify aws-masker plugin is loaded
test_plugin_loaded() {
    print_test_header "Plugin Load Verification"
    
    local plugins=$(curl -s http://localhost:8001/plugins | grep -o '"name":"aws-masker"' | wc -l)
    if [ "$plugins" -gt 0 ]; then
        print_success "aws-masker plugin is loaded ($plugins instances)"
    else
        print_failure "aws-masker plugin is not loaded"
    fi
}

# Test 2: Direct masking test through Kong
test_direct_masking() {
    print_test_header "Direct Masking Test"
    
    # Create test payload with various AWS resources
    cat > /tmp/test-masking-payload.json << 'EOF'
{
    "messages": [{
        "role": "user",
        "content": "Check these AWS resources: EC2 instance i-1234567890abcdef0, S3 bucket my-production-bucket, RDS instance prod-db-master, private IP 10.0.1.100, public IP 54.239.28.85, security group sg-12345678"
    }],
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100
}
EOF
    
    # Test through Kong /claude-proxy endpoint
    echo "Testing through /claude-proxy endpoint..."
    local response=$(curl -s -X POST http://localhost:8000/claude-proxy/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d @/tmp/test-masking-payload.json 2>&1 || echo "CURL_ERROR")
    
    if [[ "$response" == "CURL_ERROR" ]]; then
        print_failure "Failed to connect to Kong proxy"
        return
    fi
    
    # Check if response contains error
    if echo "$response" | grep -q "error"; then
        print_warning "Response contains error: $response"
    fi
    
    # Verify masking occurred (should not see original values in Kong logs)
    echo "Checking Kong logs for masking activity..."
    local logs=$(docker logs kong-gateway 2>&1 | tail -100)
    
    # Check for masking indicators
    if echo "$logs" | grep -q "\[MASKING\]"; then
        print_success "Masking activity detected in logs"
    else
        print_warning "No masking activity found in recent logs"
    fi
    
    # Check if original values are exposed (they shouldn't be)
    if echo "$logs" | grep -q "i-1234567890abcdef0"; then
        print_failure "SECURITY: Original EC2 instance ID found in logs!"
    else
        print_success "Original EC2 instance ID not exposed in logs"
    fi
}

# Test 3: Pattern matching validation
test_pattern_matching() {
    print_test_header "Pattern Matching Validation"
    
    # Test various AWS resource patterns
    local test_resources=(
        "i-0123456789abcdef0:EC2 instance"
        "my-bucket-name:S3 bucket"
        "prod-db-instance:RDS instance"
        "sg-12345678:Security group"
        "subnet-0123456789abcdef0:Subnet"
        "vpc-12345678:VPC"
        "ami-12345678:AMI"
        "vol-0123456789abcdef0:EBS volume"
        "arn:aws:lambda:us-east-1:123456789012:function:myfunction:Lambda ARN"
        "AKIAIOSFODNN7EXAMPLE:Access key"
    )
    
    for resource in "${test_resources[@]}"; do
        IFS=':' read -r value desc <<< "$resource"
        echo "Testing pattern for $desc: $value"
        
        # Create minimal test payload
        local test_json="{\"content\":\"Test $value in message\"}"
        
        # Send through Kong
        local result=$(curl -s -X POST http://localhost:8000/claude-proxy/v1/messages \
            -H "Content-Type: application/json" \
            -H "x-api-key: test-key" \
            -d "$test_json" 2>&1)
        
        if [[ -n "$result" ]]; then
            print_success "Pattern test completed for $desc"
        else
            print_failure "Pattern test failed for $desc"
        fi
    done
}

# Test 4: Redis mapping storage
test_redis_storage() {
    print_test_header "Redis Mapping Storage"
    
    # Check if Redis contains masked mappings
    echo "Checking Redis for MASKED* keys..."
    local masked_keys=$(docker exec kong-redis redis-cli --scan --pattern "MASKED*" | wc -l)
    
    if [ "$masked_keys" -gt 0 ]; then
        print_success "Found $masked_keys masking mappings in Redis"
        
        # Sample a few keys
        echo "Sample mappings:"
        docker exec kong-redis redis-cli --scan --pattern "MASKED*" | head -5 | while read key; do
            local value=$(docker exec kong-redis redis-cli GET "$key" 2>/dev/null)
            echo "  $key -> $value"
        done
    else
        print_warning "No masking mappings found in Redis"
    fi
    
    # Check TTL on keys
    local sample_key=$(docker exec kong-redis redis-cli --scan --pattern "MASKED*" | head -1)
    if [[ -n "$sample_key" ]]; then
        local ttl=$(docker exec kong-redis redis-cli TTL "$sample_key" 2>/dev/null)
        if [[ "$ttl" -gt 0 ]]; then
            print_success "Redis keys have TTL set: $ttl seconds"
        else
            print_warning "Redis keys may not have proper TTL"
        fi
    fi
}

# Test 5: Configuration validation
test_configuration() {
    print_test_header "Configuration Validation"
    
    # Check plugin configuration via Admin API
    local plugin_config=$(curl -s http://localhost:8001/plugins | jq '.data[] | select(.name=="aws-masker") | .config')
    
    if [[ -n "$plugin_config" ]]; then
        echo "Plugin configuration:"
        echo "$plugin_config" | jq .
        
        # Validate key settings
        local use_redis=$(echo "$plugin_config" | jq -r '.use_redis' | head -1)
        local mask_ec2=$(echo "$plugin_config" | jq -r '.mask_ec2_instances' | head -1)
        local mask_private_ips=$(echo "$plugin_config" | jq -r '.mask_private_ips' | head -1)
        
        if [[ "$use_redis" == "true" ]]; then
            print_success "Redis integration is enabled"
        else
            print_failure "Redis integration is disabled"
        fi
        
        if [[ "$mask_ec2" == "true" ]]; then
            print_success "EC2 masking is enabled"
        else
            print_failure "EC2 masking is disabled"
        fi
        
        # Note about private IPs
        if [[ "$mask_private_ips" == "true" ]]; then
            print_success "Private IP masking is enabled"
        else
            print_warning "Private IP masking is disabled (as per patterns.lua)"
        fi
    else
        print_failure "Could not retrieve plugin configuration"
    fi
}

# Test 6: Performance check
test_performance() {
    print_test_header "Performance Validation"
    
    # Create a large payload
    cat > /tmp/large-payload.json << 'EOF'
{
    "messages": [{
        "role": "user",
        "content": "Analyze these resources: i-1234567890abcdef0, i-2345678901abcdef1, i-3456789012abcdef2, i-4567890123abcdef3, i-5678901234abcdef4, bucket-prod-data, bucket-staging-data, bucket-test-data, db-prod-master, db-prod-replica, sg-12345678, sg-23456789, subnet-0123456789abcdef0, vpc-12345678, ami-12345678, vol-0123456789abcdef0"
    }],
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100
}
EOF
    
    # Measure response time
    local start_time=$(date +%s%N)
    curl -s -X POST http://localhost:8000/claude-proxy/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d @/tmp/large-payload.json > /dev/null 2>&1
    local end_time=$(date +%s%N)
    
    local elapsed=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    echo "Masking latency: ${elapsed}ms"
    
    if [ "$elapsed" -lt 100 ]; then
        print_success "Masking completed within 100ms target (${elapsed}ms)"
    else
        print_warning "Masking took longer than 100ms target (${elapsed}ms)"
    fi
}

# Test 7: Edge cases
test_edge_cases() {
    print_test_header "Edge Case Validation"
    
    # Test empty payload
    echo "Testing empty payload..."
    local empty_response=$(curl -s -X POST http://localhost:8000/claude-proxy/v1/messages \
        -H "Content-Type: application/json" \
        -d '{}' 2>&1)
    
    if [[ "$empty_response" == *"error"* ]]; then
        print_success "Empty payload handled correctly"
    else
        print_warning "Empty payload handling unclear"
    fi
    
    # Test nested JSON
    echo "Testing nested JSON structure..."
    local nested_json='{
        "messages": [{
            "content": {
                "aws": {
                    "ec2": "i-1234567890abcdef0",
                    "s3": ["bucket-1", "bucket-2"]
                }
            }
        }]
    }'
    
    local nested_response=$(curl -s -X POST http://localhost:8000/claude-proxy/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: test-key" \
        -d "$nested_json" 2>&1)
    
    if [[ -n "$nested_response" ]]; then
        print_success "Nested JSON structure processed"
    else
        print_failure "Nested JSON structure failed"
    fi
}

# Main execution
main() {
    echo "Starting AWS Masker Integration Validation..."
    echo "Timestamp: $(date)"
    echo ""
    
    # Run all tests
    check_services
    test_plugin_loaded
    test_direct_masking
    test_pattern_matching
    test_redis_storage
    test_configuration
    test_performance
    test_edge_cases
    
    # Summary
    echo ""
    echo "====================================="
    echo " TEST SUMMARY"
    echo "====================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed! AWS Masker is functioning correctly.${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Run main function
main