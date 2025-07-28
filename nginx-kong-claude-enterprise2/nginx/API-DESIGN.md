# Nginx Reverse Proxy API Design

## Architecture Overview

The Nginx reverse proxy serves as an additional layer between clients and Kong Gateway, providing:

1. **Load Balancing**: Distributes requests across Kong instances
2. **Rate Limiting**: Protects backend services from overload
3. **Monitoring**: Provides detailed metrics and health checks
4. **Security**: Adds additional security headers and CORS handling
5. **Logging**: Structured JSON logging for observability

## API Endpoints

### 1. Health Check Endpoints

#### GET /health
- **Purpose**: Basic health check for load balancers
- **Response**: 
  ```json
  {
    "status": "healthy",
    "service": "nginx-proxy",
    "timestamp": "2024-01-20T12:00:00Z"
  }
  ```
- **Status Codes**: 200 (healthy)

#### GET /health/full
- **Purpose**: Comprehensive health check including dependencies
- **Response**:
  ```json
  {
    "status": "healthy",
    "service": "nginx-proxy",
    "timestamp": "2024-01-20T12:00:00Z",
    "version": "1.25.3",
    "dependencies": {
      "kong": {
        "status": "healthy",
        "response_time_ms": 15.3
      }
    },
    "metrics": {
      "connections": {
        "active": 10,
        "reading": 0,
        "writing": 2,
        "waiting": 8
      }
    }
  }
  ```

### 2. Monitoring Endpoints

#### GET /metrics
- **Purpose**: Prometheus-compatible metrics
- **Port**: 8082 (main), 9090 (dedicated monitoring)
- **Format**: Prometheus text format
- **Metrics**:
  - `nginx_up`: Nginx availability
  - `nginx_http_requests_total`: Request count by status
  - `nginx_http_request_duration_seconds`: Request latency histogram
  - `nginx_connections_current`: Current connection states

#### GET /nginx_status
- **Purpose**: Nginx stub_status output
- **Access**: Restricted to internal networks
- **Format**: Plain text nginx status

### 3. Claude API Proxy

#### POST /v1/messages
- **Purpose**: Proxy Claude API messages
- **Rate Limit**: 10 req/s per IP, burst of 20
- **Headers Required**:
  - `anthropic-version`
  - `x-api-key`
  - `Content-Type: application/json`
- **Features**:
  - CORS enabled
  - Streaming support (buffering disabled)
  - Extended timeouts (300s)
  - Request ID injection

### 4. AWS Analyze Proxy

#### POST /analyze
- **Purpose**: Proxy AWS resource analysis requests
- **Rate Limit**: 10 req/s per IP, burst of 10
- **Headers**: Standard HTTP headers
- **Timeouts**: 60s (shorter than Claude API)

## Design Principles

### 1. Performance Optimization
- **Connection Pooling**: Keepalive connections to Kong
- **Compression**: Gzip enabled for text responses
- **Buffering**: Optimized buffer sizes for large requests
- **Worker Configuration**: Auto-scaled based on CPU cores

### 2. Security Features
- **Rate Limiting**: Zone-based rate limiting per IP
- **Security Headers**: 
  - X-Content-Type-Options: nosniff
  - X-Frame-Options: DENY
  - X-XSS-Protection: 1; mode=block
- **Request Size Limit**: 100MB for Claude API payloads
- **Version Hiding**: Server tokens disabled

### 3. Observability Strategy
- **Structured Logging**: JSON format with request tracking
- **Request IDs**: Generated or forwarded for tracing
- **Metrics Collection**: Basic Prometheus metrics
- **Log Rotation**: Via Docker logging driver
- **Access Patterns**: Separate logs for different endpoints

### 4. High Availability
- **Health Checks**: Multiple granularity levels
- **Graceful Degradation**: Error pages for backend failures
- **Connection Limits**: Prevents resource exhaustion
- **Timeout Management**: Appropriate for each service type

## Configuration Management

### Environment Variables
- `TZ`: Timezone setting (Asia/Seoul)
- Container-level settings via docker-compose

### Volume Mounts
- `/etc/nginx/nginx.conf`: Main configuration (read-only)
- `/etc/nginx/conf.d/`: Additional configs (read-only)
- `/usr/share/nginx/html/`: Static error pages
- `/var/log/nginx/`: Log storage (persistent volume)

## Integration Points

### 1. Kong Gateway
- **Upstream**: kong:8000
- **Health Check**: kong:8001/status
- **Connection**: HTTP/1.1 with keepalive
- **Failover**: 3 attempts with 30s timeout

### 2. Docker Network
- **Network**: kong-net (external)
- **Service Discovery**: Docker DNS
- **Port Exposure**: 8082 (main), 9090 (monitoring)

### 3. Logging Infrastructure
- **Driver**: json-file
- **Rotation**: 10MB max size, 3 files
- **Format**: Structured JSON with trace IDs

## API Evolution Strategy

### Versioning
- Path-based versioning for Claude API (/v1/)
- Header-based versioning support ready
- Backward compatibility through proxy rules

### Extension Points
1. Additional upstream servers in upstream block
2. New location blocks for service endpoints  
3. Custom Lua scripts for advanced logic
4. Metric exporters for monitoring systems

### Migration Path
- Gradual traffic shift using weighted upstreams
- A/B testing through header-based routing
- Canary deployments with percentage splits

## Performance Targets

- **Latency**: < 5ms proxy overhead
- **Throughput**: 1000+ req/s per instance
- **Availability**: 99.9% uptime target
- **Error Rate**: < 0.1% proxy errors

## Security Considerations

1. **API Key Protection**: Keys never logged
2. **Request Validation**: Size and rate limits
3. **Error Handling**: Generic error messages
4. **Access Control**: Network-level restrictions
5. **TLS Termination**: Ready for HTTPS configuration