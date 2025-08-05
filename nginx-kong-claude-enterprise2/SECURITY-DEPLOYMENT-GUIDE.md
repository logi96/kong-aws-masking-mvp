# Security Deployment Guide
Kong AWS Masking Enterprise 2 - Production Security Best Practices

## 🔒 API Key Security Management

### ❌ NEVER DO: Hardcode API Keys
```bash
# ❌ Don't do this in production
ANTHROPIC_API_KEY=sk-ant-api03-actual-key-here
```

### ✅ RECOMMENDED: Environment Variable Management

#### **Method 1: System Environment Variables**
```bash
# Set system-level environment variables
export ANTHROPIC_API_KEY_PRODUCTION="sk-ant-api03-your-actual-key"
export REDIS_PASSWORD_PRODUCTION="your-strong-64-char-password"

# Use in docker-compose
docker-compose --env-file config/production.env up -d
```

#### **Method 2: Docker Secrets (Recommended)**
```bash
# Create Docker secrets
echo "sk-ant-api03-your-actual-key" | docker secret create anthropic_api_key -
echo "your-strong-redis-password" | docker secret create redis_password -

# Update docker-compose.yml
services:
  kong:
    secrets:
      - anthropic_api_key
      - redis_password
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - REDIS_PASSWORD_FILE=/run/secrets/redis_password
```

#### **Method 3: External Secret Management**
```bash
# AWS Systems Manager Parameter Store
aws ssm put-parameter \
  --name "/claude/production/anthropic-api-key" \
  --value "sk-ant-api03-your-actual-key" \
  --type "SecureString"

# HashiCorp Vault
vault kv put secret/claude/production \
  anthropic-api-key="sk-ant-api03-your-actual-key" \
  redis-password="your-strong-password"
```

## 🛡️ Production Security Checklist

### **Before Deployment**
- [ ] Remove all hardcoded API keys from `.env` files
- [ ] Update `.gitignore` to exclude production `.env` files
- [ ] Generate strong passwords (minimum 64 characters)
- [ ] Enable SSL/TLS certificates
- [ ] Configure firewall rules (only necessary ports)
- [ ] Enable Redis authentication
- [ ] Set Kong to `warn` log level (not `debug`)

### **During Deployment**
- [ ] Use `config/production.env` with environment variable references
- [ ] Verify no sensitive data in container logs
- [ ] Test all API endpoints with production keys
- [ ] Validate SSL certificate installation
- [ ] Check Redis connection with authentication

### **After Deployment**
- [ ] Monitor logs for any exposed secrets
- [ ] Rotate API keys every 90 days
- [ ] Review access logs for suspicious activity
- [ ] Backup encrypted configuration files
- [ ] Test disaster recovery procedures

## 🔑 Strong Password Generation

### **Redis Password (64+ characters)**
```bash
# Generate strong Redis password
openssl rand -base64 48 | tr -d "=+/" | cut -c1-64
# Example: CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL
```

### **JWT Secrets (32+ characters)**
```bash
# Generate JWT secret
openssl rand -hex 32
# Example: a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

## 🌐 SSL/TLS Configuration

### **Production SSL Setup**
```nginx
# nginx/conf.d/ssl-production.conf
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    ssl_certificate /certs/production.crt;
    ssl_certificate_key /certs/production.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
}
```

## 🚨 Security Incident Response

### **If API Key is Compromised**
1. **Immediate Action**
   ```bash
   # Revoke compromised key immediately
   # Generate new API key from Anthropic Console
   # Update environment variables
   docker-compose restart kong
   ```

2. **Investigation**
   - Check access logs for unauthorized usage
   - Review Git history for exposed keys
   - Audit all systems that had access to the key

3. **Recovery**
   - Update all environment configurations
   - Rotate all related passwords
   - Update documentation and team

## 📋 Production Environment Template

### **config/production.env**
```bash
# Production Environment Configuration
NODE_ENV=production
DEPLOYMENT_ENV=production

# API Configuration (Use environment variable references)
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY_PRODUCTION}

# Redis Configuration (Use environment variable references)
REDIS_PASSWORD=${REDIS_PASSWORD_PRODUCTION}

# Security Settings
KONG_LOG_LEVEL=warn
ENABLE_DEBUG_LOGS=false
ENABLE_SSL=true

# Performance Settings
KONG_MEMORY_LIMIT=6G
KONG_WORKER_PROCESSES=4
NGINX_WORKER_CONNECTIONS=2048
```

### **System Environment Setup**
```bash
#!/bin/bash
# production-env-setup.sh

# Set production environment variables
export ANTHROPIC_API_KEY_PRODUCTION="[GET-FROM-SECURE-VAULT]"
export REDIS_PASSWORD_PRODUCTION="[GENERATE-STRONG-PASSWORD]"
export BACKUP_S3_BUCKET="claude-enterprise-backups"
export ALERT_WEBHOOK_URL="https://hooks.slack.com/services/..."

# Verify all required variables are set
required_vars=(
    "ANTHROPIC_API_KEY_PRODUCTION"
    "REDIS_PASSWORD_PRODUCTION"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "❌ ERROR: $var is not set"
        exit 1
    fi
done

echo "✅ All production environment variables are set"
```

## 🔒 Security Validation Commands

### **Pre-deployment Security Check**
```bash
# Check for hardcoded secrets
grep -r "sk-ant-api03" . --exclude-dir=.git --exclude="*.md"
grep -r "ANTHROPIC_API_KEY=" . --exclude-dir=.git --exclude="*.example"

# Verify environment variable references
grep -r "\${" config/production.env

# Test API key access (should fail if not set)
docker-compose --env-file config/production.env config | grep -i "api"
```

### **Post-deployment Security Validation**
```bash
# Verify no secrets in logs
docker-compose logs | grep -i "sk-ant-api03" || echo "✅ No API keys in logs"

# Check SSL certificate
curl -I https://your-domain.com

# Verify Redis authentication
redis-cli -h localhost -p 6379 ping  # Should require auth
```

## 🎯 Security Compliance Summary

| **Security Aspect** | **Development** | **Production** | **Status** |
|---------------------|-----------------|----------------|------------|
| API Key Storage | `.env` file | Environment variables | ✅ Implemented |
| Redis Authentication | Basic password | Strong 64-char password | ✅ Implemented |
| SSL/TLS | Optional | Required | ✅ Configured |
| Log Level | Debug | Warn/Error | ✅ Configured |
| Secret Scanning | Manual | Automated | ⚠️ Recommended |
| Key Rotation | Manual | 90-day cycle | ⚠️ Recommended |

---

**Remember**: Security is not a one-time setup but an ongoing process. Regularly review and update these configurations as your security requirements evolve.