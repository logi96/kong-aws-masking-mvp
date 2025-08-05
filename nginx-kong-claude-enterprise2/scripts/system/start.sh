#!/bin/bash

# Kong AWS Masker - System Start Script
# Description: Starts all services in the correct order with health checks

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

# Load environment variables
load_env() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
        log_info "Environment variables loaded"
    else
        log_warn "No .env file found, using defaults"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check ports
    local ports=(6379 8000 8001 8080 3000)
    for port in "${ports[@]}"; do
        if lsof -i :$port &> /dev/null; then
            log_error "Port $port is already in use"
            exit 1
        fi
    done
    
    # Check disk space (minimum 1GB)
    local available_space=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 1 ]; then
        log_error "Insufficient disk space (less than 1GB available)"
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Create necessary directories
create_directories() {
    log_info "Creating necessary directories..."
    
    mkdir -p "$PROJECT_ROOT/logs/kong"
    mkdir -p "$PROJECT_ROOT/logs/nginx"
    mkdir -p "$PROJECT_ROOT/logs/redis"
    mkdir -p "$PROJECT_ROOT/monitoring/metrics"
    mkdir -p "$PROJECT_ROOT/redis/data"
    
    # Set permissions
    chmod -R 755 "$PROJECT_ROOT/logs"
    chmod -R 755 "$PROJECT_ROOT/monitoring"
    chmod -R 755 "$PROJECT_ROOT/redis/data"
    
    log_info "Directories created successfully"
}

# Start services
start_services() {
    log_info "Starting services..."
    
    cd "$PROJECT_ROOT"
    
    # Determine environment
    local compose_file="docker-compose.yml"
    if [ "${ENVIRONMENT:-development}" = "production" ]; then
        compose_file="docker-compose.prod.yml"
        log_info "Using production configuration"
    fi
    
    # Pull latest images
    log_info "Pulling latest Docker images..."
    docker-compose -f "$compose_file" pull
    
    # Start services in order
    log_info "Starting Redis..."
    docker-compose -f "$compose_file" up -d redis
    sleep 5
    
    log_info "Starting Kong..."
    docker-compose -f "$compose_file" up -d kong
    sleep 10
    
    log_info "Starting Nginx..."
    docker-compose -f "$compose_file" up -d nginx
    sleep 5
    
    log_info "Starting Backend..."
    docker-compose -f "$compose_file" up -d backend
    sleep 5
    
    log_info "All services started"
}

# Health check function
health_check() {
    local service=$1
    local url=$2
    local max_attempts=30
    local attempt=0
    
    log_info "Checking health of $service..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$url" > /dev/null; then
            log_info "$service is healthy"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_warn "Waiting for $service to be ready... ($attempt/$max_attempts)"
        sleep 2
    done
    
    log_error "$service failed to become healthy"
    return 1
}

# Verify all services
verify_services() {
    log_info "Verifying services..."
    
    # Check Redis
    if ! docker exec kong-redis redis-cli ping | grep -q PONG; then
        log_error "Redis health check failed"
        return 1
    fi
    
    # Check Kong Admin API
    if ! health_check "Kong Admin API" "http://localhost:8001/status"; then
        return 1
    fi
    
    # Check Kong Proxy
    if ! health_check "Kong Proxy" "http://localhost:8000"; then
        return 1
    fi
    
    # Check Nginx
    if ! health_check "Nginx" "http://localhost:8080/health"; then
        return 1
    fi
    
    # Check Backend
    if ! health_check "Backend" "http://localhost:3000/health"; then
        return 1
    fi
    
    log_info "All services verified successfully"
}

# Test plugin functionality
test_plugin() {
    log_info "Testing AWS masker plugin..."
    
    # Test masking with a simple EC2 instance ID
    local test_response=$(curl -s -X POST http://localhost:8000/analyze \
        -H "Content-Type: application/json" \
        -d '{"content":"EC2 instance i-1234567890abcdef0 is running"}' 2>/dev/null || echo "")
    
    if [[ "$test_response" == *"EC2_"* ]]; then
        log_info "AWS masker plugin is working correctly"
    else
        log_warn "AWS masker plugin test returned unexpected result"
    fi
}

# Display status
display_status() {
    log_info "System status:"
    echo -e "\n${GREEN}=== Service URLs ===${NC}"
    echo "Kong Admin API:  http://localhost:8001"
    echo "Kong Proxy:      http://localhost:8000"
    echo "Nginx Proxy:     http://localhost:8080"
    echo "Backend API:     http://localhost:3000"
    echo "Redis:           localhost:6379"
    echo -e "\n${GREEN}=== Health Check URLs ===${NC}"
    echo "Kong Status:     http://localhost:8001/status"
    echo "Backend Health:  http://localhost:3000/health"
    echo "Nginx Health:    http://localhost:8080/health"
    echo -e "\n${GREEN}=== Monitoring ===${NC}"
    echo "Health Dashboard: http://localhost:8080/monitoring/"
    echo "Logs Directory:   $PROJECT_ROOT/logs/"
    echo -e "\n${GREEN}=== Quick Test ===${NC}"
    echo "curl -X POST http://localhost:8000/analyze -H 'Content-Type: application/json' -d '{\"content\":\"Test EC2 i-1234567890abcdef0\"}'"
}

# Main execution
main() {
    log_info "Starting Kong AWS Masker System..."
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Execute startup sequence
    load_env
    check_prerequisites
    create_directories
    start_services
    
    # Verify services
    if verify_services; then
        test_plugin
        display_status
        log_info "System started successfully!"
        exit 0
    else
        log_error "System startup failed. Check logs for details."
        log_info "Run './scripts/stop.sh' to clean up."
        exit 1
    fi
}

# Error handler
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"