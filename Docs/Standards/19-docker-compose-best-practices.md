# 🐳 **Docker Compose Best Practices - Kong AWS Masking MVP**

<!-- Tags: #docker #compose #containers #networking #deployment #best-practices -->

> **PURPOSE**: Comprehensive guide for Docker Compose configuration and best practices for Kong Gateway deployment  
> **SCOPE**: Service configuration, networking, volumes, environment management, security, performance  
> **COMPLEXITY**: ⭐⭐⭐ Intermediate | **DURATION**: 2-3 hours for complete setup  
> **TARGET**: Development and production-ready Docker Compose configurations

---

## ⚡ **QUICK START - Essential Configuration**

### 🎯 **Minimal Working Configuration**
```yaml
version: '3.8'

services:
  kong:
    image: kong:3.9.0.1
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: "/kong/kong.yml"
      KONG_PROXY_ACCESS_LOG: "/dev/stdout"
      KONG_PROXY_ERROR_LOG: "/dev/stderr"
    ports:
      - "8000:8000"
    volumes:
      - ./kong/kong.yml:/kong/kong.yml:ro
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 🔍 **Quick Commands**
```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f kong

# Restart service
docker-compose restart kong

# Clean shutdown
docker-compose down
```

---

## 📋 **DOCKER COMPOSE ARCHITECTURE**

### **Service Dependencies**
```yaml
version: '3.8'

services:
  backend:
    build: ./backend
    depends_on:
      - kong
    environment:
      - NODE_ENV=production
    networks:
      - app-network
    restart: unless-stopped

  kong:
    image: kong:3.9.0.1
    depends_on:
      backend:
        condition: service_healthy
    networks:
      - app-network
    restart: always

networks:
  app-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### **Service Configuration Hierarchy**
```
docker-compose.yml (base)
├── docker-compose.override.yml (development)
├── docker-compose.prod.yml (production)
└── docker-compose.test.yml (testing)
```

---

## 🏗️ **CONFIGURATION BEST PRACTICES**

### **Environment Variables Management**
```yaml
# ✅ Best Practice: Use .env files
services:
  backend:
    image: node:20-alpine
    env_file:
      - .env
      - .env.local  # Local overrides
    environment:
      # Override specific vars
      NODE_ENV: ${NODE_ENV:-development}
      PORT: ${BACKEND_PORT:-3000}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:?Error: API key required}
```

### **.env File Structure**
```bash
# .env
KONG_VERSION=3.9.0.1
BACKEND_PORT=3000
NODE_ENV=development

# AWS Configuration
AWS_REGION=us-east-1
AWS_PROFILE=default

# API Keys (never commit!)
ANTHROPIC_API_KEY=sk-ant-api03-xxxxx
```

### **Build Configuration**
```yaml
# ✅ Optimized build configuration
services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
      args:
        NODE_VERSION: ${NODE_VERSION:-20}
        BUILD_ENV: ${BUILD_ENV:-production}
      cache_from:
        - node:20-alpine
      target: production  # Multi-stage build target
    image: kong-aws-backend:${VERSION:-latest}
```

---

## 🔒 **SECURITY BEST PRACTICES**

### **Secrets Management**
```yaml
# ✅ Docker secrets (Swarm mode)
version: '3.8'

secrets:
  anthropic_key:
    external: true
  aws_credentials:
    file: ~/.aws/credentials

services:
  backend:
    secrets:
      - anthropic_key
      - aws_credentials
    environment:
      ANTHROPIC_API_KEY_FILE: /run/secrets/anthropic_key
```

### **Non-Root User**
```yaml
# ✅ Run as non-root
services:
  backend:
    image: node:20-alpine
    user: "1000:1000"  # node user
    read_only: true    # Read-only root filesystem
    tmpfs:
      - /tmp
      - /app/tmp
```

### **Network Isolation**
```yaml
# ✅ Network segmentation
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # No external access

services:
  kong:
    networks:
      - frontend
      - backend
  
  backend:
    networks:
      - backend  # Only backend network
```

---

## 🚀 **PERFORMANCE OPTIMIZATION**

