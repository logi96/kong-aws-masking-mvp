#!/bin/bash

# Production Deployment Script for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: One-click deployment with comprehensive validation and monitoring

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
CONFIG_FILE="${PROJECT_ROOT}/config/${ENVIRONMENT}.env"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
PROD_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.prod.yml"

# Deployment configuration
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-120}"
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
SKIP_TESTS="${SKIP_TESTS:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Deployment tracking
DEPLOYMENT_START_TIME=$(date +%s)
DEPLOYMENT_ID="deploy-$(date +%Y%m%d-%H%M%S)"
DEPLOYMENT_LOG="${PROJECT_ROOT}/logs/deployments/${DEPLOYMENT_ID}.log"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$DEPLOYMENT_LOG"
}

# Utility functions
create_deployment_directories() {
    log_info "Creating deployment directories..."
    
    local dirs=(
        "logs/deployments"
        "backups/pre-deploy"
        "backups/config"
        "backups/redis"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${PROJECT_ROOT}/${dir}"
    done
    
    log_success "Deployment directories created"
}

load_environment_config() {
    log_info "Loading environment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Source the environment configuration
    set -a
    source "$CONFIG_FILE"
    set +a
    
    # Set deployment-specific variables
    export DEPLOYMENT_ID
    export DEPLOYMENT_TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    export SERVICE_VERSION="${SERVICE_VERSION:-${DEPLOYMENT_ID}}"
    
    log_success "Environment configuration loaded: $ENVIRONMENT"
    log_info "Service version: $SERVICE_VERSION"
}

run_pre_deployment_checks() {
    log_info "Running pre-deployment checks..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Skipping pre-deployment checks"
        return 0
    fi
    
    local check_script="${SCRIPT_DIR}/pre-deploy-check.sh"
    if [[ -f "$check_script" ]]; then
        if "$check_script" "$ENVIRONMENT"; then
            log_success "Pre-deployment checks passed"
        else
            log_error "Pre-deployment checks failed"
            exit 1
        fi
    else
        log_warning "Pre-deployment check script not found"
    fi
}

backup_current_state() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        log_info "Backup disabled, skipping..."
        return 0
    fi
    
    log_info "Backing up current state..."
    
    local backup_dir="${PROJECT_ROOT}/backups/pre-deploy/${DEPLOYMENT_ID}"
    mkdir -p "$backup_dir"
    
    # Backup configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$backup_dir/config.env"
        log_success "Configuration backed up"
    fi
    
    # Backup Redis data if container is running
    if docker ps -q -f name=claude-redis | grep -q .; then
        log_info "Backing up Redis data..."
        if docker exec claude-redis redis-cli --rdb /data/backup-${DEPLOYMENT_ID}.rdb; then
            log_success "Redis backup completed"
        else
            log_warning "Redis backup failed, continuing deployment"
        fi
    fi
    
    # Backup current docker-compose state
    if docker-compose ps --format json > "$backup_dir/services-state.json" 2>/dev/null; then
        log_success "Services state backed up"
    fi
    
    log_success "Backup completed: $backup_dir"
}

stop_existing_services() {
    log_info "Stopping existing services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would stop services with: docker-compose down"
        return 0
    fi
    
    # Graceful shutdown with timeout
    if docker-compose down --timeout 30 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
        log_success "Services stopped gracefully"
    else
        log_warning "Some services may not have stopped cleanly"
    fi
    
    # Force cleanup if needed
    local remaining=$(docker ps -q -f name=claude- || true)
    if [[ -n "$remaining" ]]; then
        log_warning "Force stopping remaining containers..."
        echo "$remaining" | xargs -r docker stop
        echo "$remaining" | xargs -r docker rm
    fi
    
    # Network cleanup
    if docker network ls --format '{{.Name}}' | grep -q "claude-enterprise"; then
        docker network rm claude-enterprise 2>/dev/null || true
    fi
}

select_compose_file() {
    log_info "Selecting appropriate compose file..."
    
    if [[ "$ENVIRONMENT" == "production" && -f "$PROD_COMPOSE_FILE" ]]; then
        COMPOSE_FILE="$PROD_COMPOSE_FILE"
        log_success "Using production compose file: $PROD_COMPOSE_FILE"
    else
        log_success "Using default compose file: $COMPOSE_FILE"
    fi
    
    # Validate compose file
    if docker-compose -f "$COMPOSE_FILE" config &> /dev/null; then
        log_success "Compose file validation passed"
    else
        log_error "Compose file validation failed"
        exit 1
    fi
}

