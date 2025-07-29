# Kong Transparent Proxy Implementation Guide

## 📋 Executive Summary

This guide provides multiple approaches to implement transparent proxy functionality in Kong Gateway, allowing Backend applications to call external APIs (e.g., api.anthropic.com) directly while Kong intercepts and processes the traffic without any Backend code modifications.

## 🎯 Goal

Enable Kong to transparently intercept Backend's direct API calls to `api.anthropic.com` and apply AWS resource masking/unmasking without modifying the Backend application code.

## 📊 Comparison of Approaches

| Approach | Complexity | Backend Changes | Pros | Cons |
|----------|------------|-----------------|------|------|
| DNS Override | Low | None | Simple, Docker-native | SSL certificate issues |
| HTTP(S) Proxy | Medium | None | Standard proxy mechanism | HTTPS tunnel limitations |
| iptables Redirect | High | None | True transparent proxy | Complex setup, Linux-specific |
| SOCKS Proxy | Medium | None | Flexible protocol support | Limited application support |

## 🔧 Implementation Methods

### Method 1: DNS Override with Docker Extra Hosts

#### Overview
Redirect DNS resolution of `api.anthropic.com` to Kong container using Docker's networking features.

#### Implementation Steps

1. **Update docker-compose.yml**
```yaml
services:
  backend:
    # ... existing configuration ...
    extra_hosts:
      - "api.anthropic.com:kong"  # Resolves to Kong container
    environment:
      NODE_TLS_REJECT_UNAUTHORIZED: "0"  # Required for SSL bypass
```

2. **Configure Kong Route**
```yaml
# kong.yml
routes:
  - name: anthropic-transparent
    service: claude-api-service
    hosts:
      - api.anthropic.com
    paths:
      - /v1/messages
    methods:
      - POST
    strip_path: false
    preserve_host: false  # Important: Kong sets correct Host header
    request_buffering: true
    response_buffering: true
    tags:
      - masking-required

plugins:
  - name: aws-masker
    route: anthropic-transparent
    config:
      use_redis: true
      mask_ec2_instances: true
      mask_s3_buckets: true
      mask_rds_instances: true
      mask_private_ips: true
```

#### Advantages
- No Backend code changes required
- Simple Docker configuration
- Works with existing Kong plugins

#### Disadvantages
- SSL certificate validation issues
- Requires disabling TLS verification (security concern)
- Only works within Docker network

### Method 2: HTTP(S) Proxy Configuration

#### Overview
Configure Backend to use Kong as an HTTP(S) proxy using standard proxy environment variables.

#### Implementation Steps

1. **Set Proxy Environment Variables**
```yaml
# docker-compose.yml
services:
  backend:
    environment:
      HTTP_PROXY: http://kong:8000
      HTTPS_PROXY: http://kong:8000
      NO_PROXY: localhost,127.0.0.1,backend,redis
```

2. **Create Kong Forward Proxy Handler**
```lua
-- kong/plugins/forward-proxy/handler.lua
local ForwardProxy = {
  VERSION = "1.0.0",
  PRIORITY = 1000,
}

function ForwardProxy:access(conf)
  local method = kong.request.get_method()
  
  -- Handle CONNECT method for HTTPS tunneling
  if method == "CONNECT" then
    -- Extract target host and port
    local target = kong.request.get_path()
    local host, port = target:match("^([^:]+):(%d+)$")
    
    if host == "api.anthropic.com" then
      -- Respond with 200 Connection Established
      kong.response.exit(200, "Connection established\r\n\r\n", {
        ["Proxy-Agent"] = "Kong/" .. kong.version
      })
      
      -- Note: Actual tunnel handling requires TCP stream module
    end
  else
    -- Handle regular HTTP requests
    local url = kong.request.get_scheme() .. "://" .. 
                kong.request.get_host() .. 
                kong.request.get_path_with_query()
    
    -- Forward to actual destination
    -- Apply masking before forwarding
  end
end

return ForwardProxy
```

