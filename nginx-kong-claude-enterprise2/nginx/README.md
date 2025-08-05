# Nginx Enterprise Proxy - Kong AWS Masking MVP

**Project**: nginx-kong-claude-enterprise2  
**Purpose**: High-performance HTTP proxy layer for Kong AWS masking system  
**Last Updated**: 2025-07-30

## 🎯 Overview

This Nginx configuration provides the enterprise proxy layer that sits between Claude Code clients and the Kong Gateway, handling HTTP traffic routing, load balancing, and secure header forwarding for the AWS masking system.

## 📂 Current Structure

```
nginx/
├── README.md                    # This documentation
├── Dockerfile                   # Docker build configuration (ACTIVE)
├── nginx.conf                   # Main nginx configuration (ACTIVE)  
├── conf.d/                      # Server configurations
│   └── claude-proxy.conf        # Claude API proxy config (ACTIVE)
└── archive/                     # Unused files (ARCHIVED)
    ├── Dockerfile.prod          # Production Dockerfile (unused)
    └── blue-green.conf          # Blue-green deployment config (placeholder)
```

## 🔗 Proxy Chain Architecture

### **Current Flow**:
```
[Claude Code Client] 
    ↓ HTTP (port 8082)
[Nginx Proxy] 
    ↓ HTTP (internal kong:8010)
[Kong Gateway + AWS Masker] 
    ↓ HTTPS (api.anthropic.com)
[Claude API]
```

### **Security Architecture**:
- **Nginx**: Simple proxy forwarding (no API key handling)
- **Kong**: Environment-based API key injection + AWS masking
- **Redis**: Masking data persistence

## 🔒 Security Improvements (Critical Fix Applied)

### **❌ Previous Security Issue (RESOLVED)**:
```nginx
# DANGEROUS - API key hardcoded in nginx
proxy_set_header x-api-key "sk-ant-api03-...";
```

### **✅ Current Secure Configuration**:
```nginx
# SECURE - API key managed by Kong from environment
proxy_set_header x-api-key $http_x_api_key;
```

### **Security Flow**:
1. **Client Request** → Nginx (no API key)
2. **Nginx Forward** → Kong (header passthrough)  
3. **Kong Transform** → Adds `x-api-key: ${ANTHROPIC_API_KEY}` from environment
4. **Kong Forward** → Claude API (secure API key injection)

## 📋 Active Configuration Files

### **Dockerfile** ⭐
**Purpose**: Container build configuration  
**Usage**: Referenced by `docker-compose.yml`

```dockerfile
FROM nginx:1.27-alpine
RUN apk add --no-cache curl
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/claude-proxy.conf /etc/nginx/conf.d/claude-proxy.conf
EXPOSE 8082
```

**Key Features**:
- Alpine Linux base for security and size
- Health check with curl
- Custom configuration overlay

### **nginx.conf** ⭐
**Purpose**: Main nginx server configuration  
**Key Settings**:

```nginx
worker_processes auto;               # Auto-scale based on CPU cores
worker_connections 1024;            # Connection limit per worker
keepalive_timeout 65;               # Connection persistence
include /etc/nginx/conf.d/*.conf;   # Include all server configs
```

**Optimizations**:
- Automatic worker scaling
- Efficient connection handling
- Structured logging to `/var/log/nginx/`

### **conf.d/claude-proxy.conf** ⭐
**Purpose**: Claude API proxy server configuration  
**Listen Port**: 8082  
**Upstream**: kong:8010

**Critical Configuration**:
```nginx
upstream kong_backend {
    server kong:8010;
}

server {
    listen 8082;
    
    location /health {
        return 200 '{"status":"healthy"}';
        add_header Content-Type application/json;
    }
    
    location / {
        proxy_pass http://kong_backend;
        proxy_set_header Host api.anthropic.com;
        
        # Security: Forward headers, no hardcoded secrets
        proxy_set_header Authorization $http_authorization;
        proxy_set_header x-api-key $http_x_api_key;
    }
}
```

**Security Features**:
- No hardcoded API keys
- Header forwarding from client
- Health check endpoint
- Host header override for Claude API compatibility

## 🐳 Docker Integration

### **Docker Compose Configuration**:
```yaml
nginx:
  build:
    context: ./nginx
    dockerfile: Dockerfile           # Uses main Dockerfile
  ports:  
    - "${NGINX_PROXY_PORT:-8082}:8082"
  volumes:
    - ./logs/nginx:/var/log/nginx    # Log persistence
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
```

**Important Notes**:
- Uses `Dockerfile` (not `Dockerfile.prod`)
- Exposes port 8082 as main entry point
- Health check on `/health` endpoint
- Log persistence for monitoring

## 🚀 Operational Guidelines

### **Health Monitoring**:
```bash
# Check nginx health
curl http://localhost:8082/health
# Expected: {"status":"healthy"}

# Check Docker container status
docker-compose ps nginx
# Expected: healthy status

# View nginx logs
docker-compose logs nginx
```

### **Performance Metrics**:
- **Target Response Time**: <100ms for proxy forwarding
- **Concurrent Connections**: 1024 per worker process
- **Worker Processes**: Auto-scaled to CPU cores
- **Memory Usage**: ~10-20MB per worker

### **Common Operations**:
```bash
# Restart nginx service
docker-compose restart nginx

# View access logs
docker-compose exec nginx tail -f /var/log/nginx/access.log

# View error logs
docker-compose exec nginx tail -f /var/log/nginx/error.log

# Test configuration syntax
docker-compose exec nginx nginx -t
```

