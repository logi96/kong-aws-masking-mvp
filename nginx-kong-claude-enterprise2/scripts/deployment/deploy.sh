#!/bin/bash
# Production Deployment Script with Blue-Green Strategy

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_LOG="${PROJECT_ROOT}/deployments/deployment-$(date +%Y%m%d%H%M%S).log"
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_INTERVAL=5

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${DEPLOYMENT_LOG}"
}

# Pre-deployment checks
pre_deployment_checks() {
    log "INFO" "${BLUE}Running pre-deployment checks...${NC}"
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "${RED}Docker daemon is not running${NC}"
        exit 1
    fi
    
    # Check required files
    local required_files=(
        "${PROJECT_ROOT}/docker-compose.yml"
        "${PROJECT_ROOT}/docker-compose.prod.yml"
        "${PROJECT_ROOT}/.env.production"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log "ERROR" "${RED}Required file missing: $file${NC}"
            exit 1
        fi
    done
    
    # Check disk space
    local available_space=$(df -BG "${PROJECT_ROOT}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 10 ]]; then
        log "WARNING" "${YELLOW}Low disk space: ${available_space}GB available${NC}"
    fi
    
    # Backup current configuration
    backup_current_deployment
    
    log "INFO" "${GREEN}Pre-deployment checks passed${NC}"
}

# Backup current deployment
backup_current_deployment() {
    log "INFO" "Creating backup of current deployment..."
    
    local backup_dir="${PROJECT_ROOT}/deployments/backups/$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Save current container state
    docker-compose ps --format json > "${backup_dir}/container-state.json"
    
    # Save current images
    docker-compose config --images > "${backup_dir}/images.txt"
    
    # Copy environment files
    cp "${PROJECT_ROOT}/.env"* "${backup_dir}/" 2>/dev/null || true
    
    log "INFO" "Backup created at: ${backup_dir}"
}

# Determine deployment color (blue/green)
get_deployment_color() {
    local current_color=$(docker ps --filter "label=com.claude.deployment.color" --format '{{.Labels}}' | grep -oP 'com.claude.deployment.color=\K\w+' | head -1)
    
    if [[ "$current_color" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

# Deploy new version
deploy_new_version() {
    local deployment_color=$1
    log "INFO" "${BLUE}Deploying new version to ${deployment_color} environment...${NC}"
    
    # Set deployment environment variables
    export DEPLOYMENT_COLOR="${deployment_color}"
    export DEPLOYMENT_TIMESTAMP=$(date +%Y%m%d%H%M%S)
    export DEPLOYMENT_VERSION="${SERVICE_VERSION}-${DEPLOYMENT_TIMESTAMP}"
    
    # Build new images
    log "INFO" "Building new images..."
    docker-compose -f docker-compose.prod.yml build --no-cache
    
    # Start new containers in background
    log "INFO" "Starting ${deployment_color} containers..."
    docker-compose -f docker-compose.prod.yml -f docker-compose.override.yml --profile blue-green up -d "kong-${deployment_color}"
    
    # Wait for health checks
    wait_for_health_checks "${deployment_color}"
}

# Wait for health checks
wait_for_health_checks() {
    local deployment_color=$1
    local retries=0
    
    log "INFO" "Waiting for ${deployment_color} environment to be healthy..."
    
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        if docker exec "claude-kong-${deployment_color}" kong health >/dev/null 2>&1; then
            log "INFO" "${GREEN}${deployment_color} environment is healthy${NC}"
            return 0
        fi
        
        retries=$((retries + 1))
        log "INFO" "Health check attempt ${retries}/${HEALTH_CHECK_RETRIES}..."
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log "ERROR" "${RED}${deployment_color} environment failed health checks${NC}"
    return 1
}

# Switch traffic to new deployment
switch_traffic() {
    local deployment_color=$1
    log "INFO" "${BLUE}Switching traffic to ${deployment_color} environment...${NC}"
    
    # Update nginx upstream configuration
    cat > "${PROJECT_ROOT}/nginx/conf.d/upstream-switch.conf" <<EOF
upstream kong_backend {
    server kong-${deployment_color}:8000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
EOF
    
    # Reload nginx configuration
    docker-compose exec -T nginx nginx -s reload
    
    log "INFO" "${GREEN}Traffic switched to ${deployment_color} environment${NC}"
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Run smoke tests
    "${SCRIPT_DIR}/smoke-tests.sh"
    
    # Check error rates
    local error_rate=$(docker-compose exec -T nginx awk '$9 >= 500 {count++} END {print (count/NR)*100}' /var/log/nginx/access.log | tail -1)
    if (( $(echo "$error_rate > 5" | bc -l) )); then
        log "ERROR" "${RED}High error rate detected: ${error_rate}%${NC}"
        return 1
    fi
    
    log "INFO" "${GREEN}Deployment validation passed${NC}"
    return 0
}

# Cleanup old deployment
cleanup_old_deployment() {
    local old_color=$1
    log "INFO" "Cleaning up ${old_color} environment..."
    
    # Stop old containers gracefully
    docker-compose -f docker-compose.prod.yml -f docker-compose.override.yml --profile blue-green stop "kong-${old_color}"
    
    # Remove old containers after grace period
    sleep 30
    docker-compose -f docker-compose.prod.yml -f docker-compose.override.yml --profile blue-green rm -f "kong-${old_color}"
    
    log "INFO" "Cleanup completed"
}

# Rollback deployment
rollback_deployment() {
    local current_color=$1
    local previous_color=$2
    
    log "WARNING" "${YELLOW}Initiating rollback from ${current_color} to ${previous_color}...${NC}"
    
    # Switch traffic back
    switch_traffic "$previous_color"
    
    # Stop failed deployment
    docker-compose -f docker-compose.prod.yml -f docker-compose.override.yml --profile blue-green stop "kong-${current_color}"
    
    # Remove failed containers
    docker-compose -f docker-compose.prod.yml -f docker-compose.override.yml --profile blue-green rm -f "kong-${current_color}"
    
    log "INFO" "${GREEN}Rollback completed${NC}"
}

# Main deployment flow
main() {
    log "INFO" "${BLUE}Starting production deployment...${NC}"
    
    # Create deployment directory
    mkdir -p "${PROJECT_ROOT}/deployments"
    
    # Load production environment
    if [[ -f "${PROJECT_ROOT}/.env.production" ]]; then
        source "${PROJECT_ROOT}/.env.production"
    fi
    
    # Run pre-deployment checks
    pre_deployment_checks
    
    # Determine deployment strategy
    local current_color=$(docker ps --filter "label=com.claude.deployment.color" --format '{{.Labels}}' | grep -oP 'com.claude.deployment.color=\K\w+' | head -1 || echo "none")
    local new_color=$(get_deployment_color)
    
    log "INFO" "Current deployment: ${current_color}, New deployment: ${new_color}"
    
    # Deploy new version
    if deploy_new_version "$new_color"; then
        # Switch traffic
        switch_traffic "$new_color"
        
        # Validate deployment
        if validate_deployment; then
            # Cleanup old deployment
            if [[ "$current_color" != "none" ]] && [[ "$current_color" != "$new_color" ]]; then
                cleanup_old_deployment "$current_color"
            fi
            
            log "INFO" "${GREEN}Deployment completed successfully!${NC}"
            exit 0
        else
            # Rollback on validation failure
            if [[ "$current_color" != "none" ]]; then
                rollback_deployment "$new_color" "$current_color"
            fi
            
            log "ERROR" "${RED}Deployment failed and rolled back${NC}"
            exit 1
        fi
    else
        log "ERROR" "${RED}Deployment failed during startup${NC}"
        exit 1
    fi
}

# Run main function
main "$@"