# 🛠️ **AIDA SCRIPTS COLLECTION - Phase 2 Essential Scripts**

<!-- Tags: #scripts #phase2 #database #security #infrastructure #validation -->

> **PURPOSE**: Essential scripts for Phase 2 deployment - database management, security validation, and infrastructure testing  
> **SCOPE**: Database setup, migrations, security compliance, infrastructure validation, code quality  
> **COMPLEXITY**: ⭐⭐⭐⭐ Expert | **DURATION**: Varies by script  
> **PHASE**: Phase 2 - Production-Ready System

---

## ⚡ **QUICK NAVIGATION - Phase 2 Essential Scripts**

### 🎯 **Database Management**
```bash
# PostgreSQL & ClickHouse Setup
1. [Database Setup](./database/setup-database.ts)           # Initialize AIDA databases
2. [Run Migrations](./database/run-migrations.ts)          # Execute database migrations

### 🔍 **MCP Search Integration**
```bash
# Document Search Fallback (when standard tools fail)
1. [MCP Usage Guide](./mcp/USAGE-MCP.md)                    # Vector search for AIDA documentation
2. [MCP Scripts](./mcp/)                                    # MCP server integration tools

# Infrastructure Testing
3. [Infrastructure Test Setup](./infrastructure/infrastructure-test-setup.ts) # K8s & DB connectivity
4. [Connection Validator](./infrastructure/validate-connections.ts)          # Validate all connections

# K8s Remote Access
5. [SSH Tunnel Setup](./k8s-remote/setup_k8s_ssh_tunnel.sh)       # SSH tunnel for K8s access
6. [K8s Remote Install](./k8s-remote/install_k8s_remote_access.sh) # Auto-install K8s remote access

# Security & Compliance
7. [Security Validator](./security/validate-security.ts)    # CLAUDE.md compliance checking
8. [Quick Validation](./validation/validate-quick-stable.ts) # Fast (<30s) stable validation

# Code Quality & Maintenance
9. [Circular Dependency Checker](./maintenance/check-circular-deps.ts)  # Detect circular imports
10. [ESLint Fixer](./maintenance/fix-eslint-errors.ts)                # Automated code quality repair
11. [TDD Enforcer](./tdd-enforcer.ts)                                # Test-driven development automation
```

### 🔍 **Phase 2 Deployment Flow**
```
Infrastructure Setup → Database Init → Security Validation → Code Quality → Production Ready
        ↓                   ↓                ↓                    ↓               ↓
   SSH Tunnel          PostgreSQL       CLAUDE.md Check      ESLint Fix    Health Monitoring
