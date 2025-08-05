# ECS-Fargate Environment - Complete Setup Guide

**Environment**: ECS with AWS Fargate  
**Complexity**: ⭐⭐ Medium  
**Best For**: Serverless Containers, Balanced Simplicity and Power  
**Setup Time**: 15-25 minutes  
**Status**: ✅ **Production Ready**  

## 🏗️ **Architecture Overview**

```
[ALB] → [Nginx Task] → [Kong Task] → [Claude API]
             ↑             ↑
       [Backend Task]  [ElastiCache Redis]
        
        ECS SERVICE WITH FARGATE LAUNCH TYPE
```

### **ECS-Fargate Benefits**
- ✅ **Serverless Containers**: No infrastructure to manage
- ✅ **AWS-Native**: Integrated with AWS ecosystem
- ✅ **Simpler than Kubernetes**: Less complexity than EKS
- ✅ **Auto Scaling**: Built-in service auto scaling
- ✅ **Cost Effective**: Pay only for running tasks

## 📋 **Prerequisites**

### **Required Tools**
```bash
aws --version
jq --version
curl --version
```

### **AWS Requirements**
- **ECS Cluster** with Fargate capacity providers
- **ElastiCache Redis** cluster
- **VPC** with public and private subnets
- **Application Load Balancer** (ALB)
- **IAM Roles** for task execution and task roles

### **Environment Variables**
```bash
export ANTHROPIC_API_KEY="sk-ant-api03-your-key-here"
export ECS_CLUSTER_NAME="kong-masking-fargate"
export AWS_REGION="ap-northeast-2"
export ELASTICACHE_ENDPOINT="your-cluster.cache.amazonaws.com"
export VPC_ID="vpc-xxxxxxxxx"
export SUBNET_IDS="subnet-xxx,subnet-yyy"
```

## 🚀 **Quick Deployment**

### **One-Command Deployment**
```bash
cd setup-environment/ecs-fargate/
./manifests/deploy-ecs-fargate.sh
```

### **Manual Step-by-Step**
```bash
# 1. Create ECS cluster
aws ecs create-cluster \
  --cluster-name $ECS_CLUSTER_NAME \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE

# 2. Create task definitions
aws ecs register-task-definition --cli-input-json file://manifests/task-definition.json

# 3. Create services
aws ecs create-service --cli-input-json file://manifests/service-definition.json

# 4. Create load balancer and target groups
./scripts/create-alb.sh
```

## 📁 **Directory Structure**

```
setup-environment/ecs-fargate/
├── README.md                           # This comprehensive guide
├── manifests/                          # All ECS configurations
│   ├── deploy-ecs-fargate.sh           # Automated deployment script
│   ├── task-definition.json            # Fargate task definition
│   ├── service-definition.json         # ECS service configuration
│   ├── elasticache-cluster.json        # ElastiCache configuration
│   └── kong-plugins/                   # Kong plugin files
│       └── aws-masker/                 # AWS masker plugin source
├── scripts/                            # Automation scripts
│   ├── create-alb.sh                   # ALB creation script
│   ├── create-ecs-cluster.sh           # ECS cluster setup
│   └── health-check.sh                 # Service health validation
├── tests/                              # Environment-specific tests
│   └── test-ecs-fargate-integration.sh # ECS-Fargate integration test
├── docs/                               # Additional documentation
└── configs/                            # Configuration files
```

## 🔧 **Detailed Setup Process**

### **Step 1: Create ECS Cluster**
```bash
# Create ECS cluster with Fargate
aws ecs create-cluster \
  --cluster-name $ECS_CLUSTER_NAME \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1

# Verify cluster creation
aws ecs describe-clusters --clusters $ECS_CLUSTER_NAME
```

### **Step 2: Create ElastiCache Cluster**
```bash
# Create ElastiCache Redis cluster
aws elasticache create-cache-cluster \
  --cache-cluster-id kong-redis-ecs \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 \
  --subnet-group-name default
```

### **Step 3: Create IAM Roles**
```bash
# Create task execution role
aws iam create-role \
  --role-name ecsTaskExecutionRole-kong \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole-kong \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### **Step 4: Deploy Tasks and Services**
```bash
cd manifests/
./deploy-ecs-fargate.sh

# Monitor deployment
aws ecs describe-services \
  --cluster $ECS_CLUSTER_NAME \
  --services kong-gateway-service nginx-proxy-service backend-api-service
```

## 🧪 **Testing & Validation**

### **ECS-Specific Testing**
```bash
cd tests/
./test-ecs-fargate-integration.sh
```

### **Manual Validation**
```bash
# Check task status
aws ecs list-tasks --cluster $ECS_CLUSTER_NAME
aws ecs describe-tasks --cluster $ECS_CLUSTER_NAME --tasks TASK_ARN

# Get load balancer DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names kong-aws-masking-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Test endpoints
curl http://$ALB_DNS/health
curl -H "x-api-key: $ANTHROPIC_API_KEY" http://$ALB_DNS/v1/health
```

### **Service Health Monitoring**
```bash
# Check service health
aws ecs describe-services \
  --cluster $ECS_CLUSTER_NAME \
  --services kong-gateway-service \
  --query 'services[0].runningCount'

# View service events
aws ecs describe-services \
  --cluster $ECS_CLUSTER_NAME \
  --services kong-gateway-service \
  --query 'services[0].events'
```

## ⚡ **Auto-scaling Configuration**

### **Service Auto Scaling**
```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/$ECS_CLUSTER_NAME/kong-gateway-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 8

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/$ECS_CLUSTER_NAME/kong-gateway-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name kong-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

