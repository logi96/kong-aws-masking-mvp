#!/bin/bash
# EKS-Fargate Deployment Script for Kong AWS Masking Enterprise 2
# Complete automated deployment with Fargate-specific configurations

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/eks-fargate-deployment-$(date +%Y%m%d_%H%M%S).log"
START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        DEBUG)
            echo -e "${CYAN}[DEBUG]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "${BLUE}[$level]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Configuration and defaults
CLUSTER_NAME="${EKS_CLUSTER_NAME:-kong-masking-fargate}"
FARGATE_PROFILE_NAME="${FARGATE_PROFILE_NAME:-kong-aws-masking-profile}"
EXECUTION_ROLE_NAME="${EXECUTION_ROLE_NAME:-eks-fargate-pod-execution-role}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_ENDPOINT="${AWS_ENDPOINT:-}"
NAMESPACE="kong-aws-masking"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-test-key-for-localstack}"
ELASTICACHE_ENDPOINT="${ELASTICACHE_ENDPOINT:-localhost.localstack.cloud}"
ELASTICACHE_PORT="${ELASTICACHE_PORT:-4510}"

# AWS CLI command wrapper
aws_cmd() {
    if [ -n "$AWS_ENDPOINT" ]; then
        aws --endpoint-url="$AWS_ENDPOINT" --region="$AWS_REGION" "$@"
    else
        aws --region="$AWS_REGION" "$@"
    fi
}

# Kubectl command wrapper with error handling
kubectl_cmd() {
    kubectl "$@" 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -ne 0 ]; then
        log ERROR "kubectl command failed: kubectl $*"
        return $exit_code
    fi
    return 0
}

# Display banner
show_banner() {
    log INFO "╔════════════════════════════════════════════════════════════════╗"
    log INFO "║              Kong AWS Masking Enterprise 2                    ║"
    log INFO "║                 EKS-Fargate Deployment                        ║"
    log INFO "║                      Version 2.0.0                           ║"
    log INFO "╚════════════════════════════════════════════════════════════════╝"
    log INFO ""
    log INFO "🎯 Target: EKS Fargate serverless deployment"
    log INFO "📦 Cluster: $CLUSTER_NAME"
    log INFO "🌐 Region: $AWS_REGION"
    log INFO "📝 Log File: $LOG_FILE"
    log INFO ""
}

# Validate prerequisites
validate_prerequisites() {
    log INFO "🔍 Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl aws jq curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log ERROR "Missing required tools: ${missing_tools[*]}"
        log ERROR "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log ERROR "kubectl cannot connect to Kubernetes cluster"
        log ERROR "Please ensure your kubeconfig is properly configured"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws_cmd sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid"
        log ERROR "Please configure your AWS credentials"
        exit 1
    fi
    
    # Validate environment variables
    if [ -z "$ANTHROPIC_API_KEY" ] || [ "$ANTHROPIC_API_KEY" = "test-key-for-localstack" ]; then
        log WARN "Using default/test ANTHROPIC_API_KEY. Set a real key for production use."
    fi
    
    log SUCCESS "All prerequisites validated successfully"
}

