#!/bin/bash

# Day 4 Alerting System for Kong AWS Masking Enterprise 2
# Purpose: Monitor metrics and trigger alerts based on configurable thresholds
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create required directories
mkdir -p "${PROJECT_ROOT}/logs/monitoring/day4"
mkdir -p "${PROJECT_ROOT}/monitoring/alerts"
mkdir -p "${PROJECT_ROOT}/pids"

# Configuration files
ALERT_CONFIG="${PROJECT_ROOT}/monitoring/alerts/alert-config.json"
ALERT_LOG="${PROJECT_ROOT}/logs/monitoring/day4/alerts.log"
ALERT_HISTORY="${PROJECT_ROOT}/monitoring/alerts/alert-history.json"
ALERT_PID="${PROJECT_ROOT}/pids/day4-alerting.pid"

# Metrics locations
METRICS_DIR="${PROJECT_ROOT}/monitoring/metrics"

# Alert thresholds (configurable)
AWS_MASKING_FAILURE_THRESHOLD=10    # Percentage
RESPONSE_TIME_P95_THRESHOLD=5000    # Milliseconds
RESPONSE_TIME_P99_THRESHOLD=10000   # Milliseconds
REDIS_MEMORY_THRESHOLD=104857600    # 100MB in bytes
KONG_PLUGIN_ERROR_THRESHOLD=5       # Number of errors
SYSTEM_CPU_THRESHOLD=80             # Percentage
SYSTEM_MEMORY_THRESHOLD=80          # Percentage

# Functions
log_alert() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local alert_entry="[$timestamp] [$level] $message"
    
    echo "$alert_entry" | tee -a "$ALERT_LOG"
    
    # Send to system log as well
    logger -t "kong-alerts" "$alert_entry"
}

# Initialize alert configuration
init_alert_config() {
    if [[ ! -f "$ALERT_CONFIG" ]]; then
        cat > "$ALERT_CONFIG" << EOF
{
    "alert_thresholds": {
        "aws_masking_failure_rate": $AWS_MASKING_FAILURE_THRESHOLD,
        "response_time_p95_ms": $RESPONSE_TIME_P95_THRESHOLD,
        "response_time_p99_ms": $RESPONSE_TIME_P99_THRESHOLD,
        "redis_memory_bytes": $REDIS_MEMORY_THRESHOLD,
        "kong_plugin_errors": $KONG_PLUGIN_ERROR_THRESHOLD,
        "system_cpu_percent": $SYSTEM_CPU_THRESHOLD,
        "system_memory_percent": $SYSTEM_MEMORY_THRESHOLD
    },
    "alert_cooldown_minutes": 15,
    "notification_channels": {
        "log": true,
        "system_logger": true,
        "file": true
    },
    "enabled": true
}
EOF
        log_alert "INFO" "Alert configuration initialized"
    fi
}

# Load alert configuration
load_config() {
    if [[ -f "$ALERT_CONFIG" ]]; then
        AWS_MASKING_FAILURE_THRESHOLD=$(jq -r '.alert_thresholds.aws_masking_failure_rate' "$ALERT_CONFIG")
        RESPONSE_TIME_P95_THRESHOLD=$(jq -r '.alert_thresholds.response_time_p95_ms' "$ALERT_CONFIG")
        RESPONSE_TIME_P99_THRESHOLD=$(jq -r '.alert_thresholds.response_time_p99_ms' "$ALERT_CONFIG")
        REDIS_MEMORY_THRESHOLD=$(jq -r '.alert_thresholds.redis_memory_bytes' "$ALERT_CONFIG")
        KONG_PLUGIN_ERROR_THRESHOLD=$(jq -r '.alert_thresholds.kong_plugin_errors' "$ALERT_CONFIG")
        SYSTEM_CPU_THRESHOLD=$(jq -r '.alert_thresholds.system_cpu_percent' "$ALERT_CONFIG")
        SYSTEM_MEMORY_THRESHOLD=$(jq -r '.alert_thresholds.system_memory_percent' "$ALERT_CONFIG")
    fi
}

# Check if alert was recently triggered (cooldown)
check_alert_cooldown() {
    local alert_type="$1"
    local cooldown_minutes=15
    
    if [[ -f "$ALERT_HISTORY" ]]; then
        cooldown_minutes=$(jq -r '.alert_thresholds.alert_cooldown_minutes // 15' "$ALERT_CONFIG" 2>/dev/null || echo "15")
        
        local last_alert=$(jq -r --arg type "$alert_type" '.alerts[] | select(.type == $type) | .timestamp' "$ALERT_HISTORY" 2>/dev/null | tail -1 || echo "")
        
        if [[ -n "$last_alert" ]]; then
            local last_alert_epoch=$(date -d "$last_alert" +%s 2>/dev/null || echo "0")
            local current_epoch=$(date +%s)
            local minutes_since=$(( (current_epoch - last_alert_epoch) / 60 ))
            
            if [[ $minutes_since -lt $cooldown_minutes ]]; then
                return 1  # Still in cooldown
            fi
        fi
    fi
    
    return 0  # Not in cooldown
}

