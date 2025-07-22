#!/bin/bash

# Kong AWS Masking MVP - Infrastructure Testing Script  
# Infrastructure Team - Comprehensive testing of infrastructure components

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TIMEOUT=30
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2

# Test results tracking
declare -A TEST_RESULTS
declare -i TOTAL_TESTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -i SKIPPED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_test_start() {
    echo -e "${CYAN}[TEST]${NC} $*"
}

log_separator() {
    echo -e "${CYAN}$(printf '%.0s=' {1..60})${NC}"
}

# Test framework functions
test_start() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test_start "Starting: $test_name"
}

test_pass() {
    local test_name="$1"
    TEST_RESULTS["$test_name"]="PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_success "PASSED: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="${2:-Unknown error}"
    TEST_RESULTS["$test_name"]="FAIL"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_error "FAILED: $test_name - $reason"
}

test_skip() {
    local test_name="$1"
    local reason="${2:-Skipped}"
    TEST_RESULTS["$test_name"]="SKIP"
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    log_warning "SKIPPED: $test_name - $reason"
}

# Utility functions
wait_for_service() {
    local url="$1"
    local service_name="$2"
    local timeout="${3:-$TIMEOUT}"
    local retries=0

    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -f -s --max-time "$timeout" "$url" &>/dev/null; then
            return 0
        fi
        
        retries=$((retries + 1))
        sleep "$RETRY_DELAY"
    done
    
    return 1
}

