#!/bin/bash

# Day 2 Automation Integration for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: Integrate existing Day 2 automation with deployment system

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-production}"
OPERATION="${2:-start}"

# Create log directories first
mkdir -p "${PROJECT_ROOT}/logs/day2-integration"
mkdir -p "${PROJECT_ROOT}/logs/monitoring"
mkdir -p "${PROJECT_ROOT}/logs/health-checks"
mkdir -p "${PROJECT_ROOT}/pids"

# Day 2 integration tracking
INTEGRATION_START_TIME=$(date +%s)
INTEGRATION_ID="day2-$(date +%Y%m%d-%H%M%S)"
INTEGRATION_LOG="${PROJECT_ROOT}/logs/day2-integration/${INTEGRATION_ID}.log"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$INTEGRATION_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$INTEGRATION_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$INTEGRATION_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$INTEGRATION_LOG"
}

# Utility functions
create_integration_directories() {
    log_info "Creating Day 2 integration directories..."
    
    local dirs=(
        "logs/day2-integration"
        "logs/monitoring"
        "logs/health-checks"
        "pids"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${PROJECT_ROOT}/${dir}"
    done
    
    log_success "Integration directories created"
}

validate_day2_scripts() {
    log_info "Validating Day 2 automation scripts..."
    
    local day2_scripts=(
        "scripts/day2-health-check.sh"
        "scripts/day2-smoke-test.sh"
        "scripts/day2-system-monitor.sh"
        "scripts/day2-regression-test.sh"
        "scripts/day2-run-all-tests.sh"
    )
    
    local valid_scripts=()
    local missing_scripts=()
    
    for script in "${day2_scripts[@]}"; do
        local script_path="${PROJECT_ROOT}/${script}"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            log_success "Day 2 script validated: $script"
            valid_scripts+=("$script")
        else
            log_warning "Day 2 script missing or not executable: $script"
            missing_scripts+=("$script")
        fi
    done
    
    log_info "Valid scripts: ${#valid_scripts[@]}, Missing scripts: ${#missing_scripts[@]}"
    
    if [[ ${#valid_scripts[@]} -lt 3 ]]; then
        log_error "Insufficient Day 2 scripts available for integration"
        return 1
    fi
    
    return 0
}

start_health_monitoring() {
    log_info "Starting continuous health monitoring..."
    
    # Use unified monitoring daemon
    if "${PROJECT_ROOT}/scripts/monitoring-daemon.sh" start >/dev/null 2>&1; then
        log_success "Health monitoring started successfully"
        return 0
    else
        log_error "Failed to start health monitoring"
        return 1
    fi
    
}

start_system_monitoring() {
    log_info "Starting system performance monitoring..."
    
    local monitor_script="${PROJECT_ROOT}/scripts/day2-system-monitor.sh"
    local monitoring_log="${PROJECT_ROOT}/logs/monitoring/system-monitoring.log"
    local pid_file="${PROJECT_ROOT}/pids/system-monitoring.pid"
    
    if [[ ! -f "$monitor_script" ]]; then
        log_warning "System monitor script not found: $monitor_script"
        return 0
    fi
    
    # Check if already running
    if [[ -f "$pid_file" ]]; then
        local existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_warning "System monitoring already running (PID: $existing_pid)"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    # Start system monitoring
    nohup "$monitor_script" --daemon --log-file "$monitoring_log" > /dev/null 2>&1 &
    local monitor_pid=$!
    echo "$monitor_pid" > "$pid_file"
    
    log_success "System monitoring started (PID: $monitor_pid)"
}

setup_regression_testing() {
    log_info "Setting up automated regression testing..."
    
    local regression_script="${PROJECT_ROOT}/scripts/day2-regression-test.sh"
    local test_log="${PROJECT_ROOT}/logs/monitoring/regression-tests.log"
    local pid_file="${PROJECT_ROOT}/pids/regression-tests.pid"
    
    if [[ ! -f "$regression_script" ]]; then
        log_warning "Regression test script not found: $regression_script"
        return 0
    fi
    
    # Setup cron-like regression testing (every 4 hours)
    nohup bash -c "
        while true; do
            echo \"[$(date)] Running regression tests...\" >> \"$test_log\"
            if \"$regression_script\" --automated >> \"$test_log\" 2>&1; then
                echo \"[$(date)] Regression tests passed\" >> \"$test_log\"
            else
                echo \"[$(date)] Regression tests failed\" >> \"$test_log\"
                # Could trigger alerts or notifications
            fi
            sleep 14400  # 4 hours
        done
    " > /dev/null 2>&1 &
    
    local test_pid=$!
    echo "$test_pid" > "$pid_file"
    
    log_success "Regression testing scheduled (PID: $test_pid)"
    log_info "Test interval: 4 hours"
}

run_initial_smoke_test() {
    log_info "Running initial smoke test..."
    
    local smoke_script="${PROJECT_ROOT}/scripts/day2-smoke-test.sh"
    
    if [[ ! -f "$smoke_script" ]]; then
        log_warning "Smoke test script not found: $smoke_script"
        return 0
    fi
    
    if "$smoke_script" --deployment-validation 2>&1 | tee -a "$INTEGRATION_LOG"; then
        log_success "Initial smoke test passed"
        return 0
    else
        log_error "Initial smoke test failed"
        return 1
    fi
}

stop_monitoring_services() {
    log_info "Stopping Day 2 monitoring services..."
    
    local pid_files=(
        "pids/health-monitoring.pid"
        "pids/system-monitoring.pid"
        "pids/regression-tests.pid"
    )
    
    local stopped_count=0
    
    for pid_file in "${pid_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${pid_file}"
        if [[ -f "$full_path" ]]; then
            local pid=$(cat "$full_path")
            local service_name=$(basename "$pid_file" .pid)
            
            if kill -0 "$pid" 2>/dev/null; then
                if kill "$pid" 2>/dev/null; then
                    log_success "Stopped $service_name (PID: $pid)"
                    ((stopped_count++))
                else
                    log_warning "Failed to stop $service_name (PID: $pid)"
                fi
            else
                log_info "$service_name was not running (stale PID file)"
            fi
            
            rm -f "$full_path"
        fi
    done
    
    log_info "Stopped $stopped_count monitoring services"
}

check_monitoring_status() {
    log_info "Checking Day 2 monitoring status..."
    
    local services=(
        "health-monitoring:Health Check Monitor"
        "system-monitoring:System Performance Monitor"
        "regression-tests:Regression Test Scheduler"
    )
    
    for service_def in "${services[@]}"; do
        local service="${service_def%%:*}"
        local description="${service_def##*:}"
        local pid_file="${PROJECT_ROOT}/pids/${service}.pid"
        
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                log_success "$description is running (PID: $pid)"
            else
                log_warning "$description has stale PID file"
                rm -f "$pid_file"
            fi
        else
            log_warning "$description is not running"
        fi
    done
}

create_monitoring_dashboard() {
    log_info "Creating monitoring dashboard configuration..."
    
    local dashboard_config="${PROJECT_ROOT}/monitoring/day2-dashboard-config.json"
    mkdir -p "$(dirname "$dashboard_config")"
    
    cat > "$dashboard_config" << 'EOF'
{
    "dashboard": {
        "title": "Kong AWS Masking MVP - Day 2 Operations",
        "version": "1.0.0",
        "environment": "${ENVIRONMENT}",
        "monitoring": {
            "health_checks": {
                "interval": "60s",
                "log_file": "logs/monitoring/health-monitoring.log",
                "alerts": {
                    "enabled": true,
                    "threshold": 3
                }
            },
            "system_metrics": {
                "interval": "30s",
                "log_file": "logs/monitoring/system-monitoring.log",
                "metrics": [
                    "cpu_usage",
                    "memory_usage",
                    "disk_usage",
                    "network_io"
                ]
            },
            "regression_tests": {
                "interval": "4h",
                "log_file": "logs/monitoring/regression-tests.log",
                "test_suites": [
                    "proxy_chain",
                    "aws_masking",
                    "redis_integration",
                    "performance"
                ]
            }
        },
        "endpoints": {
            "nginx_proxy": "http://localhost:${NGINX_PROXY_PORT:-8085}",
            "kong_admin": "http://localhost:${KONG_ADMIN_PORT:-8001}",
            "kong_proxy": "http://localhost:${KONG_PROXY_PORT:-8000}",
            "redis": "localhost:${REDIS_PORT:-6379}"
        }
    }
}
EOF
    
    log_success "Monitoring dashboard configuration created"
    log_info "Dashboard config: $dashboard_config"
}

generate_integration_report() {
    local integration_end_time=$(date +%s)
    local integration_duration=$((integration_end_time - INTEGRATION_START_TIME))
    
    log_info "Generating Day 2 integration report..."
    
    cat << EOF | tee -a "$INTEGRATION_LOG"

==========================================
Day 2 Automation Integration Report
==========================================
Integration ID: $INTEGRATION_ID
Environment: $ENVIRONMENT
Operation: $OPERATION
Start Time: $(date -d @$INTEGRATION_START_TIME)
End Time: $(date -d @$integration_end_time)
Duration: ${integration_duration} seconds

Monitoring Services Status:
$(check_monitoring_status 2>/dev/null || echo "Status check unavailable")

Available Day 2 Scripts:
$(find "${PROJECT_ROOT}/scripts" -name "day2-*.sh" -executable | wc -l) executable scripts found

Log Files:
- Integration Log: $INTEGRATION_LOG
- Health Monitoring: logs/monitoring/health-monitoring.log
- System Monitoring: logs/monitoring/system-monitoring.log
- Regression Tests: logs/monitoring/regression-tests.log

PID Files:
- Health Monitor: pids/health-monitoring.pid
- System Monitor: pids/system-monitoring.pid
- Regression Tests: pids/regression-tests.pid

Configuration:
- Dashboard Config: monitoring/day2-dashboard-config.json

Commands:
- Check Status: $0 $ENVIRONMENT status
- Stop Services: $0 $ENVIRONMENT stop
- Restart Services: $0 $ENVIRONMENT restart

==========================================
EOF

    log_success "Day 2 automation integration completed successfully!"
}

# Main integration process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Day 2 Integration"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Operation: $OPERATION"
    echo "Integration ID: $INTEGRATION_ID"
    echo "Timestamp: $(date)"
    echo
    
    # Create integration infrastructure
    create_integration_directories
    
    # Validate Day 2 scripts
    if ! validate_day2_scripts; then
        log_error "Day 2 script validation failed"
        exit 1
    fi
    
    case "$OPERATION" in
        "start")
            log_info "Starting Day 2 automation services..."
            
            # Run initial smoke test
            run_initial_smoke_test
            
            # Start monitoring services
            start_health_monitoring
            start_system_monitoring
            setup_regression_testing
            
            # Create dashboard configuration
            create_monitoring_dashboard
            ;;
            
        "stop")
            log_info "Stopping Day 2 automation services..."
            stop_monitoring_services
            ;;
            
        "restart")
            log_info "Restarting Day 2 automation services..."
            stop_monitoring_services
            sleep 5
            start_health_monitoring
            start_system_monitoring
            setup_regression_testing
            ;;
            
        "status")
            log_info "Checking Day 2 automation status..."
            check_monitoring_status
            ;;
            
        *)
            log_error "Unknown operation: $OPERATION"
            echo "Available operations: start, stop, restart, status"
            exit 1
            ;;
    esac
    
    # Generate final report
    generate_integration_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment] [operation]"
    echo
    echo "Integrate Day 2 automation with Kong AWS Masking MVP deployment"
    echo
    echo "Arguments:"
    echo "  environment    Target environment (development|staging|production)"
    echo "  operation      Operation to perform (start|stop|restart|status)"
    echo "                 Default: start"
    echo
    echo "Operations:"
    echo "  start          Start all Day 2 monitoring services"
    echo "  stop           Stop all Day 2 monitoring services"
    echo "  restart        Restart all Day 2 monitoring services"
    echo "  status         Check status of Day 2 monitoring services"
    echo
    echo "Examples:"
    echo "  $0 production start        # Start Day 2 automation"
    echo "  $0 staging status          # Check automation status"
    echo "  $0 production restart      # Restart all services"
    echo
    exit 0
fi

# Run main function
main "$@"