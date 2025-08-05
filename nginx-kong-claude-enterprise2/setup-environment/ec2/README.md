# EC2 Environment - Complete Setup Guide

**Environment**: Single EC2 Instance with Docker Compose  
**Complexity**: ⭐ Low  
**Best For**: Quick POC, Development, Testing  
**Setup Time**: 8-12 minutes  
**Status**: ✅ **Production Ready**  

## 🏗️ **Architecture Overview**

```
[Claude Code SDK] → [Nginx:8082] → [Kong:8000] → [Claude API]
                         ↑              ↑
                    [Backend:3000]  [Redis:6379]
        
        ALL RUNNING ON SINGLE EC2 INSTANCE
```

### **EC2-Specific Benefits**
- ✅ **Fastest Setup**: 8-12 minutes fully automated deployment
- ✅ **Lowest Cost**: Single EC2 instance pricing
- ✅ **Simple Debugging**: Direct access to all logs and services
- ✅ **Development Friendly**: Easy iteration and testing
- ✅ **Self-Contained**: No external dependencies beyond EC2

## 📋 **Prerequisites**

### **AWS Requirements**
- **AWS CLI** configured with appropriate permissions
- **EC2 Key Pair** for SSH access
- **VPC and Subnet** (can use default VPC)
- **Security Group** allowing ports 22, 80, 443, 8082

### **Required Permissions**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:CreateTags",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress"
      ],
      "Resource": "*"
    }
  ]
}
```

### **Environment Variables**
```bash
# Required environment variables
export ANTHROPIC_API_KEY="sk-ant-api03-your-key-here"
export AWS_REGION="ap-northeast-2"
export EC2_KEY_NAME="your-key-pair-name"

# Optional (with defaults)
export EC2_INSTANCE_TYPE="t3.medium"
export EC2_SUBNET_ID="subnet-xxxxxxxxx"  # Will use default if not specified
```

## 🚀 **Quick Deployment Options**

### **Option 1: Automated EC2 Launch (Recommended)**
```bash
cd setup-environment/ec2/
./scripts/deploy-ec2.sh
```

### **Option 2: Manual EC2 Launch with User Data**
```bash
# Launch EC2 instance with user data script
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.medium \
  --key-name $EC2_KEY_NAME \
  --user-data file://manifests/user_data_full.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kong-aws-masking-ec2}]'
```

### **Option 3: Terraform Deployment**
```bash
cd manifests/
terraform init
terraform plan -var="anthropic_api_key=$ANTHROPIC_API_KEY"
terraform apply
```

### **Option 4: Docker Compose (Existing Instance)**
```bash
# If you already have an EC2 instance
scp docker-compose.yml ubuntu@$EC2_IP:/home/ubuntu/
ssh ubuntu@$EC2_IP
sudo docker-compose up -d
```

## 📁 **Directory Structure**

```
setup-environment/ec2/
├── README.md                           # This comprehensive guide
├── manifests/                          # Deployment configurations
│   ├── docker-compose.yml              # Main Docker Compose file
│   ├── user_data_full.sh               # Complete user data automation
│   ├── main.tf                         # Terraform configuration
│   ├── variables.tf                    # Terraform variables
│   ├── outputs.tf                      # Terraform outputs
│   └── terraform.tfvars.example        # Example Terraform variables
├── scripts/                            # Automation scripts
│   ├── deploy-ec2.sh                   # Automated EC2 deployment
│   ├── setup-docker.sh                 # Docker installation script
│   └── health-check.sh                 # Health validation script
├── tests/                              # Environment-specific tests
│   ├── phase2/                         # EC2-specific tests
│   ├── performance/                    # Performance benchmarks
│   └── logging/                        # Logging validation tests
├── docs/                               # Additional documentation
│   └── USER_DATA_INSTALLATION_GUIDE.md # User data script guide
└── configs/                            # Configuration files
    ├── development.env                 # Development environment
    ├── production.env                  # Production environment
    └── .env.example                    # Environment template
```

## 🔧 **Detailed Setup Process**

### **Step 1: Prepare Environment**
```bash
# Clone the project and navigate to EC2 environment
cd setup-environment/ec2/

# Set required environment variables
export ANTHROPIC_API_KEY="sk-ant-api03-your-key-here"
export AWS_REGION="ap-northeast-2"
export EC2_KEY_NAME="your-key-pair-name"

# Create configuration file
cp configs/.env.example configs/.env
# Edit configs/.env with your actual values
```

### **Step 2: Deploy EC2 Instance**
```bash
# Automated deployment (recommended)
./scripts/deploy-ec2.sh

# Monitor deployment progress
./scripts/health-check.sh
```

### **Step 3: Verify Deployment**
```bash
# Get EC2 instance IP
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=kong-aws-masking-ec2" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Test endpoints
curl http://$EC2_IP:8082/health
curl http://$EC2_IP:8082/v1/health
```

### **Step 4: Access Services**
```bash
# SSH into instance
ssh -i ~/.ssh/$EC2_KEY_NAME.pem ubuntu@$EC2_IP

