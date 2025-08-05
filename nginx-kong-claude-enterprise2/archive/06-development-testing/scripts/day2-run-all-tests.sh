#!/bin/bash

#
# Day 2: Integrated Test Runner - Kong AWS Masking MVP
# 
# Purpose: Orchestrate all Day 2 automation scripts for comprehensive validation
# Target: Execute health check, smoke test, regression test in sequence
# Success Criteria: All tests pass or provide clear failure guidance
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test execution tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
START_TIME=$(date +%s)

# Create comprehensive report
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
COMPREHENSIVE_REPORT="$REPORT_DIR/day2-comprehensive-test-$TIMESTAMP.md"
mkdir -p "$REPORT_DIR"

# Test suite results
declare -a SUITE_RESULTS
declare -a SUITE_DETAILS

# Usage information
usage() {
    cat << EOF
Kong AWS Masking MVP - Day 2 Test Runner

USAGE:
    $0 [OPTIONS] [TEST_MODE]

TEST MODES:
    quick       - Health check + Core smoke test only (~2 minutes)
    standard    - Health + Smoke + Regression tests (~5 minutes)
    full        - All tests + System monitoring (~7 minutes)
    monitor     - System monitoring only (continuous mode)

OPTIONS:
    --silent    - Suppress detailed output, log to files only
    --report    - Generate only comprehensive report from existing results
    --help, -h  - Show this help message

EXAMPLES:
    $0 quick                    # Quick deployment validation
    $0 standard                 # Standard pre-deployment testing
    $0 full                     # Complete validation suite
    $0 monitor                  # Continuous monitoring mode
    $0 --silent standard        # Run tests quietly
    $0 --report                 # Generate comprehensive report only

EXIT CODES:
    0  - All tests passed
    1  - Critical tests failed, do not deploy
    2  - Minor failures, deployment with caution
    3  - Configuration or execution error

EOF
}

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}" | tee -a "$COMPREHENSIVE_REPORT"
}

log_suite_start() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')] === $1 ===${NC}" | tee -a "$COMPREHENSIVE_REPORT"
}

log_suite_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}" | tee -a "$COMPREHENSIVE_REPORT"
    PASSED_SUITES=$((PASSED_SUITES + 1))
}

log_suite_failure() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}" | tee -a "$COMPREHENSIVE_REPORT"
    FAILED_SUITES=$((FAILED_SUITES + 1))
}

log_suite_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️ $1${NC}" | tee -a "$COMPREHENSIVE_REPORT"
}

# Initialize comprehensive report
init_comprehensive_report() {
    cat > "$COMPREHENSIVE_REPORT" << EOF
# Day 2: Comprehensive Test Execution Report

**Execution Time**: $(date '+%Y-%m-%d %H:%M:%S')  
**Purpose**: Comprehensive validation for continuous deployment  
**Mode**: ${TEST_MODE:-standard}  
**Baseline**: Day 1 achieved 95% success rate

## Test Environment
- Kong Proxy: $KONG_PROXY_URL
- Kong Admin: $KONG_ADMIN_URL
- Nginx Proxy: $NGINX_URL  
- Redis: $REDIS_HOST:$REDIS_PORT
- Test Mode: ${TEST_MODE:-standard}

---

## Test Execution Log

EOF
}

# Run health check suite
run_health_check() {
    log_suite_start "HEALTH CHECK SUITE"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    local start_time=$(date +%s)
    local health_script="$SCRIPT_DIR/day2-health-check.sh"
    
    if [[ ! -x "$health_script" ]]; then
        log_suite_failure "Health check script not found or not executable: $health_script"
        SUITE_RESULTS+=("health_check:FAILED:CRITICAL")
        SUITE_DETAILS+=("health_check:Script not found")
        return 1
    fi
    
    # Execute health check
    if [[ "${SILENT_MODE:-false}" == "true" ]]; then
        if "$health_script" > /dev/null 2>&1; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    else
        if "$health_script"; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    fi
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    # Analyze results
    if [[ $exit_code -eq 0 ]]; then
        log_suite_success "Health Check: PASSED (${execution_time}s)"
        SUITE_RESULTS+=("health_check:PASSED:CRITICAL")
        SUITE_DETAILS+=("health_check:All systems healthy:${execution_time}s")
    else
        log_suite_failure "Health Check: FAILED (exit code: $exit_code, ${execution_time}s)"
        SUITE_RESULTS+=("health_check:FAILED:CRITICAL")
        SUITE_DETAILS+=("health_check:System issues detected:${execution_time}s")
        return 1
    fi
    
    return 0
}

