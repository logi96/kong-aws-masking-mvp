# Kong AWS Masking Enterprise - Kubernetes Manifests

**Version**: v2.0.0-elasticache  
**Target Platform**: EKS (Elastic Kubernetes Service)  
**Integration**: ElastiCache Redis  
**Architecture**: Kong Gateway + Nginx Proxy + Backend API + Claude Code SDK

## 🏗️ **Architecture Overview**

```
[Claude Code SDK] → [Nginx Proxy] → [Kong Gateway] → [Claude API]
                         ↑               ↑
                    [Backend API]   [ElastiCache Redis]
                                        (AWS Managed)
```

### **Component Flow**
1. **Claude Code SDK** sends requests to Nginx Proxy (port 8082)
2. **Nginx Proxy** forwards to Kong Gateway (port 8000) 
3. **Kong Gateway** applies AWS masking via ElastiCache plugin
4. **ElastiCache Redis** stores/retrieves masking mappings
5. **Kong Gateway** forwards masked requests to Claude API
6. **Response unmasking** occurs in reverse order

## 📁 **Directory Structure**

```
k8s-manifests/
├── 📄 README.md                    # This comprehensive guide
├── 🚀 deploy-all.sh               # Complete deployment script
├── 📁 namespace/                   # Kubernetes namespace and RBAC
│   └── 01-namespace.yaml          # Namespace, ResourceQuota, NetworkPolicy
├── 📁 elasticache/                 # ElastiCache configuration
│   └── 02-elasticache-config.yaml # ConfigMap, Secret, Plugin config
├── 📁 kong/                        # Kong Gateway deployment
│   ├── 03-kong-deployment.yaml    # Kong Deployment, Service, HPA
│   └── 04-kong-config.yaml        # Declarative config, Plugin files
├── 📁 nginx/                       # Nginx Proxy deployment
│   ├── 05-nginx-deployment.yaml   # Nginx Deployment, Service, HPA
│   └── 06-nginx-config.yaml       # Nginx configuration files
└── 📁 claude-sdk/                  # Backend and SDK deployment
    ├── 07-backend-deployment.yaml  # Backend API Deployment, Service, HPA
    ├── 08-claude-sdk-deployment.yaml # Claude SDK Deployment, Test Job
    └── 09-backend-source.yaml      # Backend source code ConfigMap
```

## 🚀 **Quick Deployment**

### **Prerequisites**
- EKS cluster with kubectl access
- ElastiCache Redis cluster (or LocalStack for testing)
- Environment variables configured

### **Environment Setup**
```bash
# Required environment variables
export ANTHROPIC_API_KEY="sk-ant-api03-your-key-here"
export ELASTICACHE_ENDPOINT="your-cluster.cache.amazonaws.com"

# Optional (with defaults)
export ELASTICACHE_PORT="6379"
export AWS_REGION="ap-northeast-2"
```

### **One-Command Deployment**
```bash
# Full deployment
./deploy-all.sh deploy

# Verify deployment
./deploy-all.sh verify

# Check status
./deploy-all.sh status

# Cleanup
./deploy-all.sh cleanup
```

## 📋 **Component Details**

### **1. Namespace (01-namespace.yaml)**
- **Namespace**: `kong-aws-masking`
- **ResourceQuota**: CPU/Memory limits for the namespace
- **NetworkPolicy**: Security policies for pod communication
- **Labels**: Environment and version tagging

**Key Features:**
- Resource isolation with quotas (4 CPU, 8Gi memory requests)
- Network security with ingress/egress rules
- Production-ready namespace configuration

### **2. ElastiCache Configuration (02-elasticache-config.yaml)**
- **ConfigMap**: ElastiCache connection settings
- **Secret**: API keys and authentication tokens
- **Plugin Config**: Kong plugin configuration template

**Configuration Values:**
```yaml
ELASTICACHE_ENDPOINT: "your-cluster.cache.amazonaws.com"
ELASTICACHE_PORT: "6379"
ELASTICACHE_SSL_ENABLED: "true"
CONNECTION_POOL_SIZE: "100"
MAPPING_TTL: "604800"  # 7 days
```

