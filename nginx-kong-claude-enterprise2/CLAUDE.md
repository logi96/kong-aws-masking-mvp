# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

엔터프라이즈 수준의 Claude Code 통합 솔루션 구축

- Nginx를 통한 고성능 HTTP 프록시
- Kong Gateway의 aws-masker 플러그인을 통한 AWS 리소스 마스킹
- Redis를 통한 마스킹 데이터 영속성
- Claude Code SDK 테스트 환경

### 아키텍처

```
[Claude Code Client]
        ↓ HTTP (port 8082)
[Nginx Proxy Container]
        ↓ HTTP (internal)
[Kong Gateway Container + aws-masker]
        ↓ Redis (port 6379)
[Redis Container]
        ↑
        └── [Kong] → HTTPS → [Claude API]
```

**핵심 컴포넌트:**
- **Nginx Proxy**: 고성능 HTTP 프록시 및 로드 밸런싱 (port 8082)
- **Kong Gateway**: AWS masker 플러그인이 포함된 API Gateway (Lua)  
- **Redis**: 마스킹 매핑의 영속적 저장소 (port 6379)
- **Claude Code SDK**: 대화형 CLI 테스트 환경 (컨테이너화)
- **Claude API**: 외부 AI 서비스 (마스킹된 데이터만 전송)

## 🚀 **Environment-Based Deployment System**

**📂 All deployment environments are now organized in `setup-environment/`**

### **🎯 Choose Your Deployment Environment**

| Environment | Complexity | Setup Time | Best For | Status |
|-------------|------------|------------|-----------|--------|
| **[EC2](./setup-environment/ec2/README.md)** | ⭐ Low | 8-12 min | Development, POC | ✅ Ready |
| **[EKS-EC2](./setup-environment/eks-ec2/README.md)** | ⭐⭐⭐ High | 20-30 min | Production K8s | ✅ Ready |
| **[EKS-Fargate](./setup-environment/eks-fargate/README.md)** | ⭐⭐⭐⭐ Very High | 25-35 min | Serverless K8s | ✅ **Complete** |
| **[ECS-Fargate](./setup-environment/ecs-fargate/README.md)** | ⭐⭐ Medium | 15-25 min | Serverless Containers | ✅ Ready |

### **🏃‍♂️ Quick Start Commands**

```bash
# EC2 Environment (Fastest - 8-12 minutes)
cd setup-environment/ec2/
./scripts/deploy-ec2.sh

# EKS-EC2 Environment (Production Kubernetes)
cd setup-environment/eks-ec2/
./manifests/deploy-all.sh

# EKS-Fargate Environment (Serverless Kubernetes)
cd setup-environment/eks-fargate/
./manifests/deploy-fargate.sh

# ECS-Fargate Environment (Serverless Containers)
cd setup-environment/ecs-fargate/
./manifests/deploy-ecs-fargate.sh
```

### **📋 Environment Selection Guide**
📂 **[Complete Environment Guide](./setup-environment/README.md)** - Comprehensive comparison and selection matrix

- ✅ **All 4 Environments Complete**: EC2, EKS-EC2, EKS-Fargate, ECS-Fargate
- ✅ **Independent Setup**: Each environment has complete manifests, tests, and documentation
- ✅ **Production Ready**: All environments validated and deployment-ready
- ✅ **Environment-Specific Testing**: Tailored test suites for each deployment type

## Essential Commands

### System Management
```bash
# Start entire system
./scripts/system/start.sh

# Stop system gracefully  
./scripts/system/stop.sh

# Health check all services
./scripts/system/health-check.sh

# System validation
./scripts/system/validate-system.sh

# View real-time logs
docker-compose logs -f

# Restart specific service
docker-compose restart kong
```

### Development Setup
```bash
# Copy and configure environment (from project root)
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY and other values

# Start entire enterprise system (including Claude Code SDK)
docker-compose up --build

# Interactive Claude Code SDK access
docker exec -it claude-code-sdk /bin/bash

# Backend development commands
cd backend/
npm start                # Production mode
npm run start:dev        # Development mode  
npm run dev             # Hot reload with nodemon
```