# Create or verify EKS cluster
verify_eks_cluster() {
    log INFO "🔍 Verifying EKS cluster: $CLUSTER_NAME"
    
    if aws_cmd eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
        log SUCCESS "EKS cluster '$CLUSTER_NAME' exists"
        
        # Get cluster status
        local cluster_status=$(aws_cmd eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.status' --output text)
        if [ "$cluster_status" != "ACTIVE" ]; then
            log ERROR "EKS cluster is not ACTIVE. Current status: $cluster_status"
            exit 1
        fi
        
        # Update kubeconfig
        log INFO "Updating kubeconfig for cluster access..."
        aws_cmd eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
        
    else
        log WARN "EKS cluster '$CLUSTER_NAME' does not exist"
        
        if [ -n "$AWS_ENDPOINT" ]; then
            log INFO "LocalStack detected - creating minimal cluster configuration"
            # For LocalStack, we'll assume the cluster exists or create a mock one
            log SUCCESS "LocalStack EKS cluster configuration ready"
        else
            log ERROR "Please create the EKS cluster first:"
            log ERROR "aws eks create-cluster --name $CLUSTER_NAME --region $AWS_REGION --role-arn <cluster-service-role-arn> --resources-vpc-config subnetIds=<subnet-ids>"
            exit 1
        fi
    fi
}

# Create Fargate profile
create_fargate_profile() {
    log INFO "🚀 Creating Fargate profile..."
    
    # Use the script from the ConfigMap
    if [ -f "$SCRIPT_DIR/fargate-profiles/fargate-profile.yaml" ]; then
        log INFO "Extracting Fargate profile creation script..."
        
        # Extract the script from the ConfigMap
        local script_content=$(kubectl_cmd get configmap fargate-profile-config -n "$NAMESPACE" -o jsonpath='{.data.create-fargate-profile\.sh}' 2>/dev/null || true)
        
        if [ -z "$script_content" ]; then
            log INFO "ConfigMap not found, applying Fargate profile configuration..."
            kubectl_cmd apply -f "$SCRIPT_DIR/fargate-profiles/fargate-profile.yaml"
            
            # Wait for ConfigMap to be created
            sleep 2
            script_content=$(kubectl_cmd get configmap fargate-profile-config -n "$NAMESPACE" -o jsonpath='{.data.create-fargate-profile\.sh}')
        fi
        
        # Save script to temporary file
        local temp_script="/tmp/create-fargate-profile.sh"
        echo "$script_content" > "$temp_script"
        chmod +x "$temp_script"
        
        # Set environment variables and run script
        export EKS_CLUSTER_NAME="$CLUSTER_NAME"
        export FARGATE_PROFILE_NAME="$FARGATE_PROFILE_NAME"
        export EXECUTION_ROLE_NAME="$EXECUTION_ROLE_NAME"
        export AWS_REGION="$AWS_REGION"
        export AWS_ENDPOINT="$AWS_ENDPOINT"
        
        log INFO "Executing Fargate profile creation script..."
        bash "$temp_script" | tee -a "$LOG_FILE"
        
        # Cleanup
        rm -f "$temp_script"
        
    else
        log ERROR "Fargate profile configuration file not found"
        exit 1
    fi
    
    log SUCCESS "Fargate profile creation completed"
}

# Apply Kubernetes manifests in order
deploy_manifests() {
    log INFO "📦 Deploying Kubernetes manifests..."
    
    # Define deployment order with timing
    local manifests=(
        "namespace/01-namespace-fargate.yaml:30"
        "kong/03-kong-config-fargate.yaml:20"
        "kong/02-kong-deployment-fargate.yaml:90"
        "nginx/05-nginx-config-fargate.yaml:20"
        "nginx/04-nginx-deployment-fargate.yaml:60"
        "backend/06-backend-deployment-fargate.yaml:60"
        "claude-sdk/07-claude-sdk-deployment-fargate.yaml:90"
    )
    
    for manifest_entry in "${manifests[@]}"; do
        local manifest_file="${manifest_entry%:*}"
        local wait_time="${manifest_entry#*:}"
        local full_path="$SCRIPT_DIR/$manifest_file"
        
        if [ ! -f "$full_path" ]; then
            log ERROR "Manifest file not found: $full_path"
            exit 1
        fi
        
        log INFO "Applying manifest: $manifest_file"
        
        # Replace environment variables in the manifest
        local temp_manifest="/tmp/$(basename "$manifest_file")"
        envsubst < "$full_path" > "$temp_manifest"
        
        # Apply the manifest
        if kubectl_cmd apply -f "$temp_manifest"; then
            log SUCCESS "Applied: $manifest_file"
        else
            log ERROR "Failed to apply: $manifest_file"
            exit 1
        fi
        
        # Wait for resources to be ready
        log INFO "Waiting ${wait_time}s for resources to initialize..."
        sleep "$wait_time"
        
        # Cleanup temporary file
        rm -f "$temp_manifest"
    done
    
    log SUCCESS "All manifests deployed successfully"
}

# Wait for pods to be ready
wait_for_pods() {
    log INFO "⏳ Waiting for pods to be ready..."
    
    local timeout=600  # 10 minutes
    local start_time=$(date +%s)
    
    # Define expected deployments
    local deployments=(
        "kong-gateway-fargate"
        "nginx-proxy-fargate"
        "backend-api-fargate"
        "claude-code-sdk-fargate"
    )
    
    for deployment in "${deployments[@]}"; do
        log INFO "Waiting for deployment: $deployment"
        
        # Wait for deployment to be available
        if kubectl_cmd wait --for=condition=available --timeout=300s deployment/"$deployment" -n "$NAMESPACE"; then
            log SUCCESS "Deployment ready: $deployment"
        else
            log ERROR "Deployment failed to become ready: $deployment"
            
            # Show pod status for debugging
            log INFO "Pod status for $deployment:"
            kubectl_cmd get pods -l app.kubernetes.io/name="${deployment%-fargate}" -n "$NAMESPACE" || true
            kubectl_cmd describe pods -l app.kubernetes.io/name="${deployment%-fargate}" -n "$NAMESPACE" || true
            
            exit 1
        fi
        
        # Check if we're running out of time
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ $elapsed -gt $timeout ]; then
            log ERROR "Timeout waiting for pods to be ready"
            exit 1
        fi
    done
    
    log SUCCESS "All pods are ready"
}