3. **Configure Kong Stream Module (kong.conf)**
```nginx
# Enable stream module for TCP proxying
stream_listen = 0.0.0.0:8443 ssl
```

#### Advantages
- Uses standard HTTP proxy mechanism
- Works with any HTTP client supporting proxies
- No DNS manipulation required

#### Disadvantages
- Complex HTTPS tunnel handling
- Cannot inspect/modify encrypted HTTPS traffic
- Requires Kong stream module configuration

### Method 3: iptables Transparent Proxy

#### Overview
Use Linux netfilter/iptables to redirect outbound traffic to Kong transparently.

#### Implementation Steps

1. **Create Init Container for iptables Rules**
```yaml
# docker-compose.yml
services:
  backend:
    # ... existing configuration ...
    cap_add:
      - NET_ADMIN  # Required for iptables
    
  iptables-init:
    image: alpine:latest
    container_name: iptables-setup
    network_mode: "container:backend-api"
    cap_add:
      - NET_ADMIN
    command: |
      sh -c '
        apk add --no-cache iptables
        
        # Get Kong IP
        KONG_IP=$(getent hosts kong | awk "{ print \$1 }")
        
        # Redirect TCP traffic to api.anthropic.com:443 to Kong:8443
        iptables -t nat -A OUTPUT -p tcp -d api.anthropic.com --dport 443 \
          -j DNAT --to-destination ${KONG_IP}:8443
        
        # Mark packets to avoid loops
        iptables -t mangle -A OUTPUT -p tcp -d api.anthropic.com --dport 443 \
          -j MARK --set-mark 1
        
        # SNAT to ensure return traffic comes back
        iptables -t nat -A POSTROUTING -m mark --mark 1 \
          -j SNAT --to-source ${BACKEND_IP}
      '
```

2. **Configure Kong TCP Stream Proxy**
```lua
-- kong/plugins/tcp-interceptor/handler.lua
local TcpInterceptor = {
  VERSION = "1.0.0",
  PRIORITY = 1000,
}

function TcpInterceptor:preread(conf)
  -- This runs in stream context
  local sock = ngx.req.socket(true)
  
  -- Peek at SNI to determine target
  local data = sock:peek(1024)
  local sni = extract_sni(data)  -- Custom function to parse TLS ClientHello
  
  if sni == "api.anthropic.com" then
    -- Set up upstream
    ngx.var.upstream = "api.anthropic.com:443"
    
    -- Note: Cannot modify encrypted data here
    -- Would need SSL termination
  end
end

return TcpInterceptor
```

#### Advantages
- True transparent proxy
- No application configuration needed
- Works with any TCP/IP application

#### Disadvantages
- Complex iptables configuration
- Requires NET_ADMIN capability
- Platform-specific (Linux only)
- Still cannot decrypt HTTPS traffic

### Method 4: Kong Service Mesh with Sidecar

#### Overview
Deploy Kong as a sidecar container that intercepts all network traffic.

#### Implementation Steps

1. **Pod Configuration**
```yaml
# docker-compose.yml (simulating pod structure)
services:
  app-pod:
    image: busybox
    command: ["sleep", "3600"]
    network_mode: "container:kong-sidecar"
    
  kong-sidecar:
    image: kong:3.7
    container_name: kong-sidecar
    environment:
      KONG_DATABASE: "off"
      KONG_PROXY_LISTEN: "0.0.0.0:8443 transparent ssl"
      KONG_TRANSPARENT_LISTEN: "on"
    volumes:
      - ./kong/kong.yml:/opt/kong/kong.yml:ro
      
  backend:
    # ... existing configuration ...
    network_mode: "container:kong-sidecar"
```

2. **Configure Transparent Proxy Mode**
```yaml
# kong.yml
_format_version: "3.0"
_transform: true

upstreams:
  - name: anthropic-upstream
    targets:
      - target: api.anthropic.com:443

services:
  - name: transparent-service
    host: anthropic-upstream
    port: 443
    protocol: https

routes:
  - name: transparent-route
    service: transparent-service
    sources:
      - ip: 0.0.0.0/0  # Match all sources
    destinations:
      - ip: api.anthropic.com
        port: 443
```