### **Resource Limits**
```yaml
# ✅ Define resource constraints
services:
  kong:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

### **Health Checks**
```yaml
# ✅ Comprehensive health checks
services:
  backend:
    healthcheck:
      test: ["CMD", "node", "healthcheck.js"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
  
  kong:
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

### **Logging Configuration**
```yaml
# ✅ Optimized logging
services:
  kong:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        labels: "service=kong,env=production"
```

---

## 📁 **VOLUME MANAGEMENT**

### **Named Volumes**
```yaml
# ✅ Use named volumes for persistence
volumes:
  kong-config:
    driver: local
  app-data:
    driver: local

services:
  kong:
    volumes:
      - kong-config:/usr/local/kong
      - ./kong/kong.yml:/kong/kong.yml:ro
      - ./kong/plugins:/usr/local/share/lua/5.1/kong/plugins:ro
```

### **Volume Optimization**
```yaml
# ✅ Volume mount optimization
services:
  backend:
    volumes:
      # Bind mounts for development
      - type: bind
        source: ./backend/src
        target: /app/src
        read_only: true
      
      # Named volume for node_modules
      - type: volume
        source: node_modules
        target: /app/node_modules
      
      # tmpfs for temporary files
      - type: tmpfs
        target: /app/tmp
        tmpfs:
          size: 100m
```

---

## 🔄 **DEPLOYMENT STRATEGIES**

### **Multi-Stage Configuration**
```yaml
# docker-compose.yml (base)
version: '3.8'

services:
  backend:
    image: kong-backend:${VERSION:-latest}
    networks:
      - default

# docker-compose.override.yml (dev)
services:
  backend:
    build: ./backend
    volumes:
      - ./backend:/app
    command: npm run dev

# docker-compose.prod.yml (production)
services:
  backend:
    restart: always
    deploy:
      replicas: 2
```

### **Usage Patterns**
```bash
# Development
docker-compose up

# Production
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Testing
docker-compose -f docker-compose.yml -f docker-compose.test.yml run tests
```

---

## 🎯 **KONG-SPECIFIC CONFIGURATION**

### **DB-less Mode Setup**
```yaml
services:
  kong:
    image: kong:3.9.0.1
    environment:
      # DB-less mode
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: "/kong/kong.yml"
      
      # Proxy settings
      KONG_PROXY_LISTEN: "0.0.0.0:8000"
      KONG_ADMIN_LISTEN: "0.0.0.0:8001"
      
      # Logging
      KONG_LOG_LEVEL: ${KONG_LOG_LEVEL:-info}
      KONG_PROXY_ACCESS_LOG: "/dev/stdout"
      KONG_PROXY_ERROR_LOG: "/dev/stderr"
      KONG_ADMIN_ACCESS_LOG: "/dev/stdout"
      KONG_ADMIN_ERROR_LOG: "/dev/stderr"
      
      # Plugins
      KONG_PLUGINS: "bundled,aws-masker"
      KONG_LUA_PACKAGE_PATH: "/opt/?.lua;;"
    
    volumes:
      - ./kong/kong.yml:/kong/kong.yml:ro
      - ./kong/plugins:/opt/kong/plugins:ro
    
    ports:
      - "8000:8000"  # Proxy
      - "8001:8001"  # Admin API
```

### **Kong Plugin Development**
```yaml
services:
  kong-dev:
    extends:
      service: kong
    environment:
      KONG_LOG_LEVEL: debug
      KONG_NGINX_WORKER_PROCESSES: 1
    volumes:
      # Hot reload for plugin development
      - ./kong/plugins:/usr/local/share/lua/5.1/kong/plugins
    command: >
      sh -c "
        kong migrations bootstrap &&
        kong migrations up &&
        kong start --vv
      "
```

---

## 🔧 **TROUBLESHOOTING CONFIGURATION**

### **Debug Mode**
```yaml
# docker-compose.debug.yml
services:
  backend:
    command: node --inspect=0.0.0.0:9229 server.js
    ports:
      - "9229:9229"  # Node.js debugger
    environment:
      DEBUG: "*"
      LOG_LEVEL: debug
  
  kong:
    environment:
      KONG_LOG_LEVEL: debug
      KONG_NGINX_DAEMON: "off"  # Run in foreground
```

### **Common Issues Resolution**
```yaml
# ✅ File permission issues
services:
  backend:
    volumes:
      - ./data:/app/data:rw
    # Fix permissions on startup
    entrypoint: >
      sh -c "
        chown -R node:node /app/data &&
        exec node server.js
      "

# ✅ DNS resolution issues
services:
  backend:
    dns:
      - 8.8.8.8
      - 8.8.4.4
    dns_search:
      - service.local

# ✅ Container startup order
services:
  backend:
    depends_on:
      kong:
        condition: service_healthy
    restart: on-failure:3
    command: >
      sh -c "
        while ! nc -z kong 8001; do
          echo 'Waiting for Kong...'
          sleep 1
        done
        node server.js
      "
```

---

## 💡 **BEST PRACTICES SUMMARY**

### **Do's**
```yaml
# ✅ Recommended practices
- Use specific image tags (not :latest)
- Define health checks for all services
- Set resource limits
- Use named volumes for data
- Implement proper logging
- Use .env files for configuration
- Define restart policies
- Use multi-stage configurations
```

### **Don'ts**
```yaml
# ❌ Avoid these
- Don't hardcode secrets
- Don't use host network mode
- Don't run as root
- Don't ignore health checks
- Don't use unbounded resources
- Don't mix dev and prod configs
- Don't ignore security contexts
```

---

## 🚀 **PRODUCTION CHECKLIST**

### **Pre-Deployment**
```bash
□ All images tagged with specific versions
□ Resource limits defined
□ Health checks implemented
□ Logging configured
□ Secrets externalized
□ Networks segmented
□ Volumes properly configured
□ Restart policies set
```

### **Monitoring Setup**
```yaml
# Monitoring integration
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    
  grafana:
    image: grafana/grafana
    depends_on:
      - prometheus
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
    ports:
      - "3001:3000"
```

---

## 🎓 **ADVANCED PATTERNS**

### **Blue-Green Deployment**
```yaml
# Blue environment
services:
  backend-blue:
    image: backend:v1.0.0
    networks:
      - app-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.backend.rule=Host(`api.example.com`)"
      - "traefik.http.services.backend.loadbalancer.server.port=3000"

# Green environment (new version)
  backend-green:
    image: backend:v1.1.0
    networks:
      - app-network
    labels:
      - "traefik.enable=false"  # Disabled initially
```

### **Development Workflow**
```yaml
# Development with hot reload
services:
  backend:
    build:
      context: ./backend
      target: development
    volumes:
      - ./backend:/app
      - /app/node_modules  # Exclude node_modules
    environment:
      - NODE_ENV=development
      - CHOKIDAR_USEPOLLING=true  # For file watching
    command: npm run dev
```

---

**🔑 Key Message**: Well-configured Docker Compose files ensure consistent, secure, and performant deployments. Focus on security, resource management, and clear separation between development and production configurations.