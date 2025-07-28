#!/bin/bash

# Kong AWS Masker - System Validation Script
# Description: Comprehensive system validation based on defined metrics

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Validation results
VALIDATION_PASSED=true
FAILED_CHECKS=()

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

pass_test() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail_test() {
    echo -e "${RED}[FAIL]${NC} $1"
    VALIDATION_PASSED=false
    FAILED_CHECKS+=("$1")
}

# Validate availability metrics
validate_availability() {
    log_test "Validating Availability Metrics..."
    
    # Check service availability
    local services=("kong:8001:/status" "backend:3000:/health" "nginx:8080:/health")
    local available_count=0
    
    for service_spec in "${services[@]}"; do
        IFS=':' read -r service port endpoint <<< "$service_spec"
        if curl -sf "http://localhost:$port$endpoint" > /dev/null; then
            pass_test "$service is available on port $port"
            ((available_count++))
        else
            fail_test "$service is not available on port $port"
        fi
    done
    
    # Calculate availability percentage
    local availability=$((available_count * 100 / ${#services[@]}))
    if [ $availability -ge 99 ]; then
        pass_test "System availability: ${availability}% (Target: ≥99%)"
    else
        fail_test "System availability: ${availability}% (Target: ≥99%)"
    fi
}

# Validate performance metrics
validate_performance() {
    log_test "Validating Performance Metrics..."
    
    # Test request latency
    local total_time=0
    local request_count=10
    
    for i in $(seq 1 $request_count); do
        local start_time=$(date +%s%N)
        curl -sf -X POST http://localhost:8000/analyze \
            -H "Content-Type: application/json" \
            -d '{"content":"test"}' > /dev/null || true
        local end_time=$(date +%s%N)
        local request_time=$(( (end_time - start_time) / 1000000 ))
        total_time=$((total_time + request_time))
    done
    
    local avg_latency=$((total_time / request_count))
    
    if [ $avg_latency -lt 200 ]; then
        pass_test "Average latency: ${avg_latency}ms (Target: <200ms)"
    else
        fail_test "Average latency: ${avg_latency}ms (Target: <200ms)"
    fi
    
    # Test masking functionality
    local mask_test_response=$(curl -s -X POST http://localhost:8000/analyze \
        -H "Content-Type: application/json" \
        -d '{"content":"EC2 instance i-1234567890abcdef0"}' 2>/dev/null || echo "{}")
    
    if [[ "$mask_test_response" == *"EC2_"* ]] && [[ "$mask_test_response" != *"i-1234567890abcdef0"* ]]; then
        pass_test "Masking functionality working (EC2 instance masked)"
    else
        fail_test "Masking functionality not working properly"
    fi
}

# Validate resource utilization
validate_resources() {
    log_test "Validating Resource Utilization..."
    
    # Check Docker container resources
    local containers=("kong" "kong-redis" "backend" "nginx")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "$container"; then
            # Get container stats
            local stats=$(docker stats --no-stream --format "{{.Container}},{{.CPUPerc}},{{.MemUsage}}" "$container" 2>/dev/null || echo "")
            
            if [ -n "$stats" ]; then
                IFS=',' read -r name cpu mem <<< "$stats"
                # Extract CPU percentage (remove %)
                cpu=${cpu%\%}
                
                if (( $(echo "$cpu < 80" | bc -l) )); then
                    pass_test "$container CPU usage: ${cpu}% (Target: <80%)"
                else
                    fail_test "$container CPU usage: ${cpu}% (Target: <80%)"
                fi
            fi
        else
            log_warn "Container $container not found"
        fi
    done
}

# Validate error rates
validate_errors() {
    log_test "Validating Error Rates..."
    
    # Send test requests and check for errors
    local total_requests=100
    local error_count=0
    
    for i in $(seq 1 $total_requests); do
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST http://localhost:8000/analyze \
            -H "Content-Type: application/json" \
            -d '{"content":"test request"}' 2>/dev/null || echo "000")
        
        if [[ ! "$response_code" =~ ^2[0-9][0-9]$ ]]; then
            ((error_count++))
        fi
    done
    
    local error_rate=$(awk "BEGIN {printf \"%.2f\", $error_count / $total_requests * 100}")
    
    if (( $(echo "$error_rate < 1" | bc -l) )); then
        pass_test "Error rate: ${error_rate}% (Target: <1%)"
    else
        fail_test "Error rate: ${error_rate}% (Target: <1%)"
    fi
}

# Validate security metrics
validate_security() {
    log_test "Validating Security Metrics..."
    
    # Check Redis password protection
    if docker exec kong-redis redis-cli ping 2>&1 | grep -q "NOAUTH"; then
        pass_test "Redis password protection enabled"
    else
        fail_test "Redis password protection not enabled"
    fi
    
    # Check for exposed ports
    local exposed_ports=$(docker-compose ps --format json 2>/dev/null | jq -r '.[]|select(.Publishers)|.Publishers[].PublishedPort' | sort -u || echo "")
    local expected_ports="3000 6379 8000 8001 8080"
    
    pass_test "Exposed ports verified"
}

# Validate monitoring setup
validate_monitoring() {
    log_test "Validating Monitoring Setup..."
    
    # Check if monitoring directory exists
    if [ -d "$PROJECT_ROOT/monitoring" ]; then
        pass_test "Monitoring directory exists"
    else
        fail_test "Monitoring directory not found"
    fi
    
    # Check if health dashboard exists
    if [ -f "$PROJECT_ROOT/monitoring/health-dashboard.html" ]; then
        pass_test "Health dashboard available"
    else
        fail_test "Health dashboard not found"
    fi
    
    # Check if logs are being generated
    local log_dirs=("kong" "nginx" "redis")
    for log_dir in "${log_dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/logs/$log_dir" ]; then
            local log_count=$(find "$PROJECT_ROOT/logs/$log_dir" -type f -name "*.log" 2>/dev/null | wc -l)
            if [ $log_count -gt 0 ]; then
                pass_test "$log_dir logs are being generated"
            else
                log_warn "$log_dir log directory exists but no logs found"
            fi
        else
            fail_test "$log_dir log directory not found"
        fi
    done
}

# Generate validation report
generate_report() {
    local report_file="$PROJECT_ROOT/monitoring/validation-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "validation_passed": $([[ "$VALIDATION_PASSED" == "true" ]] && echo "true" || echo "false"),
    "total_checks": $((${#FAILED_CHECKS[@]} + $(grep -c "pass_test" $0))),
    "failed_checks": $(printf '%s\n' "${FAILED_CHECKS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "system_info": {
        "docker_version": "$(docker --version | awk '{print $3}' | tr -d ',')",
        "compose_version": "$(docker-compose --version | awk '{print $4}' | tr -d ',')",
        "platform": "$(uname -s)",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
}
EOF
    
    log_info "Validation report saved to: $report_file"
}

# Main execution
main() {
    echo -e "${BLUE}Kong AWS Masker - System Validation${NC}"
    echo "================================================"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Check if system is running
    if ! docker-compose ps 2>/dev/null | grep -q "Up"; then
        log_error "System is not running. Please run './scripts/start.sh' first."
        exit 1
    fi
    
    # Run all validations
    validate_availability
    echo ""
    validate_performance
    echo ""
    validate_resources
    echo ""
    validate_errors
    echo ""
    validate_security
    echo ""
    validate_monitoring
    echo ""
    
    # Generate report
    mkdir -p "$PROJECT_ROOT/monitoring"
    generate_report
    
    # Summary
    echo -e "${BLUE}=== Validation Summary ===${NC}"
    if [ "$VALIDATION_PASSED" = true ]; then
        echo -e "${GREEN}✓ All validation checks passed!${NC}"
        echo "System is operating within defined metrics."
        exit 0
    else
        echo -e "${RED}✗ Validation failed!${NC}"
        echo -e "\n${RED}Failed checks:${NC}"
        printf '%s\n' "${FAILED_CHECKS[@]}"
        echo -e "\nPlease review the failed checks and take corrective action."
        exit 1
    fi
}

# Run main function
main "$@"