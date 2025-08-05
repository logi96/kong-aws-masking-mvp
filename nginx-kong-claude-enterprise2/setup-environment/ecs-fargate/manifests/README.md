# Kong AWS Masker ElastiCache - ECS Fargate Edition

**🚀 Production-ready serverless Kong Gateway with AWS resource masking and ElastiCache integration**

Version: `2.0.0-elasticache-ecs`  
Launch Type: `AWS Fargate`  
ElastiCache: `Redis 7.0+ with SSL/TLS`

## 📋 Overview

Complete ECS Fargate deployment package for Kong Gateway with:
- **AWS Resource Masking**: 50+ AWS patterns (EC2, S3, RDS, VPC, IAM)
- **ElastiCache Integration**: High-performance Redis caching
- **Serverless Architecture**: No EC2 instances to manage
- **Production Security**: SSL/TLS, encryption at rest/in transit
- **Auto-scaling**: Based on CPU/memory utilization
- **Health Monitoring**: CloudWatch logs and metrics

## 🏗️ Architecture

```
[Client Request] 
        ↓
[Application Load Balancer]
        ↓
[ECS Fargate Tasks] ← → [ElastiCache Redis]
        ↓
[Claude API] (with masked AWS resources)
```

## 📁 Package Contents

```
ecs-fargate-manifests/
├── task-definition.json          # ECS Task Definition (Fargate-optimized)
├── service-definition.json       # ECS Service configuration
├── elasticache-cluster.json      # ElastiCache Redis cluster config
├── deploy-ecs-fargate.sh         # Automated deployment script
├── Dockerfile                    # Kong + Plugin custom image
├── kong-plugins/                 # AWS Masker Plugin files
│   └── aws-masker/
│       ├── handler.lua           # Main plugin logic
│       ├── schema.lua            # Configuration schema
│       ├── elasticache_client.lua # Redis client
│       └── ...                   # Additional plugin files
└── README.md                     # This file
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Docker** (for custom image builds)
3. **jq** for JSON processing
4. **LocalStack Pro** (for local development)

### 1-Click Deployment

```bash
# Navigate to deployment directory
cd ecs-fargate-manifests/

# Run automated deployment
./deploy-ecs-fargate.sh
```

### Manual Deployment Steps

#### 1. Create ECS Cluster
```bash
aws ecs create-cluster \
    --cluster-name kong-elasticache-cluster \
    --capacity-providers FARGATE FARGATE_SPOT \
    --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
```

#### 2. Create ElastiCache Cluster
```bash
aws elasticache create-cache-cluster \
    --cli-input-json file://elasticache-cluster.json
```

#### 3. Register Task Definition
```bash
aws ecs register-task-definition \
    --cli-input-json file://task-definition.json
```

#### 4. Create ECS Service
```bash
aws ecs create-service \
    --cli-input-json file://service-definition.json
```

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `ELASTICACHE_ENDPOINT` | ElastiCache Redis endpoint | - | ✅ |
| `ELASTICACHE_PORT` | Redis port | `6379` | ✅ |
| `ELASTICACHE_SSL_ENABLED` | Enable SSL/TLS | `true` | ✅ |
| `ANTHROPIC_API_KEY` | Claude API key | - | ✅ |
| `AWS_REGION` | AWS region | `us-east-1` | ✅ |
| `KONG_LOG_LEVEL` | Logging level | `info` | ❌ |

### ElastiCache Configuration

```json
{
    "CacheNodeType": "cache.t3.medium",
    "Engine": "redis",
    "EngineVersion": "7.0",
    "AtRestEncryptionEnabled": true,
    "TransitEncryptionEnabled": true,
    "AuthToken": "your-secure-token"
}
```

### Task Resources (Fargate)

| Configuration | CPU | Memory | Cost/Hour |
|---------------|-----|--------|-----------|
| **Small** | 0.25 vCPU | 0.5 GB | ~$0.01 |
| **Medium** | 0.5 vCPU | 1 GB | ~$0.02 |
| **Large** | 1 vCPU | 2 GB | ~$0.04 |
| **Production** | 2 vCPU | 4 GB | ~$0.08 |

## 🔒 Security Features

### Network Security
- **VPC Isolation**: Private subnets with NAT Gateway
- **Security Groups**: Minimal required ports (8000, 8001, 8100)
- **Service Discovery**: Internal DNS resolution

### Data Security
- **ElastiCache Encryption**: At-rest and in-transit
- **AUTH Tokens**: Redis authentication
- **IAM Roles**: Least privilege access
- **Secrets Manager**: API key management

### Application Security
- **Fail-Secure**: Block requests if masking fails
- **Pattern Validation**: 50+ AWS resource patterns
- **Request Logging**: Structured audit logs

## 📊 Monitoring & Observability

### CloudWatch Metrics
- Task CPU/Memory utilization
- Request count and latency
- Error rates and status codes
- ElastiCache hit/miss ratios

### Health Checks
```bash
# Kong Gateway status
curl http://[load-balancer]/status

