# Alternative Proxy Solutions Analysis for HTTPS Interception and Masking

## Executive Summary

This report analyzes alternative proxy solutions for intercepting Claude Code's HTTPS traffic to mask AWS resource IDs before sending to Claude API. After evaluating 6 different approaches, **mitmproxy** emerges as the most suitable solution, followed by HAProxy as a production-ready alternative.

## Solution Comparison Matrix

| Solution | Technical Feasibility | Security Risk | Implementation Complexity | Production Ready | Recommendation Score |
|----------|---------------------|---------------|-------------------------|------------------|-------------------|
| **mitmproxy** | 9/10 | Medium | Low-Medium | Yes | 9/10 |
| **HAProxy** | 8/10 | Low | Medium | Yes | 8/10 |
| **Squid (SSL Bump)** | 7/10 | High | High | Yes | 6/10 |
| **Envoy Proxy** | 8/10 | Low | High | Yes | 7/10 |
| **NGINX + njs** | 7/10 | Low | Medium | Yes | 7/10 |
| **Service Mesh (Istio)** | 6/10 | Low | Very High | Yes | 5/10 |

## Detailed Analysis

### 1. mitmproxy - **RECOMMENDED SOLUTION**

#### Overview
- **Type**: Specialized HTTPS interception proxy with programmatic API
- **Latest Version**: 11 (2024) with HTTP/3 support
- **Primary Use**: Development, testing, and API modification

#### Technical Capabilities
- **SSL/TLS Interception**: ✅ Full HTTPS decryption and re-encryption
- **Content Modification**: ✅ Python API for request/response manipulation
- **Integration**: ✅ Can run as transparent proxy or reverse proxy
- **Performance**: Good for moderate traffic loads

#### Implementation Example
```python
from mitmproxy import http

def request(flow: http.HTTPFlow):
    # Intercept requests to Claude API
    if "api.anthropic.com" in flow.request.host:
        # Mask AWS resources in request body
        body = flow.request.get_text()
        masked_body = mask_aws_resources(body)
        flow.request.set_text(masked_body)

def response(flow: http.HTTPFlow):
    # Unmask resources in response
    if "api.anthropic.com" in flow.request.host:
        body = flow.response.get_text()
        unmasked_body = unmask_aws_resources(body)
        flow.response.set_text(unmasked_body)
```

#### Pros
- Purpose-built for HTTPS interception
- Excellent programmatic API
- Active development (v11 in 2024)
- Docker-ready deployment
- Minimal configuration needed

#### Cons
- Certificate installation required on client
- Not designed for high-volume production traffic
- Python-based (potential performance limitations)

#### Security Considerations
- Requires CA certificate installation on Claude Code's system
- All HTTPS traffic will be decrypted (privacy implications)
- Should run in isolated environment

---

### 2. HAProxy - **PRODUCTION ALTERNATIVE**

#### Overview
- **Type**: High-performance load balancer with SSL termination
- **Primary Use**: Production traffic management and SSL offloading

#### Technical Capabilities
- **SSL/TLS Termination**: ✅ Decrypt at proxy, re-encrypt to backend
- **Content Modification**: ✅ HTTP header manipulation, limited body modification
- **Integration**: ✅ Works well with Kong Gateway
- **Performance**: Excellent, handles millions of requests

#### Implementation Approach
```
Client → HAProxy (SSL termination) → Content Modification → HAProxy (SSL re-encryption) → Claude API
```

#### Configuration Example
```haproxy
frontend https_frontend
    bind *:443 ssl crt /etc/haproxy/certs/
    mode http
    
    # Capture and modify requests
    http-request set-header X-Original-Body %[req.body]
    http-request lua.mask_aws_resources
    
backend claude_backend
    mode http
    server claude api.anthropic.com:443 ssl verify required
```

#### Pros
- Production-grade performance
- Mature and stable
- Native SSL termination/re-encryption
- Can integrate with Lua scripts for content modification
- No client certificate needed if used as reverse proxy

#### Cons
- Limited request body modification capabilities
- Requires Lua scripting for complex transformations
- More complex configuration than mitmproxy

---

### 3. Squid Proxy with SSL Bump

#### Overview
- **Type**: Traditional caching proxy with SSL interception capabilities
- **Feature**: SSL Bump for HTTPS inspection

#### Technical Capabilities
- **SSL/TLS Interception**: ✅ Via SSL Bump feature
- **Content Modification**: ⚠️ Limited, requires ICAP server or external adapters
- **Performance**: Good for caching scenarios

#### Challenges
- Complex certificate management
- HSTS and certificate pinning issues
- High security risk due to certificate warnings
- Limited content modification without external tools

#### Recommendation
Not recommended due to complexity and limited content modification capabilities.

---

### 4. Envoy Proxy

#### Overview
- **Type**: Modern cloud-native proxy with extensive filter system
- **Primary Use**: Service mesh and API gateway scenarios

#### Technical Capabilities
- **SSL/TLS**: ✅ Full termination and re-encryption support
- **Content Modification**: ✅ Via HTTP filter chain
- **Integration**: ✅ Works well in Kubernetes environments

#### Implementation Complexity
- Requires understanding of Envoy's filter chain architecture
- Configuration is verbose and complex
- Better suited for service mesh scenarios

#### Recommendation
Good option if already using Envoy/Istio, otherwise overly complex for this use case.

---

### 5. NGINX with njs Module

#### Overview
- **Type**: Web server/proxy with JavaScript scripting
- **Feature**: njs module for dynamic content handling

#### Technical Capabilities
- **SSL/TLS**: ✅ Native SSL termination
- **Content Modification**: ✅ Via JavaScript handlers
- **Performance**: Excellent

#### Limitations
- njs has limited JavaScript API compared to full Node.js
- Request body modification can be complex
- Better suited for header manipulation than body transformation

---

### 6. Service Mesh Solutions (Istio/Linkerd)

#### Overview
- **Type**: Kubernetes-native traffic management
- **Primary Use**: Microservices communication

#### Assessment
- Overkill for single application proxy needs
- Requires Kubernetes environment
- High operational complexity

---

## Implementation Recommendations

### For Development/Testing: mitmproxy
```bash
# Quick setup
pip install mitmproxy
mitmdump -s mask_aws.py --mode reverse:https://api.anthropic.com@8080
```

### For Production: HAProxy with Lua
```lua
-- haproxy-aws-mask.lua
core.register_action("mask_aws", {"http-req"}, function(txn)
    local body = txn.req:dup()
    -- Implement masking logic
    txn.req:set(masked_body)
end)
```

## Security Best Practices

1. **Certificate Management**
   - Use proper CA certificates
   - Implement certificate pinning exceptions carefully
   - Rotate certificates regularly

2. **Network Isolation**
   - Run proxy in isolated network segment
   - Limit proxy access to Claude API only
   - Monitor all intercepted traffic

3. **Audit Logging**
   - Log all modifications made
   - Maintain audit trail for compliance
   - Encrypt logs containing sensitive data

## Conclusion

**mitmproxy** is the recommended solution for intercepting and modifying HTTPS traffic between Claude Code and Claude API due to:
- Purpose-built for HTTPS interception
- Excellent programmatic API for content modification
- Quick implementation with Python scripts
- Active development and modern features (HTTP/3 support)

For production environments requiring high performance and reliability, **HAProxy** with Lua scripting provides a robust alternative, though with more complex implementation requirements.

Both solutions successfully solve the core problem of inspecting and modifying HTTPS traffic that Tinyproxy cannot handle.