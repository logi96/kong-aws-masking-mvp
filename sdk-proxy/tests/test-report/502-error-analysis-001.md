# 502 Bad Gateway Error Analysis Report

**Date**: 2025-07-27
**Test Type**: SDK Proxy Connection Analysis
**Issue**: 502 Bad Gateway errors when connecting to Claude API

## Executive Summary

The SDK proxy tests are failing with 502 Bad Gateway errors due to SSL/TLS handshake failures between nginx proxy and Claude API servers. The root cause is missing SNI (Server Name Indication) configuration and incompatible TLS settings.

## Error Analysis

### 1. Primary Error Pattern
```
SSL_do_handshake() failed (SSL: error:0A000410:SSL routines::ssl/tls alert handshake failure:SSL alert number 40)
```

**Interpretation**: The Claude API server is rejecting the SSL handshake because:
- No SNI hostname is being sent
- TLS protocol version mismatch
- Missing required cipher suites

### 2. Secondary Error Pattern
```
connect() to [2607:6bc0::10]:443 failed (101: Network unreachable)
```

**Interpretation**: IPv6 connectivity issues in Docker environment

### 3. Cascade Failure
```
no live upstreams while connecting to upstream
```

**Interpretation**: All upstream servers marked as unavailable after initial failures

## Root Causes

### 1. **Missing SNI Configuration**
- nginx was not sending the hostname in TLS handshake
- Claude API requires SNI for proper SSL negotiation
- Fix: Add `proxy_ssl_server_name on` and `proxy_ssl_name api.anthropic.com`

### 2. **DNS Resolution Issues**
- No explicit DNS resolver configured
- IPv6 addresses being returned but not reachable
- Fix: Add explicit DNS resolver and force IPv4

### 3. **Incompatible SSL/TLS Settings**
- Generic cipher suite not compatible with Claude API
- Missing HTTP/1.1 keep-alive configuration
- Fix: Update cipher suite and HTTP version settings

## Failed Test Results

| Test Method | Result | Error Type |
|-------------|--------|------------|
| Direct Connection | ✅ Pass | Blocked as expected |
| ProxyAgent | ❌ Fail | Connection error |
| Environment Variable | ❌ Fail | 502 Bad Gateway |
| Custom Fetch | ❌ Fail | 502 Bad Gateway |

## Solution Implementation

### nginx.conf Changes
```nginx
# Critical additions:
resolver 8.8.8.8 8.8.4.4 valid=300s;
proxy_ssl_server_name on;
proxy_ssl_name api.anthropic.com;
proxy_http_version 1.1;
set $backend "api.anthropic.com:443";
proxy_pass https://$backend;
```

### Applied Fixes
1. **DNS Resolver**: Added Google DNS for reliable resolution
2. **SNI Support**: Enabled server name indication
3. **Force IPv4**: Use variable to force IPv4 resolution
4. **HTTP/1.1**: Enable persistent connections
5. **Updated Ciphers**: Match Claude API requirements

## Verification Steps

1. Apply fixed configuration:
   ```bash
   ./fix-502-error.sh
   ```

2. Monitor nginx error logs:
   ```bash
   docker logs -f sdk-test-proxy
   ```

3. Check test results:
   ```bash
   cat results/test-results.json | jq '.summary'
   ```

## Expected Outcomes

After applying fixes:
- ProxyAgent test should succeed
- Environment variable test should succeed
- Custom fetch test should succeed
- No 502 errors in logs
- SSL handshake should complete successfully

## Monitoring Recommendations

1. **Real-time Log Monitoring**:
   ```bash
   tail -f results/logs/claude_errors.log
   ```

2. **Connection Verification**:
   ```bash
   curl -v http://localhost:8888/proxy-status
   ```

3. **SSL Debug**:
   ```bash
   openssl s_client -connect api.anthropic.com:443 -servername api.anthropic.com
   ```

## Conclusion

The 502 errors were caused by improper SSL/TLS configuration in the nginx proxy. The primary issue was the missing SNI header, which is required by modern API services like Claude. The provided fixes address all identified issues and should restore full proxy functionality.