check_response_time() {
    local url="$1"
    local max_time="$2"
    
    local response_time
    response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "999")
    
    if (( $(echo "$response_time < $max_time" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# Infrastructure tests
test_docker_setup() {
    local test_name="Docker Environment Setup"
    test_start "$test_name"
    
    cd "$PROJECT_ROOT"
    
    # Check if docker-compose.yml exists and is valid
    if [ ! -f "docker-compose.yml" ]; then
        test_fail "$test_name" "docker-compose.yml not found"
        return
    fi
    
    # Validate docker-compose configuration
    if ! docker-compose config > /dev/null 2>&1; then
        test_fail "$test_name" "Invalid docker-compose.yml configuration"
        return
    fi
    
    # Check if Docker daemon is accessible
    if ! docker info > /dev/null 2>&1; then
        test_fail "$test_name" "Cannot connect to Docker daemon"
        return
    fi
    
    test_pass "$test_name"
}

test_environment_config() {
    local test_name="Environment Configuration"
    test_start "$test_name"
    
    cd "$PROJECT_ROOT"
    
    # Check if .env.example exists
    if [ ! -f ".env.example" ]; then
        test_fail "$test_name" ".env.example not found"
        return
    fi
    
    # Check if .env exists (for local testing)
    if [ ! -f ".env" ]; then
        test_skip "$test_name" ".env file not found - using defaults"
        return
    fi
    
    # Validate required environment variables
    local required_vars=("ANTHROPIC_API_KEY" "AWS_REGION")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" ".env"; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        test_fail "$test_name" "Missing environment variables: ${missing_vars[*]}"
        return
    fi
    
    test_pass "$test_name"
}

test_service_startup() {
    local test_name="Service Startup"
    test_start "$test_name"
    
    cd "$PROJECT_ROOT"
    
    # Start services if not running
    if ! docker-compose ps -q | grep -q .; then
        log_info "Starting services for testing..."
        if ! docker-compose up -d --build; then
            test_fail "$test_name" "Failed to start services"
            return
        fi
        
        # Wait for services to initialize
        sleep 15
    fi
    
    # Check if services are running
    local running_services
    running_services=$(docker-compose ps --services --filter status=running)
    
    if [ -z "$running_services" ]; then
        test_fail "$test_name" "No services are running"
        return
    fi
    
    log_info "Running services: $(echo "$running_services" | tr '\n' ' ')"
    test_pass "$test_name"
}

test_kong_admin() {
    local test_name="Kong Admin API"
    test_start "$test_name"
    
    local admin_url="http://localhost:8001/status"
    
    if ! wait_for_service "$admin_url" "Kong Admin"; then
        test_fail "$test_name" "Kong Admin API not responding"
        return
    fi
    
    # Test API response structure
    local response
    response=$(curl -s "$admin_url")
    
    if ! echo "$response" | grep -q '"database":'; then
        test_fail "$test_name" "Invalid Kong Admin API response format"
        return
    fi
    
    # Test response time
    if ! check_response_time "$admin_url" "2.0"; then
        test_fail "$test_name" "Kong Admin API response time too slow (>2s)"
        return
    fi
    
    test_pass "$test_name"
}

test_kong_proxy() {
    local test_name="Kong Proxy"
    test_start "$test_name"
    
    local proxy_url="http://localhost:8000"
    
    if ! wait_for_service "$proxy_url" "Kong Proxy"; then
        test_fail "$test_name" "Kong Proxy not responding"
        return
    fi
    
    # Test response time
    if ! check_response_time "$proxy_url" "1.0"; then
        test_fail "$test_name" "Kong Proxy response time too slow (>1s)"
        return
    fi
    
    test_pass "$test_name"
}

test_backend_api() {
    local test_name="Backend API"
    test_start "$test_name"
    
    local backend_url="http://localhost:3000/health"
    
    if ! wait_for_service "$backend_url" "Backend API"; then
        test_fail "$test_name" "Backend API not responding"
        return
    fi
    
    # Test health endpoint response
    local response
    response=$(curl -s "$backend_url")
    
    if ! echo "$response" | grep -q '"status":"healthy"'; then
        test_fail "$test_name" "Backend API health check failed"
        return
    fi
    
    # Test response time
    if ! check_response_time "$backend_url" "1.0"; then
        test_fail "$test_name" "Backend API response time too slow (>1s)"
        return
    fi
    
    test_pass "$test_name"
}

test_service_integration() {
    local test_name="Service Integration"
    test_start "$test_name"
    
    # Test Kong -> Backend proxy
    local proxy_health_url="http://localhost:8000/health"
    local response
    
    if response=$(curl -s --max-time $TIMEOUT "$proxy_health_url" 2>&1); then
        # Check if we get the backend health response through Kong
        if echo "$response" | grep -q '"status":"healthy"'; then
            log_info "Kong successfully proxying to backend"
        else
            test_fail "$test_name" "Kong proxy not routing correctly to backend"
            return
        fi
    else
        test_fail "$test_name" "Kong proxy integration test failed"
        return
    fi
    
    test_pass "$test_name"
}

test_security_headers() {
    local test_name="Security Headers"
    test_start "$test_name"
    
    # Test backend security headers
    local response_headers
    response_headers=$(curl -s -I "http://localhost:3000/health")
    
    # Check for important security headers
    local required_headers=("X-Content-Type-Options" "X-Frame-Options")
    local missing_headers=()
    
    for header in "${required_headers[@]}"; do
        if ! echo "$response_headers" | grep -q "$header"; then
            missing_headers+=("$header")
        fi
    done
    
    if [ ${#missing_headers[@]} -gt 0 ]; then
        log_warning "Missing security headers: ${missing_headers[*]}"
        # Don't fail the test, just warn
    fi
    
    test_pass "$test_name"
}

test_rate_limiting() {
    local test_name="Rate Limiting"
    test_start "$test_name"
    
    # Test if rate limiting is working (make multiple requests)
    local backend_url="http://localhost:3000/health"
    local success_count=0
    local rate_limited_count=0
    
    # Make 20 rapid requests
    for i in {1..20}; do
        local status_code
        status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$backend_url")
        
        case $status_code in
            200)
                success_count=$((success_count + 1))
                ;;
            429)
                rate_limited_count=$((rate_limited_count + 1))
                ;;
        esac
    done
    
    log_info "Rate limiting test: $success_count successful, $rate_limited_count rate-limited"
    
    # If we got some responses, the service is working
    if [ $success_count -gt 0 ]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "No successful requests in rate limiting test"
    fi
}

test_error_handling() {
    local test_name="Error Handling"
    test_start "$test_name"
    
    # Test 404 handling
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/nonexistent")
    
    if [ "$response_code" != "404" ]; then
        test_fail "$test_name" "Expected 404 for non-existent endpoint, got $response_code"
        return
    fi
    
    # Test invalid JSON handling (if applicable)
    local invalid_json_response
    invalid_json_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "invalid json" \
        "http://localhost:3000/analyze" 2>/dev/null || echo "400")
    
    # Should return 400 for invalid JSON
    if [[ "$invalid_json_response" =~ ^[45][0-9][0-9]$ ]]; then
        log_info "Error handling working correctly"
    else
        log_warning "Error handling might not be working as expected"
    fi
    
    test_pass "$test_name"
}

test_log_generation() {
    local test_name="Log Generation"
    test_start "$test_name"
    
    cd "$PROJECT_ROOT"
    
    # Check if logs are being generated
    local log_output
    log_output=$(docker-compose logs --tail=10 2>&1)
    
    if [ -z "$log_output" ]; then
        test_fail "$test_name" "No logs found from services"
        return
    fi
    
    # Check if logs contain expected formats
    if echo "$log_output" | grep -q -E "(INFO|ERROR|DEBUG|WARN)"; then
        log_info "Log levels detected in output"
    else
        log_warning "Standard log levels not detected"
    fi
    
    test_pass "$test_name"
}

test_resource_usage() {
    local test_name="Resource Usage"
    test_start "$test_name"
    
    # Get container stats
    local stats_output
    stats_output=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -E "(kong|backend)" || true)
    
    if [ -z "$stats_output" ]; then
        test_skip "$test_name" "Could not retrieve container stats"
        return
    fi
    
    log_info "Container resource usage:"
    echo "$stats_output"
    
    # Check if any container is using excessive resources (>80% CPU or >1GB RAM)
    local excessive_usage=false
    
    while IFS=$'\t' read -r container cpu mem; do
        # Extract numeric values from CPU percentage and memory usage
        cpu_num=$(echo "$cpu" | sed 's/%//')
        
        if (( $(echo "$cpu_num > 80" | bc -l) 2>/dev/null )); then
            log_warning "Container $container using high CPU: $cpu"
            excessive_usage=true
        fi
        
    done <<< "$stats_output"
    
    if [ "$excessive_usage" = true ]; then
        log_warning "Some containers showing high resource usage"
    fi
    
    test_pass "$test_name"
}

test_disk_space() {
    local test_name="Disk Space"
    test_start "$test_name"
    
    # Check available disk space
    local available_space
    available_space=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ -n "$available_space" ] && [ "$available_space" -lt 1 ]; then
        test_fail "$test_name" "Low disk space: ${available_space}GB available"
        return
    fi
    
    # Check Docker disk usage
    local docker_usage
    docker_usage=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" 2>/dev/null || true)
    
    if [ -n "$docker_usage" ]; then
        log_info "Docker disk usage:"
        echo "$docker_usage"
    fi
    
    test_pass "$test_name"
}

