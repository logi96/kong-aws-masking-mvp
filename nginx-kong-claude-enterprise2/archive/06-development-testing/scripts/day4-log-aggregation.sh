#!/bin/bash

# Day 4 Log Aggregation and Analysis System
# Purpose: Aggregate, analyze, and classify logs from Kong, Nginx, Redis, and Backend services
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create required directories
mkdir -p "${PROJECT_ROOT}/logs/monitoring/day4/aggregated"
mkdir -p "${PROJECT_ROOT}/logs/monitoring/day4/analysis"
mkdir -p "${PROJECT_ROOT}/logs/monitoring/day4/reports"

# Log source paths
KONG_ACCESS_LOG="${PROJECT_ROOT}/logs/kong/access.log"
KONG_ERROR_LOG="${PROJECT_ROOT}/logs/kong/error.log"
KONG_ADMIN_LOG="${PROJECT_ROOT}/logs/kong/admin_access.log"
NGINX_ACCESS_LOG="${PROJECT_ROOT}/logs/nginx/access.log"
NGINX_ERROR_LOG="${PROJECT_ROOT}/logs/nginx/error.log"
BACKEND_LOG="${PROJECT_ROOT}/backend/logs/combined.log"
BACKEND_ERROR_LOG="${PROJECT_ROOT}/backend/logs/error.log"
HEALTH_LOG="${PROJECT_ROOT}/logs/monitoring/health-monitoring.log"
SYSTEM_LOG="${PROJECT_ROOT}/logs/monitoring/system-monitoring.log"
REGRESSION_LOG="${PROJECT_ROOT}/logs/monitoring/regression-tests.log"

# Output paths
AGGREGATED_LOG="${PROJECT_ROOT}/logs/monitoring/day4/aggregated/all-logs-$(date +%Y%m%d_%H%M%S).log"
ERROR_ANALYSIS="${PROJECT_ROOT}/logs/monitoring/day4/analysis/error-analysis-$(date +%Y%m%d_%H%M%S).json"
TREND_REPORT="${PROJECT_ROOT}/logs/monitoring/day4/reports/trend-report-$(date +%Y%m%d_%H%M%S).json"
LOG_SUMMARY="${PROJECT_ROOT}/logs/monitoring/day4/analysis/log-summary-$(date +%Y%m%d_%H%M%S).log"

# Functions
log_message() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [LOG-AGGREGATOR] $message"
}

