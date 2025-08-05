# Kong AWS Masking Enterprise 2 - Environment Setup Guide

**Version**: v2.0.0  
**Last Updated**: August 5, 2025  
**Project**: nginx-kong-claude-enterprise2  
**Status**: All 4 environments completed and verified ✅  

## 🎯 **Environment Selection Matrix**

Choose the deployment environment that best fits your requirements:

| Environment | Best For | Complexity | Cost | Management | Scalability | Status |
|-------------|----------|------------|------|------------|-------------|--------|
| **[EC2](./ec2/)** | Quick POC, Development | ⭐ Low | 💰 Low | Manual | Limited | ✅ **Ready** |
| **[EKS-EC2](./eks-ec2/)** | Production K8s | ⭐⭐⭐ High | 💰💰 Medium | K8s | High | ✅ **Ready** |
| **[EKS-Fargate](./eks-fargate/)** | Serverless K8s | ⭐⭐⭐⭐ Very High | 💰💰💰 High | Managed | Auto | ✅ **Ready** |
| **[ECS-Fargate](./ecs-fargate/)** | Serverless Containers | ⭐⭐ Medium | 💰💰 Medium | Managed | High | ✅ **Ready** |

## 📋 **Quick Decision Guide**

### **🚀 I want to get started quickly (5-10 minutes)**
→ **[EC2 Environment](./ec2/README.md)**
- Docker Compose deployment
- Single EC2 instance
- Automated user data script
- Perfect for development and testing

### **🏗️ I need production Kubernetes with full control**
→ **[EKS-EC2 Environment](./eks-ec2/README.md)**
- Full Kubernetes cluster
- EC2 worker nodes
- ElastiCache Redis integration
- Comprehensive monitoring and scaling

### **☁️ I want serverless Kubernetes (no infrastructure management)**
→ **[EKS-Fargate Environment](./eks-fargate/README.md)**
- AWS Fargate serverless compute
- No EC2 instances to manage
- Automatic scaling and patching
- Advanced security contexts

### **🐳 I prefer container services over Kubernetes**
→ **[ECS-Fargate Environment](./ecs-fargate/README.md)**
- ECS service with Fargate launch type
- Simpler than Kubernetes
- AWS-native container orchestration
- Good balance of simplicity and power

## 🏛️ **Architecture Comparison**

### **Core Components (All Environments)**
All environments include these components:
- **Kong Gateway** with aws-masker plugin
- **Nginx Proxy** for high-performance HTTP handling
- **Backend API** (Node.js) for business logic
- **Redis** for masking data persistence
- **Claude Code SDK** for interactive testing

### **Environment-Specific Architecture**

#### **EC2 Environment**
```
[Claude Code SDK] → [Nginx:8082] → [Kong:8000] → [Claude API]
                         ↑              ↑
                    [Backend:3000]  [Redis:6379]
        
        ALL RUNNING ON SINGLE EC2 INSTANCE
```

#### **EKS-EC2 Environment**
```
[Load Balancer] → [Nginx Pods] → [Kong Pods] → [Claude API]
                       ↑             ↑
                  [Backend Pods]  [ElastiCache Redis]
        
        KUBERNETES CLUSTER WITH EC2 WORKER NODES
```

#### **EKS-Fargate Environment**
```
[NLB] → [Nginx Fargate] → [Kong Fargate] → [Claude API]
              ↑                ↑
        [Backend Fargate]  [ElastiCache Redis]
        
        SERVERLESS KUBERNETES WITH AWS FARGATE
```

#### **ECS-Fargate Environment**
```
[ALB] → [Nginx Task] → [Kong Task] → [Claude API]
             ↑             ↑
       [Backend Task]  [ElastiCache Redis]
        
        ECS SERVICE WITH FARGATE LAUNCH TYPE
```

## 📊 **Feature Comparison Matrix**

| Feature | EC2 | EKS-EC2 | EKS-Fargate | ECS-Fargate |
|---------|-----|---------|-------------|-------------|
| **Setup Time** | 8-12 min | 20-30 min | 25-35 min | 15-25 min |
| **Infrastructure Management** | Manual | K8s | AWS Managed | AWS Managed |
| **Auto Scaling** | Manual | HPA | HPA + Fargate | ECS Auto Scaling |
| **High Availability** | Single AZ | Multi-AZ | Multi-AZ | Multi-AZ |
| **Cost Optimization** | Manual | K8s Resources | Fargate Pricing | Fargate Pricing |
| **Security** | EC2 + SG | K8s RBAC | Fargate + K8s | ECS + IAM |
| **Monitoring** | Basic | Prometheus | CloudWatch | CloudWatch |
| **Deployment** | Docker Compose | Kubernetes | Kubernetes | ECS |

## 🛠️ **Environment-Specific Setup Instructions**

### **EC2 Environment**
```bash
cd setup-environment/ec2/
./scripts/deploy-ec2.sh
```
- **Time**: 8-12 minutes
- **Requirements**: AWS CLI, valid EC2 key pair
- **Best for**: Development, POC, quick testing

### **EKS-EC2 Environment**
```bash
cd setup-environment/eks-ec2/
./scripts/deploy-eks-ec2.sh
```
- **Time**: 20-30 minutes
- **Requirements**: kubectl, eksctl, ElastiCache cluster
- **Best for**: Production Kubernetes workloads

