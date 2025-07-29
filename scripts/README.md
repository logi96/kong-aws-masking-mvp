# Scripts Directory

This directory contains operational scripts for the Kong AWS Masking MVP project. These scripts handle environment setup, monitoring, logging, and emergency operations.

## 📋 Available Scripts

### 🚀 Environment Management

#### **setup.sh**
- **Purpose**: Initial development environment setup from scratch
- **Usage**: `./setup.sh`
- **Features**:
  - Environment file configuration
  - Docker compose setup
  - Service dependency verification
  - Development environment initialization

#### **reset.sh**
- **Purpose**: Complete development environment reset
- **Usage**: `./reset.sh`
- **Features**:
  - Stops all Docker containers
  - Removes containers and volumes
  - Cleans temporary files
  - Resets to clean state

### 🔍 Monitoring & Health

#### **health-check.sh**
- **Purpose**: Comprehensive system health validation
- **Usage**: `./health-check.sh`
- **Features**:
  - Kong Gateway status check (Admin API: 8001, Proxy: 8000)
  - Backend API health check (Port: 3000)
  - Service connectivity validation
  - Component health reports
  - Retry logic with timeout handling

#### **logs.sh**
- **Purpose**: Log aggregation and management
- **Usage**: `./logs.sh [service]`
- **Features**:
  - Real-time log streaming
  - Service-specific log filtering
  - Log file management
  - Docker container log access

### 🚨 Emergency Operations

#### **emergency-rollback.sh**
- **Purpose**: Critical emergency rollback execution
- **Usage**: `./emergency-rollback.sh "reason"`
- **Features**:
  - Immediate Kong plugin deactivation
  - Traffic routing bypass
  - Previous version restoration
  - Kong service restart
  - Emergency logging

#### **auto-rollback-monitor.sh**
- **Purpose**: Automated monitoring with rollback triggers
- **Usage**: `./auto-rollback-monitor.sh` (background process)
- **Features**:
  - Error rate monitoring (threshold: 1%)
  - Latency monitoring (threshold: 100ms)
  - Memory usage monitoring (threshold: 95%)
  - Automatic emergency rollback triggering
  - Continuous health surveillance

## 🔧 Usage Examples

### Development Setup
```bash
# Initial setup
./scripts/setup.sh

# Check system health
./scripts/health-check.sh

# View logs
./scripts/logs.sh

# Reset environment
./scripts/reset.sh
```

### Production Operations
```bash
# Emergency rollback
./scripts/emergency-rollback.sh "High error rate detected"

# Start monitoring (background)
nohup ./scripts/auto-rollback-monitor.sh &
```

## 📊 Script Dependencies

### Common Dependencies
- **Docker & Docker Compose**: Container orchestration
- **curl**: HTTP health checks and API calls
- **jq**: JSON processing (for health checks)
- **bash 4.0+**: Advanced shell features

### Service Endpoints
- **Kong Admin API**: `http://localhost:8001`
- **Kong Proxy**: `http://localhost:8000`
- **Backend API**: `http://localhost:3000`
- **Monitoring**: `http://localhost:9090/metrics`

## 🛡️ Security Considerations

- All scripts include error handling with `set -euo pipefail`
- Emergency rollback scripts have priority execution
- Health checks include timeout protection
- Log scripts filter sensitive information
- Monitoring thresholds prevent false positives

## 📝 Maintenance

### Adding New Scripts
1. Follow existing naming conventions
2. Include comprehensive error handling
3. Add logging functions with color output
4. Update this README with script documentation
5. Test scripts in isolation before integration

### Script Standards
- Use readonly variables for configuration
- Include usage documentation in script headers
- Implement retry logic for network operations
- Provide clear success/failure indicators
- Log all critical operations

## 🔗 Related Documentation

- [Project README](../README.md) - Main project documentation
- [Infrastructure Guide](../README-INFRA.md) - Infrastructure setup
- [Security Guidelines](../SECURITY-GUIDELINES.md) - Security best practices
- [CLAUDE.md](../CLAUDE.md) - Development guidelines