# Aggregate all logs with timestamps and sources
aggregate_logs() {
    log_message "Starting log aggregation process..."
    
    # Initialize aggregated log file
    echo "=== Kong AWS Masking Enterprise 2 - Day 4 Log Aggregation ===" > "$AGGREGATED_LOG"
    echo "Aggregation Start Time: $(date)" >> "$AGGREGATED_LOG"
    echo "=======================================================" >> "$AGGREGATED_LOG"
    echo >> "$AGGREGATED_LOG"
    
    local total_lines=0
    
    # Process Kong access logs
    if [[ -f "$KONG_ACCESS_LOG" ]]; then
        echo "=== KONG ACCESS LOGS ===" >> "$AGGREGATED_LOG"
        local kong_access_lines=$(wc -l < "$KONG_ACCESS_LOG" 2>/dev/null || echo "0")
        tail -n 1000 "$KONG_ACCESS_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[KONG-ACCESS] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + kong_access_lines))
        echo >> "$AGGREGATED_LOG"
        log_message "Processed Kong access logs: $kong_access_lines lines"
    fi
    
    # Process Kong error logs
    if [[ -f "$KONG_ERROR_LOG" ]]; then
        echo "=== KONG ERROR LOGS ===" >> "$AGGREGATED_LOG"
        local kong_error_lines=$(wc -l < "$KONG_ERROR_LOG" 2>/dev/null || echo "0")
        tail -n 500 "$KONG_ERROR_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[KONG-ERROR] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + kong_error_lines))
        echo >> "$AGGREGATED_LOG" 
        log_message "Processed Kong error logs: $kong_error_lines lines"
    fi
    
    # Process Nginx logs
    if [[ -f "$NGINX_ACCESS_LOG" ]]; then
        echo "=== NGINX ACCESS LOGS ===" >> "$AGGREGATED_LOG"
        local nginx_access_lines=$(wc -l < "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
        tail -n 500 "$NGINX_ACCESS_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[NGINX-ACCESS] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + nginx_access_lines))
        echo >> "$AGGREGATED_LOG"
        log_message "Processed Nginx access logs: $nginx_access_lines lines"
    fi
    
    if [[ -f "$NGINX_ERROR_LOG" ]]; then
        echo "=== NGINX ERROR LOGS ===" >> "$AGGREGATED_LOG"
        local nginx_error_lines=$(wc -l < "$NGINX_ERROR_LOG" 2>/dev/null || echo "0")
        tail -n 500 "$NGINX_ERROR_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[NGINX-ERROR] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + nginx_error_lines))
        echo >> "$AGGREGATED_LOG"
        log_message "Processed Nginx error logs: $nginx_error_lines lines"
    fi
    
    # Process Backend logs
    if [[ -f "$BACKEND_LOG" ]]; then
        echo "=== BACKEND LOGS ===" >> "$AGGREGATED_LOG"
        local backend_lines=$(wc -l < "$BACKEND_LOG" 2>/dev/null || echo "0")
        tail -n 500 "$BACKEND_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[BACKEND] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + backend_lines))
        echo >> "$AGGREGATED_LOG"
        log_message "Processed Backend logs: $backend_lines lines"
    fi
    
    # Process monitoring logs
    if [[ -f "$HEALTH_LOG" ]]; then
        echo "=== HEALTH MONITORING LOGS ===" >> "$AGGREGATED_LOG"
        local health_lines=$(wc -l < "$HEALTH_LOG" 2>/dev/null || echo "0")
        tail -n 100 "$HEALTH_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[HEALTH-MONITOR] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + health_lines))
        echo >> "$AGGREGATED_LOG"
        log_message "Processed Health monitoring logs: $health_lines lines"
    fi
    
    if [[ -f "$SYSTEM_LOG" ]]; then
        echo "=== SYSTEM MONITORING LOGS ===" >> "$AGGREGATED_LOG"
        local system_lines=$(wc -l < "$SYSTEM_LOG" 2>/dev/null || echo "0")
        tail -n 100 "$SYSTEM_LOG" 2>/dev/null | while IFS= read -r line; do
            echo "[SYSTEM-MONITOR] $line" >> "$AGGREGATED_LOG"
        done || true
        total_lines=$((total_lines + system_lines))
        echo >> "$AGGREGATED_LOG"
        log_message "Processed System monitoring logs: $system_lines lines"
    fi
    
    # Add summary to aggregated log
    echo "=== AGGREGATION SUMMARY ===" >> "$AGGREGATED_LOG"
    echo "Total lines processed: $total_lines" >> "$AGGREGATED_LOG"
    echo "Aggregation End Time: $(date)" >> "$AGGREGATED_LOG"
    echo "===============================" >> "$AGGREGATED_LOG"
    
    log_message "Log aggregation completed: $total_lines total lines"
}

# Analyze errors and classify them
analyze_errors() {
    log_message "Starting error analysis..."
    
    local error_patterns=(
        "ERROR"
        "CRITICAL"
        "FATAL"
        "Exception"
        "failed"
        "timeout"
        "connection refused"
        "500"
        "502"
        "503"
        "504"
    )
    
    local error_counts=()
    local total_errors=0
    
    # Count each error type
    for pattern in "${error_patterns[@]}"; do
        local count=0
        if [[ -f "$AGGREGATED_LOG" ]]; then
            count=$(grep -ci "$pattern" "$AGGREGATED_LOG" 2>/dev/null || echo "0")
        fi
        error_counts+=("$count")
        total_errors=$((total_errors + count))
    done
    
    # Analyze Kong-specific errors
    local kong_plugin_errors=0
    local kong_auth_errors=0
    local masking_errors=0
    
    if [[ -f "$AGGREGATED_LOG" ]]; then
        kong_plugin_errors=$(grep -c "plugin.*error" "$AGGREGATED_LOG" 2>/dev/null || echo "0")
        kong_auth_errors=$(grep -c "auth.*failed\|unauthorized" "$AGGREGATED_LOG" 2>/dev/null || echo "0")
        masking_errors=$(grep -c "masking.*error\|mask.*failed" "$AGGREGATED_LOG" 2>/dev/null || echo "0")
    fi
    
    # Recent error trends (last hour)
    local recent_errors=0
    local current_hour=$(date "+%Y-%m-%d %H")
    if [[ -f "$AGGREGATED_LOG" ]]; then
        recent_errors=$(grep "$current_hour" "$AGGREGATED_LOG" | grep -ci "error\|failed\|exception" 2>/dev/null || echo "0")
    fi
    
    # Generate error analysis JSON
    cat > "$ERROR_ANALYSIS" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "error_analysis": {
        "total_errors": $total_errors,
        "recent_errors_last_hour": $recent_errors,
        "error_breakdown": {
$(for i in "${!error_patterns[@]}"; do
    echo "            \"${error_patterns[$i]}\": ${error_counts[$i]},"
done | sed '$ s/,$//')
        },
        "kong_specific_errors": {
            "plugin_errors": $kong_plugin_errors,
            "auth_errors": $kong_auth_errors,
            "masking_errors": $masking_errors
        },
        "error_rate": {
            "errors_per_hour": $recent_errors,
            "severity_classification": {
                "critical": $(( (kong_plugin_errors + masking_errors + kong_auth_errors) )),
                "warning": $(( total_errors - (kong_plugin_errors + masking_errors + kong_auth_errors) )),
                "info": 0
            }
        }
    }
}
EOF
    
    log_message "Error analysis completed: $total_errors total errors, $recent_errors recent errors"
}

