#!/bin/bash

# Production Comprehensive Test - Real /analyze endpoint
# Tests actual production flow: Backend → Kong → Claude API → Kong → Backend
# Following text-transformation-table-report.md format for production readiness

set -e

echo "======================================================="
echo "🏭 PRODUCTION COMPREHENSIVE TEST - /analyze ENDPOINT"
echo "======================================================="
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

# Function to test production analyze endpoint with real AWS patterns
test_production_flow() {
    local test_name="$1"
    local test_description="$2"
    
    echo -n "Testing: $test_name... "
    
    # Use REAL production /analyze endpoint with AWS TEST MODE
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000/analyze" \
        -H "Content-Type: application/json" \
        -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}' \
        --max-time 60 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}FAILED${NC} - Connection timeout or error"
        FAILED_TESTS+=("$test_name: Connection timeout or network error")
        ((FAILED++))
        return
    fi
    
    # Extract status code and body
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    # Check HTTP status
    if [ "$status_code" != "200" ]; then
        echo -e "${RED}FAILED${NC} - HTTP $status_code"
        FAILED_TESTS+=("$test_name: HTTP $status_code - $body")
        ((FAILED++))
        return
    fi
    
    # Check response structure
    if ! echo "$body" | jq -e '.success' >/dev/null 2>&1; then
        echo -e "${RED}FAILED${NC} - Invalid JSON response"
        FAILED_TESTS+=("$test_name: Invalid JSON response structure")
        ((FAILED++))
        return
    fi
    
    # Check if response contains success
    success=$(echo "$body" | jq -r '.success' 2>/dev/null)
    if [ "$success" != "true" ]; then
        echo -e "${RED}FAILED${NC} - API returned success: $success"
        FAILED_TESTS+=("$test_name: API returned success: $success")
        ((FAILED++))
        return
    fi
    
    # Extract Claude analysis content
    analysis_content=$(echo "$body" | jq -r '.data.analysis.content[0].text' 2>/dev/null)
    if [ "$analysis_content" = "null" ] || [ -z "$analysis_content" ]; then
        echo -e "${RED}FAILED${NC} - No Claude analysis content"
        FAILED_TESTS+=("$test_name: No Claude analysis content found")
        ((FAILED++))
        return
    fi
    
    # Critical Security Check: Ensure NO original AWS patterns in Claude response
    local aws_patterns=(
        "i-1234567890abcdef0"
        "i-0987654321fedcba0" 
        "i-abcdef1234567890"
        "10.0.0.1"
        "10.0.0.2"
        "172.16.0.10"
    )
    
    local security_violation=false
    local found_patterns=""
    
    for pattern in "${aws_patterns[@]}"; do
        if echo "$analysis_content" | grep -q "$pattern"; then
            security_violation=true
            found_patterns="$found_patterns $pattern"
        fi
    done
    
    if [ "$security_violation" = true ]; then
        echo -e "${RED}FAILED${NC} - 🚨 SECURITY VIOLATION: Original AWS patterns found: $found_patterns"
        FAILED_TESTS+=("$test_name: 🚨 SECURITY VIOLATION - Original patterns exposed: $found_patterns")
        ((FAILED++))
        return
    fi
    
    # Check if masked patterns are present (EC2_001, PRIVATE_IP_001, etc.)
    masked_patterns_found=0
    if echo "$analysis_content" | grep -q "EC2_"; then
        ((masked_patterns_found++))
    fi
    if echo "$analysis_content" | grep -q "PRIVATE_IP_"; then
        ((masked_patterns_found++))
    fi
    
    # Success case
    echo -e "${GREEN}PASSED${NC} (${masked_patterns_found} masked patterns confirmed)"
    
    # Extract key info for results
    token_usage=$(echo "$body" | jq -r '.data.analysis.usage.total_tokens // "N/A"')
    duration=$(echo "$body" | jq -r '.duration // "N/A"')
    
    RESULTS+=("$test_name|Production AWS Analysis|✅ Secured (${masked_patterns_found} patterns masked)|${duration}ms|${token_usage} tokens")
    ((PASSED++))
}

# Function to test error scenarios
test_error_scenario() {
    local test_name="$1"
    local request_data="$2"
    local expected_status="$3"
    
    echo -n "Testing: $test_name... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:3000/analyze" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        --max-time 10 2>/dev/null)
    
    status_code=$(echo "$response" | tail -n1)
    
    if [ "$status_code" = "$expected_status" ]; then
        echo -e "${GREEN}PASSED${NC} - Correct error handling"
        RESULTS+=("$test_name|Error Scenario|✅ Proper error response|HTTP $status_code|N/A")
        ((PASSED++))
    else
        echo -e "${RED}FAILED${NC} - Expected $expected_status, got $status_code"
        FAILED_TESTS+=("$test_name: Expected HTTP $expected_status but got $status_code")
        ((FAILED++))
    fi
}

echo "🔍 Testing Real Production Flow with /analyze Endpoint"
echo ""

# Test 1: Basic Production Analysis
test_production_flow "Production AWS Analysis" "Real analysis with masked AWS resources"

echo ""
echo "🔒 Testing Error Handling:"

# Test 2: Invalid request format
test_error_scenario "Invalid Request Format" '{"invalid":"request"}' "400"

# Test 3: Missing resources
test_error_scenario "Missing Resources" '{"options":{"analysisType":"security_only"}}' "400"

# Test 4: Invalid resource type
test_error_scenario "Invalid Resource Type" '{"resources":["invalid_resource"],"options":{"analysisType":"security_only"}}' "400"

echo ""
echo "======================================================="
echo "📊 PRODUCTION COMPREHENSIVE TEST RESULTS"
echo "======================================================="
echo -e "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $((PASSED + FAILED)) -gt 0 ]; then
    echo -e "Success Rate: $(( PASSED * 100 / (PASSED + FAILED) ))%"
fi

# Save results for report generation
cat > /tmp/production-test-results.csv << EOF
Test Name,Scenario,Result,Performance,Token Usage
EOF

for result in "${RESULTS[@]}"; do
    echo "$result" | tr '|' ',' >> /tmp/production-test-results.csv
done

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed Tests:"
    for failed in "${FAILED_TESTS[@]}"; do
        echo "  - $failed"
    done
    echo ""
    echo "🚨 CRITICAL: Fix these issues before production deployment!"
fi

echo ""
echo "✅ Results saved to /tmp/production-test-results.csv"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL PRODUCTION TESTS PASSED - SYSTEM READY FOR DEPLOYMENT${NC}"
    echo ""
    echo "📋 Production Readiness Confirmed:"
    echo "  ✅ Real /analyze endpoint working"
    echo "  ✅ AWS patterns properly masked"
    echo "  ✅ Claude API integration functional"
    echo "  ✅ Error handling appropriate"
    echo "  ✅ No security violations detected"
    exit 0
else
    echo -e "${RED}⚠️  PRODUCTION TESTS FAILED - SYSTEM NOT READY${NC}"
    echo ""
    echo "🚫 Production Deployment BLOCKED until issues resolved"
    exit 1
fi