### **Environment-Specific Testing & Quality**
```bash
# Backend testing (remains the same)
cd backend/
npm test                # Run all tests
npm run test:unit       # Unit tests only
npm run test:integration # Integration tests
npm run test:coverage   # With coverage report
npm run lint            # ESLint check
npm run type-check      # JSDoc type validation

# 🆕 **Environment-Specific Testing**
# Each environment now has its own tailored test suite

# EC2 Environment Testing
cd setup-environment/ec2/tests/
./performance/quick-core-validation.sh     # Quick EC2 validation
./phase2/ec2-actual-deployment-test.sh     # EC2-specific deployment test
./logging/test-comprehensive-logging.sh    # Logging validation

# EKS-EC2 Environment Testing
cd setup-environment/eks-ec2/tests/
./core/e2e-comprehensive-test.sh           # Complete E2E with Kubernetes
./patterns/50-patterns-complete-test.sh    # 50+ AWS patterns on K8s
./elasticache/elasticache-comprehensive-test.sh # ElastiCache integration
./performance/performance-benchmark.sh     # K8s performance testing

# EKS-Fargate Environment Testing (🎯 COMPLETE)
cd setup-environment/eks-fargate/tests/
./core/e2e-comprehensive-test.sh           # Fargate E2E testing
./patterns/comprehensive-patterns-validation.sh # Fargate pattern validation
./elasticache/elasticache-comprehensive-test.sh # Fargate ElastiCache tests
./components/kong-direct-test.sh           # Fargate Kong testing

# ECS-Fargate Environment Testing
cd setup-environment/ecs-fargate/tests/
./test-ecs-fargate-integration.sh          # ECS-Fargate integration test

# Legacy System Tests (maintained for compatibility)
cd tests/
./core/e2e-comprehensive-test.sh           # System-wide E2E
./patterns/50-patterns-complete-test.sh    # AWS patterns validation
./performance/quick-core-validation.sh     # Quick system validation

# Test reports - See individual environment test directories
ls -la setup-environment/*/tests/test-report/  # Environment-specific reports
cat tests/README.md                            # Complete testing documentation
```

### Kong Plugin Development
```bash
# Kong plugin files location
kong/plugins/aws-masker/
├── handler.lua          # Main plugin logic
├── patterns.lua         # AWS resource patterns  
├── masker_ngx_re.lua   # Masking/unmasking engine
├── redis_integration.lua # Redis storage
└── schema.lua          # Plugin configuration

# Restart Kong after plugin changes
docker-compose restart kong

# Check plugin status
curl http://localhost:8001/plugins
```

## Project Structure