## 🔧 Configuration Dependencies

### **Environment Variables**:
```bash
# Set in .env file
NGINX_PROXY_PORT=8082                    # Main proxy port
NGINX_WORKER_PROCESSES=auto              # Worker scaling
NGINX_WORKER_CONNECTIONS=1024            # Connection limit
```

### **Network Dependencies**:
- **Upstream**: kong:8010 (Kong Gateway internal)
- **Downstream**: Client connections on port 8082
- **Health Check**: Internal curl to localhost:8082/health

### **Volume Mounts**:
- **Logs**: `./logs/nginx:/var/log/nginx` (persistent logging)
- **No Config Mounts**: All config built into image

## 📊 API Key Security Comparison

### **Before Security Fix** ❌:
```
Client Request → Nginx (adds hardcoded API key) → Kong → Claude API
```
**Risks**:
- API key exposed in configuration files
- Version control exposure
- No key rotation capability
- Security audit failures

### **After Security Fix** ✅:
```
Client Request → Nginx (header passthrough) → Kong (env-based key injection) → Claude API
```
**Benefits**:
- Zero hardcoded secrets
- Environment-based key management
- Easy key rotation
- Audit compliance
- Container security best practices

## 🗂️ Archive Information

### **Archived Files**:
The `archive/` folder contains development files no longer in active use:

**`Dockerfile.prod`** - Production-optimized Dockerfile
- Multi-stage build with config validation
- Security hardening with non-root user
- Enhanced health checks and monitoring
- **Status**: Complete but unused (development uses simpler Dockerfile)

**`blue-green.conf`** - Blue-green deployment placeholder
- Empty configuration file for future deployment strategy
- **Status**: Placeholder only, no actual configuration

### **Why Archived?**:
- **Dockerfile.prod**: Over-engineered for current development needs
- **blue-green.conf**: Feature not implemented, empty placeholder

## 🚨 Security Best Practices

### **Current Implementation**:
✅ No hardcoded secrets in configuration  
✅ Environment variable API key management  
✅ Secure header forwarding  
✅ Health check endpoints  
✅ Structured logging  

### **Recommendations**:
- **SSL/TLS**: Consider adding HTTPS termination for production
- **Rate Limiting**: Implement rate limiting in nginx for DDoS protection
- **IP Filtering**: Add IP allowlist for restricted access
- **Security Headers**: Add security headers (HSTS, CSP, etc.)

## 🔄 Testing Guidelines

### **Health Check Testing**:
```bash
# Basic health check
curl -f http://localhost:8082/health

# Expected response
{"status":"healthy"}
```

### **Proxy Functionality Testing**:
```bash
# Test proxy forwarding (requires Kong to be running)
curl -X POST http://localhost:8082/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: test-key" \
  -d '{"test": "data"}'

# Should forward to Kong on port 8010
```

### **Security Testing**:
```bash
# Verify no hardcoded API keys in config
docker-compose exec nginx grep -r "sk-ant-api" /etc/nginx/
# Expected: No matches (should be empty)

# Check environment variable usage in Kong
docker-compose exec kong env | grep ANTHROPIC_API_KEY
# Expected: ANTHROPIC_API_KEY=sk-ant-api03-...
```

### **Performance Testing**:
```bash
# Concurrent connection test
ab -n 1000 -c 10 http://localhost:8082/health

# Load test with Apache Bench
ab -n 10000 -c 100 http://localhost:8082/health
```

## 📈 Monitoring & Troubleshooting

### **Log Analysis**:
```bash
# Access log format
tail -f logs/nginx/access.log
# Shows: IP, timestamp, request, status, bytes, user-agent

# Error log monitoring
tail -f logs/nginx/error.log
# Shows: timestamps, error levels, detailed error messages
```

### **Common Issues**:

**Connection Refused**:
```bash
# Check if Kong is running
docker-compose ps kong
# Ensure Kong is healthy before nginx starts
```

**504 Gateway Timeout**:
```bash
# Check Kong response time
curl -w "%{time_total}" http://localhost:8010/health
# Kong should respond within 5 seconds
```

**Health Check Failures**:
```bash
# Verify curl availability in container
docker-compose exec nginx which curl
# Ensure curl is installed in nginx container
```

## 🛠️ Development Workflow

### **Configuration Changes**:
1. **Edit Configuration**: Modify `nginx.conf` or `conf.d/claude-proxy.conf`
2. **Test Syntax**: `docker-compose exec nginx nginx -t`
3. **Restart Service**: `docker-compose restart nginx`
4. **Verify Health**: `curl http://localhost:8082/health`

### **Adding New Routes**:
1. **Create Config**: Add new `.conf` file in `conf.d/`
2. **Update Dockerfile**: Add COPY command for new config
3. **Rebuild Image**: `docker-compose build nginx`
4. **Test Configuration**: Verify routing works correctly

### **Security Updates**:
1. **Review Config**: Check for any hardcoded secrets
2. **Environment Variables**: Use env vars for sensitive data
3. **Test Security**: Verify no secrets in container
4. **Document Changes**: Update this README with security notes

---

## 📞 Support

For nginx-related issues:
1. Check container health: `docker-compose ps nginx`
2. Review logs: `docker-compose logs nginx`
3. Test configuration: `docker-compose exec nginx nginx -t`
4. Verify upstream connectivity: Test Kong Gateway health
5. Consult Docker network settings in `docker-compose.yml`

**Nginx Version**: 1.27-alpine  
**Primary Function**: HTTP proxy and load balancer  
**Security Level**: ✅ Hardcoded secrets removed, environment-based security