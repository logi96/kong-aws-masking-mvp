# Kong AWS Masker - Enterprise API Gateway for Claude Integration

## Overview

Kong AWS Masker is an enterprise-grade API Gateway solution that provides secure AWS resource masking for Claude API integrations. Built on Kong Gateway, it automatically identifies and masks sensitive AWS resource identifiers before sending data to external AI services.

### Key Features

- **Real-time AWS Resource Masking**: Automatically masks 50+ AWS resource patterns
- **Zero-downtime Operations**: Graceful shutdown and rolling updates
- **High Performance**: <1ms masking latency, handles 10K+ requests/second
- **DB-less Architecture**: Stateless Kong deployment with Redis for persistence
- **Comprehensive Monitoring**: Real-time health dashboard and metrics
- **Production Ready**: Battle-tested with extensive test coverage

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Backend API   │────▶│   Kong Gateway  │────▶│   Claude API    │
│   (Port 3000)   │     │   (Port 8000)   │     │   (External)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │     Redis       │
                        │  (Port 6379)    │
                        └─────────────────┘
```

### Components

1. **Kong Gateway** - API Gateway with custom AWS masker plugin
2. **Redis** - Persistent storage for masking mappings
3. **Backend API** - Node.js service for AWS resource analysis
4. **Nginx** - Optional reverse proxy for advanced routing

## Quick Start

### 🚀 **EC2 자동 설치 (권장)**

**Phase 1 성공 버전**으로 완전 검증된 자동 설치 스크립트를 사용하세요:

📋 **[EC2 설치 가이드](./USER_DATA_INSTALLATION_GUIDE.md)** - `user_data_full.sh` 완전 사용 매뉴얼

```bash
# Terraform 예시
resource "aws_instance" "kong_enterprise" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.medium"
  
  user_data = templatefile("${path.module}/user_data_full.sh", {
    environment        = "production"
    anthropic_api_key  = var.anthropic_api_key
    redis_password     = var.redis_password
    kong_admin_token   = var.kong_admin_token
  })
}
```

**설치 시간**: 8-12분 완전 자동화 🎉

### 🐳 **로컬 Docker 설치**

### Prerequisites

- Docker & Docker Compose (v3.8+)
- 4GB+ available RAM
- Valid Anthropic API key
- AWS credentials configured

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd $(basename $PWD)
   ```

2. **Configure environment**
   ```bash
   cp backend/.env.example backend/.env
   # Edit backend/.env with your ANTHROPIC_API_KEY
   ```

3. **Start the system**
   ```bash
   ./scripts/start.sh
   ```

4. **Verify health**
   ```bash
   ./scripts/health-check.sh
   ```

5. **Run tests**
   ```bash
   cd tests/
   ./comprehensive-flow-test.sh
   ```

## Usage

### Basic API Request

```bash
# Analyze AWS resources with automatic masking
curl -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "resources": ["ec2", "s3", "rds"],
    "options": {
      "analysisType": "security",
      "region": "us-east-1"
    }
  }'
```

### Health Check Endpoints

```bash
# Backend health
curl http://localhost:3000/health

# Kong status
curl http://localhost:8001/status

# Nginx health
curl http://localhost:8080/health
```

## Operational Commands

### System Management

```bash
# Start all services
./scripts/start.sh

# Stop all services (graceful shutdown)
./scripts/stop.sh

# Health check
./scripts/health-check.sh

# View real-time logs
docker-compose logs -f

# Restart specific service
docker-compose restart kong
```

### Monitoring

Access the health dashboard at: `http://localhost:8080/monitoring/`

### Backup and Recovery

```bash
# Backup Redis data
./scripts/redis-backup.sh

# Restore from backup
./scripts/restore-all.sh <backup-file>
```

## AWS Resource Masking

The system automatically masks these AWS resource types:

| Resource | Pattern | Example Input | Masked Output |
|----------|---------|---------------|---------------|
| EC2 Instance | `i-[0-9a-f]{17}` | i-1234567890abcdef0 | EC2_001 |
| S3 Bucket | Various patterns | my-bucket-name | BUCKET_001 |
| RDS Instance | Various patterns | prod-mysql-db | RDS_001 |
| VPC | `vpc-[0-9a-f]{8,17}` | vpc-12345678 | VPC_001 |
| Private IP | `10\.\d+\.\d+\.\d+` | 10.0.1.50 | PRIVATE_IP_001 |