### **NEW: Environment-Based Organization (v2.0.0)**
```
nginx-kong-claude-enterprise2/
├── 📄 CLAUDE.md                    # Claude Code operation guide (updated for v2.0)
├── 📄 README.md                    # Project overview and setup
├── 📄 DEPLOYMENT.md                # Production deployment guide
├── 📄 ROLLBACK.md                  # System rollback procedures
├── 📄 SECURITY-DEPLOYMENT-GUIDE.md # Security deployment guide
├── 📄 TROUBLESHOOTING.md           # Operational troubleshooting
├── 📁 setup-environment/           # 🆕 **ORGANIZED DEPLOYMENT ENVIRONMENTS**
│   ├── 📄 README.md               # Environment selection matrix and complete guide
│   ├── 📁 ec2/                    # EC2 Docker Compose environment (8-12 min setup)
│   │   ├── 📄 README.md           # Complete EC2 deployment guide
│   │   ├── 📁 manifests/          # Docker Compose + Terraform + User Data
│   │   ├── 📁 scripts/            # EC2-specific automation scripts
│   │   ├── 📁 tests/              # EC2 environment tests
│   │   ├── 📁 docs/               # EC2-specific documentation
│   │   └── 📁 configs/            # Environment configurations
│   ├── 📁 eks-ec2/                # EKS with EC2 worker nodes (20-30 min setup)
│   │   ├── 📄 README.md           # Complete EKS-EC2 deployment guide
│   │   ├── 📁 manifests/          # Kubernetes manifests + ElastiCache
│   │   ├── 📁 scripts/            # EKS-EC2 automation scripts
│   │   ├── 📁 tests/              # Kubernetes environment tests
│   │   ├── 📁 docs/               # EKS-EC2 documentation
│   │   └── 📁 configs/            # Kubernetes configurations
│   ├── 📁 eks-fargate/            # 🎯 **EKS with Fargate (25-35 min setup) - COMPLETE**
│   │   ├── 📄 README.md           # Complete EKS-Fargate deployment guide
│   │   ├── 📁 manifests/          # Fargate-optimized Kubernetes manifests
│   │   ├── 📁 scripts/            # Fargate deployment automation
│   │   ├── 📁 tests/              # Fargate-specific tests
│   │   ├── 📁 docs/               # Fargate documentation
│   │   └── 📁 configs/            # Fargate configurations
│   └── 📁 ecs-fargate/            # ECS with Fargate launch type (15-25 min setup)
│       ├── 📄 README.md           # Complete ECS-Fargate deployment guide
│       ├── 📁 manifests/          # ECS task definitions + service configs
│       ├── 📁 scripts/            # ECS automation scripts
│       ├── 📁 tests/              # ECS-Fargate integration tests
│       ├── 📁 docs/               # ECS-specific documentation
│       └── 📁 configs/            # ECS configurations
├── 📁 backend/                     # Node.js backend service → See backend/README.md
├── 📁 kong/                        # Kong Gateway + AWS masker plugin
├── 📁 nginx/                       # Nginx proxy configuration → See nginx/README.md
├── 📁 redis/                       # Redis configuration → See redis/README.md
├── 📁 claude-code-sdk/             # Claude Code SDK environment
├── 📁 config/                      # Environment-specific configurations
├── 📁 deploy/                      # Active deployment scripts → See deploy/README.md
├── 📁 monitoring/                  # Real-time monitoring system → See monitoring/README.md
├── 📁 docs/                        # Active operational documentation → See docs/README.md
├── 📁 tests/                       # Organized test suite → See tests/README.md
├── 📁 scripts/                     # Core operational scripts → See scripts/README.md
├── 📁 logs/                        # Runtime logs (kong/, nginx/, redis/, backend/, claude-code-sdk/)
└── 📁 archive/                     # Development history preservation (105+ files)
```

### Archive Structure (Development History)
All development artifacts are systematically preserved in `archive/`:
```
archive/
├── 01-development-process/      # Daily development reports & process analysis
├── 02-phase-implementation/     # Phase completion reports & QA verification
├── 03-quality-assurance/        # Validation reports & quality dashboards
├── 04-test-execution-logs/      # Historical test execution reports
├── 05-alternative-solutions/    # Kubernetes, Terraform, Docker variants
├── 06-development-testing/      # Development scripts & security verification
├── 07-architecture-planning/    # Development stage architecture documents
└── 08-deployment-variants/      # Legacy deployment scripts
```

**Total Archived Items**: 105+ development files systematically organized

## 📚 README.md Navigation System

This project has comprehensive README.md files in each major directory. **Always check these README files first** before working with any component:

### **🏗️ Core Infrastructure READMEs**
- **[backend/README.md](./backend/README.md)** - Complete backend service guide
  - Health monitoring API endpoints and detailed features
  - Installation, testing, and development workflows  
  - Node.js service architecture and security features
  - Performance monitoring and troubleshooting guides

- **[nginx/README.md](./nginx/README.md)** - Enterprise proxy configuration
  - High-performance HTTP proxy layer documentation
  - Security architecture and proxy chain flow
  - Configuration files and Docker setup details
  - Security improvements and troubleshooting