### **Manual Scaling**
```bash
# Scale service manually
aws ecs update-service \
  --cluster $ECS_CLUSTER_NAME \
  --service kong-gateway-service \
  --desired-count 5
```

## 📊 **Monitoring & Observability**

### **CloudWatch Integration**
```bash
# ECS services automatically send metrics to CloudWatch
# View metrics in CloudWatch console or CLI

# Get service utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=kong-gateway-service Name=ClusterName,Value=$ECS_CLUSTER_NAME \
  --start-time 2025-08-05T00:00:00Z \
  --end-time 2025-08-05T23:59:59Z \
  --period 3600 \
  --statistics Average
```

### **Application Load Balancer Metrics**
```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN

# ALB metrics available in CloudWatch
# RequestCount, TargetResponseTime, HTTPCode_Target_2XX_Count, etc.
```

### **Logging**
```bash
# ECS logs go to CloudWatch Logs automatically
# View logs in CloudWatch Logs console or CLI

# Get log events
aws logs get-log-events \
  --log-group-name /ecs/kong-gateway \
  --log-stream-name STREAM_NAME
```

## 🚨 **Troubleshooting**

### **Common Issues**

#### **Task Failed to Start**
```bash
# Check task definition
aws ecs describe-task-definition --task-definition kong-gateway:1

# Check task events
aws ecs describe-tasks \
  --cluster $ECS_CLUSTER_NAME \
  --tasks TASK_ARN \
  --query 'tasks[0].stoppedReason'

# Check CloudWatch logs
aws logs describe-log-streams \
  --log-group-name /ecs/kong-gateway
```

#### **Service Unhealthy**
```bash
# Check service health
aws ecs describe-services \
  --cluster $ECS_CLUSTER_NAME \
  --services kong-gateway-service \
  --query 'services[0].runningCount'

# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN
```

#### **ElastiCache Connectivity**
```bash
# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx

# Test connectivity from task
aws ecs execute-command \
  --cluster $ECS_CLUSTER_NAME \
  --task TASK_ARN \
  --container kong-gateway \
  --interactive \
  --command "/bin/bash"
```

### **Debug Commands**
```bash
# List all resources
aws ecs list-clusters
aws ecs list-services --cluster $ECS_CLUSTER_NAME
aws ecs list-tasks --cluster $ECS_CLUSTER_NAME

# Check capacity providers
aws ecs describe-clusters \
  --clusters $ECS_CLUSTER_NAME \
  --include CAPACITY_PROVIDERS
```

## 🔒 **Security Configuration**

### **Task Role and Execution Role**
```json
{
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskRole-kong",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole-kong"
}
```

### **Network Security**
- **VPC**: Tasks run in private subnets
- **Security Groups**: Minimal required ports
- **ALB**: Public-facing load balancer with SSL termination
- **ElastiCache**: Accessible only from ECS tasks

### **Secrets Management**
```json
{
  "secrets": [
    {
      "name": "ANTHROPIC_API_KEY",
      "valueFrom": "arn:aws:secretsmanager:region:account:secret:anthropic-api-key"
    }
  ]
}
```

## 🔄 **Maintenance Operations**

### **Updates and Rollouts**
```bash
# Update task definition
aws ecs register-task-definition --cli-input-json file://updated-task-definition.json

# Update service with new task definition
aws ecs update-service \
  --cluster $ECS_CLUSTER_NAME \
  --service kong-gateway-service \
  --task-definition kong-gateway:2

# Monitor deployment
aws ecs wait services-stable \
  --cluster $ECS_CLUSTER_NAME \
  --services kong-gateway-service
```

### **Rollback**
```bash
# Rollback to previous task definition
aws ecs update-service \
  --cluster $ECS_CLUSTER_NAME \
  --service kong-gateway-service \
  --task-definition kong-gateway:1
```

## 💰 **Cost Optimization**

### **Fargate Pricing**
- **vCPU**: $0.04048 per vCPU per hour
- **Memory**: $0.004445 per GB per hour
- **Example**: 0.5 vCPU + 1GB = ~$0.024/hour = ~$17.5/month

### **Right-sizing**
```json
{
  "cpu": "512",
  "memory": "1024",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"]
}
```

## 🎯 **Production Checklist**

### **Pre-deployment**
- [ ] ECS cluster created with Fargate capacity
- [ ] ElastiCache Redis cluster provisioned
- [ ] VPC and subnets configured
- [ ] Application Load Balancer created
- [ ] IAM roles and policies configured

### **Security Review**
- [ ] Task and execution roles have minimal permissions
- [ ] Security groups restrict access appropriately
- [ ] Secrets stored in AWS Secrets Manager
- [ ] ElastiCache encryption enabled

### **Performance Validation**
- [ ] Task definitions sized appropriately
- [ ] Auto scaling policies configured
- [ ] Load balancer health checks tuned
- [ ] ElastiCache performance tested

## 📞 **Support**

### **Quick Commands Reference**
```bash
# Check service status
aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services SERVICE_NAME

# View task logs
aws logs tail /ecs/SERVICE_NAME --follow

# Scale service
aws ecs update-service --cluster $ECS_CLUSTER_NAME --service SERVICE_NAME --desired-count N

# Execute command in task
aws ecs execute-command --cluster $ECS_CLUSTER_NAME --task TASK_ARN --container CONTAINER_NAME --interactive --command "/bin/bash"
```

---

## 🎉 **Environment Status**

**Status**: ✅ **Production Ready**  
**Last Verified**: July 30, 2025  
**Deployment Target**: ECS with Fargate Launch Type + ElastiCache Redis  

**🎯 ECS-FARGATE ENVIRONMENT - BALANCED SERVERLESS SOLUTION!**