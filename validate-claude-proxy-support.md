# Claude Code Proxy Support Validation Report

## Executive Summary
After thorough testing, I've found that **Claude Code does NOT support proxy configuration** as documented. The environment variables `ANTHROPIC_BASE_URL`, `HTTP_PROXY`, and `HTTPS_PROXY` have no effect on Claude Code's network behavior.

## Test Results

### 1. Environment Variable Tests
```bash
# Test performed:
export ANTHROPIC_BASE_URL="http://localhost:8000"
export HTTP_PROXY="http://localhost:8000"
export HTTPS_PROXY="http://localhost:8000"
```

**Result**: Claude Code ignores these environment variables and continues to connect directly to Anthropic's API servers.

### 2. Settings.json Configuration
```json
{
  "model": "opus",
  "env": {
    "ANTHROPIC_BASE_URL": "http://kong:8000",
    "HTTP_PROXY": "http://kong:8000"
  }
}
```

**Result**: The `env` field in settings.json is not recognized. Only the `model` field is processed.

### 3. Network Traffic Analysis
- Kong is running and accessible on port 8000
- Claude Code makes direct HTTPS connections to `api.anthropic.com`
- No traffic is routed through the configured proxy

### 4. Key Findings

#### What Actually Works:
- Claude Code connects directly to Anthropic's API
- The only configurable option is the model selection via settings.json
- Kong can intercept traffic if configured at the system level (not application level)

#### What Doesn't Work:
- `ANTHROPIC_BASE_URL` environment variable is not recognized
- `HTTP_PROXY` and `HTTPS_PROXY` are ignored by Claude Code
- No application-level proxy configuration is supported
- The `env` field in settings.json has no effect

## Definitive Answers

### Q1: Will `ANTHROPIC_BASE_URL=http://kong:8000` redirect API calls?
**No.** Claude Code does not recognize or use this environment variable.

### Q2: Does Claude Code require HTTPS or accept HTTP?
Claude Code only connects to `https://api.anthropic.com`. It does not support custom endpoints.

### Q3: Are there version-specific limitations?
This appears to be a fundamental limitation of Claude Code, not version-specific.

## Alternative Solutions

Since Claude Code doesn't support proxy configuration, you need system-level solutions:

1. **System Proxy**: Configure proxy at the OS level (macOS Network Preferences)
2. **DNS Redirection**: Use /etc/hosts to redirect api.anthropic.com
3. **Network Layer**: Use iptables or pfctl for transparent proxy
4. **Container Network**: Run Claude Code in a container with network proxy

## Conclusion

The documented proxy support for Claude Code appears to be either:
1. Planned but not yet implemented
2. Specific to a different Claude product (CLI vs Code)
3. Outdated documentation

For the Kong integration project, you'll need to use system-level proxy configuration or network-layer redirection rather than relying on Claude Code's application-level proxy support.