- **[redis/README.md](./redis/README.md)** - Redis integration guide  
  - Central data persistence for AWS masking operations
  - Kong plugin integration and Backend service integration
  - Redis configuration and operational procedures
  - Performance optimization and monitoring

### **🔧 Operations & Testing READMEs**
- **[scripts/README.md](./scripts/README.md)** - Production operations toolkit
  - System management scripts (start, stop, health-check, validate)
  - Deployment operations (deploy, rollback, smoke-tests)
  - Monitoring and backup management tools
  - Enterprise operational standards and procedures

- **[deploy/README.md](./deploy/README.md)** - Enterprise deployment pipeline
  - User-friendly deployment workflows and processes
  - Blue-green deployment with automated rollback
  - Pre/post deployment validation and verification
  - Relationship with scripts/ folder for modular operations

- **[tests/README.md](./tests/README.md)** - Complete test suite documentation
  - Organized test structure (core/, patterns/, components/, performance/)
  - 14+ active test scripts with execution times and priorities
  - Test report generation and validation procedures
  - Critical testing requirements and troubleshooting

### **📊 Documentation & Monitoring READMEs**
- **[docs/README.md](./docs/README.md)** - Documentation navigation hub
  - Implementation guides and how-to documents
  - Quality assurance and validation reports
  - API authentication and security compliance guides
  - Interactive quality metrics dashboard access

- **[monitoring/README.md](./monitoring/README.md)** - Comprehensive observability
  - Real-time monitoring stack and metrics collection
  - System health monitoring and alert configurations
  - Performance dashboards and log aggregation
  - SLI/SLO definitions and compliance monitoring

## 👥 Role-Based Quick Access

### **🧑‍💻 For Developers**
**Primary Focus**: Backend development, testing, documentation

**Essential Reading Order**:
1. **[backend/README.md](./backend/README.md)** - Complete backend service architecture and development workflows
2. **[tests/README.md](./tests/README.md)** - Testing requirements and test suite organization  
3. **[docs/README.md](./docs/README.md)** - Implementation guides and quality assurance documentation

**Key Commands**:
```bash
# Development workflow
cd backend/ && npm run dev              # Start development server
npm test && npm run type-check          # Run tests and type validation
./tests/core/e2e-comprehensive-test.sh  # System integration validation
```

**Critical Files**:
- `backend/src/` - All Node.js source code
- `backend/tests/` - Unit and integration tests
- `docs/guide/` - Implementation guides and best practices

### **⚙️ For Site Reliability Engineers**
**Primary Focus**: System operations, deployment, monitoring

**Essential Reading Order**:
1. **[scripts/README.md](./scripts/README.md)** - Complete operational toolkit for system management
2. **[deploy/README.md](./deploy/README.md)** - Enterprise deployment pipeline and procedures
3. **[monitoring/README.md](./monitoring/README.md)** - Observability stack and performance monitoring

**Key Commands**:
```bash
# System operations
./scripts/system/start.sh               # Start entire system
./scripts/system/health-check.sh        # Comprehensive health validation
./deploy/core/deploy.sh                 # Production deployment
./scripts/monitoring/monitoring-daemon.sh # Start monitoring
```

**Critical Files**:
- `scripts/system/` - Core system management (start, stop, health-check)
- `deploy/core/` - Deployment pipeline scripts
- `monitoring/` - Metrics, alerts, and dashboards configuration

### **🔒 For Security & Infrastructure Teams**
**Primary Focus**: Security compliance, infrastructure configuration, data protection

**Essential Reading Order**:
1. **[nginx/README.md](./nginx/README.md)** - Proxy security architecture and configuration
2. **[redis/README.md](./redis/README.md)** - Data persistence and security configuration
3. **[docs/README.md](./docs/README.md)** - Security compliance reports and authentication guides

**Key Commands**:
```bash
# Security validation
./tests/components/test-authentication.sh  # API authentication testing
./scripts/backup/redis-backup.sh           # Data backup procedures
docker-compose logs kong                   # Security audit logs
```