# Generate trend analysis
generate_trend_analysis() {
    log_message "Generating trend analysis..."
    
    # Analyze system health trends
    local health_checks_total=0
    local health_checks_success=0
    local health_checks_failed=0
    
    if [[ -f "$HEALTH_LOG" ]]; then
        health_checks_total=$(wc -l < "$HEALTH_LOG" 2>/dev/null || echo "0")
        health_checks_success=$(grep -c "✅ System healthy" "$HEALTH_LOG" 2>/dev/null || echo "0")
        health_checks_failed=$(grep -c "❌ System unhealthy" "$HEALTH_LOG" 2>/dev/null || echo "0")
    fi
    
    # Calculate health success rate
    local health_success_rate=0
    if [[ $health_checks_total -gt 0 ]]; then
        health_success_rate=$(( health_checks_success * 100 / health_checks_total ))
    fi
    
    # Analyze system resource trends
    local high_cpu_instances=0
    local high_memory_instances=0
    
    if [[ -f "$SYSTEM_LOG" ]]; then
        # Count instances where CPU > 50% or Memory > 50%
        high_cpu_instances=$(awk '{if($2 ~ /[5-9][0-9]\.[0-9]+%|100\.00%/) print}' "$SYSTEM_LOG" 2>/dev/null | wc -l || echo "0")
        high_memory_instances=$(awk '{print $3}' "$SYSTEM_LOG" | grep -E "([5-9][0-9]\.[0-9]+%|100\.00%)" 2>/dev/null | wc -l || echo "0")
    fi
    
    # Analyze request patterns (last 24 hours)
    local total_requests=0
    local successful_requests=0
    local error_requests=0
    
    if [[ -f "$KONG_ACCESS_LOG" ]]; then
        total_requests=$(wc -l < "$KONG_ACCESS_LOG" 2>/dev/null || echo "0")
        successful_requests=$(grep -c "\" 200 \|\" 201 \|\" 204 " "$KONG_ACCESS_LOG" 2>/dev/null || echo "0")
        error_requests=$(grep -c "\" 400 \|\" 401 \|\" 403 \|\" 404 \|\" 500 \|\" 502 \|\" 503 " "$KONG_ACCESS_LOG" 2>/dev/null || echo "0")
    fi
    
    # Calculate request success rate
    local request_success_rate=0
    if [[ $total_requests -gt 0 ]]; then
        request_success_rate=$(( successful_requests * 100 / total_requests ))
    fi
    
    # Generate trend report JSON
    cat > "$TREND_REPORT" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "trend_analysis": {
        "analysis_period_hours": 24,
        "system_health_trends": {
            "total_health_checks": $health_checks_total,
            "successful_checks": $health_checks_success,
            "failed_checks": $health_checks_failed,
            "health_success_rate_percent": $health_success_rate,
            "trend": "$(if [[ $health_success_rate -gt 95 ]]; then echo "stable"; elif [[ $health_success_rate -gt 80 ]]; then echo "concerning"; else echo "critical"; fi)"
        },
        "resource_usage_trends": {
            "high_cpu_instances": $high_cpu_instances,
            "high_memory_instances": $high_memory_instances,
            "resource_pressure": "$(if [[ $((high_cpu_instances + high_memory_instances)) -gt 10 ]]; then echo "high"; elif [[ $((high_cpu_instances + high_memory_instances)) -gt 5 ]]; then echo "medium"; else echo "low"; fi)"
        },
        "request_patterns": {
            "total_requests": $total_requests,
            "successful_requests": $successful_requests,
            "error_requests": $error_requests,
            "success_rate_percent": $request_success_rate,
            "requests_per_hour": $(( total_requests / 24 )),
            "error_rate_percent": $(( error_requests * 100 / (total_requests > 0 ? total_requests : 1) ))
        },
        "recommendations": [
$(if [[ $health_success_rate -lt 95 ]]; then echo '            "Investigate health check failures - success rate below 95%",'; fi)
$(if [[ $((high_cpu_instances + high_memory_instances)) -gt 10 ]]; then echo '            "High resource usage detected - consider scaling",'; fi)
$(if [[ $request_success_rate -lt 90 ]]; then echo '            "Request success rate below 90% - investigate errors",'; fi)
            "Continue monitoring trends for early issue detection"
        ]
    }
}
EOF
    
    log_message "Trend analysis completed: ${health_success_rate}% health success rate, ${request_success_rate}% request success rate"
}

