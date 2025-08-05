#!/bin/bash

# Kong AWS Masking Enterprise 2 - EKS Deployment Script
# This script automates the deployment of the complete stack to EKS

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HELM_CHART_PATH="$PROJECT_ROOT/helm/kong-aws-masking"

# Default values
ENVIRONMENT="localstack"
NAMESPACE="claude-enterprise"
RELEASE_NAME="kong-masking"
VALUES_FILE=""
CLUSTER_NAME=""
AWS_REGION="ap-northeast-2"
LOCALSTACK_TOKEN="${LOCALSTACK_AUTH_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Kong AWS Masking Enterprise 2 to EKS

OPTIONS:
    -e, --environment ENVIRONMENT    Deployment environment (localstack|production) [default: localstack]
    -n, --namespace NAMESPACE        Kubernetes namespace [default: claude-enterprise]
    -r, --release RELEASE_NAME       Helm release name [default: kong-masking]
    -c, --cluster CLUSTER_NAME       EKS cluster name (required for production)
    -R, --region AWS_REGION          AWS region [default: ap-northeast-2]
    -v, --values VALUES_FILE         Custom values file path
    -t, --token LOCALSTACK_TOKEN     LocalStack Pro auth token (for localstack environment)
    -h, --help                       Show this help message

EXAMPLES:
    # Deploy to LocalStack EKS
    $0 --environment localstack --token \$LOCALSTACK_AUTH_TOKEN

    # Deploy to production EKS
    $0 --environment production --cluster my-eks-cluster --region ap-northeast-2

    # Deploy with custom values
    $0 --environment production --values custom-values.yaml

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -R|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -v|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -t|--token)
            LOCALSTACK_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validation
if [[ "$ENVIRONMENT" == "production" && -z "$CLUSTER_NAME" ]]; then
    log_error "Cluster name is required for production environment"
    exit 1
fi

if [[ "$ENVIRONMENT" == "localstack" && -z "$LOCALSTACK_TOKEN" ]]; then
    log_error "LocalStack Pro auth token is required for localstack environment"
    exit 1
fi

# Set values file based on environment if not specified
if [[ -z "$VALUES_FILE" ]]; then
    VALUES_FILE="$HELM_CHART_PATH/values-${ENVIRONMENT}.yaml"
fi

# Verify files exist
if [[ ! -f "$VALUES_FILE" ]]; then
    log_error "Values file not found: $VALUES_FILE"
    exit 1
fi

if [[ ! -f "$HELM_CHART_PATH/Chart.yaml" ]]; then
    log_error "Helm chart not found: $HELM_CHART_PATH"
    exit 1
fi

log_info "Kong AWS Masking Enterprise 2 - EKS Deployment"
log_info "Environment: $ENVIRONMENT"
log_info "Namespace: $NAMESPACE"
log_info "Release: $RELEASE_NAME"
log_info "Values file: $VALUES_FILE"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if aws CLI is available (for production)
    if [[ "$ENVIRONMENT" == "production" ]] && ! command -v aws &> /dev/null; then
        log_error "aws CLI is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Setup LocalStack EKS
setup_localstack_eks() {
    log_info "Setting up LocalStack EKS cluster..."
    
    # Check if LocalStack is running
    if ! curl -s http://localhost:4566/health &> /dev/null; then
        log_error "LocalStack is not running. Please start LocalStack with EKS enabled."
        exit 1
    fi
    
    # Set AWS credentials for LocalStack
    export AWS_ACCESS_KEY_ID="test"
    export AWS_SECRET_ACCESS_KEY="test"
    export AWS_DEFAULT_REGION="us-east-1"
    export AWS_ENDPOINT_URL="http://localhost:4566"
    
    # Create EKS cluster if not exists
    CLUSTER_NAME="kong-masking-local"
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" --endpoint-url http://localhost:4566 &> /dev/null; then
        log_info "Creating LocalStack EKS cluster: $CLUSTER_NAME"
        aws eks create-cluster \
            --name "$CLUSTER_NAME" \
            --version "1.27" \
            --role-arn "arn:aws:iam::000000000000:role/eks-service-role" \
            --resources-vpc-config subnetIds=subnet-12345,subnet-67890 \
            --endpoint-url http://localhost:4566
        
        # Wait for cluster to be active
        log_info "Waiting for cluster to be active..."
        sleep 10
    fi
    
    # Update kubeconfig for LocalStack
    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --endpoint-url http://localhost:4566 \
        --region us-east-1
    
    log_success "LocalStack EKS cluster configured"
}

