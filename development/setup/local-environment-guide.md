# AIDA Local Environment Guide - Phase 1 Complete

## 🚀 Quick Start (5 minutes)

### Prerequisites
- Docker Desktop running
- Node.js 20+ installed
- Git repository cloned

### One-Command Setup
```bash
npm run setup:local
```

This command will:
- ✅ Check prerequisites
- ✅ Start all Docker services
- ✅ Initialize databases
- ✅ Validate setup
- ✅ Display service URLs

## 📊 Available Services

| Service | URL | Purpose | Credentials |
|---------|-----|---------|-------------|
| PostgreSQL | `localhost:5432` | Main database | `postgres / Wonder9595!!` |
| Redis | `localhost:6379` | Cache & sessions | No password |
| ClickHouse | `localhost:8123` | Metrics storage | `aida_user / Wonder9595!!` |
| Mock K8s API | `localhost:6443` | K8s simulation | No auth |
| Adminer | `http://localhost:8080` | DB management | See above |
| Redis Commander | `http://localhost:8081` | Redis management | `admin / Wonder9595!!` |
| Prometheus | `http://localhost:9090` | Metrics (optional) | No auth |
| Grafana | `http://localhost:3000` | Dashboards (optional) | `admin / Wonder9595!!` |

## 🛠️ Essential Commands

### Environment Management
```bash
# Start local environment
npm run setup:local

# Validate environment
npm run validate:local

# View service status
npm run docker:local:logs

# Stop environment
npm run docker:local:down

# Clean reset (removes all data)
npm run docker:local:clean
```

### Development Workflow
```bash
# Start development servers (after environment is running)
npm run dev:all

# Run tests
npm run test:local
npm run test:mock-k8s

# Validate code
npm run validate:quick
```

### Mock Kubernetes Testing
```bash
# Test mock K8s strategy
npm run test:mock-k8s

# Manual API testing
curl http://localhost:6443/api/v1/nodes
curl http://localhost:6443/api/v1/pods
curl http://localhost:6443/api/v1/events
```

## 🧪 Mock Kubernetes Scenarios

The local environment includes realistic K8s simulation with multiple scenarios:

### Available Scenarios
- **default**: Healthy cluster with normal operations
- **pod-crash**: CrashLoopBackOff simulation
- **high-memory**: Memory pressure and OOMKilled pods
- **network-latency**: Network connectivity issues

### Testing Different Scenarios
```typescript
// In your tests or development code
import MockK8sStrategy from '@shared/testing/mock-k8s-strategy';

const mockStrategy = new MockK8sStrategy();

// Switch to pod crash scenario
mockStrategy.setScenario('pod-crash');
const response = await mockStrategy.executeCommand('kubectl get pods -n default');
// Response will show CrashLoopBackOff pods

// Switch to high memory scenario  
mockStrategy.setScenario('high-memory');
const nodeResponse = await mockStrategy.executeCommand('kubectl describe node node-2');
// Response will show memory pressure
```

## 📁 Key Files Created

### Configuration Files
- `docker-compose.local.yml` - Enhanced Docker setup
- `.env.local` - Local environment variables
- `config/prometheus.yml` - Prometheus configuration
- `config/grafana/` - Grafana datasources and dashboards

### Scripts
- `scripts/setup-local-env.sh` - Complete environment setup
- `scripts/validate-local-env.sh` - Environment validation
- `scripts/test-local-env.sh` - Comprehensive testing
- `scripts/mock-k8s-server/` - Mock Kubernetes API server

### Mock Framework
- `src/shared/testing/mock-k8s-strategy.ts` - Mock strategy implementation
- `src/shared/testing/mock-kubernetes-executor.ts` - Mock executor
- `src/shared/testing/mock-k8s-strategy.test.ts` - Strategy tests

## 🔧 Troubleshooting

### Common Issues

#### Docker Services Not Starting
```bash
# Check Docker Desktop is running
docker ps

# Restart Docker services
npm run docker:local:down
npm run docker:local:up
```

#### Database Connection Issues
```bash
# Check PostgreSQL logs
docker logs aida-postgres-local

# Test connection manually
docker exec -it aida-postgres-local psql -U postgres -d aida
```

#### Mock K8s API Not Responding
```bash
# Check mock server logs
docker logs aida-mock-k8s-api

# Restart mock server
docker restart aida-mock-k8s-api

# Test manually
curl http://localhost:6443/healthz
```

#### Port Conflicts
```bash
# Check what's using ports
lsof -i :5432  # PostgreSQL
lsof -i :6379  # Redis
lsof -i :8123  # ClickHouse
lsof -i :6443  # Mock K8s API

# Kill conflicting processes or change ports in .env.local
```

### Reset Environment
```bash
# Complete reset
npm run docker:local:clean
docker system prune -f
npm run setup:local
```

## 🎯 Development Workflow

### 1. Initial Setup
```bash
git clone <repository>
cd AIDA
npm install
npm run setup:local
```

### 2. Daily Development
```bash
# Start environment (if not running)
npm run setup:local

# Validate everything is working
npm run validate:local

# Start development servers
npm run dev:all

# In another terminal, run tests
npm run test:local
```

### 3. Testing Different Scenarios
```bash
# Test specific K8s scenarios
npm run test:mock-k8s

# Test against different mock scenarios in your code
# See Mock Kubernetes Scenarios section above
```

### 4. Code Validation
```bash
# Before committing
npm run validate:quick

# Full validation
npm run validate:all
```

## 📈 Performance Expectations

### Local Environment Targets
- **Setup time**: < 5 minutes
- **Mock K8s response**: < 200ms
- **Database queries**: < 100ms
- **Test execution**: < 2 minutes

### Monitoring
```bash
# View real-time logs
npm run docker:local:logs

# Check resource usage
docker stats

# Test performance
npm run test:local  # Includes performance tests
```

## 🔗 Integration with Development Environment

This local setup seamlessly integrates with:
- **Phase 2 Dev Environment**: Real K8s cluster access
- **Production Environment**: Direct deployment path
- **CI/CD Pipeline**: Same validation scripts
- **Team Development**: Consistent environment across developers

## 🎉 Next Steps

After successful local setup:
1. **Start Development**: `npm run dev:all`
2. **Run Tests**: `npm run test:local`
3. **Explore Services**: Visit web interfaces listed above
4. **Read Documentation**: Check `/Docs` for detailed guides
5. **Implement Features**: Begin with mock K8s scenarios

---

**📞 Support**: If you encounter issues, check the troubleshooting section or refer to the validation script output for specific error details.