# Generate comprehensive log summary
generate_log_summary() {
    log_message "Generating comprehensive log summary..."
    
    cat > "$LOG_SUMMARY" << EOF
=== Kong AWS Masking Enterprise 2 - Day 4 Log Analysis Summary ===
Generated: $(date)
Analysis Period: Last 24 hours

=== LOG FILE STATUS ===
Kong Access Log: $(if [[ -f "$KONG_ACCESS_LOG" ]]; then echo "✅ $(wc -l < "$KONG_ACCESS_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)
Kong Error Log: $(if [[ -f "$KONG_ERROR_LOG" ]]; then echo "✅ $(wc -l < "$KONG_ERROR_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)
Nginx Access Log: $(if [[ -f "$NGINX_ACCESS_LOG" ]]; then echo "✅ $(wc -l < "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)
Nginx Error Log: $(if [[ -f "$NGINX_ERROR_LOG" ]]; then echo "✅ $(wc -l < "$NGINX_ERROR_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)
Backend Log: $(if [[ -f "$BACKEND_LOG" ]]; then echo "✅ $(wc -l < "$BACKEND_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)
Health Monitoring: $(if [[ -f "$HEALTH_LOG" ]]; then echo "✅ $(wc -l < "$HEALTH_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)
System Monitoring: $(if [[ -f "$SYSTEM_LOG" ]]; then echo "✅ $(wc -l < "$SYSTEM_LOG" 2>/dev/null || echo "0") lines"; else echo "❌ Not found"; fi)

=== ERROR SUMMARY ===
EOF
    
    # Add error summary from analysis
    if [[ -f "$ERROR_ANALYSIS" ]]; then
        echo "Total Errors Found: $(jq -r '.error_analysis.total_errors' "$ERROR_ANALYSIS")" >> "$LOG_SUMMARY"
        echo "Recent Errors (Last Hour): $(jq -r '.error_analysis.recent_errors_last_hour' "$ERROR_ANALYSIS")" >> "$LOG_SUMMARY"
        echo "Kong Plugin Errors: $(jq -r '.error_analysis.kong_specific_errors.plugin_errors' "$ERROR_ANALYSIS")" >> "$LOG_SUMMARY"
        echo "Authentication Errors: $(jq -r '.error_analysis.kong_specific_errors.auth_errors' "$ERROR_ANALYSIS")" >> "$LOG_SUMMARY"
        echo "Masking Errors: $(jq -r '.error_analysis.kong_specific_errors.masking_errors' "$ERROR_ANALYSIS")" >> "$LOG_SUMMARY"
    fi
    
    cat >> "$LOG_SUMMARY" << EOF

=== TREND ANALYSIS ===
EOF
    
    # Add trend summary
    if [[ -f "$TREND_REPORT" ]]; then
        echo "Health Check Success Rate: $(jq -r '.trend_analysis.system_health_trends.health_success_rate_percent' "$TREND_REPORT")%" >> "$LOG_SUMMARY"
        echo "Request Success Rate: $(jq -r '.trend_analysis.request_patterns.success_rate_percent' "$TREND_REPORT")%" >> "$LOG_SUMMARY"
        echo "Resource Pressure Level: $(jq -r '.trend_analysis.resource_usage_trends.resource_pressure' "$TREND_REPORT")" >> "$LOG_SUMMARY"
        echo "Health Trend Status: $(jq -r '.trend_analysis.system_health_trends.trend' "$TREND_REPORT")" >> "$LOG_SUMMARY"
    fi
    
    cat >> "$LOG_SUMMARY" << EOF

=== OUTPUT FILES ===
Aggregated Log: $AGGREGATED_LOG
Error Analysis: $ERROR_ANALYSIS
Trend Report: $TREND_REPORT
Log Summary: $LOG_SUMMARY

=== RECOMMENDATIONS ===
EOF
    
    # Add recommendations
    if [[ -f "$TREND_REPORT" ]]; then
        jq -r '.trend_analysis.recommendations[]' "$TREND_REPORT" | while IFS= read -r recommendation; do
            echo "• $recommendation" >> "$LOG_SUMMARY"
        done
    fi
    
    cat >> "$LOG_SUMMARY" << EOF

============================================================
Analysis completed at: $(date)
============================================================
EOF
    
    log_message "Log summary generated: $LOG_SUMMARY"
}