# ElastiCache connectivity
redis-cli -h [elasticache-endpoint] -p 6379 ping

# Service health
aws ecs describe-services --cluster kong-elasticache-cluster
```

### Log Groups
- `/ecs/kong-aws-masker-elasticache` - Application logs
- `/aws/elasticache/kong-redis` - ElastiCache logs

## 🧪 Testing

### Local Development (LocalStack)
```bash
# Start LocalStack Pro
docker run -d \
    -p 4566:4566 \
    -e SERVICES=ecs,elasticache,iam \
    localstack/localstack-pro

# Deploy to LocalStack
AWS_ENDPOINT=http://localhost:4566 ./deploy-ecs-fargate.sh
```

### Production Testing
```bash
# Test Kong admin API
curl https://[load-balancer]:8001/status

# Test proxy functionality
curl -X POST https://[load-balancer]:8000/v1/messages \
    -H "Content-Type: application/json" \
    -d '{"content": "Analyze this EC2 instance: i-1234567890abcdef0"}'
```

## 🔄 Scaling & Performance

### Auto Scaling Configuration
```json
{
    "minCapacity": 2,
    "maxCapacity": 20,
    "targetValue": 70,
    "scaleInCooldown": 300,
    "scaleOutCooldown": 300
}
```

### Performance Tuning
- **Connection Pooling**: ElastiCache connection reuse
- **Caching Strategy**: 7-day TTL for masked resources
- **Resource Allocation**: Right-size based on traffic

## 🚨 Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check task definition
aws ecs describe-task-definition --task-definition kong-aws-masker-elasticache

# Check service events
aws ecs describe-services --cluster kong-elasticache-cluster --services kong-aws-masker-elasticache-service
```

#### ElastiCache Connection Failed
```bash
# Verify security groups
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx

# Test connectivity
redis-cli -h [endpoint] -p 6379 --tls ping
```

#### Plugin Not Loading
```bash
# Check Kong logs
aws logs tail /ecs/kong-aws-masker-elasticache --follow

# Verify plugin files
docker exec [container-id] ls -la /usr/local/share/lua/5.1/kong/plugins/aws-masker/
```

### Debug Mode
```bash
# Enable debug logging
aws ecs update-service \
    --cluster kong-elasticache-cluster \
    --service kong-aws-masker-elasticache-service \
    --task-definition kong-aws-masker-elasticache:debug
```

## 🔧 Maintenance

### Updates
```bash
# Update service with new task definition
aws ecs update-service \
    --cluster kong-elasticache-cluster \
    --service kong-aws-masker-elasticache-service \
    --task-definition kong-aws-masker-elasticache:latest
```

### Backups
- ElastiCache automatic snapshots (5 days retention)
- Task definition versioning
- Configuration as Code (Git repository)

## 📚 Additional Resources

- [Kong Plugin Development Guide](https://docs.konghq.com/gateway/latest/plugin-development/)
- [AWS ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ElastiCache Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/BestPractices.html)

## 🆘 Support

For issues and questions:
1. Check CloudWatch logs: `/ecs/kong-aws-masker-elasticache`
2. Review service health: `aws ecs describe-services`
3. Test ElastiCache: `redis-cli -h [endpoint] ping`

---

**🎯 Production Ready**: This ECS Fargate edition provides enterprise-grade AWS resource masking with serverless scalability and high availability.

**Version**: 2.0.0-elasticache-ecs  
**License**: Enterprise  
**Maintained by**: Kong AWS Masking Enterprise Team