# Run smoke test suite
run_smoke_test() {
    log_suite_start "SMOKE TEST SUITE"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    local start_time=$(date +%s)
    local smoke_script="$SCRIPT_DIR/day2-smoke-test.sh"
    
    if [[ ! -x "$smoke_script" ]]; then
        log_suite_failure "Smoke test script not found or not executable: $smoke_script"
        SUITE_RESULTS+=("smoke_test:FAILED:CRITICAL")
        SUITE_DETAILS+=("smoke_test:Script not found")
        return 1
    fi
    
    # Execute smoke test
    if [[ "${SILENT_MODE:-false}" == "true" ]]; then
        if "$smoke_script" > /dev/null 2>&1; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    else
        if "$smoke_script"; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    fi
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    # Analyze results
    if [[ $exit_code -eq 0 ]]; then
        log_suite_success "Smoke Test: PASSED (${execution_time}s)"
        SUITE_RESULTS+=("smoke_test:PASSED:CRITICAL")
        SUITE_DETAILS+=("smoke_test:Core functionality validated:${execution_time}s")
    else
        log_suite_failure "Smoke Test: FAILED (exit code: $exit_code, ${execution_time}s)"
        SUITE_RESULTS+=("smoke_test:FAILED:CRITICAL")
        SUITE_DETAILS+=("smoke_test:Core functionality issues:${execution_time}s")
        return 1
    fi
    
    return 0
}

# Run regression test suite
run_regression_test() {
    log_suite_start "REGRESSION TEST SUITE"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    local start_time=$(date +%s)
    local regression_script="$SCRIPT_DIR/day2-regression-test.sh"
    
    if [[ ! -x "$regression_script" ]]; then
        log_suite_failure "Regression test script not found or not executable: $regression_script"
        SUITE_RESULTS+=("regression_test:FAILED:IMPORTANT")
        SUITE_DETAILS+=("regression_test:Script not found")
        return 1
    fi
    
    # Execute regression test
    if [[ "${SILENT_MODE:-false}" == "true" ]]; then
        if "$regression_script" > /dev/null 2>&1; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    else
        if "$regression_script"; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    fi
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    # Analyze results (more nuanced for regression)
    if [[ $exit_code -eq 0 ]]; then
        log_suite_success "Regression Test: PASSED (${execution_time}s)"
        SUITE_RESULTS+=("regression_test:PASSED:IMPORTANT")
        SUITE_DETAILS+=("regression_test:No regression detected:${execution_time}s")
    elif [[ $exit_code -eq 1 ]]; then
        log_suite_failure "Regression Test: FAILED (${execution_time}s)"
        SUITE_RESULTS+=("regression_test:FAILED:IMPORTANT")
        SUITE_DETAILS+=("regression_test:Regression detected:${execution_time}s")
        return 1
    else
        log_suite_warning "Regression Test: WARNING (exit code: $exit_code, ${execution_time}s)"
        SUITE_RESULTS+=("regression_test:WARNING:IMPORTANT")
        SUITE_DETAILS+=("regression_test:Minor issues detected:${execution_time}s")
    fi
    
    return 0
}