### **3. Kong Gateway (03-kong-deployment.yaml, 04-kong-config.yaml)**
- **Deployment**: 2 replicas with rolling updates
- **Service**: ClusterIP for internal communication
- **HPA**: Auto-scaling based on CPU/memory usage
- **Plugin Integration**: AWS Masker ElastiCache Edition v2.0.0

**Key Features:**
- DB-less mode with declarative configuration
- ElastiCache plugin with SSL/TLS support
- Health probes and monitoring integration
- Resource limits and security context

**Plugin Configuration:**
```yaml
plugins:
  - name: aws-masker-elasticache
    config:
      elasticache_endpoint: "${ELASTICACHE_ENDPOINT}"
      mask_ec2_instances: true
      mask_s3_buckets: true
      anthropic_api_key: "${ANTHROPIC_API_KEY}"
      fail_secure: true
```

### **4. Nginx Proxy (05-nginx-deployment.yaml, 06-nginx-config.yaml)**
- **Deployment**: 2 replicas with anti-affinity
- **LoadBalancer Service**: External access via AWS ELB
- **Configuration**: High-performance proxy with security headers
- **Monitoring**: Prometheus metrics via sidecar

**Key Features:**
- Rate limiting and connection limiting
- SSL termination ready (future enhancement)
- Health monitoring with nginx-exporter
- Security headers and access control

**Endpoints:**
- `/health` - Health check endpoint
- `/v1/` - Claude API proxy (main endpoint) 
- `/kong-admin/` - Kong admin proxy (internal)
- `/nginx_status` - Nginx metrics (monitoring)

### **5. Backend API (07-backend-deployment.yaml, 09-backend-source.yaml)**
- **Deployment**: 2 replicas with rolling updates
- **Source Code**: Embedded in ConfigMap for container deployment
- **Node.js App**: Express server with health endpoints
- **Integration**: Proxy-aware configuration

**API Endpoints:**
- `GET /health` - Health check with feature status
- `GET /status` - Service configuration details
- `POST /analyze` - AWS resource analysis endpoint
- `GET /test-proxy` - Proxy configuration testing
- `GET /metrics` - Basic application metrics

### **6. Claude Code SDK (08-claude-sdk-deployment.yaml)**
- **Interactive Container**: Node.js with Claude SDK
- **Proxy Integration**: All requests routed through Nginx
- **Test Scripts**: Automated AWS masking validation
- **Persistent Logs**: Mounted volume for test results

**Usage:**
```bash
# Interactive access
kubectl exec -it -n kong-aws-masking deployment/claude-code-sdk -- /bin/bash

# Run AWS masking test
kubectl exec -n kong-aws-masking deployment/claude-code-sdk -- /home/claude/scripts/test-aws-masking.js

# Check health
kubectl exec -n kong-aws-masking deployment/claude-code-sdk -- /home/claude/scripts/health-check.sh
```

## 🔧 **Configuration Management**

### **Environment Variables**
The deployment script automatically processes these environment variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | ✅ | - | Claude API key |
| `ELASTICACHE_ENDPOINT` | ⚠️ | localhost.localstack.cloud | ElastiCache endpoint |
| `ELASTICACHE_PORT` | ❌ | 6379 | ElastiCache port |
| `AWS_REGION` | ❌ | ap-northeast-2 | AWS region |

### **ConfigMap Updates**
```bash
# Update ElastiCache endpoint
kubectl patch configmap elasticache-config -n kong-aws-masking --patch '{"data":{"ELASTICACHE_ENDPOINT":"new-endpoint.cache.amazonaws.com"}}'

# Restart Kong to apply changes
kubectl rollout restart deployment/kong-gateway -n kong-aws-masking
```

### **Secret Management**
```bash
# Update API key
kubectl patch secret kong-plugin-config -n kong-aws-masking --patch '{"data":{"anthropic-api-key":"'$(echo -n "new-api-key" | base64)'"}}'

# Restart all components
kubectl rollout restart deployment -n kong-aws-masking
```

## 📊 **Monitoring and Observability**

### **Health Checks**
```bash
# Check all pod status
kubectl get pods -n kong-aws-masking

# Service health checks
kubectl exec -n kong-aws-masking deployment/kong-gateway -- curl -s http://localhost:8100/status
kubectl exec -n kong-aws-masking deployment/nginx-proxy -- curl -s http://localhost:8082/health
kubectl exec -n kong-aws-masking deployment/backend-api -- curl -s http://localhost:3000/health
```