#### Advantages
- True sidecar pattern
- All traffic automatically routed through Kong
- No application changes

#### Disadvantages
- Complex networking setup
- All containers must share network namespace
- Still requires SSL termination for data inspection

## 🔐 SSL/TLS Considerations

### The HTTPS Problem

All methods face the same fundamental challenge:
- HTTPS traffic is encrypted end-to-end
- To inspect/modify data, Kong must terminate SSL
- This creates a man-in-the-middle scenario

### Solutions

1. **SSL Termination at Kong**
```nginx
# Generate Kong certificate that mimics api.anthropic.com
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout kong-anthropic.key \
  -out kong-anthropic.crt \
  -subj "/CN=api.anthropic.com"

# Configure Kong to use this certificate
ssl_cert = /etc/kong/certs/kong-anthropic.crt
ssl_cert_key = /etc/kong/certs/kong-anthropic.key
```

2. **Disable Certificate Verification in Backend**
```javascript
// Not recommended for production
process.env["NODE_TLS_REJECT_UNAUTHORIZED"] = 0;
```

3. **Custom CA Certificate**
```bash
# Add Kong's CA to Backend's trust store
cat kong-ca.crt >> /etc/ssl/certs/ca-certificates.crt
update-ca-certificates
```

## 📈 Performance Considerations

| Method | Latency Impact | CPU Overhead | Memory Usage |
|--------|----------------|--------------|--------------|
| DNS Override | Minimal | Low | Low |
| HTTP Proxy | +5-10ms | Medium | Medium |
| iptables | +1-2ms | Low | Low |
| Sidecar | +2-5ms | Medium | High |

## 🚨 Security Implications

### Risks
1. **SSL Certificate Validation Bypass**
   - Disabling certificate checks opens MITM attacks
   - Should only be used in controlled environments

2. **Data Exposure**
   - Decrypted traffic visible to Kong
   - Ensure proper access controls

3. **Network Isolation**
   - Transparent proxy can intercept all traffic
   - Implement proper network segmentation

### Mitigations
1. Use mutual TLS between Kong and Backend
2. Implement strict network policies
3. Enable audit logging for all intercepted traffic
4. Use encrypted storage for sensitive data

## 🎯 Recommended Approach

For most use cases, **DNS Override with Extra Hosts** provides the best balance of:
- Simplicity
- Maintainability  
- Compatibility

Combined with proper SSL certificate management, this approach can provide transparent proxy functionality without Backend modifications.

## 📚 Additional Resources

- [Kong Gateway Documentation](https://docs.konghq.com/)
- [Docker Networking Guide](https://docs.docker.com/network/)
- [iptables Tutorial](https://www.netfilter.org/documentation/)
- [SSL/TLS Best Practices](https://wiki.mozilla.org/Security/Server_Side_TLS)

## 🔧 Troubleshooting

### Common Issues

1. **SSL Certificate Errors**
```bash
# Check certificate details
openssl s_client -connect kong:8443 -servername api.anthropic.com

# Verify Kong is responding
curl -k https://kong:8443/v1/messages
```

2. **DNS Resolution Issues**
```bash
# Inside Backend container
nslookup api.anthropic.com
ping api.anthropic.com

# Check extra_hosts
docker exec backend-api cat /etc/hosts
```

3. **iptables Rules Not Working**
```bash
# List current rules
docker exec backend-api iptables -t nat -L -n -v

# Check packet counts
docker exec backend-api iptables -t nat -L OUTPUT -n -v
```

## 📝 Conclusion

While implementing a true transparent proxy for HTTPS traffic presents significant challenges, the approaches outlined in this guide provide viable solutions for intercepting and processing API traffic without modifying Backend applications. Choose the method that best fits your security requirements and operational constraints.