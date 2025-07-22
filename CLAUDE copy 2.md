# CLAUDE.md - AIDA Project Guidelines

**AIDA**: AI-Driven Incident Diagnosis & Analysis System
**Current Phase**: Phase 2 - K8s Health Analyzer & Alert Storm Management
**Business Context**: $5.58M/year contract, 93 banks, 3,000-10,000 alerts/hour capability

## 🌐 Communication Guidelines

**IMPORTANT**: When responding to users, ALWAYS provide explanations and descriptions in English. This ensures consistency and clarity in technical communication.

## 🚨 Critical Rules (MUST FOLLOW)

1. **NEVER use `any` type** - always define proper TypeScript types
2. **NEVER skip A2A protocol** - all agent communication via Task/Message/Artifact
3. **ALWAYS run validation** - `npm run validate:quick` before ANY commit
4. **ALWAYS follow TDD** - write test first, then implement
5. **Documentation Location** - Create docs ONLY in `@Project_Docs/`
   - Active: `@Project_Docs/active/`
   - Complete: `@Project_Docs/complete/`
   - Reference: `@Docs/` (read-only)
6. **DOCUMENTATION-FIRST PROTOCOL** - MANDATORY before ANY action:
   a) Identify relevant documentation for user instruction
   b) Check if you remember the document content
   c) If not found in Quick References → Explore category folders
   d) If not remembered → Read the document FIRST
   e) Then execute the instruction based on documentation
7. **ALWAYS follow RED-GREEN-REFACTOR-COMMIT cycle** - No exceptions
   - RED: Test first (failing test required)
   - GREEN: Minimal implementation
   - REFACTOR (BLUE): Apply quality patterns
   - COMMIT: Use `/commit` to trigger quality verification
8. **Pre-commit validation MANDATORY** - Automatic quality gates
   - TypeScript compilation check
   - ESLint with Korean error messages
   - Test execution for changed files
   - Code pattern validation
   - Method length check (<30 lines)

## 📖 Mandatory Documentation Workflow (MUST FOLLOW)

### 🚨 BEFORE EXECUTING ANY USER INSTRUCTION:

#### Step 1: Documentation Identification
- **ALWAYS** identify which documentation relates to the user's instruction
- Check "📁 Quick References" section for relevant paths
- Map user instruction to specific documentation files

#### Step 2: Documentation Discovery (if not in Quick References)
- **IF** relevant document not found in Quick References:
  - Identify appropriate category folder (agents/, architecture/, code-guide/, etc.)
  - **USE LS tool** to explore the category folder structure
  - **USE Grep tool** to search for specific topics within category
  - Map user instruction to discovered documentation

#### Step 2.5: MCP Search Fallback (if LS/Grep fails)
- **IF** standard search tools cannot locate documentation:
  - **REFER TO**: `Docs/scripts/mcp/USAGE-MCP.md` for MCP search guidance
  - **USE MCP search**: AIDA project (ID: a17256e5) with confidence_threshold 0.3-0.5
  - **EXAMPLE**: `search_docs --query "your topic" --project_id "a17256e5" --confidence_threshold 0.3`
  - **ESCALATE**: Lower confidence_threshold to 0.1 if no results found

#### Step 3: Memory Verification
- **ASK YOURSELF**: "Do I remember the current content of this documentation?"
- If uncertain about ANY detail → Proceed to Step 4
- If confident → Proceed to Step 5

#### Step 4: Documentation Review (MANDATORY if uncertain)
- **READ** the identified documentation files using Read tool
- **UNDERSTAND** current implementation status
- **NOTE** any recent changes or updates

#### Step 5: Instruction Execution
- Execute user instruction **BASED ON** documentation content
- Follow patterns and standards from documentation
- Maintain consistency with documented approaches

### ❌ PROHIBITED WORKFLOWS:
- Executing instructions without documentation check
- Assuming documentation content without verification
- Skipping folder exploration when documents not in Quick References
- Using outdated memory of documentation

### ✅ REQUIRED PATTERN:
```
User: "Implement X feature"
✅ Process:
1. Identify: "This relates to Docs/agents/[component]/implementation/"
2. Discover: [Use LS/Grep if not in Quick References]
3. Check: "Do I remember current implementation patterns?"
4. Read: [Read relevant documentation if uncertain]
5. Execute: [Implement based on documentation guidelines]

❌ Wrong:
1. Implement directly without documentation check
```