**Critical Files**:
- `nginx/conf.d/claude-proxy.conf` - Proxy security configuration
- `kong/kong.yml` - Gateway security settings
- `docs/guide/SECURITY_COMPLIANCE_REPORT.md` - Security compliance documentation
- `redis/data/` - Encrypted data persistence layer

## Code Architecture

### Kong Plugin Architecture (Lua)
The AWS masker plugin follows Kong's standard plugin lifecycle:

1. **Access Phase** (`handler:access()`):
   - Validates Redis connectivity (fail-secure)
   - Masks AWS resources in request body
   - Stores mapping context for response unmasking
   - Pre-fetches unmask data for Redis mode

2. **Header Filter Phase** (`handler:header_filter()`):
   - Captures Claude API response status/headers
   - Logs detailed error information for failed requests

3. **Body Filter Phase** (`handler:body_filter()`):
   - Unmasks AWS resources in response chunks
   - Applies stored mappings to restore original identifiers

**Key Plugin Files:**
- `handler.lua`: Main plugin orchestration (629 lines)
- `masker_ngx_re.lua`: Core masking engine with Redis integration
- `patterns.lua`: 50+ AWS resource patterns (EC2, S3, RDS, VPC, etc.)
- `redis_integration.lua`: Redis connection management and fail-secure logic

### Backend API Architecture (Node.js)
```
backend/src/
├── server.js           # Entry point with graceful shutdown
├── app.js             # Express application setup
├── routes/            # API endpoints
│   ├── analyze.js     # Main AWS analysis endpoint
│   ├── auth.js        # Authentication endpoints
│   ├── health.js      # Health check endpoints  
│   └── monitoring.js  # Monitoring endpoints
├── services/          # Business logic layer
│   ├── auth/          # API key & JWT authentication services
│   ├── claude/        # Claude API integration
│   ├── aws/          # AWS CLI execution
│   ├── redis/        # Redis services + event subscription
│   ├── masking/      # Masking service coordination
│   ├── health/       # Health check services
│   └── monitoring/   # Monitoring services
├── middlewares/       # Express middlewares
│   ├── auth.js       # Authentication middleware
│   └── errorHandler.js # Error handling middleware
└── utils/            # Utility functions
    └── logger.js     # Structured logging utility
```

**Note**: Backend focuses solely on Node.js services. Kong plugin code is located in the separate `kong/plugins/aws-masker/` directory.

**Architecture Patterns:**
- Service layer architecture with clear separation of concerns
- JSDoc type annotations for development-time type checking  
- Graceful shutdown handling for Redis connections
- Event subscription for real-time masking validation
- Comprehensive error handling with structured logging

### Security Architecture
- **Fail-Secure Design**: Service blocks if Redis unavailable (prevents AWS data exposure)
- **Circuit Breaker**: Automatic failure detection and recovery
- **Pattern Detection**: Pre-validates AWS patterns exist before processing
- **Memory Isolation**: Separate mapping stores per request context
- **Event Publishing**: Real-time monitoring of masking operations

### Claude Code SDK Integration Architecture
The system includes a containerized Claude Code SDK environment for interactive testing:

**Container Configuration:**
```yaml
claude-code-sdk:
  environment:
    - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    - HTTP_PROXY=http://nginx:8082
    - ANTHROPIC_BASE_URL=http://nginx:8082/v1
```

**Key Features:**
- **Proxy Integration**: All Claude API calls route through the masking proxy
- **Interactive CLI**: Full Claude Code functionality within the container
- **Volume Mapping**: Access to test scripts and logs
- **Network Isolation**: Secure internal network communication

**Usage Patterns:**
```bash
# Access Claude Code SDK
docker exec -it claude-code-sdk /bin/bash

# Test masking with Claude Code
docker exec claude-code-sdk claude-code --prompt "Analyze this EC2 instance: i-1234567890abcdef0"

# View Claude Code logs
docker exec claude-code-sdk tail -f /home/claude/logs/api-test.log
```

