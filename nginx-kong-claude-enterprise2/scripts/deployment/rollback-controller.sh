#!/bin/sh
# Automatic Rollback Controller
# Monitors deployment health and triggers rollback if thresholds are exceeded

set -e

# Configuration
ROLLBACK_THRESHOLD_ERROR_RATE=${ROLLBACK_THRESHOLD_ERROR_RATE:-5}
ROLLBACK_THRESHOLD_RESPONSE_TIME=${ROLLBACK_THRESHOLD_RESPONSE_TIME:-5000}
ROLLBACK_CHECK_INTERVAL=${ROLLBACK_CHECK_INTERVAL:-30}
METRICS_WINDOW=${METRICS_WINDOW:-300}  # 5 minutes

# State file
STATE_FILE="/deployments/rollback-state.json"
METRICS_FILE="/deployments/metrics.json"

# Initialize state
initialize_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo '{"deployment_version":"'${DEPLOYMENT_VERSION}'","start_time":'$(date +%s)',"rollback_triggered":false}' > "$STATE_FILE"
    fi
}

# Collect metrics from services
collect_metrics() {
    local timestamp=$(date +%s)
    local error_count=0
    local total_requests=0
    local avg_response_time=0
    
    # Get Kong metrics
    if kong_metrics=$(wget -qO- http://kong:8100/status 2>/dev/null); then
        # Parse metrics (simplified for Alpine compatibility)
        total_requests=$(echo "$kong_metrics" | grep -o '"total":[0-9]*' | cut -d: -f2 | head -1)
        error_count=$(echo "$kong_metrics" | grep -o '"5xx":[0-9]*' | cut -d: -f2 | head -1)
    fi
    
    # Get Nginx metrics from access logs
    if [ -f "/var/log/nginx/access.log" ]; then
        # Calculate average response time from last N minutes
        avg_response_time=$(tail -n 1000 /var/log/nginx/access.log | \
            awk -v window=$METRICS_WINDOW -v now=$(date +%s) '
            {
                # Parse nginx log timestamp and response time
                # Assuming standard log format
                if ($NF ~ /^[0-9.]+$/) {
                    sum += $NF
                    count++
                }
            }
            END {
                if (count > 0) print int(sum/count * 1000)
                else print 0
            }')
    fi
    
    # Calculate error rate
    local error_rate=0
    if [ "$total_requests" -gt 0 ]; then
        error_rate=$((error_count * 100 / total_requests))
    fi
    
    # Save metrics
    cat > "$METRICS_FILE" <<EOF
{
    "timestamp": $timestamp,
    "total_requests": ${total_requests:-0},
    "error_count": ${error_count:-0},
    "error_rate": ${error_rate:-0},
    "avg_response_time": ${avg_response_time:-0}
}
EOF
    
    echo "Metrics collected - Error rate: ${error_rate}%, Avg response time: ${avg_response_time}ms"
}

# Check if rollback is needed
check_rollback_conditions() {
    if [ ! -f "$METRICS_FILE" ]; then
        return 1
    fi
    
    # Read current metrics
    local error_rate=$(grep -o '"error_rate":[0-9]*' "$METRICS_FILE" | cut -d: -f2)
    local avg_response_time=$(grep -o '"avg_response_time":[0-9]*' "$METRICS_FILE" | cut -d: -f2)
    
    # Check error rate threshold
    if [ "$error_rate" -gt "$ROLLBACK_THRESHOLD_ERROR_RATE" ]; then
        echo "ERROR: Error rate ${error_rate}% exceeds threshold ${ROLLBACK_THRESHOLD_ERROR_RATE}%"
        return 0
    fi
    
    # Check response time threshold
    if [ "$avg_response_time" -gt "$ROLLBACK_THRESHOLD_RESPONSE_TIME" ]; then
        echo "ERROR: Average response time ${avg_response_time}ms exceeds threshold ${ROLLBACK_THRESHOLD_RESPONSE_TIME}ms"
        return 0
    fi
    
    return 1
}

# Trigger rollback
trigger_rollback() {
    echo "ALERT: Triggering automatic rollback!"
    
    # Update state
    local state=$(cat "$STATE_FILE")
    echo "$state" | sed 's/"rollback_triggered":false/"rollback_triggered":true/' > "$STATE_FILE"
    
    # Send alert (integrate with your alerting system)
    if [ -n "$ALERT_WEBHOOK_URL" ]; then
        wget -qO- --post-data='{
            "text": "Automatic rollback triggered for deployment '${DEPLOYMENT_VERSION}'",
            "severity": "critical",
            "metrics": '"$(cat $METRICS_FILE)"'
        }' "$ALERT_WEBHOOK_URL" || true
    fi
    
    # Execute rollback
    if [ -x "/rollback.sh" ]; then
        /rollback.sh auto
    else
        echo "ERROR: Rollback script not found!"
        exit 1
    fi
}

# Main monitoring loop
main() {
    echo "Starting rollback controller for deployment: ${DEPLOYMENT_VERSION}"
    
    # Initialize
    mkdir -p /deployments
    initialize_state
    
    # Grace period for new deployment
    echo "Waiting for deployment stabilization (60s)..."
    sleep 60
    
    # Monitoring loop
    while true; do
        # Check if rollback was already triggered
        if grep -q '"rollback_triggered":true' "$STATE_FILE" 2>/dev/null; then
            echo "Rollback already triggered, exiting..."
            exit 0
        fi
        
        # Collect metrics
        collect_metrics
        
        # Check rollback conditions
        if check_rollback_conditions; then
            trigger_rollback
            exit 1
        fi
        
        # Wait before next check
        sleep "$ROLLBACK_CHECK_INTERVAL"
    done
}

# Run main function
main