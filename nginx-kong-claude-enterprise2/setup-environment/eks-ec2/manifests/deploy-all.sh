#!/bin/bash

# Kong AWS Masking Enterprise - Kubernetes Deployment Script
# EKS + ElastiCache Redis Integration
# Version: v2.0.0-elasticache

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="kong-aws-masking"
DEPLOYMENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/k8s-deployment-${DEPLOYMENT_TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed or not in PATH"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi
    
    # Check required environment variables
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        error_exit "ANTHROPIC_API_KEY environment variable is required"
    fi
    
    if [[ -z "${ELASTICACHE_ENDPOINT:-}" ]]; then
        warning "ELASTICACHE_ENDPOINT not set, using default localhost.localstack.cloud"
        export ELASTICACHE_ENDPOINT="localhost.localstack.cloud"
    fi
    
    success "Prerequisites check completed"
}

# Update configurations with environment variables
update_configurations() {
    info "Updating configurations with environment variables..."
    
    # Create temporary directory for processed manifests
    TEMP_DIR="/tmp/k8s-manifests-${DEPLOYMENT_TIMESTAMP}"
    mkdir -p "$TEMP_DIR"
    
    # Copy all manifests to temp directory
    cp -r "$SCRIPT_DIR"/* "$TEMP_DIR/"
    
    # Update ElastiCache endpoint in configuration
    if [[ -f "$TEMP_DIR/elasticache/02-elasticache-config.yaml" ]]; then
        sed -i.bak "s/localhost.localstack.cloud/${ELASTICACHE_ENDPOINT}/g" "$TEMP_DIR/elasticache/02-elasticache-config.yaml"
        success "Updated ElastiCache endpoint to: ${ELASTICACHE_ENDPOINT}"
    fi
    
    # Encode API key for secret
    ENCODED_API_KEY=$(echo -n "${ANTHROPIC_API_KEY}" | base64)
    if [[ -f "$TEMP_DIR/elasticache/02-elasticache-config.yaml" ]]; then
        sed -i.bak "s/anthropic-api-key: \"\"/anthropic-api-key: ${ENCODED_API_KEY}/g" "$TEMP_DIR/elasticache/02-elasticache-config.yaml"
        success "Updated Anthropic API key in secret"
    fi
    
    export PROCESSED_MANIFESTS_DIR="$TEMP_DIR"
    success "Configuration update completed"
}

# Deploy namespace and RBAC
deploy_namespace() {
    info "Deploying namespace and RBAC..."
    
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/namespace/01-namespace.yaml"
    
    # Wait for namespace to be ready
    kubectl wait --for=condition=Active namespace/$NAMESPACE --timeout=30s
    
    success "Namespace '$NAMESPACE' deployed successfully"
}

# Deploy ElastiCache configuration
deploy_elasticache_config() {
    info "Deploying ElastiCache configuration..."
    
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/elasticache/02-elasticache-config.yaml"
    
    # Verify ConfigMap and Secret creation
    kubectl get configmap elasticache-config -n $NAMESPACE
    kubectl get secret elasticache-auth -n $NAMESPACE
    kubectl get secret kong-plugin-config -n $NAMESPACE
    
    success "ElastiCache configuration deployed successfully"
}

# Deploy Kong Gateway
deploy_kong() {
    info "Deploying Kong Gateway..."
    
    # Deploy Kong plugin files first
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/kong/10-kong-plugin-files.yaml"
    
    # Deploy Kong configuration
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/kong/04-kong-config.yaml"
    
    # Deploy Kong Gateway
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/kong/03-kong-deployment.yaml"
    
    # Wait for Kong to be ready
    info "Waiting for Kong Gateway to be ready..."
    kubectl wait --for=condition=available deployment/kong-gateway -n $NAMESPACE --timeout=300s
    
    # Check Kong admin API
    kubectl exec -n $NAMESPACE deployment/kong-gateway -- kong health
    
    success "Kong Gateway deployed successfully"
}

# Deploy Nginx Proxy
deploy_nginx() {
    info "Deploying Nginx Proxy..."
    
    # Deploy Nginx configuration
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/nginx/06-nginx-config.yaml"
    
    # Deploy Nginx proxy
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/nginx/05-nginx-deployment.yaml"
    
    # Wait for Nginx to be ready
    info "Waiting for Nginx Proxy to be ready..."
    kubectl wait --for=condition=available deployment/nginx-proxy -n $NAMESPACE --timeout=180s
    
    success "Nginx Proxy deployed successfully"
}

# Deploy Backend and Claude SDK
deploy_backend_and_sdk() {
    info "Deploying Backend API and Claude Code SDK..."
    
    # Deploy backend source code
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/claude-sdk/09-backend-source.yaml"
    
    # Deploy backend API
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/claude-sdk/07-backend-deployment.yaml"
    
    # Deploy Claude Code SDK
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/claude-sdk/08-claude-sdk-deployment.yaml"
    
    # Wait for backend to be ready
    info "Waiting for Backend API to be ready..."
    kubectl wait --for=condition=available deployment/backend-api -n $NAMESPACE --timeout=240s
    
    # Wait for Claude SDK to be ready
    info "Waiting for Claude Code SDK to be ready..."
    kubectl wait --for=condition=ready pod -l app=claude-code-sdk -n $NAMESPACE --timeout=180s
    
    success "Backend API and Claude Code SDK deployed successfully"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    echo ""
    echo "=== Deployment Status ==="
    kubectl get all -n $NAMESPACE
    
    echo ""
    echo "=== Service Endpoints ==="
    kubectl get services -n $NAMESPACE
    
    echo ""
    echo "=== Health Checks ==="
    
    # Test Kong Gateway health
    if kubectl exec -n $NAMESPACE deployment/kong-gateway -- curl -s http://localhost:8100/status &> /dev/null; then
        success "Kong Gateway health check: PASSED"
    else
        warning "Kong Gateway health check: FAILED"
    fi
    
    # Test Nginx proxy health
    if kubectl exec -n $NAMESPACE deployment/nginx-proxy -- curl -s http://localhost:8082/health &> /dev/null; then
        success "Nginx Proxy health check: PASSED"
    else
        warning "Nginx Proxy health check: FAILED"
    fi
    
    # Test Backend API health
    if kubectl exec -n $NAMESPACE deployment/backend-api -- curl -s http://localhost:3000/health &> /dev/null; then
        success "Backend API health check: PASSED"
    else
        warning "Backend API health check: FAILED"
    fi
    
    # Test Claude SDK health
    if kubectl exec -n $NAMESPACE deployment/claude-code-sdk -- /home/claude/scripts/health-check.sh &> /dev/null; then
        success "Claude Code SDK health check: PASSED"
    else
        warning "Claude Code SDK health check: FAILED"
    fi
    
    success "Deployment verification completed"
}

# Run integration test
run_integration_test() {
    info "Running integration test..."
    
    # Create and run integration test job
    kubectl apply -f "$PROCESSED_MANIFESTS_DIR/claude-sdk/08-claude-sdk-deployment.yaml"
    
    # Wait for test job to complete
    info "Waiting for integration test to complete..."
    kubectl wait --for=condition=complete job/claude-sdk-integration-test -n $NAMESPACE --timeout=120s
    
    # Show test results
    echo ""
    echo "=== Integration Test Results ==="
    kubectl logs job/claude-sdk-integration-test -n $NAMESPACE
    
    success "Integration test completed"
}

# Display access information
display_access_info() {
    info "Deployment completed successfully!"
    
    echo ""
    echo "🎉 Kong AWS Masking Enterprise - EKS Deployment Complete!"
    echo "=============================================================="
    echo ""
    echo "📋 Deployment Information:"
    echo "  • Namespace: $NAMESPACE"
    echo "  • Version: v2.0.0-elasticache"
    echo "  • Timestamp: $DEPLOYMENT_TIMESTAMP"
    echo "  • Log File: $LOG_FILE"
    echo ""
    echo "🔗 Service Access:"
    
    # Get LoadBalancer IP/hostname for Nginx
    NGINX_LB=$(kubectl get service nginx-proxy-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    if [[ "$NGINX_LB" != "pending" && -n "$NGINX_LB" ]]; then
        echo "  • Nginx Proxy (External): http://${NGINX_LB}:8082"
        echo "  • Health Check: http://${NGINX_LB}:8082/health"
    else
        echo "  • Nginx Proxy: Use port-forward for access"
        echo "    kubectl port-forward -n $NAMESPACE service/nginx-proxy-service 8082:8082"
    fi
    
    echo "  • Kong Admin (Internal): kubectl port-forward -n $NAMESPACE service/kong-admin-service 8001:8001"
    echo "  • Backend API (Internal): kubectl port-forward -n $NAMESPACE service/backend-api-service 3000:3000"
    echo ""
    echo "🖥️  Interactive Access:"
    echo "  • Claude Code SDK: kubectl exec -it -n $NAMESPACE deployment/claude-code-sdk -- /bin/bash"
    echo "  • Test AWS Masking: kubectl exec -n $NAMESPACE deployment/claude-code-sdk -- /home/claude/scripts/test-aws-masking.js"
    echo ""
    echo "📊 Monitoring:"
    echo "  • View Logs: kubectl logs -f -n $NAMESPACE deployment/kong-gateway"
    echo "  • Pod Status: kubectl get pods -n $NAMESPACE -w"
    echo "  • Service Status: kubectl get services -n $NAMESPACE"
    echo ""
    echo "🛠️  Management:"
    echo "  • Scale Kong: kubectl scale -n $NAMESPACE deployment/kong-gateway --replicas=3"
    echo "  • Restart Services: kubectl rollout restart -n $NAMESPACE deployment/nginx-proxy"
    echo "  • Delete All: kubectl delete namespace $NAMESPACE"
    echo ""
    
    success "Access information displayed"
}

# Main deployment function
main() {
    echo ""
    echo "🚀 Kong AWS Masking Enterprise - Kubernetes Deployment"
    echo "======================================================"
    echo "Version: v2.0.0-elasticache"
    echo "Target Namespace: $NAMESPACE"
    echo "Deployment ID: $DEPLOYMENT_TIMESTAMP"
    echo ""
    
    log "Starting Kubernetes deployment"
    
    # Execute deployment steps
    check_prerequisites
    update_configurations
    deploy_namespace
    deploy_elasticache_config
    deploy_kong
    deploy_nginx
    deploy_backend_and_sdk
    verify_deployment
    run_integration_test
    display_access_info
    
    log "Kubernetes deployment completed successfully"
    
    # Cleanup temp directory
    rm -rf "$PROCESSED_MANIFESTS_DIR"
    
    echo ""
    echo "✅ Deployment Complete! Check the log file for details: $LOG_FILE"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "verify")
        check_prerequisites
        verify_deployment
        ;;
    "cleanup")
        info "Cleaning up deployment..."
        kubectl delete namespace $NAMESPACE --ignore-not-found=true
        success "Cleanup completed"
        ;;
    "status")
        kubectl get all -n $NAMESPACE
        ;;
    *)
        echo "Usage: $0 [deploy|verify|cleanup|status]"
        echo "  deploy  - Full deployment (default)"
        echo "  verify  - Verify existing deployment"
        echo "  cleanup - Delete all resources"
        echo "  status  - Show deployment status"
        exit 1
        ;;
esac