## Configuration Management

### Environment Configuration
Primary config file: `.env` (copy from `.env.example`)  
**Note**: `.env.example` is located in the project root directory
```bash
# Critical settings
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
REDIS_PASSWORD=your-secure-redis-password
AWS_REGION=ap-northeast-2

# Kong settings  
KONG_PROXY_PORT=8000
KONG_ADMIN_PORT=8001
KONG_MEMORY_LIMIT=4G

# Service ports
PORT=3000              # Backend API (internal)
NGINX_PROXY_PORT=8082  # Nginx proxy (Claude Code entry point)
KONG_PROXY_PORT=8010   # Kong Gateway (internal)
REDIS_PORT=6379        # Redis (internal)
```

### Kong Plugin Configuration
Located in `kong/kong.yml`:
```yaml
plugins:
  - name: aws-masker
    config:
      mask_ec2_instances: true
      mask_s3_buckets: true  
      use_redis: true
      mapping_ttl: 86400  # 24 hours
      max_entries: 10000
```

## Development Workflow

### Adding New AWS Resource Patterns
1. Edit `kong/plugins/aws-masker/patterns.lua`
2. Add pattern to appropriate category (EC2, S3, RDS, etc.)
3. Update masking logic in `masker_ngx_re.lua` if needed
4. Test with `./patterns/comprehensive-patterns-validation.sh`
5. Restart Kong: `docker-compose restart kong`

### Modifying Backend Logic  
1. Edit files in `backend/src/`
2. Add JSDoc type annotations
3. Run quality checks: `npm run quality:check`
4. Test changes: `npm test`
5. Backend auto-reloads with nodemon in dev mode

### Testing Requirements

**📋 Complete Testing Guide**: See **[tests/README.md](./tests/README.md)** for comprehensive testing documentation

**CRITICAL RULES**:
- Every test execution MUST generate a report in `tests/test-report/`
- Test structure organized by category: `core/`, `patterns/`, `components/`, `performance/`
- 14+ active test scripts with defined priorities and execution times
- No duplicate test functionality without explicit approval

**🚨 Essential Test Sequence**:
```bash
# Before ANY code changes (Critical Priority)
./tests/core/e2e-comprehensive-test.sh     # ~5 min - Complete E2E flow verification
./tests/core/proxy-chain-verification.sh   # ~2 min - Proxy chain validation

# Pattern validation (High Priority)
./tests/patterns/50-patterns-complete-test.sh  # ~10 min - Complete AWS patterns

# Quick validation (Medium Priority)
./tests/performance/quick-core-validation.sh   # ~1 min - Rapid feedback
```