# Main aggregation and analysis function
run_full_analysis() {
    log_message "Starting comprehensive log aggregation and analysis..."
    
    aggregate_logs
    analyze_errors
    generate_trend_analysis
    generate_log_summary
    
    log_message "✅ Complete log analysis finished"
    
    # Display summary
    echo
    echo "=== Day 4 Log Analysis Summary ==="
    echo "Aggregated Log: $AGGREGATED_LOG"
    echo "Error Analysis: $ERROR_ANALYSIS"
    echo "Trend Report: $TREND_REPORT"
    echo "Log Summary: $LOG_SUMMARY"
    echo
    
    if [[ -f "$ERROR_ANALYSIS" ]]; then
        echo "Total Errors: $(jq -r '.error_analysis.total_errors' "$ERROR_ANALYSIS")"
        echo "Recent Errors: $(jq -r '.error_analysis.recent_errors_last_hour' "$ERROR_ANALYSIS")"
    fi
    
    if [[ -f "$TREND_REPORT" ]]; then
        echo "Health Success Rate: $(jq -r '.trend_analysis.system_health_trends.health_success_rate_percent' "$TREND_REPORT")%"
        echo "Request Success Rate: $(jq -r '.trend_analysis.request_patterns.success_rate_percent' "$TREND_REPORT")%"
    fi
    echo "=================================="
}

# Main execution
case "${1:-full}" in
    full)
        run_full_analysis
        ;;
    aggregate)
        aggregate_logs
        ;;
    analyze-errors)
        analyze_errors
        ;;
    trends)
        generate_trend_analysis
        ;;
    summary)
        generate_log_summary
        ;;
    help)
        echo "Day 4 Log Aggregation and Analysis System"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  full           Run complete analysis (aggregate + analyze + trends + summary)"
        echo "  aggregate      Aggregate logs from all sources only"
        echo "  analyze-errors Analyze and classify errors only"
        echo "  trends         Generate trend analysis only"
        echo "  summary        Generate log summary only"
        echo "  help           Show this help message"
        echo
        echo "Output files will be created in:"
        echo "  - logs/monitoring/day4/aggregated/"
        echo "  - logs/monitoring/day4/analysis/"
        echo "  - logs/monitoring/day4/reports/"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac