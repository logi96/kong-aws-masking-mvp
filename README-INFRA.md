# Kong AWS Masking MVP - Infrastructure Guide

This document provides infrastructure setup and management instructions for the Kong AWS Masking MVP project.

## 📋 Overview

This infrastructure provides a complete Docker-based environment for running:
- Kong Gateway (DB-less mode) with custom AWS masking plugin
- Backend API server (Node.js) for AWS CLI integration
- Development and production configurations

## 🚀 Quick Start

### Prerequisites
- Docker Engine 20.10+ and Docker Compose 3.8+
- Node.js 20.x LTS (for local development)
- AWS CLI v2 (will be installed in containers)
- Valid AWS credentials and Anthropic API key

### Environment Setup

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Configure required environment variables**:
   ```bash
   # Edit .env file with your credentials
   ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
   AWS_REGION=us-east-1
   ```

3. **Start the infrastructure**:
   ```bash
   docker-compose up --build
   ```

## 🏗️ Project Structure

```
kong-aws-masking-mvp/
├── docker/                 # Docker configuration files
│   ├── kong/              # Kong Gateway Dockerfile
│   │   └── Dockerfile
│   └── backend/           # Backend API Dockerfile
│       └── Dockerfile
├── kong/                  # Kong Gateway files
│   ├── kong.yml          # Declarative configuration
│   └── plugins/          # Custom plugins directory
│       └── aws-masker/   # AWS masking plugin
├── backend/               # Backend API files
│   ├── environments/     # Environment configurations
│   └── server.js         # Main API server
├── scripts/              # Utility scripts
│   ├── setup.sh          # Initial setup script
│   ├── reset.sh          # Environment reset
│   ├── health-check.sh   # Health verification
│   ├── logs.sh           # Log aggregation
│   └── test-infra.sh     # Infrastructure tests
├── .docker/              # Docker runtime data
│   └── volumes/          # Persistent volumes
└── docker-compose.yml    # Container orchestration

```

## 🔧 Configuration

### Docker Compose Services

#### Kong Gateway
- **Ports**: 8000 (proxy), 8001 (admin API)
- **Mode**: DB-less (declarative configuration)
- **Version**: 3.9.0.1
- **Resources**: 512MB memory, 0.5 CPU

#### Backend API
- **Port**: 3000
- **Runtime**: Node.js 20 Alpine
- **Features**: Hot reload with nodemon
- **Resources**: 256MB memory, 0.25 CPU

### Network Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────▶│    Kong     │────▶│   Backend   │
│             │     │  Gateway    │     │     API     │
└─────────────┘     └─────────────┘     └─────────────┘
                          │                     │
                          ▼                     ▼
                    AWS Masking           AWS CLI/Claude
                      Plugin
```

## 📝 Development Workflow

### Starting Development Environment
```bash
# Start with live reload
docker-compose up

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f [service-name]
```

### Making Changes

#### Kong Configuration
1. Edit `kong/kong.yml`
2. Restart Kong: `docker-compose restart kong`

#### Kong Plugin Development
1. Edit plugin files in `kong/plugins/aws-masker/`
2. Kong auto-reloads plugins in development mode

#### Backend Development
1. Edit files in `backend/`
2. Nodemon auto-reloads on file changes

### Testing Infrastructure
```bash
# Run infrastructure tests
./scripts/test-infra.sh

# Health check all services
./scripts/health-check.sh

# Check specific service
curl http://localhost:8001/status  # Kong
curl http://localhost:3000/health  # Backend
```

## 🔒 Security Considerations

1. **AWS Credentials**: Mounted read-only at runtime
2. **Non-root Containers**: All services run as non-root users
3. **Network Isolation**: Backend network is internal-only
4. **Environment Variables**: Sensitive data never in images
5. **Resource Limits**: Prevent resource exhaustion

## 🛠️ Utility Scripts

### setup.sh
Initial environment setup and validation
```bash
./scripts/setup.sh
```

### reset.sh
Clean environment and volumes
```bash
./scripts/reset.sh
```

### logs.sh
Aggregate logs from all services
```bash
./scripts/logs.sh [--follow] [service-name]
```

### test-infra.sh
Run infrastructure validation tests
```bash
./scripts/test-infra.sh
```

## 📊 Monitoring

### Health Endpoints
- Kong Admin: `http://localhost:8001/status`
- Kong Proxy: `http://localhost:8000`
- Backend API: `http://localhost:3000/health`

### Logs
- Container logs: `docker-compose logs [service]`
- Aggregated logs: `./scripts/logs.sh`

### Metrics
- Container stats: `docker stats`
- Resource usage: Built-in limits enforced

## 🚨 Troubleshooting

### Common Issues

1. **Port conflicts**:
   ```bash
   # Check port usage
   lsof -i :8000 -i :8001 -i :3000
   ```

2. **Container startup failures**:
   ```bash
   # Check container logs
   docker-compose logs [service-name]
   ```

3. **Permission issues**:
   ```bash
   # Fix volume permissions
   sudo chown -R $(id -u):$(id -g) .docker/volumes
   ```

4. **Resource limits**:
   ```bash
   # Increase limits in docker-compose.yml
   mem_limit: 1g
   cpus: "1.0"
   ```

## 🔄 Maintenance

### Regular Tasks
- Monitor disk usage in `.docker/volumes/`
- Rotate logs if needed
- Update base images monthly
- Review and update dependencies

### Backup
```bash
# Backup configurations
tar -czf backup-kong.tar.gz kong/

# Backup volumes (if stateful)
tar -czf backup-volumes.tar.gz .docker/volumes/
```

## 📚 References

- [Kong Documentation](https://docs.konghq.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- Project Standards: `Docs/Standards/`
  - [19-docker-compose-best-practices.md](./Docs/Standards/19-docker-compose-best-practices.md)
  - [05-service-stability-strategy.md](./Docs/Standards/05-service-stability-strategy.md)

## 👥 Team Interfaces

### For Kong Team
- Plugin directory mounted at `/usr/local/share/lua/5.1/kong/plugins`
- Kong Admin API available at `http://localhost:8001`
- Declarative config at `kong/kong.yml`

### For Backend Team
- Source code mounted at `/app` in container
- Auto-reload enabled with nodemon
- Environment variables auto-injected

### For Testing Team
- All services accessible via localhost
- Mock endpoints available for isolated testing
- Health checks for automated validation

---

**Infrastructure Team** - Providing the foundation for secure AWS resource masking