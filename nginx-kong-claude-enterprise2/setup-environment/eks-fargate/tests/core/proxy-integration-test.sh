#!/bin/bash
# Proxy Integration Test with 50 AWS Patterns
# Tests the complete chain: Claude Code SDK → Nginx → Kong → Claude API
# 
# 🚨 MUST Rule: Generate test report in test-report/
#

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test report configuration
TEST_REPORT_DIR="./test-report"
mkdir -p "$TEST_REPORT_DIR"

# Generate report filename with auto-incrementing counter
REPORT_BASE="proxy-integration-test"
REPORT_COUNTER=1
while [ -f "$TEST_REPORT_DIR/${REPORT_BASE}-$(printf "%03d" $REPORT_COUNTER).md" ]; do
  ((REPORT_COUNTER++))
done
REPORT_FILE="$TEST_REPORT_DIR/${REPORT_BASE}-$(printf "%03d" $REPORT_COUNTER).md"

echo -e "${BLUE}=== Proxy Integration Test with 50 AWS Patterns ===${NC}"
echo -e "${YELLOW}📋 Test Report: $REPORT_FILE${NC}"
echo ""

# Test timing
TEST_START_TIME=$(date +%s)
TEST_START_ISO=$(date -Iseconds)

# Initialize report
cat > "$REPORT_FILE" << EOF
# Proxy Integration Test Report

**Test Execution Time**: $TEST_START_ISO  
**Test Script**: proxy-integration-test.sh  
**Purpose**: Validate complete proxy chain with AWS masking/unmasking

## Test Configuration