### 📂 Documentation Category Mapping:
- **Agent Implementation**: `Docs/agents/[agent-name]/`
- **Architecture & Design**: `Docs/architecture/`
- **Code Quality & TDD**: `Docs/code-guide/`
- **Infrastructure Setup**: `Docs/infrastructure/`
- **Operations & Deployment**: `Docs/operations/`
- **Testing Strategies**: `Docs/code-guide/06-testing/`
- **A2A Protocol**: `Docs/reference/a2a-spec-v0.2.5/`
- **Phase 2 Development Process**: `Docs/development-process/`

## 🔄 Phase 2 Development Cycle

### Mandatory Development Process
```bash
# 1. RED Phase - Test First
npm run generate:test <component>  # Generate test template
# Write failing test

# 2. GREEN Phase - Minimal Implementation
# Implement only to pass test

# 3. REFACTOR Phase - Apply Patterns
# Extract methods, apply DI, ensure <30 lines

# 4. COMMIT Phase - Quality Verification through Claude Code
/commit -m "feat: your commit message"
# Pre-commit hook automatically runs all quality gates
# If fail: Fix issues and retry
# If pass: Commit completes successfully
```

### Pre-commit Enforcement
All commits automatically validated. Failures block commit with Korean error messages:
- ❌ TypeScript 오류: "타입 안전성 검증 실패"
- ❌ ESLint 오류: "코드 품질 규칙 위반"
- ❌ Test 오류: "테스트 실패 - TDD 원칙 위반"
- ❌ Pattern 오류: "금지된 패턴 사용"
- ❌ Method 오류: "30줄 초과 메소드"

## 🏗️ Architecture Overview

```
Gateway Agent (:8000) → A2A Protocol → Smart Investigator (:8001)
                                    ↘ K8s Health Analyzer (:8002)
```

**K8s Problem Distribution**: 35% Node, 30% Network, 20% Storage, 10% Config, 5% Pod

## 📁 Quick References

### Development & Code Quality
- **Complete Development Guide**: [Docs/code-guide/README.md](./Docs/code-guide/README.md) - test-driven development methodology, TypeScript strict mode enforcement, ESLint configuration rules, import path guidelines, error handling patterns, dependency injection container, method design principles, security validation guidelines, testing strategy implementation, code quality standards
- **Phase 2 TDD Guidelines**: [Docs/development-process/phase2-tdd-guidelines.md](./Docs/development-process/phase2-tdd-guidelines.md) - RED-GREEN-REFACTOR-VERIFY cycle, K8s Health Analyzer patterns, alert storm handling examples, layer analysis implementation, mandatory test patterns
- **Quality Gates Reference**: [Docs/development-process/quality-gates.md](./Docs/development-process/quality-gates.md) - pre-commit validation rules, Korean error messages, resolution guides, automated enforcement, quality metrics

### Architecture & Infrastructure  
- **Getting Started**: [Docs/getting-started/README.md](./Docs/getting-started/README.md) - project onboarding workflow, system architecture overview, agent-to-agent protocol concepts, quick setup procedures, development environment initialization, basic concepts understanding
- **Development Environment**: [Docs/development/README.md](./Docs/development/README.md) - technology stack configuration, environment variables management, development tools setup, Node.js runtime, TypeScript compilation, package dependencies
- **Infrastructure Setup**: [Docs/infrastructure/README.md](./Docs/infrastructure/README.md) - PostgreSQL database configuration, Kubernetes port forwarding, SSH tunnel establishment, monitoring systems, security protocols, connection validation

### Agent Implementation
- **All Agents Guide**: [Docs/agents/README.md](./Docs/agents/README.md) - Gateway Agent architecture, Smart Investigator implementation, K8s Health Analyzer design, agent-to-agent integration patterns, webhook handling, task coordination, message routing
- **K8s Health Analyzer**: [Docs/agents/k8s-health-analyzer/README.md](./Docs/agents/k8s-health-analyzer/README.md) - holistic Kubernetes analysis, golden command execution, alert storm management, five-layer diagnostic approach, node-network-storage-config-pod analysis

