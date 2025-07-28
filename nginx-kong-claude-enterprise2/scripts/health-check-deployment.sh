#!/bin/sh
# Deployment Health Check Script

set -e

# Configuration
HEALTH_CHECK_RETRIES=${HEALTH_CHECK_RETRIES:-5}
DEPLOYMENT_VERSION=${DEPLOYMENT_VERSION:-unknown}

# Colors for output (works in Alpine)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Services to check
SERVICES="redis kong nginx"

# Health check endpoints
REDIS_HEALTH="redis-cli -h redis -p 6379 ping"
KONG_HEALTH="curl -sf http://kong:8001/status"
NGINX_HEALTH="curl -sf http://nginx:8082/health"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check individual service
check_service() {
    local service=$1
    local health_cmd=$2
    local retries=0
    
    while [ $retries -lt $HEALTH_CHECK_RETRIES ]; do
        if eval "$health_cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} $service is healthy"
            return 0
        fi
        
        retries=$((retries + 1))
        sleep 2
    done
    
    echo -e "${RED}✗${NC} $service is unhealthy"
    return 1
}

# Check all services
check_all_services() {
    local all_healthy=true
    
    log "Checking service health for deployment: $DEPLOYMENT_VERSION"
    
    # Check Redis
    if ! check_service "Redis" "$REDIS_HEALTH"; then
        all_healthy=false
    fi
    
    # Check Kong
    if ! check_service "Kong" "$KONG_HEALTH"; then
        all_healthy=false
    fi
    
    # Check Nginx
    if ! check_service "Nginx" "$NGINX_HEALTH"; then
        all_healthy=false
    fi
    
    # Check Kong plugins
    if curl -sf http://kong:8001/plugins/enabled | grep -q "aws-masker"; then
        echo -e "${GREEN}✓${NC} aws-masker plugin is enabled"
    else
        echo -e "${RED}✗${NC} aws-masker plugin is not enabled"
        all_healthy=false
    fi
    
    # Performance check
    check_performance
    
    if [ "$all_healthy" = true ]; then
        log "All services are healthy"
        return 0
    else
        log "Some services are unhealthy"
        return 1
    fi
}

# Check performance metrics
check_performance() {
    log "Checking performance metrics..."
    
    # Test Kong response time
    local start_time=$(date +%s%N)
    if curl -sf -o /dev/null http://kong:8000/health; then
        local end_time=$(date +%s%N)
        local response_time=$(( (end_time - start_time) / 1000000 ))
        
        if [ $response_time -lt 1000 ]; then
            echo -e "${GREEN}✓${NC} Kong response time: ${response_time}ms"
        else
            echo -e "${YELLOW}⚠${NC} Kong response time: ${response_time}ms (slow)"
        fi
    fi
    
    # Check memory usage
    if command -v free >/dev/null 2>&1; then
        local mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
        echo "Memory usage: ${mem_usage}%"
    fi
}

# Generate health report
generate_health_report() {
    local report_file="/deployments/health-report-$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$report_file" <<EOF
{
    "deployment_version": "$DEPLOYMENT_VERSION",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "services": {
        "redis": $(check_service "Redis" "$REDIS_HEALTH" >/dev/null 2>&1 && echo "\"healthy\"" || echo "\"unhealthy\""),
        "kong": $(check_service "Kong" "$KONG_HEALTH" >/dev/null 2>&1 && echo "\"healthy\"" || echo "\"unhealthy\""),
        "nginx": $(check_service "Nginx" "$NGINX_HEALTH" >/dev/null 2>&1 && echo "\"healthy\"" || echo "\"unhealthy\"")
    }
}
EOF
    
    log "Health report saved to: $report_file"
}

# Main execution
main() {
    log "Starting health check for deployment version: $DEPLOYMENT_VERSION"
    
    # Create reports directory
    mkdir -p /deployments
    
    # Run health checks
    if check_all_services; then
        generate_health_report
        exit 0
    else
        generate_health_report
        exit 1
    fi
}

# Run main
main