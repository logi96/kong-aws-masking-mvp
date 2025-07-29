# Kong Gateway Configuration

This directory contains the Kong Gateway configuration files and plugins for the Kong AWS Masking MVP project. Kong operates in **DB-less declarative mode** to provide API Gateway functionality with custom AWS resource masking capabilities.

## 📋 Directory Structure

```
kong/
├── kong.yml                 # Main declarative configuration
├── kong-backup.yml          # Backup configuration
├── kong-simple.yml          # Simplified configuration for testing
├── kong-test.yml           # Test environment configuration
├── kong-test.yml.bak       # Test configuration backup
└── plugins/
    └── aws-masker/         # Custom AWS masking plugin
```

## 🚀 Kong Gateway Overview

### DB-less Declarative Mode
Kong Gateway operates in **DB-less mode** using declarative configuration files. This approach provides:

- **Zero Database Dependencies**: Configuration stored in YAML files
- **Version Control Integration**: All configurations tracked in Git
- **Immutable Deployments**: Consistent configuration across environments
- **Faster Startup**: No database connection required
- **Enhanced Security**: Reduced attack surface with no database

### Core Architecture
```
Backend API (Port 3000) → Kong Gateway (Port 8000) → Claude API
                            ↓
                      AWS Masking Plugin
                      (Masks sensitive data)
```

## ⚙️ Configuration Files

### `kong.yml` - Main Configuration
The primary declarative configuration file containing:
- **Services**: Claude API service definition with timeout settings
- **Routes**: API routing rules for `/analyze-claude` endpoint
- **Plugins**: AWS masking plugin configuration
- **Security**: CORS, authentication, and rate limiting settings

### `kong-backup.yml` - Backup Configuration
Production-ready backup configuration for emergency rollback scenarios.

### `kong-simple.yml` - Simplified Configuration
Minimal configuration for development and testing purposes with reduced complexity.

### `kong-test.yml` - Test Configuration
Specialized configuration optimized for testing environments with enhanced logging and debugging features.

## 🔌 Custom Plugins

### AWS Masker Plugin
The core functionality of this Kong deployment is provided by the custom **aws-masker** plugin located in `plugins/aws-masker/`.

**⚠️ IMPORTANT**: For complete technical documentation, implementation details, and usage guidelines, please refer to:

**📚 [AWS Masker Plugin Documentation](./plugins/aws-masker/docs/README.md)**

The plugin documentation provides comprehensive coverage of:
- Technical implementation details
- Source code changes and improvements
- Configuration guidelines
- Performance benchmarks and security validation
- Troubleshooting and maintenance procedures

## 🏗️ Plugin Directory Structure

```
plugins/aws-masker/
├── docs/                   # 📚 Complete technical documentation
├── infra/                  # 🏗️ Infrastructure configuration
├── spec/                   # 🧪 Test specifications
├── backup/                 # 💾 Backup files
├── handler.lua            # 🔧 Main plugin handler
├── patterns.lua           # 🎯 AWS resource patterns
├── masker_ngx_re.lua      # 🔒 Masking engine
└── schema.lua             # 📋 Configuration schema
```

## 🚦 Getting Started

### Prerequisites
- Kong Gateway 3.9.0.1+
- Docker and Docker Compose
- Valid Anthropic API key

### Quick Start
1. **Configuration**: Review and customize `kong.yml` for your environment
2. **Environment Variables**: Set required API keys and configuration
3. **Deploy**: Use Docker Compose to start Kong Gateway
4. **Verify**: Check plugin functionality with health checks

### Configuration Management
```bash
# Validate configuration
kong config parse kong.yml

# Apply configuration (DB-less mode)
kong start -c kong.conf --declarative-config kong.yml

# Hot reload configuration
kong reload --prefix /usr/local/kong
```

## 🔍 Monitoring and Troubleshooting

### Health Checks
- **Kong Admin API**: `http://localhost:8001/status`
- **Plugin Status**: `http://localhost:8001/plugins`
- **Service Status**: `http://localhost:8001/services`

### Log Locations
- **Kong Logs**: Docker container logs via `docker logs kong`
- **Plugin Logs**: Integrated with Kong's logging system
- **Access Logs**: Available through Kong Admin API

## 🛡️ Security Considerations

### Production Deployment
- **Admin API Security**: Restrict access to Kong Admin API in production
- **Plugin Configuration**: Review plugin security settings
- **Network Security**: Implement proper network segmentation
- **Certificate Management**: Use proper TLS certificates

### Security Features
- **Request/Response Masking**: Automatic AWS resource masking
- **Fail-Safe Operation**: Secure defaults when masking fails
- **Audit Logging**: Complete request/response logging
- **Rate Limiting**: Built-in protection against abuse

## 📚 Additional Resources

- **Project Documentation**: [../README.md](../README.md)
- **Infrastructure Guide**: [../README-INFRA.md](../README-INFRA.md)
- **Security Guidelines**: [../SECURITY-GUIDELINES.md](../SECURITY-GUIDELINES.md)
- **Scripts**: [../scripts/README.md](../scripts/README.md)

## 🔗 Related Links

- [Kong Gateway Documentation](https://docs.konghq.com/gateway/)
- [Kong DB-less Mode Guide](https://docs.konghq.com/gateway/latest/production/deployment-topologies/db-less-and-declarative-config/)
- [Kong Plugin Development](https://docs.konghq.com/gateway/latest/plugin-development/)

---

*For detailed AWS masking plugin implementation, technical specifications, and troubleshooting guides, always refer to [plugins/aws-masker/docs/README.md](./plugins/aws-masker/docs/README.md).*