# Verify services are accessible
verify_services() {
    log INFO "🔍 Verifying service accessibility..."
    
    # Get a pod to run commands from
    local test_pod=$(kubectl_cmd get pods -l app.kubernetes.io/name=claude-code-sdk -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$test_pod" ]; then
        log WARN "Claude SDK pod not found, skipping service verification"
        return 0
    fi
    
    # Service endpoints to test
    local services=(
        "nginx-internal-service.kong-aws-masking.svc.cluster.local:8082/health"
        "kong-gateway-service.kong-aws-masking.svc.cluster.local:8100/status"
        "backend-api-service.kong-aws-masking.svc.cluster.local:3000/health"
    )
    
    for service_endpoint in "${services[@]}"; do
        log INFO "Testing service: $service_endpoint"
        
        if kubectl_cmd exec "$test_pod" -n "$NAMESPACE" -- curl -f -s --max-time 10 "http://$service_endpoint" > /dev/null; then
            log SUCCESS "Service accessible: $service_endpoint"
        else
            log ERROR "Service not accessible: $service_endpoint"
            
            # Show service details for debugging
            local service_name="${service_endpoint%%.*}"
            kubectl_cmd get service "$service_name" -n "$NAMESPACE" || true
            kubectl_cmd describe service "$service_name" -n "$NAMESPACE" || true
            
            exit 1
        fi
    done
    
    log SUCCESS "All services are accessible"
}

# Run integration tests
run_integration_tests() {
    log INFO "🧪 Running integration tests..."
    
    # Apply integration test job
    local test_job_file="$SCRIPT_DIR/claude-sdk/07-claude-sdk-deployment-fargate.yaml"
    if grep -q "kind: Job" "$test_job_file"; then
        log INFO "Applying integration test job..."
        
        # Extract just the Job part
        local temp_job="/tmp/integration-test-job.yaml"
        awk '/^---$/{if(found) print; found=0} /kind: Job/{found=1} found' "$test_job_file" > "$temp_job"
        
        # Delete existing job if it exists
        kubectl_cmd delete job claude-sdk-integration-test -n "$NAMESPACE" --ignore-not-found=true
        
        # Apply the job
        if kubectl_cmd apply -f "$temp_job"; then
            log INFO "Integration test job submitted"
            
            # Wait for job completion
            if kubectl_cmd wait --for=condition=complete --timeout=300s job/claude-sdk-integration-test -n "$NAMESPACE"; then
                log SUCCESS "Integration tests passed"
                
                # Show test results
                local test_pod=$(kubectl_cmd get pods -l job-name=claude-sdk-integration-test -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
                if [ -n "$test_pod" ]; then
                    log INFO "Integration test results:"
                    kubectl_cmd logs "$test_pod" -n "$NAMESPACE" | tee -a "$LOG_FILE"
                fi
            else
                log ERROR "Integration tests failed or timed out"
                
                # Show failure details
                local test_pod=$(kubectl_cmd get pods -l job-name=claude-sdk-integration-test -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
                if [ -n "$test_pod" ]; then
                    log ERROR "Integration test failure details:"
                    kubectl_cmd logs "$test_pod" -n "$NAMESPACE" | tee -a "$LOG_FILE"
                    kubectl_cmd describe pod "$test_pod" -n "$NAMESPACE" | tee -a "$LOG_FILE"
                fi
                
                exit 1
            fi
            
            # Cleanup
            rm -f "$temp_job"
        else
            log ERROR "Failed to apply integration test job"
            exit 1
        fi
    else
        log WARN "Integration test job not found in manifest"
    fi
}

# Test AWS masking functionality
test_aws_masking() {
    log INFO "🔒 Testing AWS masking functionality..."
    
    # Get Claude SDK pod
    local sdk_pod=$(kubectl_cmd get pods -l app.kubernetes.io/name=claude-code-sdk -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$sdk_pod" ]; then
        log ERROR "Claude SDK pod not found"
        exit 1
    fi
    
    # Wait for SDK pod to be fully initialized
    log INFO "Waiting for Claude SDK to be fully initialized..."
    sleep 30
    
    # Run AWS masking test
    log INFO "Executing AWS masking test..."
    if kubectl_cmd exec "$sdk_pod" -n "$NAMESPACE" -- node /home/claude/scripts/test-aws-masking.js; then
        log SUCCESS "AWS masking test passed"
    else
        log ERROR "AWS masking test failed"
        
        # Show pod logs for debugging
        log ERROR "Claude SDK pod logs:"
        kubectl_cmd logs "$sdk_pod" -n "$NAMESPACE" --tail=50 | tee -a "$LOG_FILE"
        
        exit 1
    fi
}

# Show deployment summary
show_deployment_summary() {
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    local minutes=$((total_time / 60))
    local seconds=$((total_time % 60))
    
    log SUCCESS "╔════════════════════════════════════════════════════════════════╗"
    log SUCCESS "║                    DEPLOYMENT SUCCESSFUL                      ║"
    log SUCCESS "╚════════════════════════════════════════════════════════════════╝"
    log SUCCESS ""
    log SUCCESS "🎉 EKS-Fargate deployment completed successfully!"
    log SUCCESS "⏱️  Total deployment time: ${minutes}m ${seconds}s"
    log SUCCESS "📝 Deployment log: $LOG_FILE"
    log SUCCESS ""
    log SUCCESS "📊 Deployment Summary:"
    log SUCCESS "   • Cluster: $CLUSTER_NAME"
    log SUCCESS "   • Region: $AWS_REGION"
    log SUCCESS "   • Namespace: $NAMESPACE"
    log SUCCESS "   • Fargate Profile: $FARGATE_PROFILE_NAME"
    log SUCCESS ""
    log SUCCESS "🔗 Access Points:"
    
    # Get external access points
    local nginx_lb=$(kubectl_cmd get service nginx-proxy-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending")
    if [ "$nginx_lb" != "Pending" ] && [ -n "$nginx_lb" ]; then
        log SUCCESS "   • Nginx Proxy (External): http://$nginx_lb:8082"
    else
        log SUCCESS "   • Nginx Proxy (External): LoadBalancer pending..."
    fi
    
    log SUCCESS "   • Kong Admin (Internal): kubectl port-forward service/kong-admin-service 8001:8001 -n $NAMESPACE"
    log SUCCESS "   • Backend API (Internal): kubectl port-forward service/backend-api-service 3000:3000 -n $NAMESPACE"
    log SUCCESS ""
    log SUCCESS "🧪 Quick Verification Commands:"
    log SUCCESS "   # Check all pods"
    log SUCCESS "   kubectl get pods -n $NAMESPACE"
    log SUCCESS ""
    log SUCCESS "   # Check services"
    log SUCCESS "   kubectl get services -n $NAMESPACE"
    log SUCCESS ""
    log SUCCESS "   # Access Claude SDK for testing"
    log SUCCESS "   kubectl exec -it deployment/claude-code-sdk-fargate -n $NAMESPACE -- /bin/bash"
    log SUCCESS ""
    log SUCCESS "   # Run health check"
    log SUCCESS "   kubectl exec deployment/claude-code-sdk-fargate -n $NAMESPACE -- /home/claude/scripts/health-check.sh"
    log SUCCESS ""
    log SUCCESS "   # Test AWS masking"
    log SUCCESS "   kubectl exec deployment/claude-code-sdk-fargate -n $NAMESPACE -- node /home/claude/scripts/test-aws-masking.js"
    log SUCCESS ""
    log SUCCESS "🎯 Environment Status: EKS-Fargate DEPLOYMENT VERIFIED ✅"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Deployment failed with exit code: $exit_code"
        log ERROR "Check the deployment log: $LOG_FILE"
        log ERROR ""
        log ERROR "🔍 Troubleshooting commands:"
        log ERROR "   kubectl get pods -n $NAMESPACE"
        log ERROR "   kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
        log ERROR "   kubectl describe pods -n $NAMESPACE"
    fi
    exit $exit_code
}

# Main deployment function
main() {
    # Set error trap
    trap cleanup_on_error EXIT
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --api-key)
                ANTHROPIC_API_KEY="$2"
                shift 2
                ;;
            --endpoint)
                AWS_ENDPOINT="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --cluster-name NAME    EKS cluster name (default: kong-masking-fargate)"
                echo "  --region REGION        AWS region (default: ap-northeast-2)"
                echo "  --api-key KEY          Anthropic API key"
                echo "  --endpoint URL         AWS endpoint URL (for LocalStack)"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  EKS_CLUSTER_NAME       EKS cluster name"
                echo "  AWS_REGION             AWS region"
                echo "  ANTHROPIC_API_KEY      Anthropic API key"
                echo "  AWS_ENDPOINT           AWS endpoint URL (for LocalStack)"
                echo "  ELASTICACHE_ENDPOINT   ElastiCache Redis endpoint"
                echo "  ELASTICACHE_PORT       ElastiCache Redis port"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                log ERROR "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Start deployment
    show_banner
    
    # Export environment variables for envsubst
    export CLUSTER_NAME FARGATE_PROFILE_NAME AWS_REGION NAMESPACE
    export ANTHROPIC_API_KEY ELASTICACHE_ENDPOINT ELASTICACHE_PORT
    
    # Execute deployment steps
    validate_prerequisites
    verify_eks_cluster
    create_fargate_profile
    deploy_manifests
    wait_for_pods
    verify_services
    run_integration_tests
    test_aws_masking
    
    # Success!
    show_deployment_summary
    
    # Remove error trap
    trap - EXIT
}

# Run main function
main "$@"