### **Logs and Debugging**
```bash
# View Kong Gateway logs
kubectl logs -f -n kong-aws-masking deployment/kong-gateway

# View Nginx access logs
kubectl logs -f -n kong-aws-masking deployment/nginx-proxy

# View Backend API logs  
kubectl logs -f -n kong-aws-masking deployment/backend-api

# View Claude SDK logs
kubectl logs -f -n kong-aws-masking deployment/claude-code-sdk
```

### **Metrics Collection**
- **Kong**: Admin API metrics at `/metrics`
- **Nginx**: Prometheus exporter sidecar on port 9113
- **Backend**: Basic metrics at `/metrics` endpoint
- **Kubernetes**: Built-in resource metrics via HPA

## 🔒 **Security Features**

### **Network Security**
- **NetworkPolicy**: Restricts pod-to-pod communication
- **Service mesh ready**: Compatible with Istio service mesh
- **Internal services**: Admin APIs only accessible within cluster
- **LoadBalancer**: External access only via Nginx proxy

### **Container Security**
- **Non-root containers**: All containers run as non-root user
- **Read-only root filesystem**: Where possible for security
- **Security context**: Capabilities dropped, privilege escalation disabled
- **Resource limits**: CPU and memory limits enforced

### **Data Security**
- **ElastiCache SSL/TLS**: Production-ready encryption
- **Secret management**: Kubernetes secrets with base64 encoding
- **Fail-secure mode**: Kong blocks requests if ElastiCache unavailable
- **Network encryption**: Internal TLS between services (configurable)

## ⚡ **Performance Optimization**

### **Auto-scaling**
- **Kong Gateway**: 2-10 replicas based on CPU/memory usage
- **Nginx Proxy**: 2-8 replicas with optimized scaling policies
- **Backend API**: 2-6 replicas with performance-based scaling
- **ElastiCache**: AWS managed scaling and multi-AZ deployment

### **Resource Allocation**
```yaml
# Kong Gateway
requests: { memory: "512Mi", cpu: "250m" }
limits: { memory: "2Gi", cpu: "1" }

# Nginx Proxy  
requests: { memory: "128Mi", cpu: "100m" }
limits: { memory: "512Mi", cpu: "500m" }

# Backend API
requests: { memory: "256Mi", cpu: "200m" }
limits: { memory: "1Gi", cpu: "1" }
```

### **Connection Optimization**
- **Kong**: 2 worker processes, 4096 connections each
- **Nginx**: Auto worker processes, connection pooling
- **ElastiCache**: Connection pooling with 100 connections
- **HTTP/2**: Enabled for improved performance

## 🚨 **Troubleshooting**

### **Common Issues**

#### **Kong Gateway Not Starting**
```bash
# Check plugin loading
kubectl logs -n kong-aws-masking deployment/kong-gateway | grep "plugin"

# Verify ElastiCache connectivity
kubectl exec -n kong-aws-masking deployment/kong-gateway -- curl http://localhost:8100/status
```

#### **ElastiCache Connection Issues**
```bash
# Test ElastiCache connectivity
kubectl exec -n kong-aws-masking deployment/kong-gateway -- nslookup ${ELASTICACHE_ENDPOINT}

# Check configuration
kubectl get configmap elasticache-config -n kong-aws-masking -o yaml
```

#### **Service Discovery Issues**
```bash
# Check service endpoints
kubectl get endpoints -n kong-aws-masking

# Test internal communication
kubectl exec -n kong-aws-masking deployment/claude-code-sdk -- curl http://nginx-internal-service:8082/health
```

### **Debug Commands**
```bash
# Debug Kong configuration
kubectl exec -n kong-aws-masking deployment/kong-gateway -- kong config dump

# Test proxy chain
kubectl exec -n kong-aws-masking deployment/claude-code-sdk -- curl -v http://nginx-internal-service:8082/v1/messages

# Check plugin status
kubectl exec -n kong-aws-masking deployment/kong-gateway -- curl http://localhost:8001/plugins
```