# Setup production EKS
setup_production_eks() {
    log_info "Setting up production EKS connection..."
    
    # Update kubeconfig for production
    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION"
    
    # Verify cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to EKS cluster: $CLUSTER_NAME"
        exit 1
    fi
    
    log_success "Connected to production EKS cluster: $CLUSTER_NAME"
}

# Deploy with Helm
deploy_helm_chart() {
    log_info "Deploying Helm chart..."
    
    # Add any required Helm repositories
    # helm repo add bitnami https://charts.bitnami.com/bitnami
    # helm repo update
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Prepare Helm command
    HELM_CMD="helm upgrade --install $RELEASE_NAME $HELM_CHART_PATH"
    HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
    HELM_CMD="$HELM_CMD --values $VALUES_FILE"
    HELM_CMD="$HELM_CMD --timeout 10m"
    HELM_CMD="$HELM_CMD --wait"
    
    # Add environment-specific overrides
    if [[ "$ENVIRONMENT" == "localstack" ]]; then
        HELM_CMD="$HELM_CMD --set global.environment=localstack"
        HELM_CMD="$HELM_CMD --set secrets.claude.apiKey=test-key"
        if [[ -n "$LOCALSTACK_TOKEN" ]]; then
            HELM_CMD="$HELM_CMD --set env.LOCALSTACK_AUTH_TOKEN=$LOCALSTACK_TOKEN"
        fi
    fi
    
    log_info "Executing: $HELM_CMD"
    eval "$HELM_CMD"
    
    log_success "Helm chart deployed successfully"
}

# Run tests
run_tests() {
    log_info "Running deployment tests..."
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod \
        --selector="app.kubernetes.io/instance=$RELEASE_NAME" \
        --namespace="$NAMESPACE" \
        --timeout=300s
    
    # Run Helm tests
    if helm test "$RELEASE_NAME" --namespace "$NAMESPACE" --timeout 5m; then
        log_success "All tests passed"
    else
        log_warning "Some tests failed - check pod logs for details"
        
        # Show test pod logs
        kubectl logs --selector="app.kubernetes.io/component=test" \
            --namespace="$NAMESPACE" \
            --tail=50 || true
    fi
}

# Show deployment status
show_status() {
    log_info "Deployment Status:"
    
    echo
    echo "=== Helm Release ==="
    helm status "$RELEASE_NAME" --namespace "$NAMESPACE"
    
    echo
    echo "=== Pods ==="
    kubectl get pods --namespace "$NAMESPACE" \
        --selector="app.kubernetes.io/instance=$RELEASE_NAME"
    
    echo
    echo "=== Services ==="
    kubectl get services --namespace "$NAMESPACE" \
        --selector="app.kubernetes.io/instance=$RELEASE_NAME"
    
    echo
    echo "=== Ingress (if any) ==="
    kubectl get ingress --namespace "$NAMESPACE" \
        --selector="app.kubernetes.io/instance=$RELEASE_NAME" || true
    
    # Show access information
    echo
    echo "=== Access Information ==="
    if [[ "$ENVIRONMENT" == "localstack" ]]; then
        echo "LocalStack environment - access via NodePort or port-forward:"
        echo "kubectl port-forward service/$RELEASE_NAME-claude-sdk 8085:8085 --namespace $NAMESPACE"
    else
        echo "Production environment - check LoadBalancer or Ingress for external access"
        kubectl get service "$RELEASE_NAME-claude-sdk" --namespace "$NAMESPACE" -o wide
    fi
}

# Cleanup function
cleanup() {
    if [[ "$ENVIRONMENT" == "localstack" ]]; then
        log_info "Cleanup: Restoring AWS environment variables"
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION AWS_ENDPOINT_URL
    fi
}

# Main execution
main() {
    trap cleanup EXIT
    
    check_prerequisites
    
    if [[ "$ENVIRONMENT" == "localstack" ]]; then
        setup_localstack_eks
    else
        setup_production_eks
    fi
    
    deploy_helm_chart
    run_tests
    show_status
    
    log_success "Kong AWS Masking Enterprise 2 deployed successfully to EKS!"
}

# Run main function
main "$@"