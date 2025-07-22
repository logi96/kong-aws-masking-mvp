#!/bin/bash

# Kong AWS Masking MVP - Log Management Script
# Infrastructure Team - Aggregates and manages logs from all services

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
readonly LOG_DIR="$PROJECT_ROOT/logs"

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

log_separator() {
    echo -e "${CYAN}$(printf '%.0s=' {1..60})${NC}"
}

# Utility functions
check_services() {
    cd "$PROJECT_ROOT"
    
    if ! docker-compose ps -q | grep -q .; then
        log_warning "No running services found"
        return 1
    fi
    
    return 0
}

get_running_services() {
    cd "$PROJECT_ROOT"
    docker-compose ps --services --filter status=running
}

# Log display functions
show_live_logs() {
    local service="${1:-}"
    local tail_lines="${2:-100}"
    
    cd "$PROJECT_ROOT"
    
    if [ -n "$service" ]; then
        log_info "Showing live logs for service: $service (last $tail_lines lines)"
        log_separator
        docker-compose logs -f --tail="$tail_lines" "$service"
    else
        log_info "Showing live logs for all services (last $tail_lines lines)"
        log_separator
        docker-compose logs -f --tail="$tail_lines"
    fi
}

show_static_logs() {
    local service="${1:-}"
    local tail_lines="${2:-100}"
    
    cd "$PROJECT_ROOT"
    
    if [ -n "$service" ]; then
        log_info "Showing logs for service: $service (last $tail_lines lines)"
        log_separator
        docker-compose logs --tail="$tail_lines" "$service"
    else
        log_info "Showing logs for all services (last $tail_lines lines)"
        log_separator
        docker-compose logs --tail="$tail_lines"
    fi
}

show_error_logs() {
    local service="${1:-}"
    
    cd "$PROJECT_ROOT"
    
    log_info "Filtering error logs..."
    log_separator
    
    if [ -n "$service" ]; then
        docker-compose logs "$service" | grep -i -E "(error|exception|fail|panic|fatal)" --color=always || log_info "No error logs found for $service"
    else
        docker-compose logs | grep -i -E "(error|exception|fail|panic|fatal)" --color=always || log_info "No error logs found"
    fi
}

show_recent_logs() {
    local minutes="${1:-5}"
    local service="${2:-}"
    
    cd "$PROJECT_ROOT"
    
    log_info "Showing logs from the last $minutes minutes..."
    log_separator
    
    local since_time
    since_time=$(date -d "$minutes minutes ago" -Iseconds 2>/dev/null || date -v-"${minutes}M" -Iseconds)
    
    if [ -n "$service" ]; then
        docker-compose logs --since="$since_time" "$service" || log_error "Failed to retrieve recent logs for $service"
    else
        docker-compose logs --since="$since_time" || log_error "Failed to retrieve recent logs"
    fi
}

show_service_status() {
    cd "$PROJECT_ROOT"
    
    log_info "Service Status Overview"
    log_separator
    
    # Docker compose services
    echo -e "${YELLOW}Docker Compose Services:${NC}"
    docker-compose ps
    echo ""
    
    # Container stats if available
    if docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | grep -q "kong\|backend"; then
        echo -e "${YELLOW}Resource Usage:${NC}"
        docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | head -1
        docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | grep -E "(kong|backend)"
        echo ""
    fi
    
    # Service health checks
    echo -e "${YELLOW}Service Health:${NC}"
    
    # Kong Admin API
    if curl -s -f --max-time 5 http://localhost:8001/status &>/dev/null; then
        echo -e "${GREEN}✓${NC} Kong Admin API (http://localhost:8001)"
    else
        echo -e "${RED}✗${NC} Kong Admin API (http://localhost:8001)"
    fi
    
    # Kong Proxy
    if curl -s --max-time 5 http://localhost:8000 &>/dev/null; then
        echo -e "${GREEN}✓${NC} Kong Proxy (http://localhost:8000)"
    else
        echo -e "${RED}✗${NC} Kong Proxy (http://localhost:8000)"
    fi
    
    # Backend API
    if curl -s -f --max-time 5 http://localhost:3000/health &>/dev/null; then
        echo -e "${GREEN}✓${NC} Backend API (http://localhost:3000)"
    else
        echo -e "${RED}✗${NC} Backend API (http://localhost:3000)"
    fi
    
    echo ""
}

export_logs() {
    local output_file="${1:-logs_export_$(date +%Y%m%d_%H%M%S).txt}"
    
    cd "$PROJECT_ROOT"
    
    log_info "Exporting logs to: $output_file"
    
    {
        echo "Kong AWS Masking MVP - Log Export"
        echo "Generated: $(date -Iseconds)"
        echo "========================================"
        echo ""
        
        echo "SERVICE STATUS:"
        docker-compose ps
        echo ""
        
        echo "CONTAINER LOGS:"
        echo "========================================"
        docker-compose logs --no-color
        
    } > "$output_file"
    
    log_success "Logs exported to: $output_file"
}