deploy_services() {
    log_info "Deploying services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy with: docker-compose -f $COMPOSE_FILE up -d"
        return 0
    fi
    
    # Start services with proper dependency order
    local deploy_cmd="docker-compose -f $COMPOSE_FILE up -d --build --remove-orphans"
    
    if timeout "$DEPLOY_TIMEOUT" $deploy_cmd 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
        log_success "Services deployment completed"
    else
        log_error "Services deployment failed or timed out"
        log_info "Checking service status..."
        docker-compose -f "$COMPOSE_FILE" ps | tee -a "$DEPLOYMENT_LOG"
        exit 1
    fi
}

wait_for_services() {
    log_info "Waiting for services to be healthy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would wait for service health checks"
        return 0
    fi
    
    local services=("redis" "kong" "nginx" "claude-code-sdk")
    local max_wait=$HEALTH_CHECK_TIMEOUT
    local wait_interval=10
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        
        for service in "${services[@]}"; do
            local container_name="claude-${service}"
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown")
            
            case $health_status in
                "healthy")
                    log_success "$service is healthy"
                    ((healthy_count++))
                    ;;
                "starting")
                    log_info "$service is starting..."
                    ;;
                "unhealthy")
                    log_warning "$service is unhealthy"
                    ;;
                "unknown")
                    # Check if container is running (no health check defined)
                    if docker ps -q -f name="$container_name" | grep -q .; then
                        log_info "$service is running (no health check)"
                        ((healthy_count++))
                    else
                        log_warning "$service is not running"
                    fi
                    ;;
            esac
        done
        
        if [[ $healthy_count -eq ${#services[@]} ]]; then
            log_success "All services are healthy!"
            return 0
        fi
        
        log_info "Waiting... ($healthy_count/${#services[@]} services ready)"
        sleep $wait_interval
        ((elapsed += wait_interval))
    done
    
    log_error "Services did not become healthy within $max_wait seconds"
    log_info "Current service status:"
    docker-compose -f "$COMPOSE_FILE" ps | tee -a "$DEPLOYMENT_LOG"
    exit 1
}

run_post_deployment_validation() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        log_info "Skipping post-deployment validation (SKIP_TESTS=true)"
        return 0
    fi
    
    log_info "Running post-deployment validation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run post-deployment validation"
        return 0
    fi
    
    local validation_script="${SCRIPT_DIR}/post-deploy-verify.sh"
    if [[ -f "$validation_script" ]]; then
        if "$validation_script" "$ENVIRONMENT"; then
            log_success "Post-deployment validation passed"
        else
            log_error "Post-deployment validation failed"
            log_warning "Consider running rollback: ./rollback.sh"
            exit 1
        fi
    else
        log_warning "Post-deployment validation script not found"
        
        # Basic connectivity tests
        log_info "Running basic connectivity tests..."
        
        # Test Redis
        if docker exec claude-redis redis-cli ping | grep -q PONG; then
            log_success "Redis connectivity test passed"
        else
            log_error "Redis connectivity test failed"
        fi
        
        # Test Kong admin
        if curl -s http://localhost:${KONG_ADMIN_PORT:-8001}/status | grep -q '"database"'; then
            log_success "Kong admin API test passed"
        else
            log_error "Kong admin API test failed"
        fi
        
        # Test Nginx proxy
        if curl -s http://localhost:${NGINX_PROXY_PORT:-8085}/health | grep -q 'healthy'; then
            log_success "Nginx proxy test passed"
        else
            log_error "Nginx proxy test failed"
        fi
    fi
}

integrate_day2_monitoring() {
    log_info "Integrating Day 2 monitoring..."
    
    # Start monitoring scripts if available
    local monitoring_scripts=(
        "scripts/day2-system-monitor.sh"
        "scripts/day2-health-check.sh"
    )
    
    for script in "${monitoring_scripts[@]}"; do
        local script_path="${PROJECT_ROOT}/${script}"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            log_info "Starting monitoring: $script"
            if [[ "$DRY_RUN" != "true" ]]; then
                nohup "$script_path" > "${PROJECT_ROOT}/logs/monitoring-$(basename "$script" .sh).log" 2>&1 &
                log_success "Monitoring started: $script (PID: $!)"
            fi
        fi
    done
}

generate_deployment_report() {
    local deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    
    log_info "Generating deployment report..."
    
    cat << EOF | tee -a "$DEPLOYMENT_LOG"

==========================================
Deployment Report
==========================================
Deployment ID: $DEPLOYMENT_ID
Environment: $ENVIRONMENT
Start Time: $(date -d @$DEPLOYMENT_START_TIME)
End Time: $(date -d @$deployment_end_time)
Duration: ${deployment_duration} seconds
Service Version: $SERVICE_VERSION
Config File: $CONFIG_FILE
Compose File: $COMPOSE_FILE

Service Status:
$(docker-compose -f "$COMPOSE_FILE" ps 2>/dev/null || echo "Could not retrieve service status")

Service URLs:
- Nginx Proxy: http://localhost:${NGINX_PROXY_PORT:-8085}
- Kong Admin: http://localhost:${KONG_ADMIN_PORT:-8001}
- Kong Proxy: http://localhost:${KONG_PROXY_PORT:-8000}
- Redis: localhost:${REDIS_PORT:-6379}

Log Files:
- Deployment Log: $DEPLOYMENT_LOG
- Service Logs: docker-compose -f $COMPOSE_FILE logs

Next Steps:
1. Monitor services: docker-compose -f $COMPOSE_FILE logs -f
2. Run health checks: ./scripts/day2-health-check.sh
3. Test functionality: ./tests/e2e-comprehensive-test.sh
4. Set up monitoring: ./scripts/day2-system-monitor.sh

==========================================
EOF

    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "DRY RUN: Deployment simulation completed successfully!"
    else
        log_success "Deployment completed successfully!"
    fi
}

handle_deployment_failure() {
    local exit_code=$1
    
    log_error "Deployment failed with exit code: $exit_code"
    
    # Collect failure information
    log_info "Collecting failure information..."
    
    echo "=== Container Status ===" >> "$DEPLOYMENT_LOG"
    docker ps -a --filter name=claude- >> "$DEPLOYMENT_LOG" 2>&1 || true
    
    echo "=== Service Logs ===" >> "$DEPLOYMENT_LOG"
    docker-compose -f "$COMPOSE_FILE" logs >> "$DEPLOYMENT_LOG" 2>&1 || true
    
    echo "=== System Resources ===" >> "$DEPLOYMENT_LOG"
    docker system df >> "$DEPLOYMENT_LOG" 2>&1 || true
    
    log_info "Failure information collected in: $DEPLOYMENT_LOG"
    
    # Suggest rollback
    log_warning "Consider running rollback to restore previous state:"
    log_warning "  ./rollback.sh $ENVIRONMENT $DEPLOYMENT_ID"
    
    exit $exit_code
}

# Main deployment process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Production Deployment"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Timestamp: $(date)"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY RUN (simulation only)"
    fi
    echo
    
    # Set up error handling
    trap 'handle_deployment_failure $?' ERR
    
    # Create deployment infrastructure
    create_deployment_directories
    
    # Load configuration
    load_environment_config
    
    # Pre-deployment validation
    run_pre_deployment_checks
    
    # Backup current state
    backup_current_state
    
    # Stop existing services
    stop_existing_services
    
    # Select appropriate compose file
    select_compose_file
    
    # Deploy services
    deploy_services
    
    # Wait for services to be ready
    wait_for_services
    
    # Validate deployment
    run_post_deployment_validation
    
    # Start monitoring
    integrate_day2_monitoring
    
    # Generate report
    generate_deployment_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment] [options]"
    echo
    echo "Deploy Kong AWS Masking MVP with comprehensive validation"
    echo
    echo "Arguments:"
    echo "  environment    Target environment (development|staging|production)"
    echo "                 Default: production"
    echo
    echo "Environment Variables:"
    echo "  DEPLOY_TIMEOUT=300        Deployment timeout in seconds"
    echo "  HEALTH_CHECK_TIMEOUT=120  Health check timeout in seconds"
    echo "  BACKUP_ENABLED=true       Enable pre-deployment backup"
    echo "  SKIP_TESTS=false          Skip post-deployment validation"
    echo "  DRY_RUN=false            Simulate deployment without changes"
    echo
    echo "Examples:"
    echo "  $0                              # Deploy to production"
    echo "  $0 staging                      # Deploy to staging"
    echo "  DRY_RUN=true $0 production      # Simulate production deployment"
    echo "  SKIP_TESTS=true $0 production   # Deploy without validation tests"
    echo
    exit 0
fi

# Run main function
main "$@"