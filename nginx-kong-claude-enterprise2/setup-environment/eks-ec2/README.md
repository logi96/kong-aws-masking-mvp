# EKS-EC2 Environment - Complete Setup Guide

**Environment**: EKS with EC2 Worker Nodes  
**Complexity**: ⭐⭐⭐ High  
**Best For**: Production Kubernetes, Full Infrastructure Control  
**Setup Time**: 20-30 minutes  
**Status**: ✅ **Production Ready**  

## 🏗️ **Architecture Overview**

```
[Load Balancer] → [Nginx Pods] → [Kong Pods] → [Claude API]
                       ↑             ↑
                  [Backend Pods]  [ElastiCache Redis]
        
        KUBERNETES CLUSTER WITH EC2 WORKER NODES
```

### **EKS-EC2 Benefits**
- ✅ **Full Control**: Complete infrastructure management
- ✅ **Cost Predictable**: EC2 pricing with Reserved Instances
- ✅ **High Performance**: Dedicated compute resources
- ✅ **Customizable**: Full control over worker node configuration
- ✅ **Production Ready**: Enterprise-grade Kubernetes

## 📋 **Prerequisites**

### **Required Tools**
```bash
kubectl version --client
aws --version
eksctl version
helm version
```

### **AWS Requirements**
- **EKS Cluster** with EC2 node groups
- **ElastiCache Redis** cluster
- **VPC** with public and private subnets
- **IAM Roles** for EKS cluster and worker nodes

### **Environment Variables**
```bash
export ANTHROPIC_API_KEY="sk-ant-api03-your-key-here"
export EKS_CLUSTER_NAME="kong-masking-ec2"
export AWS_REGION="ap-northeast-2"
export ELASTICACHE_ENDPOINT="your-cluster.cache.amazonaws.com"
export NODE_GROUP_NAME="kong-worker-nodes"
```

## 🚀 **Quick Deployment**

### **One-Command Deployment**
```bash
cd setup-environment/eks-ec2/
./manifests/deploy-all.sh
```

### **Manual Step-by-Step**
```bash
# 1. Deploy namespace and RBAC
kubectl apply -f manifests/namespace/

# 2. Deploy ElastiCache configuration
kubectl apply -f manifests/elasticache/

# 3. Deploy Kong Gateway
kubectl apply -f manifests/kong/

# 4. Deploy Nginx Proxy
kubectl apply -f manifests/nginx/

# 5. Deploy Backend API and Claude SDK
kubectl apply -f manifests/claude-sdk/
```

## 📁 **Directory Structure**

```
setup-environment/eks-ec2/
├── README.md                           # This comprehensive guide
├── manifests/                          # All Kubernetes manifests
│   ├── deploy-all.sh                   # Automated deployment script
│   ├── namespace/                      # Namespace and RBAC
│   │   └── 01-namespace.yaml           # Namespace + ServiceAccount
│   ├── elasticache/                    # ElastiCache configuration
│   │   ├── 02-elasticache-config.yaml  # ConfigMap for ElastiCache
│   │   └── 03-redis-deployment.yaml    # Local Redis (development)
│   ├── kong/                           # Kong Gateway
│   │   ├── 03-kong-deployment.yaml     # Kong Deployment + Service
│   │   ├── 04-kong-config.yaml         # Declarative configuration
│   │   └── 10-kong-plugin-files.yaml   # AWS masker plugin source
│   ├── nginx/                          # Nginx Proxy
│   │   ├── 05-nginx-deployment.yaml    # Nginx Deployment + Service
│   │   └── 06-nginx-config.yaml        # Nginx configuration
│   └── claude-sdk/                     # Backend API and Claude SDK
│       ├── 07-backend-deployment.yaml  # Backend API Deployment
│       ├── 08-claude-sdk-deployment.yaml # Claude SDK environment
│       └── 09-backend-source.yaml      # Backend source code
├── tests/                              # Environment-specific tests
│   ├── core/                           # Core integration tests
│   ├── components/                     # Component-specific tests
│   ├── patterns/                       # AWS pattern validation
│   ├── performance/                    # Performance benchmarks
│   └── elasticache/                    # ElastiCache integration tests
├── scripts/                            # Automation scripts
├── docs/                               # Additional documentation
└── configs/                            # Configuration files
```

## 🔧 **Detailed Setup Process**

### **Step 1: Create EKS Cluster**
```bash
# Create EKS cluster with eksctl
eksctl create cluster \
  --name $EKS_CLUSTER_NAME \
  --region $AWS_REGION \
  --nodegroup-name $NODE_GROUP_NAME \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed

# Update kubeconfig
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
```

