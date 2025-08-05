#!/bin/bash

#
# Day 2: System Monitor - Kong AWS Masking MVP
# 
# Purpose: Continuous monitoring with automatic failure detection
# Target: Run every 5 minutes, detect issues within 10 seconds
# Success Criteria: Alert on system degradation before complete failure
#

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Monitoring state
MONITOR_STATE="HEALTHY"
ALERTS_TRIGGERED=()
WARNINGS_TRIGGERED=()
START_TIME=$(date +%s)

# Create monitoring log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MONITOR_LOG="$LOG_DIR/system-monitor-$TIMESTAMP.log"
ALERT_LOG="$LOG_DIR/system-alerts.log"
mkdir -p "$LOG_DIR"

# Monitoring thresholds (can be overridden by environment)
CPU_ALERT_THRESHOLD=${CPU_ALERT_THRESHOLD:-80}
MEMORY_ALERT_THRESHOLD=${MEMORY_ALERT_THRESHOLD:-80}
RESPONSE_TIME_ALERT_THRESHOLD=${RESPONSE_TIME_ALERT_THRESHOLD:-5000}
DISK_ALERT_THRESHOLD=${DISK_ALERT_THRESHOLD:-85}

# Logging functions
log_monitor() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] MONITOR: $1${NC}" | tee -a "$MONITOR_LOG"
}

log_alert() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ALERT: $1${NC}" | tee -a "$MONITOR_LOG" | tee -a "$ALERT_LOG"
    ALERTS_TRIGGERED+=("$1")
    MONITOR_STATE="CRITICAL"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}" | tee -a "$MONITOR_LOG"
    WARNINGS_TRIGGERED+=("$1")
    if [[ "$MONITOR_STATE" == "HEALTHY" ]]; then
        MONITOR_STATE="WARNING"
    fi
}

log_healthy() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] HEALTHY: $1${NC}" | tee -a "$MONITOR_LOG"
}

# Check service availability and response time
monitor_service_availability() {
    log_monitor "=== Service Availability Check ==="
    
    # Kong Admin API
    local kong_admin_start=$(date +%s%3N)
    if timeout 10 curl -sf "$KONG_ADMIN_URL/status" > /dev/null 2>&1; then
        local kong_admin_time=$(($(date +%s%3N) - kong_admin_start))
        if [[ $kong_admin_time -lt 2000 ]]; then
            log_healthy "Kong Admin API responsive (${kong_admin_time}ms)"
        else
            log_warning "Kong Admin API slow response (${kong_admin_time}ms)"
        fi
    else
        log_alert "Kong Admin API not responding"
    fi
    
    # Kong Proxy
    local kong_proxy_start=$(date +%s%3N)
    if timeout 10 curl -sf "$KONG_PROXY_URL" > /dev/null 2>&1; then
        local kong_proxy_time=$(($(date +%s%3N) - kong_proxy_start))
        if [[ $kong_proxy_time -lt 2000 ]]; then
            log_healthy "Kong Proxy responsive (${kong_proxy_time}ms)"
        else
            log_warning "Kong Proxy slow response (${kong_proxy_time}ms)"
        fi
    else
        log_alert "Kong Proxy not responding"
    fi
    
    # Redis connectivity
    local redis_start=$(date +%s%3N)
    if timeout 5 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping > /dev/null 2>&1; then
        local redis_time=$(($(date +%s%3N) - redis_start))
        if [[ $redis_time -lt 1000 ]]; then
            log_healthy "Redis responsive (${redis_time}ms)"
        else
            log_warning "Redis slow response (${redis_time}ms)"
        fi
    else
        log_alert "Redis not responding"
    fi
    
    # Nginx (optional, may not always be accessible)
    local nginx_start=$(date +%s%3N)
    if timeout 5 curl -sf "$NGINX_URL/health" > /dev/null 2>&1; then
        local nginx_time=$(($(date +%s%3N) - nginx_start))
        log_healthy "Nginx proxy responsive (${nginx_time}ms)"
    else
        log_warning "Nginx proxy not accessible (may be expected)"
    fi
}