```

---

## 📋 **PHASE 2 SCRIPT COMPONENTS**

### **Database Management Scripts**
| Script | Purpose | Key Features | Complexity |
|--------|---------|--------------|------------|
| **[Database Setup](./database/setup-database.ts)** | PostgreSQL initialization | Schema creation, table setup, views | ⭐⭐⭐⭐ |
| **[Run Migrations](./database/run-migrations.ts)** | Database migrations | Version control, rollback support | ⭐⭐⭐⭐ |

### **Infrastructure & Testing Scripts**
| Script | Purpose | Key Features | Complexity |
|--------|---------|--------------|------------|
| **[Infrastructure Test Setup](./infrastructure/infrastructure-test-setup.ts)** | K8s & DB connectivity | SSH tunnel, port forwarding, health checks | ⭐⭐⭐⭐⭐ |
| **[Connection Validator](./infrastructure/validate-connections.ts)** | Connection validation | PostgreSQL, K8s, network testing | ⭐⭐⭐⭐ |

### **K8s Remote Access Scripts**
| Script | Purpose | Key Features | Complexity |
|--------|---------|--------------|------------|
| **[SSH Tunnel Setup](./k8s-remote/setup_k8s_ssh_tunnel.sh)** | K8s SSH tunnel management | start/stop/status/restart commands, persistent tunnel | ⭐⭐⭐⭐ |
| **[K8s Remote Install](./k8s-remote/install_k8s_remote_access.sh)** | Auto-install remote access | Interactive setup, kubectl wrapper, config generation | ⭐⭐⭐⭐⭐ |

### **Security & Compliance Scripts**
| Script | Purpose | Key Features | Complexity |
|--------|---------|--------------|------------|
| **[Security Validator](./security/validate-security.ts)** | CLAUDE.md compliance | Security coverage, compliance scoring | ⭐⭐⭐⭐⭐ |
| **[Quick Validation](./validation/validate-quick-stable.ts)** | Fast validation (<30s) | Stable tests, no hanging, quick feedback | ⭐⭐⭐⭐ |

### **Code Quality Scripts**
| Script | Purpose | Key Features | Complexity |
|--------|---------|--------------|------------|
| **[Circular Dependency Checker](./maintenance/check-circular-deps.ts)** | Import cycle detection | Dependency graph analysis | ⭐⭐⭐⭐ |
| **[ESLint Fixer](./maintenance/fix-eslint-errors.ts)** | Code quality repair | Auto-fix patterns, style enforcement | ⭐⭐⭐⭐ |
| **[TDD Enforcer](./tdd-enforcer.ts)** | TDD automation | Red-Green-Refactor enforcement | ⭐⭐⭐⭐⭐ |

---

## 🚀 **PHASE 2 SCRIPT WORKFLOWS**

### **🎯 Initial Infrastructure Setup**
```bash
# Phase 2 infrastructure preparation
1. cd Docs/scripts/k8s-remote && ./setup_k8s_ssh_tunnel.sh start         # Start SSH tunnel
2. export KUBECONFIG=~/.kube/remote-clusters/master-config               # Set K8s config
3. kubectl port-forward -n observability svc/postgresql 5432:5432         # PostgreSQL forwarding
4. npm run infrastructure:test                                            # Test connectivity
5. npm run db:setup                                                       # Initialize database
6. npm run db:migrate                                                     # Run migrations
```

### **🔧 Security & Compliance Workflow**
```bash
# Security validation for production
1. npm run validate:security               # Full security compliance check
2. npm run validate:quick                  # Quick validation (<30s)
3. npm run check:circular-deps             # Check for circular dependencies
4. npm run test:security                   # Security-specific tests
```

### **📊 Code Quality Workflow**
```bash
# Code quality assurance
1. npm run lint -- --quiet                 # Check ESLint violations
2. npm run fix:eslint                      # Auto-fix ESLint errors
3. npm run typecheck                       # TypeScript compilation check
4. npm run build                           # Build verification
```

---

## 🎯 **PHASE 2 SCRIPT ARCHITECTURE**

### **Database Management Architecture**
```typescript
interface DatabaseManagementArchitecture {
  postgresqlSetup: "PostgreSQL schema initialization and table creation";
  migrationSystem: "Version-controlled database migrations with rollback";
  connectionValidation: "Database connectivity and health checking";
  environmentConfig: "Environment-based database configuration";
  securityCompliance: "Secure connection handling and credential management";
}
```

### **Infrastructure Testing Architecture**
```typescript
interface InfrastructureTestingArchitecture {
  sshTunnelValidation: "SSH tunnel connectivity and kubectl access";
  kubernetesAccess: "K8s cluster connectivity and namespace validation";
  databaseConnectivity: "PostgreSQL port forwarding and connection testing";
  environmentGeneration: "Test environment configuration generation";
  healthMonitoring: "Infrastructure component health checks";
}
```

### **Security Compliance Architecture**
```typescript
interface SecurityComplianceArchitecture {
  claudeMdCompliance: "CLAUDE.md requirements validation and enforcement";
  securityCoverage: "Security test coverage analysis and reporting";
  violationDetection: "Critical security violation identification";
  complianceScoring: "Automated compliance score calculation";
  quickValidation: "Fast, stable validation without hanging";
}
```

---

## 🚨 **PHASE 2 SCRIPT REQUIREMENTS**

### **MUST IMPLEMENT (Phase 2 Standards)**
```typescript
// ✅ Required Phase 2 script standards
MUST VALIDATE: Infrastructure connectivity before operations
MUST SECURE: All database connections with proper credentials
MUST CHECK: CLAUDE.md compliance for security requirements
MUST ENFORCE: Quick validation (<30s) for fast feedback
MUST HANDLE: Error recovery and rollback mechanisms
MUST LOG: All operations for audit and debugging
```

### **NEVER VIOLATE (Phase 2 Violations)**
```typescript
// ❌ Forbidden Phase 2 practices
NEVER STORE: Database credentials in code or logs
NEVER SKIP: SSH tunnel validation for K8s access
NEVER EXECUTE: Untested database migrations in production
NEVER IGNORE: Security validation failures
NEVER BYPASS: Infrastructure health checks
NEVER DEPLOY: Without running validate:quick first
```

---

## 📊 **PHASE 2 SCRIPT METRICS**

### **Production Readiness Indicators**
```typescript
const phase2Metrics = {
  infrastructure_connectivity: "100% SSH tunnel and K8s access validation",
  database_reliability: "100% PostgreSQL connection success rate",
  security_compliance: "100% CLAUDE.md requirement adherence",
  validation_speed: "<30 seconds for quick validation",
  migration_safety: "100% rollback capability for all migrations",
  error_recovery: "100% graceful error handling and recovery"
};
```

### **Phase 2 Validation Commands**
```bash
# Phase 2 script validation
npm run validate:quick                   # Fast validation (<30s)
npm run validate:all                     # Full validation with coverage
npm run validate:security                # Security compliance check
npm run test:infrastructure              # Infrastructure connectivity
npm run test:db                          # Database connection testing
```

---

## 🔧 **PHASE 2 EXECUTION PROCEDURES**

### **Database Setup Procedures**
```bash
# PostgreSQL database initialization
1. Ensure SSH tunnel is active
2. Start PostgreSQL port forwarding
3. npm run db:setup                      # Initialize database schema
4. npm run db:migrate                    # Run pending migrations
5. npm run test:db                       # Verify database connectivity
```

### **Infrastructure Testing Procedures**
```bash
# Infrastructure validation
1. ./infrastructure-test-setup.ts        # Generate test report
2. npm run test:infrastructure           # Validate all connections
3. Review .env.infrastructure-test       # Check generated config
```

### **Security Validation Procedures**
```bash
# Security and compliance checking
1. npm run validate:security             # Full security audit
2. npm run validate:quick                # Quick validation (<30s)
3. Review reports in docs/reports/       # Check compliance results
```

---

## 📚 **RELATED DOCUMENTATION**

### **Development Integration**
- **[TDD Implementation Guide](../code-guide/02-development/tdd-implementation.md)** - TDD methodology, test-driven development, red-green-refactor cycle, automation integration
- **[Development Standards](../code-guide/02-development/README.md)** - development standards, TypeScript patterns, quality guidelines, automation workflows
- **[Quick Start Development](../code-guide/01-quick-start/README.md)** - development environment setup, tool configuration, script integration

### **Quality Assurance Context**
- **[Code Quality Guidelines](../code-guide/04-code-quality/README.md)** - quality patterns, implementation standards, automated validation, script integration
- **[ESLint Configuration](../code-guide/02-development/eslint-configuration.md)** - ESLint rules, automated fixing, quality enforcement, script automation
- **[Testing Strategies](../code-guide/06-testing/README.md)** - testing methodologies, automation integration, quality validation, script testing

### **Documentation Standards**
- **[Documentation Guidelines](../reference/documentation-guidelines.md)** - writing standards, format rules, validation requirements, automation integration
- **[Documentation Creation Workflow](../reference/documentation-creation-workflow.md)** - creation workflows, quality standards, automated validation
- **[Documentation Efficiency](../reference/documentation-advanced-features.md)** - advanced features, efficiency optimization, measurement automation

### **System Integration**
- **[Getting Started Guide](../getting-started/README.md)** - project onboarding, script integration, automation workflow, development setup
- **[Development Environment](../development/README.md)** - development setup, script integration, automation tools, quality enforcement
- **[Operations Guide](../operations/README.md)** - production deployment, automation integration, quality assurance, monitoring

### **Architecture Context**
- **[System Architecture](../getting-started/architecture-overview.md)** - system design, automation integration, quality architecture, script architecture
- **[Gateway Architecture](../agents/gateway/architecture/README.md)** - agent architecture, quality integration, automation patterns, script integration
- **[Investigator Architecture](../agents/investigator/architecture/README.md)** - investigation architecture, quality validation, automation integration

---

## 🎯 **USAGE SCENARIOS**

### **For Developers**
```bash
# Complete development automation workflow
1. npm run tdd:start new-feature          # Start TDD development
2. npm run tdd:red                        # Validate failing tests
3. npm run tdd:green                      # Validate passing tests
4. npm run tdd:refactor                   # Validate refactoring quality
5. npm run quality:check                  # Final quality validation
```

### **For Quality Engineers**
```bash
# Quality assurance automation workflow
1. npm run quality:check                  # Complete quality validation
2. npm run fix:eslint                     # Automated error correction
3. npm run validate:docs                  # Documentation compliance
4. npm run analyze:patterns               # Pattern analysis
```

### **For Documentation Teams**
```bash
# Documentation automation workflow
1. npm run docs:validate                  # Validate documentation
2. npm run validate:connections           # Check cross-references
3. npm run measure:efficiency             # Measure efficiency
4. npm run docs:optimize                  # Optimize structure
```

### **For DevOps Engineers**
```bash
# CI/CD automation workflow
1. npm run scripts:validate               # Validate all scripts
2. npm run scripts:test                   # Test script functionality
3. npm run scripts:performance            # Performance benchmarking
4. npm run scripts:deploy                 # Deploy automation scripts
```

---

## 💡 **SCRIPT BEST PRACTICES**

### **TDD Automation Strategy**
1. **Phase Validation** - Enforce Red-Green-Refactor cycle compliance
2. **Test Coverage** - Maintain 90% minimum test coverage
3. **Quality Gates** - Automated quality validation at each phase
4. **State Management** - Track TDD cycle state and progression

### **Quality Automation Implementation**
1. **ESLint Integration** - Automated error detection and repair
2. **TypeScript Validation** - Continuous type checking and validation
3. **Performance Monitoring** - Script execution performance optimization
4. **Error Handling** - Comprehensive error handling and recovery

### **Documentation Automation**
1. **Link Validation** - Automated cross-reference checking
2. **Format Compliance** - Markdown format validation and enforcement
3. **Efficiency Measurement** - Documentation efficiency analytics
4. **Pattern Analysis** - Usage pattern optimization recommendations

### **Script Quality Maintenance**
1. **TypeScript Compliance** - All scripts written in TypeScript
2. **Error Handling** - Comprehensive error handling and logging
3. **Performance Optimization** - Sub-second execution time target
4. **Test Coverage** - 100% script functionality test coverage

---

## 🔧 **SCRIPT TROUBLESHOOTING**

### **Common Script Issues**
```typescript
const scriptIssues = {
  tdd_validation_failures: "TDD cycle validation errors or phase violations",
  eslint_fix_failures: "ESLint automated fixing errors or conflicts",
  documentation_validation_errors: "Markdown validation or compliance issues",
  link_validation_failures: "Broken cross-references or invalid links",
  performance_degradation: "Script execution performance issues"
};
```

### **Resolution Strategies**
```bash
# Script troubleshooting procedures
npm run scripts:diagnose                 # Diagnose script issues
npm run scripts:repair                   # Repair script configuration
npm run scripts:reset                    # Reset script environment
npm run scripts:validate                 # Validate script integrity
npm run scripts:optimize                 # Optimize script performance
```

### **Emergency Procedures**
```bash
# Emergency script recovery
npm run scripts:emergency                # Emergency script recovery
npm run scripts:backup                   # Backup current scripts
npm run scripts:restore                  # Restore from backup
npm run scripts:rebuild                  # Rebuild script environment
```

---

## 📊 **SCRIPT PERFORMANCE MONITORING**

### **Real-time Script Monitoring**
```bash
# Script performance monitoring
npm run scripts:monitor                  # Real-time script monitoring
npm run scripts:performance              # Performance analysis
npm run scripts:metrics                  # Execution metrics
npm run scripts:health                   # Script health check
```

### **Script Analytics**
```bash
# Script usage analytics
npm run scripts:analytics                # Script usage analytics
npm run scripts:efficiency               # Script efficiency measurement
npm run scripts:optimization             # Script optimization analysis
npm run scripts:report                   # Comprehensive script report
```

---

## 🚀 **SCRIPT AUTOMATION FEATURES**

### **Advanced TDD Features**
- **Phase State Management** - Complete TDD cycle state tracking
- **Coverage Integration** - Automated test coverage validation
- **Quality Gate Enforcement** - Automated quality standard enforcement
- **Cycle Automation** - Full Red-Green-Refactor cycle automation

### **Quality Assurance Features**
- **Error Auto-Correction** - Automated ESLint error repair
- **TypeScript Validation** - Continuous type checking
- **Performance Optimization** - Script execution optimization
- **Compliance Monitoring** - Quality standard compliance tracking

### **Documentation Features**
- **Link Integrity** - Automated cross-reference validation
- **Format Compliance** - Markdown format enforcement
- **Efficiency Analytics** - Documentation efficiency measurement
- **Pattern Recognition** - Usage pattern analysis and optimization

---

## 📁 **SCRIPT ORGANIZATION**

### **Directory Structure**
```
docs/scripts/
├── README.md                          # This file
├── database/                          # Database management scripts
│   ├── README.md
│   ├── setup-database.ts              # PostgreSQL initialization
│   └── run-migrations.ts              # Migration execution
├── infrastructure/                    # Infrastructure testing scripts
│   ├── README.md
│   ├── infrastructure-test-setup.ts   # K8s & DB connectivity testing
│   └── validate-connections.ts        # Connection validation
├── k8s-remote/                        # K8s remote access scripts
│   ├── README.md
│   ├── setup_k8s_ssh_tunnel.sh        # SSH tunnel management
│   └── install_k8s_remote_access.sh   # Auto-install script
├── security/                          # Security validation scripts
│   ├── README.md
│   ├── validate-security.ts           # CLAUDE.md compliance
│   └── validate-quick-stable.ts       # Fast stable validation
├── validation/                        # General validation scripts
│   ├── README.md
│   └── validate-docs.ts               # Documentation validation
├── maintenance/                       # Code maintenance scripts
│   ├── README.md
│   ├── check-circular-deps.ts         # Circular dependency detection
│   ├── fix-eslint-errors.ts           # ESLint auto-fix
│   └── analyze-usage-patterns.ts      # Usage pattern analysis
├── error-resolution/                  # Error handling scripts
│   ├── README.md
│   ├── check-specific-file.sh         # Single file checking
│   ├── enforce-workflow.sh            # Workflow enforcement
│   └── find-worst-file.sh             # Find problematic files
└── tdd-enforcer.ts                    # TDD cycle automation
```

### **Script Categories**
- **Critical for Phase 2**: database/, infrastructure/, k8s-remote/, security/, validation/
- **Code Quality**: maintenance/, error-resolution/
- **Development Process**: tdd-enforcer.ts

---

## 🚀 **PHASE 2 DEPLOYMENT CHECKLIST**

### **Pre-Deployment**
- [ ] K8s remote access installed (`./k8s-remote/install_k8s_remote_access.sh`)
- [ ] SSH tunnel active and validated (`./k8s-remote/setup_k8s_ssh_tunnel.sh start`)
- [ ] KUBECONFIG set to remote cluster config
- [ ] PostgreSQL port forwarding established
- [ ] Environment variables configured
- [ ] Infrastructure test passed
- [ ] Database schema initialized
- [ ] Migrations executed successfully

### **Security Validation**
- [ ] CLAUDE.md compliance: 100%
- [ ] Security test coverage: 100%
- [ ] No critical violations
- [ ] Quick validation passes (<30s)

### **Code Quality**
- [ ] No circular dependencies
- [ ] ESLint errors resolved
- [ ] TypeScript compilation passes
- [ ] Build verification complete

### **Final Validation**
- [ ] `npm run validate:quick` passes
- [ ] `npm run validate:all` passes
- [ ] All tests green
- [ ] Documentation updated

---

**🔑 Key Message**: Phase 2 scripts provide essential infrastructure for production deployment, focusing on database management, security compliance, and infrastructure validation. All scripts are organized for easy discovery and execution, supporting the transition from Phase 1 (2-agent system) to Phase 2 (full production deployment).