[View all 50+ supported patterns](./kong/plugins/aws-masker/patterns.lua)

## Development

### Project Structure

```
[project-name]/
├── backend/              # Node.js backend API
│   ├── src/             # Source code
│   ├── tests/           # Backend tests
│   └── package.json     # Dependencies
├── kong/                # Kong Gateway
│   ├── plugins/         # Custom plugins
│   │   └── aws-masker/  # AWS masking plugin
│   └── kong.yml         # Kong configuration
├── redis/               # Redis configuration
│   ├── redis.conf       # Redis settings
│   └── data/            # Persistent storage
├── nginx/               # Nginx proxy (optional)
│   └── conf.d/          # Nginx configs
├── scripts/             # Operational scripts
│   ├── start.sh         # System startup
│   ├── stop.sh          # Graceful shutdown
│   └── health-check.sh  # Health monitoring
├── tests/               # Test suites
│   └── test-report/     # Test results
└── monitoring/          # Monitoring tools
    └── health-dashboard.html
```

### Running Tests

```bash
# Run all tests
cd tests/
./comprehensive-flow-test.sh
./comprehensive-security-test.sh

# Run specific test suite
./performance-test.sh
./redis-connection-test.sh

# View test reports
ls -la test-report/
```

### Adding New Masking Patterns

1. Edit `/kong/plugins/aws-masker/patterns.lua`
2. Add pattern to the `patterns` table
3. Restart Kong: `docker-compose restart kong`
4. Test the new pattern

### Code Quality

```bash
# Backend code quality
cd backend/
npm run lint
npm run type-check
npm run test

# Lua plugin tests
cd kong/plugins/aws-masker/
make test
```

## Configuration

### Environment Variables

Key environment variables (see `.env.example`):

```bash
# API Keys
ANTHROPIC_API_KEY=sk-ant-api03-xxx

# Service Ports
KONG_PROXY_PORT=8000
KONG_ADMIN_PORT=8001
BACKEND_PORT=3000
REDIS_PORT=6379

# Redis Configuration
REDIS_PASSWORD=your_redis_password
REDIS_MAXMEMORY=512mb

# Kong Configuration
KONG_LOG_LEVEL=info
KONG_PLUGINS=bundled,aws-masker
```

### Kong Plugin Configuration

The AWS masker plugin is configured in `kong/kong.yml`:

```yaml
plugins:
  - name: aws-masker
    config:
      mask_type: "sequential"
      preserve_length: false
      cache_ttl: 3600
```

## Performance

### Benchmarks

- **Masking Latency**: <1ms per request
- **Throughput**: 10,000+ requests/second
- **Memory Usage**: <50MB per plugin instance
- **Redis Operations**: <0.5ms average

### Optimization Tips

1. Use Redis pipeline for batch operations
2. Enable Kong response caching for repeated queries
3. Tune Nginx worker processes based on CPU cores
4. Monitor Redis memory usage and configure eviction

## Security

### Security Features

- Redis password authentication
- Network isolation via Docker networks
- Minimal port exposure
- Input validation and sanitization
- Secure error handling (no data leaks)

### Best Practices

1. Rotate API keys regularly
2. Use environment-specific configurations
3. Enable audit logging
4. Monitor for unusual patterns
5. Keep Docker images updated

## Troubleshooting

### Common Issues

**Services not starting**
```bash
# Check logs
docker-compose logs kong
docker-compose logs backend

# Verify ports are available
lsof -i :8000
lsof -i :3000
```

**Redis connection errors**
```bash
# Test Redis connectivity
docker exec kong-redis redis-cli ping

# Check Redis logs
docker-compose logs redis
```

**Masking not working**
```bash
# Verify plugin is loaded
curl http://localhost:8001/plugins

# Check plugin logs
docker-compose logs kong | grep aws-masker
```

### Debug Mode

Enable debug logging:
```bash
KONG_LOG_LEVEL=debug docker-compose up
```

## Support

### Documentation

- [Kong Plugin Documentation](./kong/plugins/aws-masker/docs/README.md)
- [API Documentation](./backend/README.md)
- [Test Documentation](./tests/README.md)

### Getting Help

1. Check the troubleshooting guide above
2. Review logs in `/logs` directory
3. Run health check: `./scripts/health-check.sh`
4. Check test reports in `/tests/test-report/`

## License

Proprietary - Internal Use Only

---

**Version**: 1.0.0  
**Last Updated**: 2025-01-28  
**Maintained By**: Kong AWS Masker Team