## 📈 **Scaling and Performance**

### **Horizontal Scaling**
```bash
# Scale Kong Gateway
kubectl scale deployment/kong-gateway -n kong-aws-masking --replicas=5

# Scale Nginx Proxy
kubectl scale deployment/nginx-proxy -n kong-aws-masking --replicas=4

# Auto-scaling is enabled via HPA - scaling happens automatically
```

### **Performance Testing**
```bash
# Run integration test
kubectl apply -f claude-sdk/08-claude-sdk-deployment.yaml
kubectl wait --for=condition=complete job/claude-sdk-integration-test -n kong-aws-masking --timeout=120s
kubectl logs job/claude-sdk-integration-test -n kong-aws-masking
```

### **Resource Monitoring**
```bash
# Check resource usage
kubectl top pods -n kong-aws-masking
kubectl top nodes

# HPA status
kubectl get hpa -n kong-aws-masking
```

## 🔄 **Maintenance Operations**

### **Updates and Rollouts**
```bash
# Rolling update Kong Gateway
kubectl set image deployment/kong-gateway kong-gateway=kong/kong-gateway:3.10.0 -n kong-aws-masking

# Check rollout status
kubectl rollout status deployment/kong-gateway -n kong-aws-masking

# Rollback if needed
kubectl rollout undo deployment/kong-gateway -n kong-aws-masking
```

### **Configuration Updates**
```bash
# Update Kong configuration
kubectl patch configmap kong-declarative-config -n kong-aws-masking --patch-file kong-config-update.yaml

# Restart Kong to apply changes
kubectl rollout restart deployment/kong-gateway -n kong-aws-masking
```

### **Backup and Recovery**
```bash
# Backup all configurations
kubectl get all,configmaps,secrets -n kong-aws-masking -o yaml > kong-aws-masking-backup.yaml

# ElastiCache backup is handled by AWS
```

## 🎯 **Production Checklist**

### **Pre-deployment**
- [ ] EKS cluster provisioned and accessible
- [ ] ElastiCache Redis cluster created with encryption
- [ ] IAM roles and service accounts configured
- [ ] DNS and load balancer configuration ready
- [ ] SSL certificates provisioned (for HTTPS)

### **Security Review**
- [ ] NetworkPolicies reviewed and approved
- [ ] Secret management strategy implemented
- [ ] Container security contexts validated
- [ ] ElastiCache AUTH tokens configured
- [ ] SSL/TLS encryption enabled

### **Performance Validation**
- [ ] Resource limits appropriately sized
- [ ] HPA thresholds tested under load
- [ ] ElastiCache connection pooling optimized
- [ ] Kong worker processes tuned for workload

### **Monitoring Setup**
- [ ] Prometheus metrics collection configured
- [ ] Log aggregation setup (ELK/EFK stack)
- [ ] Alert rules defined for critical components
- [ ] Health check endpoints validated

## 📚 **Additional Resources**

### **Related Documentation**
- **[USER_DATA_INSTALLATION_GUIDE.md](../USER_DATA_INSTALLATION_GUIDE.md)** - EC2 installation guide
- **[Kong Plugin Documentation](../kong-elasticache/plugins/aws-masker-elasticache/)** - Plugin source code
- **[Backend API Documentation](../backend/README.md)** - Backend service details
- **[Testing Documentation](../tests/README.md)** - Test suite information

### **Kong Gateway References**
- [Kong Gateway Documentation](https://docs.konghq.com/gateway/)
- [Kong DB-less Configuration](https://docs.konghq.com/gateway/latest/production/deployment-topologies/db-less-and-declarative-config/)
- [Kong Plugin Development](https://docs.konghq.com/gateway/latest/plugin-development/)

### **Kubernetes References**
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [ElastiCache for Redis](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

---

## 📞 **Support**

For technical support and questions:
- **Documentation**: Check the comprehensive guides in `/docs/`
- **Testing**: Use the test suites in `/tests/` for validation
- **Monitoring**: Check the health dashboards and logs
- **Issues**: Review troubleshooting section above

**Deployment Version**: v2.0.0-elasticache  
**Last Updated**: $(date)  
**Deployment Target**: EKS with ElastiCache Redis