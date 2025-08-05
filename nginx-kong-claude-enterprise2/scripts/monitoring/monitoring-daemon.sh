#!/bin/bash

# Day 2 Monitoring Daemon Manager for Kong AWS Masking MVP
# Purpose: Manage background monitoring processes

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create required directories
mkdir -p "${PROJECT_ROOT}/pids"
mkdir -p "${PROJECT_ROOT}/logs/monitoring"

# PID file locations
HEALTH_PID="${PROJECT_ROOT}/pids/health-monitoring.pid"
SYSTEM_PID="${PROJECT_ROOT}/pids/system-monitoring.pid"
REGRESSION_PID="${PROJECT_ROOT}/pids/regression-tests.pid"

# Log file locations
HEALTH_LOG="${PROJECT_ROOT}/logs/monitoring/health-monitoring.log"
SYSTEM_LOG="${PROJECT_ROOT}/logs/monitoring/system-monitoring.log"
REGRESSION_LOG="${PROJECT_ROOT}/logs/monitoring/regression-tests.log"

# Functions
start_health_monitor() {
    if [[ -f "$HEALTH_PID" ]] && kill -0 "$(cat "$HEALTH_PID")" 2>/dev/null; then
        echo "Health monitor already running (PID: $(cat "$HEALTH_PID"))"
        return 0
    fi
    
    echo "Starting health monitor..."
    nohup bash -c '
        while true; do
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            if curl -s http://localhost:8085/health | grep -q healthy; then
                echo "[$timestamp] ✅ System healthy" >> '"$HEALTH_LOG"'
            else
                echo "[$timestamp] ❌ System unhealthy - Alert!" >> '"$HEALTH_LOG"'
            fi
            sleep 60
        done
    ' > /dev/null 2>&1 & 
    
    echo $! > "$HEALTH_PID"
    echo "Health monitor started (PID: $!)"
}

start_system_monitor() {
    if [[ -f "$SYSTEM_PID" ]] && kill -0 "$(cat "$SYSTEM_PID")" 2>/dev/null; then
        echo "System monitor already running (PID: $(cat "$SYSTEM_PID"))"
        return 0
    fi
    
    echo "Starting system monitor..."
    nohup bash -c '
        while true; do
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep claude- >> '"$SYSTEM_LOG"' 2>/dev/null || echo "[$timestamp] Docker stats unavailable" >> '"$SYSTEM_LOG"'
            sleep 30
        done
    ' > /dev/null 2>&1 &
    
    echo $! > "$SYSTEM_PID"
    echo "System monitor started (PID: $!)"
}

start_regression_scheduler() {
    if [[ -f "$REGRESSION_PID" ]] && kill -0 "$(cat "$REGRESSION_PID")" 2>/dev/null; then
        echo "Regression scheduler already running (PID: $(cat "$REGRESSION_PID"))"
        return 0
    fi
    
    echo "Starting regression test scheduler..."
    nohup bash -c '
        while true; do
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            echo "[$timestamp] Running regression tests..." >> '"$REGRESSION_LOG"'
            
            # Simple regression test - API call
            if timeout 30 curl -s -X POST http://localhost:8085/v1/messages \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer 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" \
                -d "{\"model\": \"claude-3-haiku-20240307\", \"max_tokens\": 10, \"messages\": [{\"role\": \"user\", \"content\": \"test\"}]}" > /dev/null; then
                echo "[$timestamp] ✅ Regression test passed" >> '"$REGRESSION_LOG"'
            else
                echo "[$timestamp] ❌ Regression test failed" >> '"$REGRESSION_LOG"'
            fi
            
            sleep 14400  # 4 hours
        done
    ' > /dev/null 2>&1 &
    
    echo $! > "$REGRESSION_PID"
    echo "Regression scheduler started (PID: $!)"
}

stop_service() {
    local service_name="$1"
    local pid_file="$2"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            echo "$service_name stopped (PID: $pid)"
        else
            rm -f "$pid_file"
            echo "$service_name was not running"
        fi
    else
        echo "$service_name is not running"
    fi
}

status_service() {
    local service_name="$1"
    local pid_file="$2"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$service_name: running (PID: $pid)"
            return 0
        else
            echo "$service_name: not running (stale PID file)"
            rm -f "$pid_file"
            return 1
        fi
    else
        echo "$service_name: not running"
        return 1
    fi
}

# Main operations
case "${1:-help}" in
    start)
        echo "Starting Day 2 monitoring services..."
        start_health_monitor
        start_system_monitor
        start_regression_scheduler
        echo "All monitoring services started"
        ;;
    stop) 
        echo "Stopping Day 2 monitoring services..."
        stop_service "Health Monitor" "$HEALTH_PID"
        stop_service "System Monitor" "$SYSTEM_PID" 
        stop_service "Regression Scheduler" "$REGRESSION_PID"
        echo "All monitoring services stopped"
        ;;
    restart)
        echo "Restarting Day 2 monitoring services..."
        "$0" stop
        sleep 2
        "$0" start
        ;;
    status)
        echo "Day 2 monitoring services status:"
        status_service "Health Monitor" "$HEALTH_PID"
        status_service "System Monitor" "$SYSTEM_PID"
        status_service "Regression Scheduler" "$REGRESSION_PID"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        echo
        echo "Manage Day 2 monitoring daemon processes"
        echo
        echo "Commands:"
        echo "  start    Start all monitoring services"
        echo "  stop     Stop all monitoring services"
        echo "  restart  Restart all monitoring services"
        echo "  status   Show status of all monitoring services"
        exit 1
        ;;
esac