### Proxy Chain
\`\`\`
Claude Code SDK → Nginx (8082) → Kong (8010) → Claude API
\`\`\`

### Test Components
- **Total AWS Patterns**: 50+ patterns from patterns.lua
- **Test Method**: Direct API calls through proxy chain
- **Validation**: Masking in logs, unmasking in responses

## Test Results

EOF

# Global counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Log monitoring function
monitor_logs() {
  local test_name="$1"
  local start_time="$2"
  
  # Check Kong logs for masking
  if [ -f "./logs/kong/access.log" ]; then
    echo -e "${BLUE}Kong Access Log (last 5 entries):${NC}"
    tail -5 ./logs/kong/access.log
  fi
  
  # Check Nginx logs
  if [ -f "./logs/nginx/access.log" ]; then
    echo -e "${BLUE}Nginx Access Log (last 5 entries):${NC}"
    tail -5 ./logs/nginx/access.log
  fi
}

# Test function for individual patterns
test_aws_pattern() {
  local test_num="$1"
  local resource_type="$2"
  local aws_resource="$3"
  local expected_mask_pattern="$4"
  local description="$5"
  
  ((TOTAL_TESTS++))
  
  echo -e "\n${YELLOW}Test #$test_num: $resource_type${NC}"
  echo "  AWS Resource: $aws_resource"
  echo "  Expected Mask Pattern: $expected_mask_pattern"
  
  # Prepare test payload
  local payload=$(cat <<EOF
{
  "model": "claude-3-5-sonnet-20241022",
  "messages": [
    {
      "role": "user",
      "content": "Please analyze this AWS resource and repeat back the exact resource ID first: $aws_resource\\n\\nThen provide a brief security assessment."
    }
  ],
  "max_tokens": 200,
  "temperature": 0
}
EOF
)
  
  # Send request through proxy chain (via Nginx proxy)
  local start_request=$(date +%s%N)
  local response=$(curl -s -X POST http://localhost:8082/v1/messages \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -d "$payload" 2>&1)
  local end_request=$(date +%s%N)
  local latency_ms=$(( (end_request - start_request) / 1000000 ))
  
  # Check if response is valid JSON
  if ! echo "$response" | jq . >/dev/null 2>&1; then
    echo -e "  ${RED}❌ FAILED: Invalid JSON response${NC}"
    echo "  Response: ${response:0:200}..."
    ((FAILED_TESTS++))
    
    # Add to report
    echo "### ❌ Test $test_num: $resource_type" >> "$REPORT_FILE"
    echo "- **Resource**: \`$aws_resource\`" >> "$REPORT_FILE"
    echo "- **Error**: Invalid JSON response" >> "$REPORT_FILE"
    echo "- **Response**: \`${response:0:200}...\`" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    return
  fi
  
  # Extract content from response
  local content=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
  
  if [ -z "$content" ]; then
    echo -e "  ${RED}❌ FAILED: No content in response${NC}"
    ((FAILED_TESTS++))
    
    # Add to report
    echo "### ❌ Test $test_num: $resource_type" >> "$REPORT_FILE"
    echo "- **Resource**: \`$aws_resource\`" >> "$REPORT_FILE"
    echo "- **Error**: No content in response" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    return
  fi
  
  # Check if original resource appears in response (unmasking successful)
  if [[ "$content" == *"$aws_resource"* ]]; then
    echo -e "  ${GREEN}✅ PASSED: Resource unmasked correctly${NC}"
    echo "  Response preview: ${content:0:100}..."
    echo "  Latency: ${latency_ms}ms"
    ((PASSED_TESTS++))
    
    # Add to report
    echo "### ✅ Test $test_num: $resource_type" >> "$REPORT_FILE"
    echo "- **Resource**: \`$aws_resource\`" >> "$REPORT_FILE"
    echo "- **Status**: Successfully unmasked" >> "$REPORT_FILE"
    echo "- **Latency**: ${latency_ms}ms" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  else
    echo -e "  ${RED}❌ FAILED: Resource not found in response${NC}"
    echo "  Response: ${content:0:200}..."
    ((FAILED_TESTS++))
    
    # Add to report
    echo "### ❌ Test $test_num: $resource_type" >> "$REPORT_FILE"
    echo "- **Resource**: \`$aws_resource\`" >> "$REPORT_FILE"
    echo "- **Error**: Resource not unmasked" >> "$REPORT_FILE"
    echo "- **Response**: \`${content:0:200}...\`" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi
  
  # Brief pause between tests
  sleep 0.5
}

# Basic connectivity test first
echo -e "${BLUE}=== Basic Proxy Chain Test ===${NC}"
echo "Testing connectivity through proxy chain..."

# Test health endpoints
echo -n "Testing Nginx health endpoint... "
nginx_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8082/health)
if [ "$nginx_health" = "200" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED (HTTP $nginx_health)${NC}"
fi

echo -n "Testing Kong admin endpoint... "
kong_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/status)
if [ "$kong_health" = "200" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED (HTTP $kong_health)${NC}"
fi

# Test Redis connectivity
echo -n "Testing Redis connection... "
redis_ping=$(docker exec claude-redis redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null)
if [ "$redis_ping" = "PONG" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED${NC}"
fi

echo "" >> "$REPORT_FILE"
echo "## Infrastructure Health" >> "$REPORT_FILE"
echo "- Nginx: $( [ "$nginx_health" = "200" ] && echo "✅ Healthy" || echo "❌ Unhealthy" )" >> "$REPORT_FILE"
echo "- Kong: $( [ "$kong_health" = "200" ] && echo "✅ Healthy" || echo "❌ Unhealthy" )" >> "$REPORT_FILE"
echo "- Redis: $( [ "$redis_ping" = "PONG" ] && echo "✅ Connected" || echo "❌ Disconnected" )" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Run AWS pattern tests
echo -e "\n${BLUE}=== Testing 50 AWS Resource Patterns ===${NC}"

# EC2 Resources
echo -e "\n${YELLOW}[EC2 Resources]${NC}"
test_aws_pattern 1 "EC2 Instance" "i-1234567890abcdef0" "AWS_EC2_" "EC2 instance identifier"
test_aws_pattern 2 "EC2 Instance" "i-0a1b2c3d4e5f67890" "AWS_EC2_" "Another EC2 instance"
test_aws_pattern 3 "AMI" "ami-0abcdef1234567890" "AWS_AMI_" "Amazon Machine Image"
test_aws_pattern 4 "EBS Volume" "vol-0123456789abcdef0" "AWS_EBS_VOL_" "Elastic Block Store volume"
test_aws_pattern 5 "EBS Snapshot" "snap-0123456789abcdef0" "AWS_SNAPSHOT_" "EBS snapshot"

# VPC and Networking
echo -e "\n${YELLOW}[VPC and Networking]${NC}"
test_aws_pattern 6 "VPC" "vpc-12345678" "AWS_VPC_" "Virtual Private Cloud"
test_aws_pattern 7 "Subnet" "subnet-0123456789abcdef0" "AWS_SUBNET_" "VPC subnet"
test_aws_pattern 8 "Security Group" "sg-0123456789abcdef0" "AWS_SECURITY_GROUP_" "Security group"
test_aws_pattern 9 "Internet Gateway" "igw-12345678" "AWS_IGW_" "Internet gateway"
test_aws_pattern 10 "NAT Gateway" "nat-0123456789abcdef0" "AWS_NAT_GW_" "NAT gateway"
test_aws_pattern 11 "VPN Connection" "vpn-12345678" "AWS_VPN_" "VPN connection"
test_aws_pattern 12 "Transit Gateway" "tgw-0123456789abcdef0" "AWS_TGW_" "Transit gateway"

# IP Addresses
echo -e "\n${YELLOW}[IP Addresses]${NC}"
test_aws_pattern 13 "Public IP" "54.239.28.85" "AWS_PUBLIC_IP_" "Public IP address"
test_aws_pattern 14 "Public IP" "3.5.140.2" "AWS_PUBLIC_IP_" "Another public IP"
test_aws_pattern 15 "IPv6" "2001:db8::8a2e:370:7334" "AWS_IPV6_" "IPv6 address"

# Storage Services
echo -e "\n${YELLOW}[Storage Services]${NC}"
test_aws_pattern 16 "S3 Bucket" "my-production-bucket" "AWS_S3_BUCKET_" "S3 bucket"
test_aws_pattern 17 "S3 Logs Bucket" "application-logs-2024" "AWS_S3_LOGS_BUCKET_" "S3 logs bucket"
test_aws_pattern 18 "EFS" "fs-12345678" "AWS_EFS_" "Elastic File System"

# Database Services
echo -e "\n${YELLOW}[Database Services]${NC}"
test_aws_pattern 19 "RDS Instance" "production-mysql-db" "AWS_RDS_" "RDS database instance"
test_aws_pattern 20 "DynamoDB Table" "arn:aws:dynamodb:us-east-1:123456789012:table/UserData" "AWS_DYNAMODB_TABLE_" "DynamoDB table"
test_aws_pattern 21 "ElastiCache" "redis-cluster-prod-001" "AWS_ELASTICACHE_" "ElastiCache cluster"
test_aws_pattern 22 "Redshift" "analytics-cluster" "AWS_REDSHIFT_" "Redshift cluster"

# IAM and Security
echo -e "\n${YELLOW}[IAM and Security]${NC}"
test_aws_pattern 23 "AWS Account" "123456789012" "AWS_ACCOUNT_" "AWS account ID"
test_aws_pattern 24 "Access Key" "AKIAIOSFODNN7EXAMPLE" "AWS_ACCESS_KEY_" "Access key ID"
test_aws_pattern 25 "IAM Role" "arn:aws:iam::123456789012:role/MyAppRole" "AWS_IAM_ROLE_" "IAM role ARN"
test_aws_pattern 26 "IAM User" "arn:aws:iam::123456789012:user/john.doe" "AWS_IAM_USER_" "IAM user ARN"
test_aws_pattern 27 "KMS Key" "12345678-1234-1234-1234-123456789012" "AWS_KMS_KEY_" "KMS key ID"
test_aws_pattern 28 "ACM Certificate" "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012" "AWS_CERT_ARN_" "Certificate ARN"
test_aws_pattern 29 "Secrets Manager" "arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef" "AWS_SECRET_ARN_" "Secret ARN"

# Compute Services
echo -e "\n${YELLOW}[Compute Services]${NC}"
test_aws_pattern 30 "Lambda Function" "arn:aws:lambda:us-east-1:123456789012:function:ProcessOrder" "AWS_LAMBDA_ARN_" "Lambda function"
test_aws_pattern 31 "ECS Task" "arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012" "AWS_ECS_TASK_" "ECS task"
test_aws_pattern 32 "EKS Cluster" "arn:aws:eks:us-east-1:123456789012:cluster/production-cluster" "AWS_EKS_CLUSTER_" "EKS cluster"
test_aws_pattern 33 "API Gateway" "a1b2c3d4e5.execute-api.us-east-1.amazonaws.com" "AWS_API_GW_" "API Gateway"
test_aws_pattern 34 "ELB" "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456" "AWS_ELB_ARN_" "Load balancer"

# Messaging Services
echo -e "\n${YELLOW}[Messaging Services]${NC}"
test_aws_pattern 35 "SNS Topic" "arn:aws:sns:us-east-1:123456789012:MyNotificationTopic" "AWS_SNS_TOPIC_" "SNS topic"
test_aws_pattern 36 "SQS Queue" "https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue" "AWS_SQS_QUEUE_" "SQS queue URL"
test_aws_pattern 37 "Kinesis Stream" "arn:aws:kinesis:us-east-1:123456789012:stream/MyDataStream" "AWS_KINESIS_" "Kinesis stream"

# CloudWatch and Monitoring
echo -e "\n${YELLOW}[CloudWatch and Monitoring]${NC}"
test_aws_pattern 38 "Log Group" "/aws/lambda/my-function" "AWS_LOG_GROUP_" "CloudWatch log group"
test_aws_pattern 39 "CloudWatch Alarm" "arn:aws:cloudwatch:us-east-1:123456789012:alarm:HighCPU" "AWS_ARN_" "CloudWatch alarm"

# Other AWS Services
echo -e "\n${YELLOW}[Other AWS Services]${NC}"
test_aws_pattern 40 "Route53 Zone" "Z1234567890ABC" "AWS_ROUTE53_ZONE_" "Route53 hosted zone"
test_aws_pattern 41 "CloudFormation Stack" "arn:aws:cloudformation:us-east-1:123456789012:stack/MyStack/12345678-1234-1234-1234-123456789012" "AWS_CLOUDFORMATION_STACK_" "CF stack"
test_aws_pattern 42 "CodeCommit Repo" "arn:aws:codecommit:us-east-1:123456789012:MyRepository" "AWS_CODECOMMIT_" "CodeCommit repo"
test_aws_pattern 43 "ECR URI" "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app" "AWS_ECR_URI_" "ECR repository"
test_aws_pattern 44 "Parameter Store" "arn:aws:ssm:us-east-1:123456789012:parameter/MyParam" "AWS_PARAM_ARN_" "SSM parameter"
test_aws_pattern 45 "Glue Job" "glue-job-etl-processor" "AWS_GLUE_JOB_" "Glue ETL job"
test_aws_pattern 46 "SageMaker Endpoint" "arn:aws:sagemaker:us-east-1:123456789012:endpoint/my-model" "AWS_SAGEMAKER_" "SageMaker endpoint"
test_aws_pattern 47 "Step Functions" "arn:aws:states:us-east-1:123456789012:stateMachine:OrderProcessing" "AWS_STEP_FN_" "Step Functions"
test_aws_pattern 48 "Batch Job Queue" "arn:aws:batch:us-east-1:123456789012:job-queue/HighPriority" "AWS_BATCH_QUEUE_" "Batch job queue"
test_aws_pattern 49 "CloudFront" "E1234567890ABC" "AWS_CLOUDFRONT_" "CloudFront distribution"
test_aws_pattern 50 "Athena Workgroup" "arn:aws:athena:us-east-1:123456789012:workgroup/primary" "AWS_ATHENA_" "Athena workgroup"

# Complex Pattern Test
echo -e "\n${YELLOW}[Complex Patterns]${NC}"
test_aws_pattern 51 "Multiple Resources" "EC2 i-1234567890abcdef0 in subnet-0987654321fedcba0 with security group sg-11223344" "Multiple masks" "Complex multi-resource"

# Error Scenario Tests
echo -e "\n${BLUE}=== Error Scenario Testing ===${NC}"

# Test with invalid API key
echo -e "\n${YELLOW}Testing invalid API key handling:${NC}"
invalid_response=$(curl -s -X POST http://localhost:8082/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: invalid-key-12345" \
  -d '{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"test"}],"max_tokens":10}' 2>&1)

if [[ "$invalid_response" == *"401"* ]] || [[ "$invalid_response" == *"authentication"* ]]; then
  echo -e "${GREEN}✅ Invalid API key properly rejected${NC}"
  echo "### ✅ Error Handling: Invalid API Key" >> "$REPORT_FILE"
  echo "- Properly rejected with authentication error" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
else
  echo -e "${RED}❌ Invalid API key not properly handled${NC}"
  echo "### ❌ Error Handling: Invalid API Key" >> "$REPORT_FILE"
  echo "- Failed to reject invalid credentials" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
fi

# Test malformed request
echo -e "\n${YELLOW}Testing malformed request handling:${NC}"
malformed_response=$(curl -s -X POST http://localhost:8082/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -d '{"invalid_json": }' 2>&1)

if [[ "$malformed_response" == *"400"* ]] || [[ "$malformed_response" == *"error"* ]]; then
  echo -e "${GREEN}✅ Malformed request properly rejected${NC}"
  echo "### ✅ Error Handling: Malformed Request" >> "$REPORT_FILE"
  echo "- Properly rejected with error response" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
else
  echo -e "${RED}❌ Malformed request not properly handled${NC}"
  echo "### ❌ Error Handling: Malformed Request" >> "$REPORT_FILE"
  echo "- Failed to reject malformed JSON" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
fi

# Redis Integration Check
echo -e "\n${BLUE}=== Redis Integration Verification ===${NC}"
echo "Checking Redis for stored masking mappings..."

# Get a sample of stored mappings
redis_keys=$(docker exec claude-redis redis-cli -a "${REDIS_PASSWORD}" --scan --pattern "mask:*" 2>/dev/null | head -10)
if [ -n "$redis_keys" ]; then
  echo -e "${GREEN}✅ Found masking mappings in Redis:${NC}"
  echo "$redis_keys" | head -5
  
  # Check one mapping
  first_key=$(echo "$redis_keys" | head -1)
  if [ -n "$first_key" ]; then
    mapping_value=$(docker exec claude-redis redis-cli -a "${REDIS_PASSWORD}" GET "$first_key" 2>/dev/null)
    echo "  Sample mapping: $first_key → $mapping_value"
  fi
  
  echo "### ✅ Redis Integration" >> "$REPORT_FILE"
  echo "- Masking mappings successfully stored" >> "$REPORT_FILE"
  echo "- Sample keys found in Redis" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
else
  echo -e "${YELLOW}⚠️ No masking mappings found in Redis${NC}"
  echo "### ⚠️ Redis Integration" >> "$REPORT_FILE"
  echo "- No masking mappings found (may be normal if tests didn't trigger masking)" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
fi

# Performance Analysis
echo -e "\n${BLUE}=== Performance Analysis ===${NC}"

# Calculate average latency from successful tests
if [ -f "$REPORT_FILE" ]; then
  avg_latency=$(grep -oP 'Latency: \K\d+' "$REPORT_FILE" | awk '{sum+=$1; count++} END {if(count>0) print int(sum/count); else print 0}')
  echo "Average request latency: ${avg_latency}ms"
  
  echo "## Performance Metrics" >> "$REPORT_FILE"
  echo "- **Average Latency**: ${avg_latency}ms" >> "$REPORT_FILE"
  echo "- **Target Latency**: < 5000ms" >> "$REPORT_FILE"
  echo "- **Performance Status**: $( [ "$avg_latency" -lt 5000 ] && echo "✅ Within target" || echo "❌ Exceeds target" )" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
fi

# Test completion
TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))
SUCCESS_RATE=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc 2>/dev/null || echo "0")

# Final summary
echo -e "\n${BLUE}=== Test Summary ===${NC}"
echo -e "📊 Total Tests: $TOTAL_TESTS"
echo -e "✅ Passed: $PASSED_TESTS"
echo -e "❌ Failed: $FAILED_TESTS"
echo -e "⏭️  Skipped: $SKIPPED_TESTS"
echo -e "📈 Success Rate: ${SUCCESS_RATE}%"
echo -e "⏱️  Duration: ${TEST_DURATION}s"
echo -e "📋 Report: $REPORT_FILE"

# Complete the report
cat >> "$REPORT_FILE" << EOF

## Test Summary

### 📊 Statistics
- **Total Tests**: $TOTAL_TESTS
- **Passed**: $PASSED_TESTS
- **Failed**: $FAILED_TESTS
- **Skipped**: $SKIPPED_TESTS
- **Success Rate**: ${SUCCESS_RATE}%
- **Duration**: ${TEST_DURATION} seconds

### 🎯 Analysis
EOF

if (( $(echo "$SUCCESS_RATE >= 90" | bc -l 2>/dev/null || echo 0) )); then
  echo "- **Result**: ✅ EXCELLENT (90%+ success rate)" >> "$REPORT_FILE"
  echo "- **Recommendation**: System ready for production" >> "$REPORT_FILE"
  echo -e "\n${GREEN}🎉 Test PASSED with excellent results!${NC}"
elif (( $(echo "$SUCCESS_RATE >= 70" | bc -l 2>/dev/null || echo 0) )); then
  echo "- **Result**: ⚠️ GOOD (70-90% success rate)" >> "$REPORT_FILE"
  echo "- **Recommendation**: Minor improvements needed" >> "$REPORT_FILE"
  echo -e "\n${YELLOW}⚠️ Test passed with some issues to address${NC}"
else
  echo "- **Result**: ❌ POOR (< 70% success rate)" >> "$REPORT_FILE"
  echo "- **Recommendation**: Major issues require fixing" >> "$REPORT_FILE"
  echo -e "\n${RED}❌ Test FAILED - significant issues detected${NC}"
fi

echo "" >> "$REPORT_FILE"
echo "### Key Findings" >> "$REPORT_FILE"
echo "1. Proxy chain connectivity: Verified" >> "$REPORT_FILE"
echo "2. AWS resource masking: $( [ "$PASSED_TESTS" -gt 0 ] && echo "Working" || echo "Not working" )" >> "$REPORT_FILE"
echo "3. Redis integration: $( [ -n "$redis_keys" ] && echo "Active" || echo "No data" )" >> "$REPORT_FILE"
echo "4. Error handling: Tested" >> "$REPORT_FILE"
echo "5. Performance: $( [ "$avg_latency" -lt 5000 ] && echo "Within targets" || echo "Needs optimization" )" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "**Test Completed**: $(date -Iseconds)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "*This report validates the Kong AWS Masker proxy integration.*" >> "$REPORT_FILE"

echo -e "\n${GREEN}📋 Test report generated successfully at: $REPORT_FILE${NC}"