### **EKS-Fargate Environment**
```bash
cd setup-environment/eks-fargate/
./manifests/deploy-fargate.sh
```
- **Time**: 25-35 minutes
- **Requirements**: EKS cluster, Fargate profiles, ElastiCache
- **Best for**: Serverless Kubernetes, zero infrastructure management

### **ECS-Fargate Environment**
```bash
cd setup-environment/ecs-fargate/
./manifests/deploy-ecs-fargate.sh
```
- **Time**: 15-25 minutes
- **Requirements**: ECS cluster, task definitions, ElastiCache
- **Best for**: Container orchestration without Kubernetes complexity

## 🧪 **Testing Strategy per Environment**

### **Common Test Categories**
All environments support these test types:
- **Core Tests**: End-to-end functionality
- **Component Tests**: Individual service testing
- **Pattern Tests**: AWS masking pattern validation
- **Performance Tests**: Load and response time testing

### **Environment-Specific Testing**

#### **EC2 Environment Testing**
```bash
cd setup-environment/ec2/tests/
./performance/quick-core-validation.sh
./phase2/ec2-actual-deployment-test.sh
```

#### **EKS Environments Testing** (EC2 & Fargate)
```bash
cd setup-environment/eks-*/tests/
./core/e2e-comprehensive-test.sh
./patterns/50-patterns-complete-test.sh
./elasticache/elasticache-comprehensive-test.sh
```

#### **ECS-Fargate Environment Testing**
```bash
cd setup-environment/ecs-fargate/tests/
./test-ecs-fargate-integration.sh
```

## 📚 **Environment Documentation**

Each environment has comprehensive documentation:

### **📖 Complete Setup Guides**
- **[EC2 Environment Guide](./ec2/README.md)** - Docker Compose deployment with user data automation
- **[EKS-EC2 Environment Guide](./eks-ec2/README.md)** - Kubernetes cluster with EC2 worker nodes
- **[EKS-Fargate Environment Guide](./eks-fargate/README.md)** - Serverless Kubernetes with Fargate compute
- **[ECS-Fargate Environment Guide](./ecs-fargate/README.md)** - ECS service with Fargate launch type

### **🔧 Configuration Guides**
Each environment directory contains:
- `manifests/` - Deployment configurations
- `scripts/` - Automation scripts
- `tests/` - Environment-specific test suites
- `docs/` - Detailed setup and troubleshooting guides
- `configs/` - Environment-specific configuration files

## 🎯 **Production Recommendations**

### **Development & Testing**
**Recommended**: EC2 Environment
- Fastest setup and iteration
- Lower costs for development workloads
- Easy debugging and log access

### **Production (Cost-Conscious)**
**Recommended**: EKS-EC2 Environment
- Full control over infrastructure
- Predictable EC2 pricing
- Comprehensive monitoring and scaling

### **Production (Fully Managed)**
**Recommended**: EKS-Fargate Environment
- Zero infrastructure management
- Automatic scaling and patching
- Enhanced security with Fargate

### **Production (Container-Focused)**
**Recommended**: ECS-Fargate Environment
- AWS-native container orchestration
- Simpler than Kubernetes
- Good balance of features and complexity

## 🚨 **Critical Requirements (All Environments)**

### **Prerequisites**
- **ANTHROPIC_API_KEY**: Valid Claude API key
- **AWS Credentials**: Configured AWS CLI with appropriate permissions
- **Region**: Consistent AWS region across all services (default: ap-northeast-2)

### **Security Requirements**
- **No Mock Mode**: All environments require real API keys
- **Fail-Secure**: Services block requests if Redis unavailable
- **Data Masking**: AWS resources masked before external API calls
- **Network Security**: Proper VPC, security groups, and network policies

### **Performance Targets**
- **Response Time**: < 5 seconds for all operations
- **Masking Latency**: < 1ms per request
- **Throughput**: 10,000+ requests/second capability
- **Availability**: 99.9% uptime SLA

## 📞 **Support & Troubleshooting**

### **Common Issues Across Environments**
1. **API Key Issues**: Ensure valid ANTHROPIC_API_KEY is set
2. **Redis Connectivity**: Check Redis password and network access
3. **AWS Permissions**: Verify IAM roles and policies
4. **Network Configuration**: Confirm security groups and VPC settings

### **Environment-Specific Support**
- **EC2**: Check user data script execution and Docker containers
- **EKS**: Verify kubectl access and pod status
- **ECS**: Check task definitions and service status
- **Fargate**: Confirm Fargate profiles and security contexts

### **Getting Help**
1. Check environment-specific README files
2. Review test execution reports in `tests/test-report/`
3. Check logs in environment-specific log directories
4. Consult troubleshooting sections in environment guides

---

## 🎉 **Environment Status Summary**

| Environment | Status | Last Verified | Deployment Time |
|-------------|--------|---------------|-----------------|
| **EC2** | ✅ **Production Ready** | 2025-07-31 | 8-12 minutes |
| **EKS-EC2** | ✅ **Production Ready** | 2025-07-30 | 20-30 minutes |
| **EKS-Fargate** | ✅ **Production Ready** | 2025-08-05 | 25-35 minutes |
| **ECS-Fargate** | ✅ **Production Ready** | 2025-07-30 | 15-25 minutes |

**🎯 ALL FOUR DEPLOYMENT ENVIRONMENTS ARE COMPLETE AND VERIFIED!**

Choose your environment and follow the specific setup guide for detailed instructions.