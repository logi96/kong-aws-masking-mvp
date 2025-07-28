# Nginx Reverse Proxy for Kong Gateway

This directory contains the Nginx reverse proxy configuration that sits in front of Kong Gateway, providing additional security, monitoring, and traffic management capabilities.

## Architecture

```
Client → Nginx (8082) → Kong (8000) → Claude API
              ↓
        Monitoring (9090)
```

## Features

### 1. **Security Enhancement**
- Rate limiting (10 req/s for Claude API, configurable burst)
- Security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection)
- Request size limits (100MB for Claude API payloads)
- CORS handling with preflight support

### 2. **Observability**
- Structured JSON logging with request tracing
- Prometheus-compatible metrics endpoint
- Health checks with dependency status
- Request ID generation and forwarding
- Detailed access logs with upstream timing

### 3. **Performance Optimization**
- Connection pooling to Kong backend
- Gzip compression for responses
- Optimized buffer sizes
- Keep-alive connections
- Worker auto-scaling based on CPU cores

### 4. **High Availability**
- Health check endpoints at multiple levels
- Graceful error handling with custom error pages
- Automatic retry with configurable timeouts
- Circuit breaker pattern for backend failures

## Directory Structure

```
nginx/
├── Dockerfile              # Alpine-based Nginx image
├── nginx.conf             # Main Nginx configuration
├── conf.d/                # Additional configurations
│   ├── claude-proxy.conf  # Main proxy configuration
│   ├── monitoring.conf    # Monitoring endpoints
│   └── production.conf    # Production overrides (if any)
├── html/                  # Static files
│   ├── 40x.json          # Client error response
│   └── 50x.json          # Server error response
├── deploy.sh             # Deployment script
├── test-nginx-proxy.sh   # Comprehensive test suite
└── API-DESIGN.md         # Detailed API design document
```

## Quick Start

### 1. Deploy Nginx Proxy

```bash
# Deploy using the provided script
./deploy.sh

# Or manually with docker-compose
docker-compose -f docker-compose.nginx.yml up -d
```

### 2. Verify Health

```bash
# Check basic health
curl http://localhost:8082/health

# Check full health with dependencies
curl http://localhost:8082/health/full | jq .

# View metrics
curl http://localhost:8082/metrics
```

### 3. Run Tests

```bash
# Run comprehensive test suite
./test-nginx-proxy.sh

# Check test report
ls -la ../tests/test-report/nginx-proxy-test-*.md
```

## Configuration

### Environment Variables

Configure in `docker-compose.yml` or `.env`:

```bash
NGINX_PROXY_PORT=8082          # Main proxy port
NGINX_WORKER_PROCESSES=auto    # Number of worker processes
NGINX_WORKER_CONNECTIONS=1024  # Connections per worker
TZ=Asia/Seoul                  # Timezone
```

### Rate Limiting

Adjust in `conf.d/claude-proxy.conf`:

```nginx
limit_req_zone $binary_remote_addr zone=claude_api:10m rate=10r/s;
```

### Upstream Configuration

Kong backend in `conf.d/claude-proxy.conf`:

```nginx
upstream kong_backend {
    server kong:8000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
```

## API Endpoints

### Health & Monitoring

| Endpoint | Port | Description |
|----------|------|-------------|
| `/health` | 8082 | Basic health check |
| `/health/full` | 9090 | Full health with dependencies |
| `/metrics` | 8082/9090 | Prometheus metrics |
| `/nginx_status` | 8082 | Nginx stub status |

### Proxied Services

| Endpoint | Description | Rate Limit |
|----------|-------------|------------|
| `/v1/messages` | Claude API proxy | 10 req/s, burst 20 |
| `/analyze` | AWS analysis proxy | 10 req/s, burst 10 |

## Monitoring

### Logs

All logs are in JSON format for easy parsing:

```bash
# View access logs
docker logs nginx-proxy | jq .

# View specific endpoint logs
docker exec nginx-proxy tail -f /var/log/nginx/claude-proxy-access.log | jq .
```

### Metrics

Prometheus-compatible metrics available at `/metrics`:

- `nginx_http_requests_total` - Total requests by status
- `nginx_http_request_duration_seconds` - Request latency histogram
- `nginx_up` - Nginx availability
- `nginx_connections_current` - Current connections by state

### Request Tracing

Every request gets a unique ID for tracing:
- Generated if not provided in `X-Request-ID` header
- Forwarded to upstream services
- Included in all log entries

## Troubleshooting

### Common Issues

1. **502 Bad Gateway**
   - Check if Kong is healthy: `curl http://localhost:8001/status`
   - Verify network connectivity: `docker network inspect kong-net`

2. **Rate Limiting (429)**
   - Check current limits: `grep limit_req conf.d/claude-proxy.conf`
   - Monitor rate limit hits in logs

3. **Connection Refused**
   - Verify Nginx is running: `docker ps | grep nginx-proxy`
   - Check port binding: `netstat -tlnp | grep 8082`

### Debug Commands

```bash
# Check Nginx configuration
docker exec nginx-proxy nginx -t

# View error logs
docker exec nginx-proxy tail -f /var/log/nginx/error.log

# Test upstream connectivity
docker exec nginx-proxy curl -v http://kong:8000/status

# Check resource usage
docker stats nginx-proxy
```

## Performance Tuning

### Worker Processes
```nginx
worker_processes auto;  # Uses CPU core count
worker_rlimit_nofile 65535;  # Max file descriptors
```

### Connection Handling
```nginx
events {
    worker_connections 4096;  # Per worker
    use epoll;  # Efficient on Linux
    multi_accept on;  # Accept multiple connections
}
```

### Buffering
```nginx
proxy_buffering on;
proxy_buffer_size 4k;
proxy_buffers 8 4k;
proxy_busy_buffers_size 8k;
```

## Security Best Practices

1. **Headers**: All security headers are automatically added
2. **Rate Limiting**: Protects backend services from abuse
3. **Request Validation**: Size limits prevent DoS attacks
4. **Error Handling**: Generic error messages prevent information leakage
5. **Access Control**: Internal endpoints restricted by IP

## Integration with CI/CD

The Nginx proxy can be integrated into your deployment pipeline:

```yaml
# Example GitHub Actions step
- name: Deploy Nginx Proxy
  run: |
    cd nginx
    ./deploy.sh
    ./test-nginx-proxy.sh
```

## Maintenance

### Log Rotation

Logs are automatically rotated by Docker:
```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

### Updates

To update Nginx configuration:
1. Modify configuration files
2. Validate: `docker run --rm -v $PWD/nginx.conf:/etc/nginx/nginx.conf nginx:1.27-alpine nginx -t`
3. Reload: `docker-compose -f docker-compose.nginx.yml restart`

### Backup

Important files to backup:
- `nginx.conf` - Main configuration
- `conf.d/*.conf` - Additional configurations
- Docker volumes for logs (if needed)