**📊 Test Categories** (See tests/README.md for complete details):
- **core/**: Essential E2E tests for system validation (3 scripts)
- **patterns/**: AWS resource pattern masking validation (4 scripts)
- **components/**: Individual component reliability tests (4 scripts)
- **performance/**: Performance benchmarks and quick validation (2 scripts)

**Test Reports**: Auto-generated in `tests/test-report/` with timestamps

## Performance & Monitoring

### Key Metrics
- **Masking Latency**: Target <1ms per request
- **Throughput**: 10,000+ requests/second capability
- **Memory Usage**: <50MB per Kong plugin instance
- **Redis Operations**: <0.5ms average

### Monitoring Endpoints
```bash
# Service health
curl http://localhost:8082/health     # Nginx (primary entry point)
curl http://localhost:8001/status     # Kong Admin
curl http://localhost:3000/health     # Backend (internal)

# Claude Code SDK test endpoints
docker exec claude-code-sdk curl http://nginx:8082/health

# Health dashboard
open http://localhost:8082/monitoring/
```

### Log Locations
```bash
logs/
├── kong/              # Kong Gateway logs
├── nginx/             # Nginx access/error logs  
├── redis/             # Redis logs
├── backend/           # Backend application logs
└── claude-code-sdk/   # Claude Code SDK interaction logs
```

## Troubleshooting

### Common Issues
**Services won't start**: Check port availability with `lsof -i :PORT`  
**Redis connection errors**: Verify password in `.env` matches `docker-compose.yml`
**Masking not working**: Check plugin status at `http://localhost:8001/plugins`
**Backend errors**: Check logs with `docker-compose logs backend`
**Claude Code SDK connectivity**: Test proxy connection with `docker exec claude-code-sdk curl http://nginx:8082/health`

### Debug Mode
```bash
# Enable debug logging
KONG_LOG_LEVEL=debug docker-compose up

# Backend debug mode  
DEBUG=true NODE_ENV=development npm run dev

# Claude Code SDK debug mode
docker exec claude-code-sdk bash -c "export DEBUG=true && claude-code --help"
```

### Health Check Script
Always use `./scripts/system/health-check.sh` for systematic diagnostics - it checks all services, ports, and plugin functionality automatically.

**Additional Health Commands**:
```bash
./scripts/system/validate-system.sh        # System validation based on SLA metrics
./deploy/core/post-deploy-verify.sh        # Post-deployment verification
./scripts/deployment/smoke-tests.sh        # Essential functionality validation
```

## Archive Management

### Accessing Development History
All development artifacts from the project lifecycle are systematically preserved in the `archive/` directory:

```bash
# View archive structure
tree archive/

# Find specific development reports
find archive/ -name "*completion*" -type f

# Access QA validation reports
ls archive/03-quality-assurance/validation-reports/

# Review test execution history
ls archive/04-test-execution-logs/unit-tests/

# Check alternative deployment solutions
ls archive/05-alternative-solutions/kubernetes/
```

### Development Documentation
- **Daily Progress**: See `archive/01-development-process/daily-reports/`
- **Phase Implementation**: See `archive/02-phase-implementation/phase-reports/`
- **Quality Assurance**: See `archive/03-quality-assurance/`
- **Architecture Planning**: See `archive/07-architecture-planning/`

### Alternative Solutions
- **Kubernetes Deployment**: `archive/05-alternative-solutions/kubernetes/`
- **Terraform Infrastructure**: `archive/05-alternative-solutions/terraform/`
- **Docker Variants**: `archive/05-alternative-solutions/docker-variants/`

**Note**: Archive is read-only for historical reference. All active development uses the main project structure.

## Important Notes

### Operational Requirements
- **No Mock Mode**: System requires real APIs only (no test/mock keys allowed)
- **Redis Dependency**: Plugin operates in fail-secure mode - blocks requests if Redis unavailable
- **Response Time Target**: <5 seconds for all operations
- **JSDoc Types**: Use JSDoc annotations for better IDE support and type checking
- **Graceful Shutdown**: Backend handles SIGTERM/SIGINT with proper Redis cleanup
- **Test Coverage**: Maintain 70%+ coverage threshold across all test suites

### Container Architecture
- **Claude Code SDK Proxy**: All SDK requests automatically route through the masking proxy (port 8082)
- **Container Dependencies**: Claude Code SDK depends on healthy Nginx proxy for operation
- **Network Isolation**: All services communicate via internal Docker network for security

### Project Structure
- **Production Ready**: Project structure is 100% operation-focused
- **Clean Separation**: Development artifacts are completely separated in `archive/`
- **No Duplicates**: All duplicate code and folders have been removed
- **Single Source**: Kong plugin code exists only in `kong/plugins/aws-masker/`
- **Archive Preservation**: 105+ development files systematically preserved for reference
- **Organized Tests**: Test suite systematically organized by functionality (14 active tests, 3 archived)

### Development History
- **Complete Traceability**: All development phases documented in archive
- **QA Records**: Full quality assurance validation history preserved
- **Alternative Solutions**: Kubernetes, Terraform, and Docker variants available in archive
- **Test History**: All test execution logs organized by context and preserved