### **Step 2: Create ElastiCache Cluster**
```bash
# Create ElastiCache Redis cluster
aws elasticache create-cache-cluster \
  --cache-cluster-id kong-redis-cluster \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 \
  --subnet-group-name default \
  --security-group-ids sg-xxxxxxxxx
```

### **Step 3: Deploy Application**
```bash
cd manifests/
./deploy-all.sh

# Monitor deployment
watch kubectl get pods -n kong-aws-masking
```

## 🧪 **Testing & Validation**

### **Comprehensive Testing**
```bash
cd tests/

# Core functionality
./core/e2e-comprehensive-test.sh
./core/proxy-integration-test.sh

# AWS pattern validation
./patterns/50-patterns-complete-test.sh

# ElastiCache integration
./elasticache/elasticache-comprehensive-test.sh

# Performance testing
./performance/performance-benchmark.sh
```

### **Manual Validation**
```bash
# Check pod status
kubectl get pods -n kong-aws-masking

# Test services
kubectl port-forward service/nginx-proxy-service 8082:8082 -n kong-aws-masking &
curl http://localhost:8082/health

# Access Claude SDK
kubectl exec -it deployment/claude-code-sdk -n kong-aws-masking -- /bin/bash
```

## ⚡ **Auto-scaling Configuration**

### **Cluster Autoscaler**
```bash
# Install cluster autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Configure for your cluster
kubectl patch deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"cluster-autoscaler","command":["./cluster-autoscaler","--v=4","--stderrthreshold=info","--cloud-provider=aws","--skip-nodes-with-local-storage=false","--expander=least-waste","--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/'$EKS_CLUSTER_NAME'"]}]}}}}'
```

### **Horizontal Pod Autoscaler**
```bash
# Kong Gateway HPA
kubectl autoscale deployment kong-gateway \
  --cpu-percent=70 \
  --min=2 \
  --max=8 \
  -n kong-aws-masking

# Nginx Proxy HPA
kubectl autoscale deployment nginx-proxy \
  --cpu-percent=70 \
  --min=2 \
  --max=6 \
  -n kong-aws-masking
```

## 📊 **Monitoring & Observability**

### **Prometheus and Grafana**
```bash
# Install Prometheus using Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Access Grafana
kubectl port-forward service/prometheus-grafana 3000:80 -n monitoring
```

### **CloudWatch Container Insights**
```bash
# Install CloudWatch agent
curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml | sed "s/{{cluster_name}}/$EKS_CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/" | kubectl apply -f -
```

## 🚨 **Troubleshooting**

### **Common Issues**

#### **Node Group Issues**
```bash
# Check node status
kubectl get nodes
kubectl describe nodes

# Check node group
aws eks describe-nodegroup \
  --cluster-name $EKS_CLUSTER_NAME \
  --nodegroup-name $NODE_GROUP_NAME
```

#### **ElastiCache Connectivity**
```bash
# Test ElastiCache from pod
kubectl exec -it deployment/kong-gateway -n kong-aws-masking -- \
  curl -v telnet://$ELASTICACHE_ENDPOINT:6379
```

#### **Ingress Issues**
```bash
# Check ingress controller
kubectl get pods -n kube-system | grep aws-load-balancer

# Check ingress resources
kubectl get ingress -n kong-aws-masking
kubectl describe ingress nginx-proxy-ingress -n kong-aws-masking
```

## 🎯 **Production Checklist**

### **Pre-deployment**
- [ ] EKS cluster created with appropriate node groups
- [ ] ElastiCache Redis cluster provisioned
- [ ] VPC and security groups configured
- [ ] IAM roles and policies in place
- [ ] SSL certificates ready for HTTPS

### **Performance Validation**
- [ ] Node instances sized appropriately
- [ ] HPA and cluster autoscaler configured
- [ ] Resource requests and limits set
- [ ] ElastiCache performance tested

### **Monitoring Setup**
- [ ] Prometheus and Grafana deployed
- [ ] CloudWatch Container Insights enabled
- [ ] Log aggregation configured
- [ ] Alert rules defined

## 📞 **Support**

### **Quick Commands Reference**
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Scale deployments
kubectl scale deployment kong-gateway --replicas=5 -n kong-aws-masking

# Access services
kubectl port-forward service/SERVICE-NAME PORT:PORT -n kong-aws-masking

# Check logs
kubectl logs -f deployment/SERVICE-NAME -n kong-aws-masking
```

---

## 🎉 **Environment Status**

**Status**: ✅ **Production Ready**  
**Last Verified**: July 30, 2025  
**Deployment Target**: EKS with EC2 Worker Nodes + ElastiCache Redis  

**🎯 EKS-EC2 ENVIRONMENT - PRODUCTION KUBERNETES READY!**