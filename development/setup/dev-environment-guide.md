# AIDA Dev Environment Guide - Phase 2 Complete

## 🚀 Quick Start (5 minutes)

### Prerequisites
- Local environment setup completed (Phase 1)
- SSH access to remote K8s cluster (192.168.254.220)
- Network connectivity to remote infrastructure

### One-Command Setup
```bash
# New fixed setup script (recommended)
./scripts/setup-dev-env-fixed.sh start

# Or use npm script (legacy)
npm run setup:dev
```

This command will:
- ✅ Establish SSH tunnel to K8s cluster
- ✅ Setup port forwarding for all services
- ✅ Configure real K8s access
- ✅ Create dev environment configuration
- ✅ Validate connectivity to all services

## 📊 Available Services (Remote via SSH Tunnel)

| Service | Local URL | Remote Source | Purpose |
|---------|-----------|---------------|---------|
| K8s API | `https://localhost:6443` | 192.168.254.220:6443 | Kubernetes cluster |
| PostgreSQL | `localhost:5432` | observability/postgresql | Main database |
| Redis | `localhost:6379` | observability/redis | Cache & sessions |
| ClickHouse | `localhost:8123` | observability/clickhouse | Metrics storage |

## 🛠️ Essential Commands

### Environment Management
```bash
# Start dev environment (recommended)
./scripts/setup-dev-env-fixed.sh start

# Validate dev environment (fixed)
./scripts/validate-dev-env-fixed.sh

# Check tunnel status
./scripts/setup-dev-env-fixed.sh status

# Stop environment
./scripts/setup-dev-env-fixed.sh stop

# Restart environment
./scripts/setup-dev-env-fixed.sh restart

# Legacy commands (may have issues)
# npm run setup:dev
# npm run validate:dev
```

### Development Workflow
```bash
# Set kubeconfig for real K8s access
export KUBECONFIG=~/.kube/remote-clusters/master-config

# Test K8s connectivity
kubectl get nodes

# Start development servers
npm run dev:all

# Run integration tests
npm run test:dev-integration
npm run test:real-k8s
```

### Real Kubernetes Operations
```bash
# Basic cluster operations
kubectl get nodes
kubectl get namespaces
kubectl get pods --all-namespaces

# Observe specific namespaces
kubectl get pods -n observability
kubectl get pods -n default
kubectl get pods -n kube-system

# Check cluster health
kubectl top nodes
kubectl get events --all-namespaces --sort-by=.lastTimestamp

# Describe resources
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>
```

## 🏗️ Dev Environment Architecture

```
Local Machine                     Remote K8s Cluster (192.168.254.220)
┌─────────────────┐              ┌────────────────────────────────────┐
│                 │              │                                    │
│  AIDA Agents    │              │  ┌─────────────────────────────┐   │
│  ├─ Gateway     │              │  │     observability namespace │   │
│  ├─ Investigator│              │  │  ├─ postgresql              │   │
│  └─ K8s Analyzer│              │  │  ├─ redis                   │   │
│                 │   SSH Tunnel │  │  └─ clickhouse              │   │
│  localhost:8000 │◄─────────────┤  └─────────────────────────────┘   │
│  localhost:8001 │              │                                    │
│  localhost:8002 │              │  ┌─────────────────────────────┐   │
│                 │              │  │        default namespace    │   │
│  Port Forwarding│              │  │  └─ (application pods)      │   │
│  ├─ :5432  ──────┼──────────────┤  └─────────────────────────────┘   │
│  ├─ :6379  ──────┼──────────────┤                                    │
│  ├─ :8123  ──────┼──────────────┤  ┌─────────────────────────────┐   │
│  └─ :6443  ──────┼──────────────┤  │      kube-system namespace │   │
│                 │              │  │  └─ (system pods)           │   │
└─────────────────┘              │  └─────────────────────────────┘   │
                                 └────────────────────────────────────┘
```

## 🧪 Real K8s Testing Capabilities

### Available Test Scenarios
- **Real Cluster Analysis**: Actual node and pod inspection
- **Live Health Monitoring**: Real-time cluster health assessment
- **Performance Testing**: Actual response time measurement
- **Security Validation**: Real RBAC and permission testing

### Integration Testing
```typescript
// Example: Real K8s integration test
import { RealKubernetesExecutor } from '@shared/testing/real-k8s-executor';

const k8sExecutor = new RealKubernetesExecutor();

// Test real cluster connectivity
const result = await k8sExecutor.executeCommand('kubectl get nodes');
expect(result.exitCode).toBe(0);
expect(result.stdout).toContain('Ready');

// Get actual cluster information
const clusterInfo = await k8sExecutor.getClusterInfo();
console.log(`Cluster has ${clusterInfo.nodes} nodes`);
console.log(`Available namespaces: ${clusterInfo.namespaces.join(', ')}`);
```

## 📁 Key Files Created

### Scripts & Automation
- `scripts/setup-dev-env.sh` - Complete dev environment setup
- `scripts/validate-dev-env.sh` - Comprehensive validation
- `.env.dev` - Dev environment configuration

### Real K8s Framework
- `src/shared/testing/real-k8s-executor.ts` - Real K8s command execution
- `test/integration/dev-environment-integration.test.ts` - Integration tests

### Configuration Files
- `~/.kube/remote-clusters/master-config` - Remote cluster kubeconfig
- Various PID files for tunnel management

## 🔧 Troubleshooting

### 🚨 Critical Issues Resolution

#### HTTPS/HTTP Protocol Mismatch (Fixed)
**Problem**: `http: server gave HTTP response to HTTPS client`
**Solution**: Use fixed scripts with `insecure-skip-tls-verify: true`
```bash
# Use fixed setup script
./scripts/setup-dev-env-fixed.sh restart

# Verify kubeconfig has insecure-skip-tls-verify
grep "insecure-skip-tls-verify" ~/.kube/remote-clusters/master-config
```