# Record alert in history
record_alert() {
    local alert_type="$1"
    local severity="$2"
    local message="$3"
    local metric_value="$4"
    local threshold="$5"
    
    # Initialize alert history if it doesn't exist
    if [[ ! -f "$ALERT_HISTORY" ]]; then
        echo '{"alerts": []}' > "$ALERT_HISTORY"
    fi
    
    # Add new alert to history
    local new_alert=$(cat << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "type": "$alert_type",
    "severity": "$severity",
    "message": "$message",
    "metric_value": "$metric_value",
    "threshold": "$threshold"
}
EOF
)
    
    # Update alert history
    jq --argjson alert "$new_alert" '.alerts += [$alert]' "$ALERT_HISTORY" > "${ALERT_HISTORY}.tmp" && mv "${ALERT_HISTORY}.tmp" "$ALERT_HISTORY"
}

# Check AWS masking metrics
check_aws_masking_alerts() {
    local latest_metrics=$(ls -t "$METRICS_DIR"/aws-masking-metrics.json 2>/dev/null | head -1)
    
    if [[ -n "$latest_metrics" && -f "$latest_metrics" ]]; then
        local failure_rate=$(jq -r '.aws_masking_metrics.failure_rate_percent // 0' "$latest_metrics")
        
        if [[ $(echo "$failure_rate > $AWS_MASKING_FAILURE_THRESHOLD" | bc) -eq 1 ]]; then
            if check_alert_cooldown "aws_masking_failure"; then
                log_alert "CRITICAL" "AWS masking failure rate exceeded threshold: ${failure_rate}% > ${AWS_MASKING_FAILURE_THRESHOLD}%"
                record_alert "aws_masking_failure" "CRITICAL" "High failure rate detected" "$failure_rate" "$AWS_MASKING_FAILURE_THRESHOLD"
            fi
        fi
        
        # Check for zero success rate (complete failure)
        local success_rate=$(jq -r '.aws_masking_metrics.success_rate_percent // 0' "$latest_metrics")
        if [[ "$success_rate" == "0" ]]; then
            if check_alert_cooldown "aws_masking_complete_failure"; then
                log_alert "CRITICAL" "AWS masking completely failed: 0% success rate"
                record_alert "aws_masking_complete_failure" "CRITICAL" "Complete masking failure" "0" "1"
            fi
        fi
    fi
}

# Check response time metrics
check_response_time_alerts() {
    local latest_metrics=$(ls -t "$METRICS_DIR"/response-time-metrics.json 2>/dev/null | head -1)
    
    if [[ -n "$latest_metrics" && -f "$latest_metrics" ]]; then
        # Check each endpoint
        local endpoints=$(jq -r '.response_time_metrics.endpoints[] | @base64' "$latest_metrics")
        
        while IFS= read -r endpoint_data; do
            local endpoint_json=$(echo "$endpoint_data" | base64 -d)
            local endpoint=$(echo "$endpoint_json" | jq -r '.endpoint')
            local p95=$(echo "$endpoint_json" | jq -r '.response_times.p95_ms // 0')
            local p99=$(echo "$endpoint_json" | jq -r '.response_times.p99_ms // 0')
            
            # Check P95 threshold
            if [[ $(echo "$p95 > $RESPONSE_TIME_P95_THRESHOLD" | bc) -eq 1 ]]; then
                if check_alert_cooldown "response_time_p95_${endpoint##*/}"; then
                    log_alert "WARNING" "P95 response time exceeded threshold for $endpoint: ${p95}ms > ${RESPONSE_TIME_P95_THRESHOLD}ms"
                    record_alert "response_time_p95" "WARNING" "High P95 response time on $endpoint" "$p95" "$RESPONSE_TIME_P95_THRESHOLD"
                fi
            fi
            
            # Check P99 threshold
            if [[ $(echo "$p99 > $RESPONSE_TIME_P99_THRESHOLD" | bc) -eq 1 ]]; then
                if check_alert_cooldown "response_time_p99_${endpoint##*/}"; then
                    log_alert "CRITICAL" "P99 response time exceeded threshold for $endpoint: ${p99}ms > ${RESPONSE_TIME_P99_THRESHOLD}ms"
                    record_alert "response_time_p99" "CRITICAL" "High P99 response time on $endpoint" "$p99" "$RESPONSE_TIME_P99_THRESHOLD"
                fi
            fi
        done <<< "$endpoints"
    fi
}