analyze_logs() {
    local service="${1:-}"
    
    cd "$PROJECT_ROOT"
    
    log_info "Analyzing logs for patterns and issues..."
    log_separator
    
    # Get logs for analysis
    local logs
    if [ -n "$service" ]; then
        logs=$(docker-compose logs "$service" 2>&1)
    else
        logs=$(docker-compose logs 2>&1)
    fi
    
    if [ -z "$logs" ]; then
        log_warning "No logs found to analyze"
        return
    fi
    
    # Count log levels
    echo -e "${YELLOW}Log Level Summary:${NC}"
    echo "ERROR:   $(echo "$logs" | grep -i error | wc -l)"
    echo "WARNING: $(echo "$logs" | grep -i warn | wc -l)"
    echo "INFO:    $(echo "$logs" | grep -i info | wc -l)"
    echo "DEBUG:   $(echo "$logs" | grep -i debug | wc -l)"
    echo ""
    
    # Find common errors
    echo -e "${YELLOW}Most Common Errors:${NC}"
    echo "$logs" | grep -i error | sort | uniq -c | sort -nr | head -5
    echo ""
    
    # Find performance issues
    echo -e "${YELLOW}Performance Issues:${NC}"
    echo "$logs" | grep -i -E "(timeout|slow|performance|latency)" | tail -5
    echo ""
    
    # Find security issues
    echo -e "${YELLOW}Security Events:${NC}"
    echo "$logs" | grep -i -E "(unauthorized|forbidden|denied|security)" | tail -5
    echo ""
}

search_logs() {
    local pattern="$1"
    local service="${2:-}"
    local context_lines="${3:-3}"
    
    cd "$PROJECT_ROOT"
    
    log_info "Searching logs for pattern: '$pattern'"
    if [ -n "$service" ]; then
        log_info "Service filter: $service"
    fi
    log_separator
    
    if [ -n "$service" ]; then
        docker-compose logs "$service" | grep -i -C"$context_lines" --color=always "$pattern" || log_info "No matches found"
    else
        docker-compose logs | grep -i -C"$context_lines" --color=always "$pattern" || log_info "No matches found"
    fi
}

# File log management
manage_file_logs() {
    log_info "Managing file-based logs..."
    
    if [ ! -d "$LOG_DIR" ]; then
        log_warning "Log directory $LOG_DIR does not exist"
        return
    fi
    
    # Show log file sizes
    echo -e "${YELLOW}Log Directory Contents:${NC}"
    du -sh "$LOG_DIR"/* 2>/dev/null || log_info "No log files found"
    echo ""
    
    # Rotate large log files
    find "$LOG_DIR" -name "*.log" -size +10M 2>/dev/null | while read -r logfile; do
        log_warning "Large log file detected: $(basename "$logfile")"
        if confirm_action "Rotate log file $logfile?"; then
            mv "$logfile" "${logfile}.$(date +%Y%m%d_%H%M%S)"
            touch "$logfile"
            log_success "Log file rotated: $(basename "$logfile")"
        fi
    done
}

confirm_action() {
    local message="$1"
    local response
    
    while true; do
        echo -n -e "${YELLOW}$message (y/n):${NC} "
        read -r response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

print_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  live [service] [lines]     - Show live logs (default: all services, 100 lines)"
    echo "  show [service] [lines]     - Show static logs (default: all services, 100 lines)"
    echo "  errors [service]           - Filter and show error logs"
    echo "  recent [minutes] [service] - Show logs from recent minutes (default: 5 minutes)"
    echo "  search <pattern> [service] - Search logs for a pattern"
    echo "  status                     - Show service status and health"
    echo "  analyze [service]          - Analyze logs for patterns and issues"
    echo "  export [filename]          - Export all logs to a file"
    echo "  rotate                     - Manage and rotate log files"
    echo "  help                       - Show this help message"
    echo ""
    echo "Services: kong, backend"
    echo ""
    echo "Examples:"
    echo "  $0 live kong              - Live logs for Kong service"
    echo "  $0 show backend 200       - Last 200 lines of backend logs"
    echo "  $0 errors                 - All error logs"
    echo "  $0 recent 10              - Logs from last 10 minutes"
    echo "  $0 search \"timeout\"       - Search for timeout-related logs"
    echo "  $0 export logs.txt        - Export logs to logs.txt"
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    # Parse command line arguments
    case "${1:-live}" in
        "live")
            if ! check_services; then
                exit 1
            fi
            show_live_logs "${2:-}" "${3:-100}"
            ;;
        "show")
            if ! check_services; then
                exit 1
            fi
            show_static_logs "${2:-}" "${3:-100}"
            ;;
        "errors")
            if ! check_services; then
                exit 1
            fi
            show_error_logs "${2:-}"
            ;;
        "recent")
            if ! check_services; then
                exit 1
            fi
            show_recent_logs "${2:-5}" "${3:-}"
            ;;
        "search")
            if [ -z "${2:-}" ]; then
                log_error "Search pattern is required"
                print_usage
                exit 1
            fi
            if ! check_services; then
                exit 1
            fi
            search_logs "$2" "${3:-}" "${4:-3}"
            ;;
        "status")
            show_service_status
            ;;
        "analyze")
            if ! check_services; then
                exit 1
            fi
            analyze_logs "${2:-}"
            ;;
        "export")
            if ! check_services; then
                exit 1
            fi
            export_logs "${2:-}"
            ;;
        "rotate")
            manage_file_logs
            ;;
        "help"|"-h"|"--help")
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $1"
            print_usage
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}Log viewing interrupted${NC}"; exit 130' INT TERM

# Run main function
main "$@"