# Check Docker containers
sudo docker-compose ps

# Check logs
sudo docker-compose logs -f
```

## 🧪 **Testing & Validation**

### **Quick Health Check**
```bash
cd tests/
./performance/quick-core-validation.sh
```

### **EC2-Specific Testing**
```bash
# EC2 deployment validation
./phase2/ec2-actual-deployment-test.sh

# Performance testing
./performance/performance-benchmark.sh

# Logging validation
./logging/test-comprehensive-logging.sh
```

### **Manual Testing**
```bash
# SSH into EC2 instance
ssh -i ~/.ssh/$EC2_KEY_NAME.pem ubuntu@$EC2_IP

# Access Claude Code SDK container
sudo docker exec -it claude-code-sdk /bin/bash

# Run AWS masking test
claude-code --prompt "Analyze this EC2 instance: i-1234567890abcdef0"
```

## 🔒 **Security Configuration**

### **Security Groups**
```bash
# Create security group with required ports
aws ec2 create-security-group \
  --group-name kong-aws-masking-sg \
  --description "Security group for Kong AWS Masking"

# Allow SSH access
aws ec2 authorize-security-group-ingress \
  --group-name kong-aws-masking-sg \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Allow HTTP access
aws ec2 authorize-security-group-ingress \
  --group-name kong-aws-masking-sg \
  --protocol tcp \
  --port 8082 \
  --cidr 0.0.0.0/0
```

### **Data Security**
- **Redis Password**: Secure Redis with authentication
- **API Keys**: Stored in environment variables, not hardcoded
- **Network Security**: VPC and security group isolation
- **File Permissions**: Proper file permissions on sensitive configurations

### **Access Control**
```bash
# SSH key-based access only
# No password authentication
# Docker containers run as non-root users where possible
# Redis authentication enabled
```

## ⚡ **Performance Optimization**

### **EC2 Instance Sizing**
- **t3.medium** (2 vCPU, 4GB RAM): Development and light testing
- **t3.large** (2 vCPU, 8GB RAM): Production workloads
- **c5.large** (2 vCPU, 4GB RAM): CPU-intensive workloads
- **m5.large** (2 vCPU, 8GB RAM): Balanced production workloads

### **Docker Optimization**
```yaml
# docker-compose.yml optimizations
services:
  kong:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 1G
```

### **Application Tuning**
```bash
# Kong worker processes
KONG_NGINX_WORKER_PROCESSES=auto

# Redis memory optimization
REDIS_MAXMEMORY=512MB
REDIS_MAXMEMORY_POLICY=allkeys-lru

# Nginx worker processes
NGINX_WORKER_PROCESSES=auto
```

## 📊 **Monitoring & Observability**

### **Health Endpoints**
```bash
# Primary endpoints
curl http://$EC2_IP:8082/health          # Nginx proxy health
curl http://$EC2_IP:8000/status          # Kong Gateway status
curl http://$EC2_IP:3000/health          # Backend API health

# Admin endpoints
curl http://$EC2_IP:8001/status          # Kong Admin API
curl http://$EC2_IP:6379                 # Redis (with auth)
```

### **Log Locations**
```bash
# Docker container logs
sudo docker-compose logs kong
sudo docker-compose logs nginx
sudo docker-compose logs backend
sudo docker-compose logs redis
sudo docker-compose logs claude-code-sdk

# System logs on EC2
sudo journalctl -u docker
sudo tail -f /var/log/syslog
```

### **Metrics Collection**
```bash
# Docker stats
sudo docker stats

# System resources
htop
df -h
free -h
iostat -x 1

# Application metrics
curl http://$EC2_IP:3000/metrics        # Backend metrics
curl http://$EC2_IP:8001/metrics        # Kong metrics
```

## 🚨 **Troubleshooting**

### **Common Issues**

#### **User Data Script Fails**
```bash
# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/cloud-init.log

# Check if Docker is installed
sudo docker --version

# Check if containers are running
sudo docker-compose ps
```

#### **Services Not Accessible**
```bash
# Check security group rules
aws ec2 describe-security-groups --group-names kong-aws-masking-sg

# Check if services are listening
sudo netstat -tlnp | grep :8082
sudo netstat -tlnp | grep :8000

# Check Docker network
sudo docker network ls
sudo docker network inspect <network_name>
```

#### **Container Health Issues**
```bash
# Check container health
sudo docker-compose ps
sudo docker inspect <container_name>

# Check container logs
sudo docker-compose logs <service_name>

# Restart services
sudo docker-compose restart
sudo docker-compose down && sudo docker-compose up -d
```

#### **API Key Issues**
```bash
# Verify API key is set
echo $ANTHROPIC_API_KEY