#### Port Conflicts with Local Services
**Problem**: Mock K8s API or other services using port 6443
**Solution**: Fixed script automatically stops conflicting services
```bash
# Manual cleanup if needed
docker stop aida-mock-k8s-api
lsof -ti :6443 | xargs kill -9

# Then restart dev environment
./scripts/setup-dev-env-fixed.sh start
```

### SSH Tunnel Issues
```bash
# Check SSH connectivity
ping 192.168.254.220

# Test SSH login with password
sshpass -p "Wonder9595!!" ssh wondermove@192.168.254.220

# Restart SSH tunnel (fixed script)
./scripts/setup-dev-env-fixed.sh restart

# Check tunnel status (fixed script)
./scripts/setup-dev-env-fixed.sh status
```

### K8s Connectivity Issues
```bash
# Check kubeconfig (should have insecure-skip-tls-verify)
kubectl config view --kubeconfig=~/.kube/remote-clusters/master-config

# Test cluster access (fixed config)
export KUBECONFIG=~/.kube/remote-clusters/master-config
kubectl cluster-info

# Check API server accessibility
curl -k https://localhost:6443/version

# Test with fixed validation
./scripts/validate-dev-env-fixed.sh

# Verify 5 nodes are accessible
kubectl get nodes
```

### Port Forwarding Issues
```bash
# Check what's using ports
lsof -i :6443  # K8s API
lsof -i :5432  # PostgreSQL
lsof -i :6379  # Redis
lsof -i :8123  # ClickHouse

# Restart specific port forwarding
kubectl port-forward -n observability svc/postgresql 5432:5432
```

### Database Connection Issues
```bash
# Test PostgreSQL connection
PGPASSWORD="Wonder9595!!" psql -h localhost -p 5432 -U postgres -d postgres -c "SELECT 1;"

# Check PostgreSQL pod status
kubectl get pods -n observability -l app=postgresql

# View PostgreSQL logs
kubectl logs -n observability deployment/postgresql
```

## 🎯 Development Workflow

### 1. Daily Setup
```bash
# Start dev environment
npm run setup:dev

# Validate everything is working
npm run validate:dev

# Set kubectl context
export KUBECONFIG=~/.kube/remote-clusters/master-config

# Test K8s access
kubectl get nodes
```

### 2. Development & Testing
```bash
# Start development servers
npm run dev:all

# Run integration tests against real cluster
npm run test:dev-integration

# Test specific K8s operations
npm run test:real-k8s

# Manual testing
kubectl get pods -n observability
kubectl describe node <node-name>
```

### 3. Real Cluster Operations
```bash
# Investigate actual cluster issues
kubectl get events --all-namespaces --sort-by=.lastTimestamp

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Analyze specific pods
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

### 4. Validation & Cleanup
```bash
# Validate dev environment periodically
npm run validate:dev

# Stop when done
./scripts/setup-dev-env.sh stop
```

## 📈 Performance Expectations

### Dev Environment Targets
- **Setup time**: < 5 minutes
- **K8s API response**: < 1 second
- **Database queries**: < 200ms
- **SSH tunnel stability**: 99%+ uptime

### Monitoring
```bash
# Check tunnel status
./scripts/setup-dev-env.sh status

# Monitor K8s performance
kubectl top nodes
kubectl get events --watch

# Test response times
npm run validate:dev  # Includes performance tests
```

## 🔐 Security Considerations

### SSH Tunnel Security
- Uses password-based authentication (for dev only)
- Tunnels are localhost-only bound
- Automatic cleanup on script termination

### K8s Access Control
- Read-only mode enforced by default
- Namespace whitelist validation
- Command validation before execution
- No destructive operations allowed

### Network Security
- All traffic goes through encrypted SSH tunnel
- No direct cluster exposure
- Local firewall rules apply

## 🔗 Integration with Other Environments

### Transition from Local (Phase 1)
- Mock strategies remain available for offline development
- Seamless switching between mock and real K8s
- Same development workflow and APIs

### Preparation for Production (Phase 3)
- Same kubectl commands and workflows
- Similar network patterns and security
- Real performance and behavior validation

## 🎉 Next Steps

After successful dev environment setup:
1. **Validate Connectivity**: `./scripts/validate-dev-env-fixed.sh`
2. **Test K8s Access**: `kubectl get nodes` (should show 5 nodes)
3. **Run Integration Tests**: `npm run test:dev-integration`
4. **Start Development**: Begin implementing with real cluster
5. **Access Services**:
   - PostgreSQL: `nc -z localhost 5432`
   - ClickHouse: `curl http://localhost:8123/ping`
   - K8s API: `kubectl cluster-info`
6. **Prepare for Production**: Use learnings for Phase 3

## 🔧 Quick Commands Reference

```bash
# Complete setup and validation
./scripts/setup-dev-env-fixed.sh start
./scripts/validate-dev-env-fixed.sh

# Daily development workflow
export KUBECONFIG=~/.kube/remote-clusters/master-config
kubectl get nodes  # Should show: master, worker001-004
npm run dev:all

# Status checking
./scripts/setup-dev-env-fixed.sh status
```

## 📊 Success Metrics

- ✅ SSH tunnel stability: 99%+ uptime
- ✅ K8s operations: < 1s response time
- ✅ Database connectivity: < 200ms latency
- ✅ Integration tests: 100% pass rate
- ✅ Security validation: All commands properly validated

---

**📞 Support**: For issues with dev environment, check troubleshooting section above or validate environment with `npm run validate:dev`

**🔄 Migration**: From local to dev environment is seamless - use `npm run setup:dev` after completing Phase 1