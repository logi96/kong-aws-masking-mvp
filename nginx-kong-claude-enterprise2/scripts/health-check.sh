#!/bin/bash

# Kong AWS Masker - Health Check Script
# Description: Comprehensive health check for all system components

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

# Health status tracking
HEALTH_STATUS="HEALTHY"
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

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_failure() {
    echo -e "${RED}[✗]${NC} $1"
    HEALTH_STATUS="UNHEALTHY"
    FAILED_CHECKS+=("$1")
}

# Check Docker services status
check_docker_services() {
    echo -e "\n${BLUE}=== Docker Services Status ===${NC}"
    
    cd "$PROJECT_ROOT"
    
    local services=("redis" "kong" "nginx" "backend")
    
    for service in "${services[@]}"; do
        if docker-compose ps $service 2>/dev/null | grep -q "Up"; then
            local container_id=$(docker-compose ps -q $service 2>/dev/null)
            local uptime=$(docker inspect -f '{{ .State.StartedAt }}' $container_id 2>/dev/null || echo "Unknown")
            log_success "$service is running (Started: $uptime)"
        else
            log_failure "$service is not running"
        fi
    done
}

# Check service health endpoints
check_health_endpoints() {
    echo -e "\n${BLUE}=== Health Endpoints ===${NC}"
    
    # Kong Admin API
    if curl -sf http://localhost:8001/status > /dev/null; then
        log_success "Kong Admin API is healthy"
    else
        log_failure "Kong Admin API is not responding"
    fi
    
    # Kong Proxy
    if curl -sf http://localhost:8000 > /dev/null; then
        log_success "Kong Proxy is healthy"
    else
        log_failure "Kong Proxy is not responding"
    fi
    
    # Nginx
    if curl -sf http://localhost:8080/health > /dev/null; then
        log_success "Nginx is healthy"
    else
        log_failure "Nginx is not responding"
    fi
    
    # Backend API
    if curl -sf http://localhost:3000/health > /dev/null; then
        local health_data=$(curl -s http://localhost:3000/health)
        log_success "Backend API is healthy: $health_data"
    else
        log_failure "Backend API is not responding"
    fi
}

# Check Redis health
check_redis() {
    echo -e "\n${BLUE}=== Redis Health ===${NC}"
    
    if docker exec kong-redis redis-cli ping 2>/dev/null | grep -q PONG; then
        log_success "Redis is responding to PING"
        
        # Check Redis memory usage
        local memory_used=$(docker exec kong-redis redis-cli INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "Unknown")
        log_info "Redis memory usage: $memory_used"
        
        # Check Redis persistence
        local last_save=$(docker exec kong-redis redis-cli LASTSAVE 2>/dev/null | tr -d '\r' || echo "0")
        local current_time=$(date +%s)
        local time_since_save=$((current_time - last_save))
        
        if [ $time_since_save -lt 3600 ]; then
            log_success "Redis last save: ${time_since_save}s ago"
        else
            log_warn "Redis last save: ${time_since_save}s ago (>1 hour)"
        fi
    else
        log_failure "Redis is not responding"
    fi
}

# Check Kong plugins
check_kong_plugins() {
    echo -e "\n${BLUE}=== Kong Plugins ===${NC}"
    
    # Check if aws-masker plugin is loaded
    local plugins=$(curl -s http://localhost:8001/plugins 2>/dev/null || echo "{}")
    
    if echo "$plugins" | grep -q "aws-masker"; then
        log_success "AWS Masker plugin is loaded"
        
        # Count active plugin instances
        local plugin_count=$(echo "$plugins" | grep -o "aws-masker" | wc -l)
        log_info "Active AWS Masker instances: $plugin_count"
    else
        log_failure "AWS Masker plugin is not loaded"
    fi
}

# Test masking functionality
test_masking() {
    echo -e "\n${BLUE}=== Masking Functionality Test ===${NC}"
    
    # Test with EC2 instance ID
    local test_payload='{"content":"Test EC2 instance i-1234567890abcdef0"}'
    local response=$(curl -s -X POST http://localhost:8000/analyze \
        -H "Content-Type: application/json" \
        -d "$test_payload" 2>/dev/null || echo "")
    
    if [[ "$response" == *"EC2_"* ]] && [[ "$response" != *"i-1234567890abcdef0"* ]]; then
        log_success "Masking test passed - EC2 instance ID was masked"
    else
        log_failure "Masking test failed - EC2 instance ID was not properly masked"
    fi
    
    # Test with multiple patterns
    local complex_payload='{"content":"VPC vpc-12345678 contains instance i-0123456789abcdef0 with IP 10.0.1.100"}'
    local complex_response=$(curl -s -X POST http://localhost:8000/analyze \
        -H "Content-Type: application/json" \
        -d "$complex_payload" 2>/dev/null || echo "")
    
    local masked_count=0
    [[ "$complex_response" == *"VPC_"* ]] && ((masked_count++))
    [[ "$complex_response" == *"EC2_"* ]] && ((masked_count++))
    [[ "$complex_response" == *"PRIVATE_IP_"* ]] && ((masked_count++))
    
    if [ $masked_count -eq 3 ]; then
        log_success "Complex masking test passed - All 3 patterns masked"
    else
        log_failure "Complex masking test failed - Only $masked_count/3 patterns masked"
    fi
}

# Check system resources
check_system_resources() {
    echo -e "\n${BLUE}=== System Resources ===${NC}"
    
    # Check CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    if (( $(echo "$cpu_usage < 80" | bc -l) )); then
        log_success "CPU usage is healthy: ${cpu_usage}%"
    else
        log_warn "CPU usage is high: ${cpu_usage}%"
    fi
    
    # Check memory usage
    local mem_total=$(free -m | grep "^Mem:" | awk '{print $2}')
    local mem_used=$(free -m | grep "^Mem:" | awk '{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    
    if [ $mem_percent -lt 80 ]; then
        log_success "Memory usage is healthy: ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
    else
        log_warn "Memory usage is high: ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
    fi
    
    # Check disk usage
    local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $disk_usage -lt 80 ]; then
        log_success "Disk usage is healthy: ${disk_usage}%"
    else
        log_warn "Disk usage is high: ${disk_usage}%"
    fi
}

# Check logs for errors
check_logs() {
    echo -e "\n${BLUE}=== Recent Log Errors ===${NC}"
    
    local services=("kong" "nginx" "backend" "redis")
    local error_found=false
    
    for service in "${services[@]}"; do
        if docker-compose ps $service 2>/dev/null | grep -q "Up"; then
            local recent_errors=$(docker-compose logs --tail=100 $service 2>&1 | grep -iE "error|exception|fatal" | tail -5 || echo "")
            
            if [ -n "$recent_errors" ]; then
                log_warn "Recent errors in $service logs:"
                echo "$recent_errors" | sed 's/^/  /'
                error_found=true
            fi
        fi
    done
    
    if [ "$error_found" = false ]; then
        log_success "No recent errors found in logs"
    fi
}

# Performance metrics
check_performance() {
    echo -e "\n${BLUE}=== Performance Metrics ===${NC}"
    
    # Test response time
    local start_time=$(date +%s%N)
    curl -s http://localhost:3000/health > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local response_time=$(( (end_time - start_time) / 1000000 ))
    
    if [ $response_time -lt 100 ]; then
        log_success "Backend response time: ${response_time}ms"
    else
        log_warn "Backend response time is slow: ${response_time}ms"
    fi
    
    # Check Kong latency
    local kong_latency=$(curl -s http://localhost:8001/status 2>/dev/null | jq -r '.server.total_requests // 0' || echo "0")
    log_info "Kong total requests processed: $kong_latency"
}

# Generate health report
generate_report() {
    local report_file="$PROJECT_ROOT/monitoring/health-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "$HEALTH_STATUS",
    "failed_checks": $(printf '%s\n' "${FAILED_CHECKS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "services": {
        "redis": $(docker-compose ps redis 2>/dev/null | grep -q "Up" && echo "true" || echo "false"),
        "kong": $(docker-compose ps kong 2>/dev/null | grep -q "Up" && echo "true" || echo "false"),
        "nginx": $(docker-compose ps nginx 2>/dev/null | grep -q "Up" && echo "true" || echo "false"),
        "backend": $(docker-compose ps backend 2>/dev/null | grep -q "Up" && echo "true" || echo "false")
    }
}
EOF
    
    log_info "Health report saved to: $report_file"
}

# Main execution
main() {
    echo -e "${BLUE}Kong AWS Masker - System Health Check${NC}"
    echo "================================================"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Run all health checks
    check_docker_services
    check_health_endpoints
    check_redis
    check_kong_plugins
    test_masking
    check_system_resources
    check_logs
    check_performance
    
    # Generate report
    mkdir -p "$PROJECT_ROOT/monitoring"
    generate_report
    
    # Summary
    echo -e "\n${BLUE}=== Health Check Summary ===${NC}"
    if [ "$HEALTH_STATUS" = "HEALTHY" ]; then
        echo -e "${GREEN}Overall Status: HEALTHY${NC}"
        exit 0
    else
        echo -e "${RED}Overall Status: UNHEALTHY${NC}"
        echo -e "\n${RED}Failed checks:${NC}"
        printf '%s\n' "${FAILED_CHECKS[@]}"
        exit 1
    fi
}

# Run main function
main "$@"