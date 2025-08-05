#!/bin/bash

# Kong AWS Masker - System Stop Script
# Description: Gracefully stops all services in the correct order

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Check if services are running
check_running_services() {
    log_info "Checking running services..."
    
    cd "$PROJECT_ROOT"
    
    local running_services=$(docker-compose ps --services --filter "status=running" 2>/dev/null || echo "")
    
    if [ -z "$running_services" ]; then
        log_warn "No services are currently running"
        return 1
    fi
    
    log_info "Found running services: $(echo $running_services | tr '\n' ' ')"
    return 0
}

# Wait for active connections to complete
wait_for_connections() {
    local service=$1
    local port=$2
    local max_wait=30
    local waited=0
    
    log_info "Waiting for active connections on $service (port $port) to complete..."
    
    while [ $waited -lt $max_wait ]; do
        local connections=$(netstat -an 2>/dev/null | grep ":$port " | grep ESTABLISHED | wc -l || echo "0")
        
        if [ "$connections" -eq 0 ]; then
            log_info "No active connections on $service"
            return 0
        fi
        
        log_info "Waiting for $connections active connections to complete... ($waited/$max_wait seconds)"
        sleep 1
        waited=$((waited + 1))
    done
    
    log_warn "Timeout waiting for connections on $service, proceeding with shutdown"
}

# Gracefully stop a service
graceful_stop() {
    local service=$1
    local timeout=${2:-30}
    
    log_info "Gracefully stopping $service..."
    
    # Send SIGTERM
    docker-compose stop -t $timeout $service 2>/dev/null || {
        log_warn "Service $service may not be running"
        return 0
    }
    
    # Wait for container to stop
    local attempts=0
    while [ $attempts -lt $timeout ]; do
        if ! docker-compose ps $service | grep -q "Up"; then
            log_info "$service stopped successfully"
            return 0
        fi
        sleep 1
        attempts=$((attempts + 1))
    done
    
    log_warn "$service did not stop gracefully, forcing..."
    docker-compose kill $service 2>/dev/null || true
}

# Save Redis data
save_redis_data() {
    log_info "Saving Redis data..."
    
    if docker-compose ps redis | grep -q "Up"; then
        # Trigger Redis BGSAVE
        docker exec kong-redis redis-cli BGSAVE || {
            log_warn "Failed to trigger Redis BGSAVE"
            return 1
        }
        
        # Wait for background save to complete
        local max_wait=30
        local waited=0
        
        while [ $waited -lt $max_wait ]; do
            local lastsave=$(docker exec kong-redis redis-cli LASTSAVE | tr -d '\r' || echo "0")
            local current_time=$(date +%s)
            local time_diff=$((current_time - lastsave))
            
            if [ $time_diff -lt 5 ]; then
                log_info "Redis data saved successfully"
                return 0
            fi
            
            log_info "Waiting for Redis save to complete... ($waited/$max_wait seconds)"
            sleep 1
            waited=$((waited + 1))
        done
        
        log_warn "Redis save timeout, proceeding anyway"
    else
        log_info "Redis is not running, skipping save"
    fi
}

# Collect logs before shutdown
collect_logs() {
    log_info "Collecting logs..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_archive="$PROJECT_ROOT/logs/shutdown_logs_$timestamp.tar.gz"
    
    # Get logs from running containers
    for service in backend nginx kong redis; do
        if docker-compose ps $service 2>/dev/null | grep -q "Up"; then
            docker-compose logs --no-color --tail=1000 $service > "$PROJECT_ROOT/logs/${service}_shutdown_$timestamp.log" 2>&1 || true
        fi
    done
    
    log_info "Logs collected at: $PROJECT_ROOT/logs/"
}

# Stop services in order
stop_services() {
    log_info "Stopping services in order..."
    
    cd "$PROJECT_ROOT"
    
    # Stop Backend first (application layer)
    if docker-compose ps backend 2>/dev/null | grep -q "Up"; then
        wait_for_connections "Backend" 3000
        graceful_stop "backend" 15
    fi
    
    # Stop Nginx (proxy layer)
    if docker-compose ps nginx 2>/dev/null | grep -q "Up"; then
        wait_for_connections "Nginx" 8080
        graceful_stop "nginx" 15
    fi
    
    # Stop Kong (API gateway)
    if docker-compose ps kong 2>/dev/null | grep -q "Up"; then
        wait_for_connections "Kong" 8000
        graceful_stop "kong" 30
    fi
    
    # Save Redis data before stopping
    save_redis_data
    
    # Stop Redis (data layer)
    if docker-compose ps redis 2>/dev/null | grep -q "Up"; then
        graceful_stop "redis" 30
    fi
    
    log_info "All services stopped"
}

# Clean up resources
cleanup_resources() {
    log_info "Cleaning up resources..."
    
    cd "$PROJECT_ROOT"
    
    # Remove containers
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # Clean up dangling volumes (optional, based on environment variable)
    if [ "${CLEANUP_VOLUMES:-false}" = "true" ]; then
        log_warn "Cleaning up volumes (CLEANUP_VOLUMES=true)"
        docker-compose down -v 2>/dev/null || true
    fi
    
    # Clean up networks
    docker network prune -f 2>/dev/null || true
    
    log_info "Cleanup completed"
}

# Display shutdown summary
display_summary() {
    log_info "Shutdown summary:"
    echo -e "\n${GREEN}=== Shutdown Complete ===${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Logs saved to: $PROJECT_ROOT/logs/"
    echo "Redis data persisted to: $PROJECT_ROOT/redis/data/"
    echo -e "\n${YELLOW}=== Next Steps ===${NC}"
    echo "To restart the system: $SCRIPT_DIR/start.sh"
    echo "To check logs: ls -la $PROJECT_ROOT/logs/"
    echo "To remove all data: CLEANUP_VOLUMES=true $SCRIPT_DIR/stop.sh"
}

# Main execution
main() {
    log_info "Stopping Kong AWS Masker System..."
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Check if services are running
    if ! check_running_services; then
        log_info "System is already stopped"
        exit 0
    fi
    
    # Collect logs before shutdown
    collect_logs
    
    # Stop services
    stop_services
    
    # Clean up resources
    cleanup_resources
    
    # Display summary
    display_summary
    
    log_info "System stopped successfully!"
}

# Handle interrupt signals
trap 'log_warn "Received interrupt signal, please wait for graceful shutdown..."; wait' INT TERM

# Error handler
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"