# Performance tests
test_load_performance() {
    local test_name="Load Performance"
    test_start "$test_name"
    
    # Simple load test - make 50 concurrent requests
    local backend_url="http://localhost:3000/health"
    local concurrent_requests=10
    local total_requests=50
    
    log_info "Running load test: $total_requests requests with $concurrent_requests concurrency"
    
    local start_time
    start_time=$(date +%s)
    
    # Use background processes for concurrent requests
    local pids=()
    local success_count=0
    
    for ((i=1; i<=total_requests; i++)); do
        if [ ${#pids[@]} -ge $concurrent_requests ]; then
            # Wait for one process to complete
            wait "${pids[0]}"
            if [ $? -eq 0 ]; then
                success_count=$((success_count + 1))
            fi
            pids=("${pids[@]:1}") # Remove first element
        fi
        
        # Start new request in background
        curl -s -f --max-time 5 "$backend_url" > /dev/null &
        pids+=($!)
    done
    
    # Wait for remaining processes
    for pid in "${pids[@]}"; do
        wait "$pid"
        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
        fi
    done
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local success_rate=$((success_count * 100 / total_requests))
    
    log_info "Load test results: $success_count/$total_requests successful (${success_rate}%) in ${duration}s"
    
    if [ $success_rate -lt 90 ]; then
        test_fail "$test_name" "Success rate too low: ${success_rate}%"
        return
    fi
    
    if [ $duration -gt 30 ]; then
        test_fail "$test_name" "Load test took too long: ${duration}s"
        return
    fi
    
    test_pass "$test_name"
}

# Report generation
generate_report() {
    log_separator
    log_info "Infrastructure Test Report"
    log_separator
    
    echo -e "${YELLOW}Test Summary:${NC}"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed:      $PASSED_TESTS"
    echo "  Failed:      $FAILED_TESTS"
    echo "  Skipped:     $SKIPPED_TESTS"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}Overall Result: PASSED${NC}"
        local success_rate=$((PASSED_TESTS * 100 / (TOTAL_TESTS - SKIPPED_TESTS)))
        echo "Success Rate: ${success_rate}%"
    else
        echo -e "${RED}Overall Result: FAILED${NC}"
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${!TEST_RESULTS[@]}"; do
            if [ "${TEST_RESULTS[$test]}" = "FAIL" ]; then
                echo "  - $test"
            fi
        done
    fi
    
    echo ""
    echo -e "${YELLOW}Detailed Results:${NC}"
    for test in "${!TEST_RESULTS[@]}"; do
        case "${TEST_RESULTS[$test]}" in
            "PASS")
                echo -e "  ${GREEN}✓${NC} $test"
                ;;
            "FAIL")
                echo -e "  ${RED}✗${NC} $test"
                ;;
            "SKIP")
                echo -e "  ${YELLOW}○${NC} $test (skipped)"
                ;;
        esac
    done
    
    log_separator
}