# Run system monitoring (single check)
run_system_monitoring() {
    log_suite_start "SYSTEM MONITORING SUITE"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    local start_time=$(date +%s)
    local monitor_script="$SCRIPT_DIR/day2-system-monitor.sh"
    
    if [[ ! -x "$monitor_script" ]]; then
        log_suite_failure "System monitor script not found or not executable: $monitor_script"
        SUITE_RESULTS+=("system_monitor:FAILED:OPTIONAL")
        SUITE_DETAILS+=("system_monitor:Script not found")
        return 1
    fi
    
    # Execute system monitoring (single run)
    if [[ "${SILENT_MODE:-false}" == "true" ]]; then
        if "$monitor_script" --silent > /dev/null 2>&1; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    else
        if "$monitor_script"; then
            local exit_code=0
        else
            local exit_code=$?
        fi
    fi
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    # Analyze results
    if [[ $exit_code -eq 0 ]]; then
        log_suite_success "System Monitoring: PASSED (${execution_time}s)"
        SUITE_RESULTS+=("system_monitor:PASSED:OPTIONAL")
        SUITE_DETAILS+=("system_monitor:System healthy:${execution_time}s")
    else
        log_suite_warning "System Monitoring: WARNING (exit code: $exit_code, ${execution_time}s)"
        SUITE_RESULTS+=("system_monitor:WARNING:OPTIONAL")
        SUITE_DETAILS+=("system_monitor:System warnings:${execution_time}s")
    fi
    
    return 0
}

# Run continuous monitoring mode
run_continuous_monitoring() {
    log_suite_start "CONTINUOUS MONITORING MODE"
    
    local monitor_script="$SCRIPT_DIR/day2-system-monitor.sh"
    
    if [[ ! -x "$monitor_script" ]]; then
        log_suite_failure "System monitor script not found: $monitor_script"
        return 1
    fi
    
    log "Starting continuous monitoring..."
    log "Press Ctrl+C to stop monitoring"
    
    # Run monitoring every 5 minutes
    while true; do
        log "Running system monitoring check..."
        if "$monitor_script" --silent; then
            log "Monitoring check completed successfully"
        else
            log_suite_warning "Monitoring check reported warnings/alerts"
        fi
        
        log "Waiting ${MONITOR_INTERVAL:-300} seconds until next check..."
        sleep ${MONITOR_INTERVAL:-300}
    done
}

# Generate comprehensive final report
generate_comprehensive_report() {
    local end_time=$(date +%s)
    local total_execution_time=$((end_time - START_TIME))
    local success_rate=0
    local critical_failures=0
    local important_failures=0
    
    if [[ $TOTAL_SUITES -gt 0 ]]; then
        success_rate=$((PASSED_SUITES * 100 / TOTAL_SUITES))
    fi
    
    # Count failure types
    for result in "${SUITE_RESULTS[@]}"; do
        if [[ "$result" == *":FAILED:CRITICAL" ]]; then
            critical_failures=$((critical_failures + 1))
        elif [[ "$result" == *":FAILED:IMPORTANT" ]]; then
            important_failures=$((important_failures + 1))
        fi
    done
    
    # Determine overall deployment status
    local deployment_status="READY"
    local exit_code=0
    
    if [[ $critical_failures -gt 0 ]]; then
        deployment_status="BLOCKED"
        exit_code=1
    elif [[ $important_failures -gt 0 ]]; then
        deployment_status="CAUTION"
        exit_code=2
    elif [[ $success_rate -lt 80 ]]; then
        deployment_status="REVIEW"
        exit_code=2
    fi
    
    cat >> "$COMPREHENSIVE_REPORT" << EOF

## 📊 Comprehensive Test Summary

### Execution Overview
- **Total Execution Time**: ${total_execution_time} seconds
- **Test Suites Run**: $TOTAL_SUITES
- **Success Rate**: $success_rate% ($PASSED_SUITES passed, $FAILED_SUITES failed)
- **Test Mode**: ${TEST_MODE:-standard}

### Deployment Assessment
**Status**: $(case $deployment_status in
    "READY") echo "✅ READY FOR DEPLOYMENT" ;;
    "CAUTION") echo "⚠️ DEPLOYMENT WITH CAUTION" ;;
    "REVIEW") echo "📋 REQUIRES REVIEW" ;;
    "BLOCKED") echo "❌ DEPLOYMENT BLOCKED" ;;
esac)

### Critical System Status
- **Critical Failures**: $critical_failures ($([ $critical_failures -eq 0 ] && echo "✅ None" || echo "❌ Block deployment"))
- **Important Failures**: $important_failures ($([ $important_failures -eq 0 ] && echo "✅ None" || echo "⚠️ Review needed"))