# Monitor system resources
monitor_system_resources() {
    log_monitor "=== System Resource Monitoring ==="
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    if (( $(echo "$cpu_usage > $CPU_ALERT_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        log_alert "CPU usage critical: ${cpu_usage}% (threshold: ${CPU_ALERT_THRESHOLD}%)"
    elif (( $(echo "$cpu_usage > $((CPU_ALERT_THRESHOLD - 10))" | bc -l 2>/dev/null || echo "0") )); then
        log_warning "CPU usage high: ${cpu_usage}%"
    else
        log_healthy "CPU usage normal: ${cpu_usage}%"
    fi
    
    # Memory usage
    local mem_total=$(free -m | grep "^Mem:" | awk '{print $2}')
    local mem_used=$(free -m | grep "^Mem:" | awk '{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    
    if [[ $mem_percent -gt $MEMORY_ALERT_THRESHOLD ]]; then
        log_alert "Memory usage critical: ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
    elif [[ $mem_percent -gt $((MEMORY_ALERT_THRESHOLD - 10)) ]]; then
        log_warning "Memory usage high: ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
    else
        log_healthy "Memory usage normal: ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
    fi
    
    # Disk usage for project directory
    local disk_usage=$(df -h "$SCRIPT_DIR/.." | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt $DISK_ALERT_THRESHOLD ]]; then
        log_alert "Disk usage critical: ${disk_usage}%"
    elif [[ $disk_usage -gt $((DISK_ALERT_THRESHOLD - 10)) ]]; then
        log_warning "Disk usage high: ${disk_usage}%"
    else
        log_healthy "Disk usage normal: ${disk_usage}%"
    fi
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_cores=$(nproc)
    local load_percent=$(echo "scale=0; $load_avg * 100 / $cpu_cores" | bc 2>/dev/null || echo "0")
    
    if [[ $load_percent -gt 80 ]]; then
        log_warning "System load high: ${load_avg} (${load_percent}% of ${cpu_cores} cores)"
    else
        log_healthy "System load normal: ${load_avg} (${load_percent}% of ${cpu_cores} cores)"
    fi
}

# Monitor Docker containers
monitor_docker_containers() {
    log_monitor "=== Docker Container Monitoring ==="
    
    local containers_total=0
    local containers_healthy=0
    
    # Check main services
    for service in redis kong nginx backend; do
        containers_total=$((containers_total + 1))
        
        if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
            containers_healthy=$((containers_healthy + 1))
            
            # Check container health/stats
            local container_id=$(docker-compose ps -q "$service" 2>/dev/null)
            if [[ -n "$container_id" ]]; then
                local container_status=$(docker inspect -f '{{ .State.Status }}' "$container_id" 2>/dev/null || echo "unknown")
                local restart_count=$(docker inspect -f '{{ .RestartCount }}' "$container_id" 2>/dev/null || echo "0")
                
                if [[ "$container_status" == "running" && $restart_count -eq 0 ]]; then
                    log_healthy "$service container stable (running, no restarts)"
                elif [[ "$container_status" == "running" && $restart_count -gt 0 ]]; then
                    log_warning "$service container unstable ($restart_count restarts)"
                else
                    log_alert "$service container unhealthy (status: $container_status)"
                fi
            fi
        else
            log_alert "$service container not running"
        fi
    done
    
    # Overall container health
    local container_health_percent=$((containers_healthy * 100 / containers_total))
    if [[ $container_health_percent -lt 100 ]]; then
        log_alert "Container health degraded: $containers_healthy/$containers_total running"
    else
        log_healthy "All containers running: $containers_healthy/$containers_total"
    fi
}

# Monitor AWS masking functionality
monitor_masking_functionality() {
    log_monitor "=== Masking Functionality Monitoring ==="
    
    # Quick test with a simple pattern
    local test_payload=$(cat << EOF
{
    "model": "$CLAUDE_MODEL",
    "max_tokens": 10,
    "messages": [
        {
            "role": "user", 
            "content": "Monitor test: i-1234567890abcdef0"
        }
    ]
}
EOF
)
    
    local masking_start=$(date +%s%3N)
    local response=$(timeout 10 curl -s -X POST "$KONG_PROXY_URL/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $CLAUDE_API_KEY" \
        -d "$test_payload" \
        -w "HTTP_CODE:%{http_code}" 2>/dev/null || echo "TIMEOUT")
    local masking_time=$(($(date +%s%3N) - masking_start))
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
    local body=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    if [[ "$http_code" == "200" ]]; then
        # Check if masking occurred (original value not in response)
        if [[ "$body" != *"i-1234567890abcdef0"* ]]; then
            if [[ $masking_time -lt $RESPONSE_TIME_ALERT_THRESHOLD ]]; then
                log_healthy "Masking functional (${masking_time}ms)"
            else
                log_warning "Masking slow but functional (${masking_time}ms)"
            fi
        else
            log_alert "Masking may have failed - original value detected in response"
        fi
    else
        log_alert "Masking endpoint failure (HTTP $http_code, ${masking_time}ms)"
    fi
}

# Monitor Redis mapping health
monitor_redis_mappings() {
    log_monitor "=== Redis Mapping Health ==="
    
    # Check Redis memory usage
    local redis_memory=$(timeout 5 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "unknown")
    
    # Count active mappings
    local mapping_count=$(timeout 5 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        eval "return #redis.call('keys', 'aws_masker:*')" 0 2>/dev/null || echo "0")
    
    # Check Redis keyspace
    local redis_keys=$(timeout 5 redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" \
        info keyspace 2>/dev/null | grep db0 || echo "")
    
    if [[ -n "$redis_memory" && "$redis_memory" != "unknown" ]]; then
        log_healthy "Redis memory usage: $redis_memory"
    else
        log_warning "Redis memory information unavailable"
    fi
    
    if [[ $mapping_count -gt 0 ]]; then
        log_healthy "Active Redis mappings: $mapping_count"
    else
        log_warning "No Redis mappings found (may be expected)"
    fi
    
    if [[ -n "$redis_keys" ]]; then
        log_healthy "Redis keyspace active: $redis_keys"
    else
        log_warning "Redis keyspace information unavailable"
    fi
}

# Check for recent errors in logs
monitor_error_patterns() {
    log_monitor "=== Error Pattern Monitoring ==="
    
    local error_patterns=("ERROR" "CRITICAL" "FATAL" "Exception" "Traceback")
    local error_found=false
    local recent_minutes=5
    
    # Check Docker logs for recent errors
    for service in kong nginx backend redis; do
        if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
            for pattern in "${error_patterns[@]}"; do
                local recent_errors=$(docker-compose logs --tail=100 --since="${recent_minutes}m" "$service" 2>&1 | \
                    grep -i "$pattern" | wc -l)
                
                if [[ $recent_errors -gt 5 ]]; then
                    log_alert "$service: High error rate - $recent_errors '$pattern' errors in last ${recent_minutes}m"
                    error_found=true
                elif [[ $recent_errors -gt 0 ]]; then
                    log_warning "$service: $recent_errors '$pattern' errors in last ${recent_minutes}m"
                    error_found=true
                fi
            done
        fi
    done
    
    if [[ "$error_found" == "false" ]]; then
        log_healthy "No significant error patterns detected in recent logs"
    fi
}

# Generate monitoring summary
generate_monitoring_summary() {
    local end_time=$(date +%s)
    local execution_time=$((end_time - START_TIME))
    
    # Create summary report
    local summary_file="$LOG_DIR/monitoring-summary-$TIMESTAMP.json"
    cat > "$summary_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "execution_time_seconds": $execution_time,
    "monitor_state": "$MONITOR_STATE",
    "alerts_count": ${#ALERTS_TRIGGERED[@]},
    "warnings_count": ${#WARNINGS_TRIGGERED[@]},
    "alerts": $(printf '%s\n' "${ALERTS_TRIGGERED[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "warnings": $(printf '%s\n' "${WARNINGS_TRIGGERED[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "monitoring_components": {
        "service_availability": "checked",
        "system_resources": "checked", 
        "docker_containers": "checked",
        "masking_functionality": "checked",
        "redis_mappings": "checked",
        "error_patterns": "checked"
    }
}
EOF
    
    log_monitor "Monitoring summary saved: $summary_file"
}

# Send alerts if configured
send_alerts() {
    if [[ ${#ALERTS_TRIGGERED[@]} -gt 0 ]]; then
        log_monitor "=== Alert Notification ==="
        
        # Log to alert file
        echo "$(date '+%Y-%m-%d %H:%M:%S') - CRITICAL ALERTS:" >> "$ALERT_LOG"
        printf '%s\n' "${ALERTS_TRIGGERED[@]}" | sed 's/^/  - /' >> "$ALERT_LOG"
        echo "" >> "$ALERT_LOG"
        
        # If external notification is configured
        if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
            local alert_message="Kong AWS Masking MVP Alert: ${#ALERTS_TRIGGERED[@]} critical issues detected"
            # curl -X POST -H 'Content-type: application/json' \
                # --data "{\"text\":\"$alert_message\"}" \
                # "$SLACK_WEBHOOK" 2>/dev/null || true
            log_monitor "Slack notification would be sent: $alert_message"
        fi
        
        log_monitor "Alerts logged to: $ALERT_LOG"
    fi
}

# Main monitoring execution
main() {
    # Silent mode option for cron jobs
    if [[ "${1:-}" == "--silent" ]]; then
        exec > "$MONITOR_LOG" 2>&1
    fi
    
    log_monitor "System monitoring started (PID: $$)"
    
    # Run all monitoring checks
    monitor_service_availability
    monitor_system_resources
    monitor_docker_containers
    monitor_masking_functionality
    monitor_redis_mappings
    monitor_error_patterns
    
    # Generate summary and handle alerts
    generate_monitoring_summary
    send_alerts
    
    # Final status
    local end_time=$(date +%s)
    local execution_time=$((end_time - START_TIME))
    
    log_monitor "Monitoring completed in ${execution_time} seconds"
    log_monitor "Final state: $MONITOR_STATE"
    log_monitor "Alerts: ${#ALERTS_TRIGGERED[@]}, Warnings: ${#WARNINGS_TRIGGERED[@]}"
    
    # Exit with appropriate code
    case "$MONITOR_STATE" in
        "HEALTHY")
            echo -e "${GREEN}✅ SYSTEM HEALTHY${NC}"
            exit 0
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️ SYSTEM WARNING (${#WARNINGS_TRIGGERED[@]} warnings)${NC}"
            exit 0  # Still exit 0 for warnings
            ;;
        "CRITICAL")
            echo -e "${RED}❌ SYSTEM CRITICAL (${#ALERTS_TRIGGERED[@]} alerts)${NC}"
            exit 1
            ;;
    esac
}

# Signal handling for graceful shutdown
trap 'log_monitor "Monitoring interrupted"; exit 130' INT TERM

# Execute main function
main "$@"