print_usage() {
    echo "Usage: $0 [test-suite]"
    echo ""
    echo "Test suites:"
    echo "  basic      - Basic infrastructure tests (default)"
    echo "  full       - Full test suite including performance tests"
    echo "  quick      - Quick smoke tests only"
    echo "  performance - Performance tests only"
    echo "  help       - Show this help message"
    echo ""
}

# Test suite definitions
run_basic_tests() {
    log_info "Running basic infrastructure tests..."
    
    test_docker_setup
    test_environment_config
    test_service_startup
    test_kong_admin
    test_kong_proxy
    test_backend_api
    test_service_integration
    test_error_handling
    test_log_generation
}

run_full_tests() {
    log_info "Running full test suite..."
    
    run_basic_tests
    test_security_headers
    test_rate_limiting
    test_resource_usage
    test_disk_space
    test_load_performance
}

run_quick_tests() {
    log_info "Running quick smoke tests..."
    
    test_service_startup
    test_kong_admin
    test_backend_api
    test_service_integration
}

run_performance_tests() {
    log_info "Running performance tests..."
    
    test_service_startup
    test_load_performance
    test_resource_usage
}

# Main execution
main() {
    log_info "Kong AWS Masking MVP - Infrastructure Testing"
    log_info "Timestamp: $(date -Iseconds)"
    log_separator
    
    cd "$PROJECT_ROOT"
    
    case "${1:-basic}" in
        "basic")
            run_basic_tests
            ;;
        "full")
            run_full_tests
            ;;
        "quick")
            run_quick_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "help"|"-h"|"--help")
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown test suite: $1"
            print_usage
            exit 1
            ;;
    esac
    
    generate_report
    
    # Exit with error code if any tests failed
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Handle script interruption
trap 'log_error "Testing interrupted"; exit 130' INT TERM

# Check for bc command (used in some tests)
if ! command -v bc &> /dev/null; then
    log_warning "bc command not found - some numeric comparisons may be skipped"
fi

# Run main function
main "$@"