### Detailed Suite Results
EOF
    
    # Add detailed suite results
    for i in "${!SUITE_RESULTS[@]}"; do
        if [[ -n "${SUITE_RESULTS[i]}" ]]; then
            local result="${SUITE_RESULTS[i]}"
            local suite_name="${result%%:*}"
            local status=$(echo "$result" | cut -d':' -f2)
            local priority=$(echo "$result" | cut -d':' -f3)
            local detail="${SUITE_DETAILS[i]:-"No details available"}"
            local icon="❌"
            local priority_label=""
            
            case $status in
                "PASSED") icon="✅" ;;
                "WARNING") icon="⚠️" ;;
                "FAILED") icon="❌" ;;
            esac
            
            case $priority in
                "CRITICAL") priority_label=" [CRITICAL]" ;;
                "IMPORTANT") priority_label=" [IMPORTANT]" ;;
                "OPTIONAL") priority_label=" [OPTIONAL]" ;;
            esac
            
            echo "- $icon **$suite_name**$priority_label: ${detail##*:}" >> "$COMPREHENSIVE_REPORT"
        fi
    done
    
    cat >> "$COMPREHENSIVE_REPORT" << EOF

### Deployment Decision Matrix

EOF
    
    case $deployment_status in
        "READY")
            cat >> "$COMPREHENSIVE_REPORT" << EOF
**✅ PROCEED WITH DEPLOYMENT**

- All critical systems functional
- No blocking issues detected
- Success rate meets requirements ($success_rate% ≥ 80%)
- Day 1 achievements maintained
EOF
            ;;
        "CAUTION")
            cat >> "$COMPREHENSIVE_REPORT" << EOF
**⚠️ DEPLOY WITH INCREASED MONITORING**

- Critical systems functional but some concerns exist
- Non-critical issues detected that should be addressed
- Proceed with deployment but monitor closely
- Schedule fixes for next maintenance window
EOF
            ;;
        "REVIEW")
            cat >> "$COMPREHENSIVE_REPORT" << EOF
**📋 REVIEW REQUIRED BEFORE DEPLOYMENT**

- Success rate below optimal threshold ($success_rate% < 80%)
- Multiple issues require investigation
- Consider postponing deployment until issues resolved
EOF
            ;;
        "BLOCKED")
            cat >> "$COMPREHENSIVE_REPORT" << EOF
**❌ DO NOT DEPLOY - CRITICAL ISSUES**

- Critical system failures detected: $critical_failures
- Deployment would likely result in system instability
- Fix critical issues before attempting deployment
- Re-run full test suite after fixes
EOF
            ;;
    esac
    
    cat >> "$COMPREHENSIVE_REPORT" << EOF

### Recommended Next Actions

EOF
    
    case $deployment_status in
        "READY")
            echo "- ✅ Proceed with production deployment" >> "$COMPREHENSIVE_REPORT"
            echo "- 📊 Activate post-deployment monitoring" >> "$COMPREHENSIVE_REPORT"
            echo "- 📅 Schedule next regression test cycle" >> "$COMPREHENSIVE_REPORT"
            ;;
        "CAUTION"|"REVIEW")
            echo "- 🔍 Review and address identified issues" >> "$COMPREHENSIVE_REPORT"
            echo "- 📊 Increase monitoring frequency during deployment" >> "$COMPREHENSIVE_REPORT"
            echo "- 🔄 Re-run affected test suites after fixes" >> "$COMPREHENSIVE_REPORT"
            ;;
        "BLOCKED")
            echo "- 🚨 Fix critical issues immediately" >> "$COMPREHENSIVE_REPORT"
            echo "- 🔄 Re-run complete test suite" >> "$COMPREHENSIVE_REPORT"
            echo "- 📋 Review system logs for error details" >> "$COMPREHENSIVE_REPORT"
            ;;
    esac
    
    cat >> "$COMPREHENSIVE_REPORT" << EOF