# Check Redis metrics
check_redis_alerts() {
    local latest_metrics=$(ls -t "$METRICS_DIR"/redis-metrics.json 2>/dev/null | head -1)
    
    if [[ -n "$latest_metrics" && -f "$latest_metrics" ]]; then
        local used_memory=$(jq -r '.redis_metrics.memory.used_memory_bytes // 0' "$latest_metrics")
        local connected_clients=$(jq -r '.redis_metrics.connections.connected_clients // 0' "$latest_metrics")
        
        # Check memory usage
        if [[ $(echo "$used_memory > $REDIS_MEMORY_THRESHOLD" | bc) -eq 1 ]]; then
            if check_alert_cooldown "redis_memory"; then
                local memory_mb=$((used_memory / 1048576))
                local threshold_mb=$((REDIS_MEMORY_THRESHOLD / 1048576))
                log_alert "WARNING" "Redis memory usage exceeded threshold: ${memory_mb}MB > ${threshold_mb}MB"
                record_alert "redis_memory" "WARNING" "High Redis memory usage" "$memory_mb" "$threshold_mb"
            fi
        fi
        
        # Check if Redis is disconnected (0 clients might indicate issues)
        if [[ "$connected_clients" == "0" ]]; then
            if check_alert_cooldown "redis_connection"; then
                log_alert "CRITICAL" "Redis has no connected clients - possible connection issues"
                record_alert "redis_connection" "CRITICAL" "No Redis connections" "0" "1"
            fi
        fi
    fi
}

# Check Kong plugin metrics
check_kong_plugin_alerts() {
    local latest_metrics=$(ls -t "$METRICS_DIR"/kong-plugin-metrics.json 2>/dev/null | head -1)
    
    if [[ -n "$latest_metrics" && -f "$latest_metrics" ]]; then
        local aws_masker_status=$(jq -r '.kong_plugin_metrics.plugins.aws_masker_status // "false"' "$latest_metrics")
        local server_status=$(jq -r '.kong_plugin_metrics.status.server_status // "unknown"' "$latest_metrics")
        
        # Check if AWS masker plugin is disabled
        if [[ "$aws_masker_status" == "false" ]]; then
            if check_alert_cooldown "kong_plugin_disabled"; then
                log_alert "CRITICAL" "AWS masker plugin is disabled or not found"
                record_alert "kong_plugin_disabled" "CRITICAL" "AWS masker plugin inactive" "false" "true"
            fi
        fi
        
        # Check Kong server health
        if [[ "$server_status" != "healthy" && "$server_status" != "unknown" ]]; then
            if check_alert_cooldown "kong_server_unhealthy"; then
                log_alert "CRITICAL" "Kong server status is unhealthy: $server_status"
                record_alert "kong_server_unhealthy" "CRITICAL" "Kong server unhealthy" "$server_status" "healthy"
            fi
        fi
    fi
}

# Check system resource metrics
check_system_resource_alerts() {
    # Check Docker container resource usage
    local system_stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}" | grep claude- 2>/dev/null || echo "")
    
    if [[ -n "$system_stats" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^claude-([^[:space:]]+)[[:space:]]+([0-9.]+)%[[:space:]]+([0-9.]+)% ]]; then
                local container="${BASH_REMATCH[1]}"
                local cpu="${BASH_REMATCH[2]}"
                local memory="${BASH_REMATCH[3]}"
                
                # Check CPU threshold
                if [[ $(echo "$cpu > $SYSTEM_CPU_THRESHOLD" | bc) -eq 1 ]]; then
                    if check_alert_cooldown "system_cpu_$container"; then
                        log_alert "WARNING" "High CPU usage on $container: ${cpu}% > ${SYSTEM_CPU_THRESHOLD}%"
                        record_alert "system_cpu" "WARNING" "High CPU on $container" "$cpu" "$SYSTEM_CPU_THRESHOLD"
                    fi
                fi
                
                # Check memory threshold
                if [[ $(echo "$memory > $SYSTEM_MEMORY_THRESHOLD" | bc) -eq 1 ]]; then
                    if check_alert_cooldown "system_memory_$container"; then
                        log_alert "WARNING" "High memory usage on $container: ${memory}% > ${SYSTEM_MEMORY_THRESHOLD}%"
                        record_alert "system_memory" "WARNING" "High memory on $container" "$memory" "$SYSTEM_MEMORY_THRESHOLD"
                    fi
                fi
            fi
        done <<< "$system_stats"
    fi
}

# Main alert checking function
check_all_alerts() {
    load_config
    
    log_alert "INFO" "Starting alert check cycle"
    
    check_aws_masking_alerts
    check_response_time_alerts
    check_redis_alerts
    check_kong_plugin_alerts
    check_system_resource_alerts
    
    log_alert "INFO" "Alert check cycle completed"
}