# Check if API key is passed to containers
sudo docker exec kong printenv | grep ANTHROPIC

# Test API key directly
curl -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  https://api.anthropic.com/v1/messages
```

### **Debug Commands**
```bash
# System status
sudo systemctl status docker
sudo docker system df
sudo docker system events

# Network debugging
sudo iptables -L
sudo ss -tlnp

# Storage debugging
sudo df -h
sudo docker system prune
```

## 🔄 **Maintenance Operations**

### **Updates and Rollouts**
```bash
# Update Docker images
sudo docker-compose pull
sudo docker-compose down
sudo docker-compose up -d

# Update specific service
sudo docker-compose pull kong
sudo docker-compose up -d kong
```

### **Backup and Recovery**
```bash
# Backup Redis data
sudo docker exec redis redis-cli --rdb /backup/dump.rdb

# Backup configuration
tar -czf kong-backup-$(date +%Y%m%d).tar.gz \
  docker-compose.yml .env kong/ nginx/

# Full system backup
sudo rsync -av /opt/kong-aws-masking/ /backup/
```

### **System Maintenance**
```bash
# Clean up Docker resources
sudo docker system prune -f
sudo docker volume prune -f

# Update system packages
sudo apt update && sudo apt upgrade -y

# Monitor disk space
sudo du -sh /var/lib/docker/
sudo docker system df
```

## 📈 **Scaling Options**

### **Vertical Scaling**
```bash
# Stop instance
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# Modify instance type
aws ec2 modify-instance-attribute \
  --instance-id $INSTANCE_ID \
  --instance-type Value=t3.large

# Start instance
aws ec2 start-instances --instance-ids $INSTANCE_ID
```

### **Horizontal Scaling (Load Balancer)**
```bash
# Create Application Load Balancer
aws elbv2 create-load-balancer \
  --name kong-aws-masking-alb \
  --subnets subnet-xxx subnet-yyy

# Create target group
aws elbv2 create-target-group \
  --name kong-aws-masking-tg \
  --protocol HTTP \
  --port 8082 \
  --vpc-id vpc-xxxxxxxxx
```

## 🎯 **Production Checklist**

### **Pre-deployment**
- [ ] EC2 key pair created and secured
- [ ] Security groups configured with minimal required access
- [ ] VPC and subnet selected for deployment
- [ ] Anthropic API key validated and secured
- [ ] Instance type sized appropriately for workload

### **Security Review**
- [ ] SSH key-based access only (no passwords)
- [ ] Security group rules reviewed and approved
- [ ] Redis authentication enabled
- [ ] API keys stored securely (not in code)
- [ ] File permissions set correctly

### **Performance Validation**
- [ ] Instance size appropriate for expected load
- [ ] Docker resource limits configured
- [ ] Application tuning parameters set
- [ ] Performance benchmarks established

### **Monitoring Setup**
- [ ] CloudWatch monitoring enabled
- [ ] Log aggregation configured
- [ ] Health check endpoints validated
- [ ] Alert rules defined for critical components

## 💰 **Cost Optimization**

### **Instance Optimization**
- **Development**: t3.micro or t3.small (1-2 vCPU, 1-2GB RAM)
- **Testing**: t3.medium (2 vCPU, 4GB RAM)
- **Production**: t3.large or m5.large (2 vCPU, 8GB RAM)

### **Cost-Saving Strategies**
```bash
# Use Spot Instances for development
aws ec2 request-spot-instances \
  --spot-price "0.05" \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification file://spot-instance-spec.json

# Schedule start/stop for development instances
# Use AWS Instance Scheduler
```

## 📞 **Support**

### **Environment-Specific Support**
- **Documentation**: Check this comprehensive guide first
- **Testing**: Use the test suites in `tests/` for validation
- **Logs**: SSH into instance and check Docker logs
- **Issues**: Review troubleshooting section above

### **Quick Commands Reference**
```bash
# Check instance status
aws ec2 describe-instances --instance-ids $INSTANCE_ID

# SSH into instance
ssh -i ~/.ssh/$EC2_KEY_NAME.pem ubuntu@$EC2_IP

# Check services
sudo docker-compose ps
sudo docker-compose logs -f

# Health checks
curl http://$EC2_IP:8082/health
./scripts/health-check.sh

# Restart services
sudo docker-compose restart
```

---

## 🎉 **Environment Status**

**Status**: ✅ **Production Ready**  
**Last Verified**: July 31, 2025  
**Deployment Target**: Single EC2 Instance with Docker Compose  
**Average Setup Time**: 8-12 minutes  
**All Components**: Kong Gateway, Nginx Proxy, Backend API, Redis, Claude Code SDK  

**🎯 EC2 ENVIRONMENT - FASTEST DEPLOYMENT PATH AVAILABLE!**