### Individual Test Reports
EOF
    
    # Link to individual test reports
    local report_files=$(find "$REPORT_DIR" -name "day2-*-$TIMESTAMP.md" 2>/dev/null || true)
    if [[ -n "$report_files" ]]; then
        echo "$report_files" | while read -r report_file; do
            local report_name=$(basename "$report_file")
            echo "- [$report_name]($report_file)" >> "$COMPREHENSIVE_REPORT"
        done
    else
        echo "- Individual reports will be available in: $REPORT_DIR" >> "$COMPREHENSIVE_REPORT"
    fi
    
    cat >> "$COMPREHENSIVE_REPORT" << EOF

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Total Execution Time**: ${total_execution_time} seconds  
**Report File**: $COMPREHENSIVE_REPORT  
**Exit Code**: $exit_code

EOF
    
    return $exit_code
}

# Main execution logic
main() {
    local test_mode="${1:-standard}"
    
    # Handle special options
    case "$test_mode" in
        --help|-h)
            usage
            exit 0
            ;;
        --report)
            echo "Generating comprehensive report from existing results..."
            # This would analyze existing reports - simplified for now
            echo "Report generation from existing results not yet implemented"
            exit 0
            ;;
        --silent)
            SILENT_MODE=true
            test_mode="${2:-standard}"
            ;;
    esac
    
    # Validate test mode
    case "$test_mode" in
        quick|standard|full|monitor)
            TEST_MODE="$test_mode"
            ;;
        *)
            echo -e "${RED}Error: Invalid test mode '$test_mode'${NC}"
            echo "Valid modes: quick, standard, full, monitor"
            echo "Use --help for more information"
            exit 3
            ;;
    esac
    
    # Special handling for monitor mode
    if [[ "$test_mode" == "monitor" ]]; then
        run_continuous_monitoring
        exit $?
    fi
    
    # Initialize
    init_comprehensive_report
    
    echo -e "${CYAN}Kong AWS Masking MVP - Day 2 Comprehensive Test Runner${NC}"
    echo "============================================================"
    echo "Mode: $TEST_MODE"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    # Execute test suites based on mode
    local health_ok=false
    local smoke_ok=false
    local regression_ok=false
    local monitor_ok=false
    
    # Health check (always run first)
    if run_health_check; then
        health_ok=true
    fi
    
    # Skip other tests if health check fails in quick mode
    if [[ "$test_mode" == "quick" && "$health_ok" == "false" ]]; then
        log "Health check failed in quick mode - skipping remaining tests"
    else
        # Smoke test (run in all modes except monitor)
        if run_smoke_test; then
            smoke_ok=true
        fi
        
        # Regression test (run in standard and full modes)
        if [[ "$test_mode" == "standard" || "$test_mode" == "full" ]]; then
            if run_regression_test; then
                regression_ok=true
            fi
        fi
        
        # System monitoring (run only in full mode)
        if [[ "$test_mode" == "full" ]]; then
            if run_system_monitoring; then
                monitor_ok=true
            fi
        fi
    fi
    
    # Generate comprehensive report and get final status
    generate_comprehensive_report
    local final_exit_code=$?
    
    # Final summary
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    
    echo
    echo -e "${CYAN}=== Day 2 Test Execution Complete ===${NC}"
    echo "Mode: $TEST_MODE"
    echo "Total time: ${total_time} seconds"
    echo "Success rate: $((PASSED_SUITES * 100 / TOTAL_SUITES))% ($PASSED_SUITES/$TOTAL_SUITES)"
    echo "Comprehensive report: $COMPREHENSIVE_REPORT"
    echo
    
    # Final status message
    case $final_exit_code in
        0)
            echo -e "${GREEN}✅ ALL TESTS PASSED - READY FOR DEPLOYMENT${NC}"
            ;;
        1)
            echo -e "${RED}❌ CRITICAL FAILURES - DO NOT DEPLOY${NC}"
            ;;
        2)
            echo -e "${YELLOW}⚠️ MINOR ISSUES - DEPLOY WITH CAUTION${NC}"
            ;;
        *)
            echo -e "${RED}❌ EXECUTION ERROR${NC}"
            ;;
    esac
    
    exit $final_exit_code
}

# Execute main function with all arguments
main "$@"