# Start alerting daemon
start_alerting_daemon() {
    if [[ -f "$ALERT_PID" ]] && kill -0 "$(cat "$ALERT_PID")" 2>/dev/null; then
        echo "Alerting daemon already running (PID: $(cat "$ALERT_PID"))"
        return 0
    fi
    
    echo "Starting Day 4 alerting daemon..."
    
    nohup bash -c '
        while true; do
            '"$(declare -f check_all_alerts log_alert load_config check_alert_cooldown record_alert check_aws_masking_alerts check_response_time_alerts check_redis_alerts check_kong_plugin_alerts check_system_resource_alerts)"'
            
            # Export variables for the functions
            export SCRIPT_DIR="'"$SCRIPT_DIR"'"
            export PROJECT_ROOT="'"$PROJECT_ROOT"'"
            export ALERT_CONFIG="'"$ALERT_CONFIG"'"
            export ALERT_LOG="'"$ALERT_LOG"'"
            export ALERT_HISTORY="'"$ALERT_HISTORY"'"
            export METRICS_DIR="'"$METRICS_DIR"'"
            export AWS_MASKING_FAILURE_THRESHOLD="'"$AWS_MASKING_FAILURE_THRESHOLD"'"
            export RESPONSE_TIME_P95_THRESHOLD="'"$RESPONSE_TIME_P95_THRESHOLD"'"
            export RESPONSE_TIME_P99_THRESHOLD="'"$RESPONSE_TIME_P99_THRESHOLD"'"
            export REDIS_MEMORY_THRESHOLD="'"$REDIS_MEMORY_THRESHOLD"'"
            export KONG_PLUGIN_ERROR_THRESHOLD="'"$KONG_PLUGIN_ERROR_THRESHOLD"'"
            export SYSTEM_CPU_THRESHOLD="'"$SYSTEM_CPU_THRESHOLD"'"
            export SYSTEM_MEMORY_THRESHOLD="'"$SYSTEM_MEMORY_THRESHOLD"'"
            
            check_all_alerts
            sleep 60  # Check every minute
        done
    ' > /dev/null 2>&1 &
    
    echo $! > "$ALERT_PID"
    echo "Alerting daemon started (PID: $!)"
}

# Stop alerting daemon
stop_alerting_daemon() {
    if [[ -f "$ALERT_PID" ]]; then
        local pid=$(cat "$ALERT_PID")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$ALERT_PID"
            echo "Alerting daemon stopped (PID: $pid)"
        else
            rm -f "$ALERT_PID"
            echo "Alerting daemon was not running"
        fi
    else
        echo "Alerting daemon is not running"
    fi
}

# Check daemon status
check_daemon_status() {
    if [[ -f "$ALERT_PID" ]]; then
        local pid=$(cat "$ALERT_PID")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Alerting daemon: running (PID: $pid)"
            return 0
        else
            echo "Alerting daemon: not running (stale PID file)"
            rm -f "$ALERT_PID"
            return 1
        fi
    else
        echo "Alerting daemon: not running"
        return 1
    fi
}

# Show alert history
show_alert_history() {
    if [[ -f "$ALERT_HISTORY" ]]; then
        echo "Recent alerts:"
        jq -r '.alerts[-10:] | .[] | "\(.timestamp) [\(.severity)] \(.message)"' "$ALERT_HISTORY" 2>/dev/null || echo "No alert history available"
    else
        echo "No alert history file found"
    fi
}

# Main execution
case "${1:-help}" in
    start)
        init_alert_config
        start_alerting_daemon
        ;;
    stop)
        stop_alerting_daemon
        ;;
    restart)
        stop_alerting_daemon
        sleep 2
        init_alert_config
        start_alerting_daemon
        ;;
    status)
        check_daemon_status
        ;;
    check)
        init_alert_config
        check_all_alerts
        ;;
    history)
        show_alert_history
        ;;
    test)
        echo "Running test alert..."
        init_alert_config
        log_alert "INFO" "Test alert triggered manually"
        record_alert "test" "INFO" "Manual test alert" "1" "0"
        echo "Test alert completed"
        ;;
    help)
        echo "Day 4 Alerting System for Kong AWS Masking Enterprise 2"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  start     Start the alerting daemon"
        echo "  stop      Stop the alerting daemon"
        echo "  restart   Restart the alerting daemon"
        echo "  status    Check daemon status"
        echo "  check     Run alert checks once (manual)"
        echo "  history   Show recent alert history"
        echo "  test      Trigger a test alert"
        echo "  help      Show this help message"
        echo
        echo "Configuration file: $ALERT_CONFIG"
        echo "Alert log: $ALERT_LOG"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac