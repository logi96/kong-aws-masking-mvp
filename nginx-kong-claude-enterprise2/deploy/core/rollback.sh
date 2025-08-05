#!/bin/bash

# Rollback Script for Kong AWS Masking MVP
# Generated: 2025-07-29
# Purpose: Fast and safe rollback to previous working state

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
DEPLOYMENT_ID="${2:-auto}"
BACKUP_DIR="${PROJECT_ROOT}/backups/pre-deploy"

# Rollback configuration
ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-120}"
FORCE_ROLLBACK="${FORCE_ROLLBACK:-false}"
PRESERVE_DATA="${PRESERVE_DATA:-true}"
DRY_RUN="${DRY_RUN:-false}"

# Rollback tracking
ROLLBACK_START_TIME=$(date +%s)
ROLLBACK_ID="rollback-$(date +%Y%m%d-%H%M%S)"
ROLLBACK_LOG="${PROJECT_ROOT}/logs/rollbacks/${ROLLBACK_ID}.log"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

# Utility functions
create_rollback_directories() {
    log_info "Creating rollback directories..."
    
    local dirs=(
        "logs/rollbacks"
        "backups/rollback-state"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${PROJECT_ROOT}/${dir}"
    done
    
    log_success "Rollback directories created"
}

detect_deployment_to_rollback() {
    log_info "Detecting deployment to rollback..."
    
    if [[ "$DEPLOYMENT_ID" == "auto" ]]; then
        # Find the most recent deployment backup
        if [[ -d "$BACKUP_DIR" ]]; then
            DEPLOYMENT_ID=$(ls -1t "$BACKUP_DIR" | head -n 1)
            if [[ -n "$DEPLOYMENT_ID" ]]; then
                log_success "Auto-detected deployment: $DEPLOYMENT_ID"
            else
                log_error "No deployment backups found in $BACKUP_DIR"
                exit 1
            fi
        else
            log_error "Backup directory not found: $BACKUP_DIR"
            exit 1
        fi
    fi
    
    local deployment_backup="${BACKUP_DIR}/${DEPLOYMENT_ID}"
    if [[ ! -d "$deployment_backup" ]]; then
        log_error "Deployment backup not found: $deployment_backup"
        exit 1
    fi
    
    log_success "Rolling back deployment: $DEPLOYMENT_ID"
    log_info "Backup location: $deployment_backup"
}

validate_rollback_safety() {
    log_info "Validating rollback safety..."
    
    # Check if services are running
    local running_services=$(docker ps -q --filter name=claude- | wc -l)
    if [[ $running_services -eq 0 ]]; then
        log_warning "No Claude services are currently running"
    else
        log_info "$running_services Claude services are currently running"
    fi
    
    # Check system resources
    local memory_usage=$(docker system df --format "table {{.Size}}" 2>/dev/null | tail -n +2 | head -n 1 || echo "unknown")
    log_info "Current Docker disk usage: $memory_usage"
    
    # Validate backup integrity
    local deployment_backup="${BACKUP_DIR}/${DEPLOYMENT_ID}"
    local required_files=("config.env")
    
    for file in "${required_files[@]}"; do
        if [[ -f "${deployment_backup}/${file}" ]]; then
            log_success "Backup file validated: $file"
        else
            log_warning "Backup file missing: $file"
        fi
    done
    
    # Check for force rollback conditions
    if [[ "$FORCE_ROLLBACK" != "true" ]]; then
        local healthy_services=0
        local total_services=0
        
        for service in redis kong nginx claude-code-sdk; do
            ((total_services++))
            local container_name="claude-${service}"
            if docker ps -q -f name="$container_name" | grep -q .; then
                local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown")
                if [[ "$health_status" == "healthy" || "$health_status" == "unknown" ]]; then
                    ((healthy_services++))
                fi
            fi
        done
        
        if [[ $healthy_services -gt $((total_services / 2)) ]]; then
            log_warning "More than half of services appear healthy"
            log_warning "Use FORCE_ROLLBACK=true to proceed anyway"
            if [[ "$DRY_RUN" != "true" ]]; then
                read -p "Continue with rollback? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Rollback cancelled by user"
                    exit 0
                fi
            fi
        fi
    fi
    
    log_success "Rollback safety validation completed"
}

backup_current_state() {
    log_info "Backing up current state before rollback..."
    
    local current_state_backup="${PROJECT_ROOT}/backups/rollback-state/${ROLLBACK_ID}"
    mkdir -p "$current_state_backup"
    
    # Backup current configuration
    local config_file="${PROJECT_ROOT}/config/${ENVIRONMENT}.env"
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$current_state_backup/config.env"
        log_success "Current configuration backed up"
    fi
    
    # Backup current service state
    if docker-compose ps --format json > "$current_state_backup/services-state.json" 2>/dev/null; then
        log_success "Current services state backed up"
    fi
    
    # Backup current Redis data if enabled and container running
    if [[ "$PRESERVE_DATA" == "true" ]] && docker ps -q -f name=claude-redis | grep -q .; then
        log_info "Backing up current Redis data..."
        if docker exec claude-redis redis-cli --rdb "/data/rollback-backup-${ROLLBACK_ID}.rdb" 2>/dev/null; then
            log_success "Redis data backed up"
        else
            log_warning "Redis backup failed, continuing rollback"
        fi
    fi
    
    log_success "Current state backup completed: $current_state_backup"
}

stop_current_services() {
    log_info "Stopping current services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would stop services with timeout"
        return 0
    fi
    
    # Graceful shutdown with timeout
    local stop_timeout=30
    
    if timeout $stop_timeout docker-compose down 2>&1 | tee -a "$ROLLBACK_LOG"; then
        log_success "Services stopped gracefully"
    else
        log_warning "Graceful shutdown timed out, forcing stop..."
        
        # Force stop containers
        local containers=$(docker ps -q --filter name=claude- || true)
        if [[ -n "$containers" ]]; then
            echo "$containers" | xargs -r docker stop -t 10
            echo "$containers" | xargs -r docker rm -f
            log_warning "Services force-stopped"
        fi
    fi
    
    # Clean up networks
    local networks=$(docker network ls --format '{{.Name}}' | grep claude- || true)
    if [[ -n "$networks" ]]; then
        echo "$networks" | xargs -r docker network rm 2>/dev/null || true
        log_info "Networks cleaned up"
    fi
}

restore_configuration() {
    log_info "Restoring configuration from backup..."
    
    local deployment_backup="${BACKUP_DIR}/${DEPLOYMENT_ID}"
    local backup_config="${deployment_backup}/config.env"
    local current_config="${PROJECT_ROOT}/config/${ENVIRONMENT}.env"
    
    if [[ -f "$backup_config" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would restore config from $backup_config"
        else
            cp "$backup_config" "$current_config"
            log_success "Configuration restored from backup"
        fi
    else
        log_warning "No configuration backup found, keeping current config"
    fi
    
    # Validate restored configuration
    if [[ "$DRY_RUN" != "true" ]]; then
        local validate_script="${PROJECT_ROOT}/config/validate-config.sh"
        if [[ -f "$validate_script" ]]; then
            if "$validate_script" "$ENVIRONMENT" &> /dev/null; then
                log_success "Restored configuration validated"
            else
                log_error "Restored configuration validation failed"
                exit 1
            fi
        fi
    fi
}

restore_redis_data() {
    if [[ "$PRESERVE_DATA" != "true" ]]; then
        log_info "Data preservation disabled, skipping Redis restore"
        return 0
    fi
    
    log_info "Restoring Redis data..."
    
    local deployment_backup="${BACKUP_DIR}/${DEPLOYMENT_ID}"
    
    # Look for Redis backup files
    local redis_backup=$(find "$deployment_backup" -name "*.rdb" | head -n 1)
    
    if [[ -n "$redis_backup" && -f "$redis_backup" ]]; then
        log_info "Found Redis backup: $(basename "$redis_backup")"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would restore Redis data from backup"
        else
            # Start Redis temporarily to restore data
            log_info "Starting Redis for data restoration..."
            docker-compose up -d redis
            
            # Wait for Redis to be ready
            local max_wait=30
            local wait_count=0
            while [[ $wait_count -lt $max_wait ]]; do
                if docker exec claude-redis redis-cli ping &> /dev/null; then
                    break
                fi
                sleep 1
                ((wait_count++))
            done
            
            if [[ $wait_count -ge $max_wait ]]; then
                log_error "Redis did not start within $max_wait seconds"
                return 1
            fi
            
            # Restore data
            if docker cp "$redis_backup" claude-redis:/data/restore.rdb; then
                # Restart Redis to load the restored data
                docker-compose restart redis
                log_success "Redis data restored from backup"
            else
                log_error "Failed to restore Redis data"
                return 1
            fi
        fi
    else
        log_warning "No Redis backup found, starting with empty data"
    fi
}

restart_services() {
    log_info "Starting services with restored configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would start services with docker-compose up -d"
        return 0
    fi
    
    # Determine compose file
    local compose_file="${PROJECT_ROOT}/docker-compose.yml"
    if [[ "$ENVIRONMENT" == "production" && -f "${PROJECT_ROOT}/docker-compose.prod.yml" ]]; then
        compose_file="${PROJECT_ROOT}/docker-compose.prod.yml"
    fi
    
    # Start services
    if timeout "$ROLLBACK_TIMEOUT" docker-compose -f "$compose_file" up -d 2>&1 | tee -a "$ROLLBACK_LOG"; then
        log_success "Services started successfully"
    else
        log_error "Failed to start services within timeout"
        exit 1
    fi
}

verify_rollback() {
    log_info "Verifying rollback success..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would verify service health"
        return 0
    fi
    
    local services=("redis" "kong" "nginx" "claude-code-sdk")
    local healthy_count=0
    local max_wait=60
    local wait_interval=5
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        healthy_count=0
        
        for service in "${services[@]}"; do
            local container_name="claude-${service}"
            
            if docker ps -q -f name="$container_name" | grep -q .; then
                local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "running")
                
                case $health_status in
                    "healthy"|"running")
                        ((healthy_count++))
                        ;;
                    "starting")
                        log_info "$service is still starting..."
                        ;;
                    *)
                        log_warning "$service status: $health_status"
                        ;;
                esac
            else
                log_warning "$service container not found"
            fi
        done
        
        if [[ $healthy_count -eq ${#services[@]} ]]; then
            log_success "All services are running after rollback"
            break
        fi
        
        log_info "Waiting for services... ($healthy_count/${#services[@]} ready)"
        sleep $wait_interval
        ((elapsed += wait_interval))
    done
    
    if [[ $healthy_count -lt ${#services[@]} ]]; then
        log_error "Not all services are healthy after rollback"
        return 1
    fi
    
    # Basic connectivity tests
    log_info "Running basic connectivity tests..."
    
    # Test Redis
    if docker exec claude-redis redis-cli ping | grep -q PONG; then
        log_success "Redis connectivity test passed"
    else
        log_error "Redis connectivity test failed"
    fi
    
    # Test Kong admin
    local kong_admin_port=$(grep KONG_ADMIN_PORT "${PROJECT_ROOT}/config/${ENVIRONMENT}.env" | cut -d'=' -f2 || echo 8001)
    if curl -s "http://localhost:${kong_admin_port}/status" | grep -q '"database"'; then
        log_success "Kong admin API test passed"
    else
        log_error "Kong admin API test failed"
    fi
    
    # Test Nginx
    local nginx_port=$(grep NGINX_PROXY_PORT "${PROJECT_ROOT}/config/${ENVIRONMENT}.env" | cut -d'=' -f2 || echo 8085)
    if curl -s "http://localhost:${nginx_port}/health" | grep -q 'healthy'; then
        log_success "Nginx proxy test passed"
    else
        log_error "Nginx proxy test failed"
    fi
    
    log_success "Rollback verification completed"
}

generate_rollback_report() {
    local rollback_end_time=$(date +%s)
    local rollback_duration=$((rollback_end_time - ROLLBACK_START_TIME))
    
    log_info "Generating rollback report..."
    
    cat << EOF | tee -a "$ROLLBACK_LOG"

==========================================
Rollback Report
==========================================
Rollback ID: $ROLLBACK_ID
Environment: $ENVIRONMENT
Rolled Back Deployment: $DEPLOYMENT_ID
Start Time: $(date -d @$ROLLBACK_START_TIME)
End Time: $(date -d @$rollback_end_time)
Duration: ${rollback_duration} seconds
Preserve Data: $PRESERVE_DATA
Force Rollback: $FORCE_ROLLBACK

Current Service Status:
$(docker-compose ps 2>/dev/null || echo "Could not retrieve service status")

Rollback Backup Location:
${PROJECT_ROOT}/backups/rollback-state/${ROLLBACK_ID}

Log Files:
- Rollback Log: $ROLLBACK_LOG
- Service Logs: docker-compose logs

Next Steps:
1. Monitor services: docker-compose logs -f
2. Run health checks: ./scripts/day2-health-check.sh
3. Verify functionality: ./tests/e2e-comprehensive-test.sh

==========================================
EOF

    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "DRY RUN: Rollback simulation completed successfully!"
    else
        log_success "Rollback completed successfully in ${rollback_duration} seconds!"
    fi
}

handle_rollback_failure() {
    local exit_code=$1
    
    log_error "Rollback failed with exit code: $exit_code"
    
    # Try emergency recovery
    log_info "Attempting emergency recovery..."
    
    # Stop all claude containers
    local containers=$(docker ps -aq --filter name=claude- || true)
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs -r docker stop -t 5
        echo "$containers" | xargs -r docker rm -f
        log_info "All containers stopped and removed"
    fi
    
    # Clean networks and volumes if needed
    docker network prune -f &> /dev/null || true
    
    log_error "Emergency recovery completed. Manual intervention may be required."
    log_info "Check rollback log: $ROLLBACK_LOG"
    
    exit $exit_code
}

# Main rollback process
main() {
    echo "=========================================="
    echo "Kong AWS Masking MVP - Rollback"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Rollback ID: $ROLLBACK_ID"
    echo "Timestamp: $(date)"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY RUN (simulation only)"
    fi
    echo
    
    # Set up error handling
    trap 'handle_rollback_failure $?' ERR
    
    # Create rollback infrastructure
    create_rollback_directories
    
    # Detect deployment to rollback
    detect_deployment_to_rollback
    
    # Validate rollback safety
    validate_rollback_safety
    
    # Backup current state
    backup_current_state
    
    # Stop current services
    stop_current_services
    
    # Restore configuration
    restore_configuration
    
    # Restore data if enabled
    restore_redis_data
    
    # Restart services
    restart_services
    
    # Verify rollback
    verify_rollback
    
    # Generate report
    generate_rollback_report
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [environment] [deployment-id] [options]"
    echo
    echo "Rollback Kong AWS Masking MVP to previous working state"
    echo
    echo "Arguments:"
    echo "  environment      Target environment (development|staging|production)"
    echo "  deployment-id    Deployment to rollback (auto|deploy-YYYYMMDD-HHMMSS)"
    echo "                   Default: auto (most recent)"
    echo
    echo "Environment Variables:"
    echo "  ROLLBACK_TIMEOUT=120      Rollback timeout in seconds"
    echo "  FORCE_ROLLBACK=false      Skip safety checks"
    echo "  PRESERVE_DATA=true        Preserve Redis data during rollback"
    echo "  DRY_RUN=false            Simulate rollback without changes"
    echo
    echo "Examples:"
    echo "  $0                                    # Rollback production to latest"
    echo "  $0 staging                           # Rollback staging to latest"
    echo "  $0 production deploy-20250729-143022 # Rollback to specific deployment"
    echo "  DRY_RUN=true $0 production           # Simulate rollback"
    echo "  FORCE_ROLLBACK=true $0 production    # Force rollback"
    echo
    echo "Available deployments:"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -1t "$BACKUP_DIR" | head -n 5
    else
        echo "  No backups found"
    fi
    echo
    exit 0
fi

# Run main function
main "$@"