### Operations & Reference
- **Operations Guide**: [Docs/operations/README.md](./Docs/operations/README.md) - production deployment procedures, system monitoring configuration, troubleshooting workflows, operational maintenance, performance optimization
- **Scripts Collection**: [Docs/scripts/README.md](./Docs/scripts/README.md) - database initialization scripts, Kubernetes SSH tunnel automation, security compliance validation, ESLint error fixing, test-driven development enforcer, infrastructure connectivity testing, database migration tools
- **MCP Search Fallback**: [Docs/scripts/mcp/USAGE-MCP.md](./Docs/scripts/mcp/USAGE-MCP.md) - vector search capability for AIDA documentation when standard tools fail, confidence threshold optimization, project ID a17256e5
- **A2A Protocol Reference**: [Docs/reference/README.md](./Docs/reference/README.md) - agent-to-agent protocol specification v0.2.5, implementation examples, integration best practices, authentication methods, message formatting, task lifecycle management

## 🚀 Essential Commands

### Validation (Optional for Local Testing)

```bash
npm run validate:quick    # ⭐ Local testing (optional)
npm run validate:all      # Full validation with coverage
npm run validate:fix      # Auto-fix common issues
```

### Phase 2 Development Commands

```bash
# Development Cycle
npm run generate:test     # Generate test template
npm run test:single       # Run single test file
npm run test:changed      # Test changed files only

# K8s Health Analyzer Specific
npm run test:k8s          # K8s Health Analyzer tests
npm run test:storm        # Alert Storm performance tests

# Quality Audits
npm run audit:patterns    # Check forbidden patterns
npm run audit:methods     # Check method length
npm run audit:all         # All quality checks
```

### Development

```bash
npm run dev:gateway       # Start Gateway Agent
npm run dev:investigator  # Start Smart Investigator
npm run dev:k8s-analyzer  # Start K8s Health Analyzer
npm run dev:all          # Start all agents
```

### Database

```bash
npm run db:setup         # Initialize database
npm run db:migrate       # Run migrations
```

### Testing

```bash
npm run test:run         # Run tests once
npm run test:security    # Security validation
npm run coverage         # Coverage report
```

## 📦 Import Pattern

```typescript
// Standard imports
import { CommandValidator } from '@shared/validators/command-validator';
import { GatewayAgent } from '@agents/gateway/src/gateway-agent';
import type { Alert } from '@shared/types/alert';
```

## 🔐 Security Rules

- ALL kubectl commands MUST be validated
- Read-only operations only
- Whitelist namespaces only
- Log for audit, never log secrets

## 📊 Performance Targets

- **Alert Processing**: <3 minutes per alert
- **Memory**: <512MB per agent
- **Alert Storm**: 3,000-10,000 alerts/hour
- **Concurrent Alerts**: 200+
- **First Attempt Success**: 90%


## 🎯 Phase 2 Goals

- K8s Health Analyzer integration
- Alert Storm management (3,000-10,000/hour)
- 93 banks support (from 28)
- Holistic K8s analysis (5-layer)
- 6-week development timeline

## 📋 Key Files

- **Phase 2 Development Process**: [@Project_Docs/active/phase2-development-process.md](./@Project_Docs/active/phase2-development-process.md)
- **Phase 2 Main Plan**: [@Project_Docs/active/phase2-main-development-plan.md](./@Project_Docs/active/phase2-main-development-plan.md)
- **Environment Setup Plan**: [@Project_Docs/active/environment-setup-plan.md](./@Project_Docs/active/environment-setup-plan.md)
- **Local Environment Guide**: [Docs/development/setup/local-environment-guide.md](./Docs/development/setup/local-environment-guide.md)
- **Dev Environment Guide**: [Docs/development/setup/dev-environment-guide.md](./Docs/development/setup/dev-environment-guide.md)
- **Phase 1 Reference**: [CLAUDE-phase1.md](./CLAUDE-phase1.md)
- **Phase 0 Learning**: [CLAUDE-phase0.md](./CLAUDE-phase0.md)
- **Documentation Standards**: [Docs/DOCUMENTATION-STANDARDS.md](./Docs/DOCUMENTATION-STANDARDS.md)

---

**Remember**: Focus on Alert Storm handling and K8s Health Analyzer for Phase 2 success!
