#!/bin/bash

# Comprehensive Test Runner for Kong AWS Masking
# Runs all test suites and generates a consolidated report

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
LOG_DIR="/app/logs"
RESULTS_DIR="/app/test-results"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
SUMMARY_FILE="$RESULTS_DIR/test-summary-${TIMESTAMP}.md"

# Create directories
mkdir -p "$LOG_DIR" "$RESULTS_DIR"

# Initialize summary
echo "# Kong AWS Masking Test Summary" > "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "**Date:** $(date +'%Y-%m-%d %H:%M:%S')" >> "$SUMMARY_FILE"
echo "**Environment:** ${NODE_ENV:-test}" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Function to run test and capture results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_description="$3"
    
    echo -e "${BLUE}Running: $test_name${NC}"
    echo "## $test_name" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "$test_description" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    local start_time=$(date +%s)
    local test_log="$LOG_DIR/${test_name// /-}-${TIMESTAMP}.log"
    
    if $test_command > "$test_log" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${GREEN}✓ $test_name completed successfully (${duration}s)${NC}"
        echo "**Status:** ✅ PASSED (${duration}s)" >> "$SUMMARY_FILE"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${RED}✗ $test_name failed (${duration}s)${NC}"
        echo "**Status:** ❌ FAILED (${duration}s)" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        echo "**Error Output:**" >> "$SUMMARY_FILE"
        echo '```' >> "$SUMMARY_FILE"
        tail -n 20 "$test_log" >> "$SUMMARY_FILE"
        echo '```' >> "$SUMMARY_FILE"
    fi
    
    echo "" >> "$SUMMARY_FILE"
    echo "---" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
}

# Main execution
main() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}Kong AWS Masking Comprehensive Test Suite${NC}"
    echo -e "${PURPLE}========================================${NC}"
    echo ""
    
    # Check prerequisites
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo -e "${RED}ERROR: ANTHROPIC_API_KEY environment variable is required${NC}"
        exit 1
    fi
    
    # Test 1: AWS Pattern Validation
    run_test \
        "AWS Pattern Validation" \
        "node /app/scripts/aws-pattern-validation.js" \
        "Validates all AWS resource patterns match expected formats and masking works correctly."
    
    # Test 2: Unit Test Scenarios
    run_test \
        "Test Scenarios Execution" \
        "node /app/scripts/run-test-scenarios.js" \
        "Executes all JSON test scenarios for EC2, S3, RDS, VPC, IAM, and mixed resources."
    
    # Test 3: Basic Masking Validation
    run_test \
        "Basic Masking Validation" \
        "/app/scripts/validate-masking.sh" \
        "Quick validation of core masking functionality through the API."
    
    # Test 4: End-to-End Integration
    run_test \
        "End-to-End Integration Test" \
        "/app/scripts/e2e-integration-test.sh" \
        "Tests the complete flow from client through nginx, kong, backend to Claude API."
    
    # Test 5: Performance Benchmark
    echo -e "${BLUE}Running: Performance Benchmark${NC}"
    echo "## Performance Benchmark" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Simple performance test
    local perf_start=$(date +%s%N)
    for i in {1..5}; do
        curl -s -X POST "http://nginx:8082/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d '{
                "model": "claude-3-5-sonnet-20241022",
                "max_tokens": 100,
                "messages": [{"role": "user", "content": "Quick test for i-1234567890abcdef0"}]
            }' > /dev/null
    done
    local perf_end=$(date +%s%N)
    local avg_time=$(( (perf_end - perf_start) / 5000000 )) # Convert to ms and divide by 5
    
    echo -e "${GREEN}✓ Average response time: ${avg_time}ms${NC}"
    echo "**Average Response Time:** ${avg_time}ms (5 requests)" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "---" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Generate final summary
    echo "" >> "$SUMMARY_FILE"
    echo "## Test Artifacts" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "- Logs: \`$LOG_DIR/\`" >> "$SUMMARY_FILE"
    echo "- Results: \`$RESULTS_DIR/\`" >> "$SUMMARY_FILE"
    echo "- Pattern validation: \`$RESULTS_DIR/pattern-validation-*.json\`" >> "$SUMMARY_FILE"
    echo "- Test scenarios: \`$RESULTS_DIR/test-results-*.json\`" >> "$SUMMARY_FILE"
    echo "- E2E report: \`$RESULTS_DIR/e2e-test-report-*.md\`" >> "$SUMMARY_FILE"
    
    # Display summary
    echo ""
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}Test Summary${NC}"
    echo -e "${PURPLE}========================================${NC}"
    echo ""
    
    # Count results
    local passed=$(grep -c "✅ PASSED" "$SUMMARY_FILE" || true)
    local failed=$(grep -c "❌ FAILED" "$SUMMARY_FILE" || true)
    local total=$((passed + failed))
    
    echo "Total Tests: $total"
    echo -e "Passed: ${GREEN}$passed${NC}"
    echo -e "Failed: ${RED}$failed${NC}"
    
    if [ $failed -eq 0 ]; then
        echo ""
        echo -e "${GREEN}🎉 All tests passed successfully!${NC}"
        echo ""
        echo "## Overall Result" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        echo "🎉 **ALL TESTS PASSED**" >> "$SUMMARY_FILE"
    else
        echo ""
        echo -e "${RED}⚠️  Some tests failed. Check the summary for details.${NC}"
        echo ""
        echo "## Overall Result" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        echo "⚠️  **SOME TESTS FAILED**" >> "$SUMMARY_FILE"
    fi
    
    echo ""
    echo "Summary report: $SUMMARY_FILE"
    echo ""
    
    # Exit with appropriate code
    exit $failed
}

# Run main function
main "$@"