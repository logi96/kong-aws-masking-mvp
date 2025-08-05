#!/bin/bash

# Kong AWS Masker Deployment Script
# This script deploys the complete infrastructure stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check .env file
    if [ ! -f "$ENV_FILE" ]; then
        log_warning ".env file not found. Creating from .env.example..."
        cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
        log_warning "Please edit .env file with your actual values before proceeding."
        exit 1
    fi
    
    # Check required environment variables
    source "$ENV_FILE"
    if [ -z "$ANTHROPIC_API_KEY" ] || [ "$ANTHROPIC_API_KEY" == "sk-ant-api03-YOUR-KEY-HERE" ]; then
        log_error "Please set ANTHROPIC_API_KEY in .env file"
        exit 1
    fi
    
    log_info "Prerequisites check passed!"
}

# Build Docker images
build_images() {
    log_info "Building Docker images..."
    
    docker-compose -f "$DOCKER_COMPOSE_FILE" build --no-cache
    
    if [ $? -eq 0 ]; then
        log_info "Docker images built successfully!"
    else
        log_error "Failed to build Docker images"
        exit 1
    fi
}

# Start services
start_services() {
    log_info "Starting services..."
    
    # Start in detached mode
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
    
    if [ $? -eq 0 ]; then
        log_info "Services started successfully!"
    else
        log_error "Failed to start services"
        exit 1
    fi
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 10
    
    # Check service health
    check_service_health
}

# Check service health
check_service_health() {
    log_info "Checking service health..."
    
    # Check Redis
    if docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T redis redis-cli ping | grep -q PONG; then
        log_info "Redis is healthy"
    else
        log_error "Redis health check failed"
        exit 1
    fi
    
    # Check Kong
    if curl -s http://localhost:8001/status > /dev/null 2>&1; then
        log_info "Kong Admin API is healthy"
    else
        log_error "Kong health check failed"
        exit 1
    fi
    
    # Check Nginx
    if curl -s http://localhost:8082/health > /dev/null 2>&1; then
        log_info "Nginx proxy is healthy"
    else
        log_warning "Nginx health check failed (may need more time to start)"
    fi
}

# Run tests
run_tests() {
    log_info "Running integration tests..."
    
    # Test Claude API through the gateway
    if docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T claude-client node test-client.js; then
        log_info "Integration tests passed!"
    else
        log_error "Integration tests failed"
        exit 1
    fi
}

# Display service information
show_info() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "Service URLs:"
    echo "  - Kong Admin API: http://localhost:8001"
    echo "  - Kong Proxy: http://localhost:8000"
    echo "  - Nginx Proxy: http://localhost:8082"
    echo "  - Redis: localhost:6379"
    echo ""
    echo "Test the deployment:"
    echo "  curl http://localhost:8082/health"
    echo ""
    echo "View logs:"
    echo "  docker-compose logs -f kong"
    echo "  docker-compose logs -f redis"
    echo "  docker-compose logs -f nginx"
    echo ""
    echo "Stop services:"
    echo "  docker-compose down"
}

# Main deployment flow
main() {
    log_info "Starting Kong AWS Masker deployment..."
    
    check_prerequisites
    build_images
    start_services
    
    # Optional: Run tests
    read -p "Run integration tests? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_tests
    fi
    
    show_info
}

# Handle script arguments
case "${1:-}" in
    "stop")
        log_info "Stopping services..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" down
        ;;
    "restart")
        log_info "Restarting services..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" restart
        ;;
    "logs")
        docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f ${2:-}
        ;;
    "status")
        docker-compose -f "$DOCKER_COMPOSE_FILE" ps
        check_service_health
        ;;
    "test")
        run_tests
        ;;
    *)
        main
        ;;
esac