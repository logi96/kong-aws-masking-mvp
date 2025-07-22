# CLAUDE.md - Kong AWS Masking MVP Guidelines

**Project**: Kong DB-less AWS Multi-Resource Masking MVP
**Type**: Security-focused API Gateway
**Current Phase**: MVP Implementation
**Purpose**: Mask sensitive AWS resource identifiers before Claude API analysis

## 🚨 Critical Rules (MUST FOLLOW)

1. **ZERO MOCK MODE**: Mock mode is STRICTLY PROHIBITED - use real APIs only
2. **Type Safety**: Always use JSDoc annotations for type checking
3. **Testing First**: Write tests before implementation
4. **Lint & Typecheck**: Run `npm run lint` and `npm run type-check` after code changes
5. **Documentation Location**: 
   - Project docs: `/Docs/`
   - Standards: `/Docs/Standards/`
6. **No Direct AWS Exposure**: All AWS resources must be masked before external API calls
7. **Response Time**: Target < 5 seconds for all operations
8. **Real API Keys Only**: No test keys, fake keys, or mock keys allowed

## Architecture
```
Backend API (3000) → Kong Gateway (8000) → Claude API
    ↓                      ↓                    ↓
AWS CLI Execution    Masking/Unmasking    AI Analysis
```

## Key Commands

### Environment Setup
```bash
# Create .env file with Korean region settings
cat > backend/.env << EOF
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
AWS_REGION=ap-northeast-2
TZ=Asia/Seoul
NODE_ENV=development
PORT=3000
EOF

# Copy example file and customize
cp backend/.env.example backend/.env
# Edit backend/.env with your actual values
```

### Backend Development & Run Commands

#### Environment-specific Startup
```bash
# Development environment (default)
npm start
npm run start:dev

# Production environment  
npm run start:prod

# Test environment
npm run start:test

# Development with hot reload
npm run dev
npm run dev:test
```

#### Testing Commands
```bash
# Run all tests (test environment)
npm test

# Run specific test suites
npm run test:unit          # Unit tests only
npm run test:integration   # Integration tests only
npm run test:analyze       # Analyze endpoint tests
npm run test:coverage      # With coverage report

# Test watch mode
npm run test:watch

# Environment connectivity test
npm run test:env           # Test Claude API connection
npm run env:check          # Check environment variables
```

#### Code Quality & Development
```bash
# Code quality checks
npm run quality:check      # Full quality pipeline
npm run lint              # ESLint check
npm run lint:fix          # Auto-fix linting issues
npm run type-check        # JSDoc type checking
npm run quality:report    # Generate quality metrics

# Security audit
npm run security:audit
```

### Docker Deployment
```bash
# Start the entire system
docker-compose up --build

# Run in detached mode  
docker-compose up -d

# Stop the system
docker-compose down
```

### API Testing
```bash
# Health checks
curl http://localhost:3000/health          # Backend API health
curl http://localhost:8001/status          # Kong Gateway status

# Core functionality
curl -X POST http://localhost:3000/analyze \
  -H "Content-Type: application/json" \
  -d '{"resources":["ec2"],"options":{"analysisType":"security_only"}}'
```

### Health Checks
```bash
# Backend API health
curl http://localhost:3000/health

# Kong Gateway status
curl http://localhost:8001/status
```

## Project Structure
```
kong-aws-masking-mvp/
├── docker-compose.yml      # Container orchestration
├── kong/
│   ├── kong.yml           # Declarative Kong config
│   └── plugins/
│       └── aws-masker/    # Custom Lua plugin
├── backend/
│   ├── server.js          # Node.js API server
│   └── package.json       # Dependencies
└── tests/                 # Test suites
```

## Technology Stack
- **Kong Gateway 3.9.0.1** (DB-less mode)
- **Node.js 20.x LTS** with JavaScript
- **Claude API** (claude-3-5-sonnet-20241022)
- **Docker Compose 3.8**
- **AWS CLI v2**
- **Type Safety**: JSDoc annotations for development-time type checking

## Masking Rules
The Kong plugin masks AWS resources using these patterns:

| Resource Type | Pattern | Example Masked |
|--------------|---------|----------------|
| EC2 Instance | `i-[0-9a-f]+` | EC2_001 |
| Private IP | `10\.\d+\.\d+\.\d+` | PRIVATE_IP_001 |
| S3 Bucket | Various naming patterns | BUCKET_001 |
| RDS Instance | Various naming patterns | RDS_001 |

## Development Workflow

### Type Checking and Code Quality
```bash
# Enable VS Code type checking
# Ensure jsconfig.json and .vscode/settings.json are configured

# Run type check manually
npm run type-check

# Lint JavaScript code
npm run lint
```

### Adding New Masking Patterns
1. Edit `/kong/plugins/aws-masker/handler.lua`
2. Update the pattern matching logic in `mask_data()` function
3. Add corresponding unmask logic
4. Restart Kong: `docker-compose restart kong`

### Modifying Backend Logic
1. Edit `/backend/server.js`
2. Add JSDoc type annotations for better IDE support
3. Backend auto-reloads if using nodemon
4. Otherwise: `docker-compose restart backend`

### Testing Changes
1. Always run health checks first
2. Test with sample AWS data
3. Verify masking/unmasking works correctly
4. Check Claude API integration

## Important Notes
- AWS credentials are mounted read-only for security
- All sensitive data must be masked before external API calls
- Response time target: < 5 seconds
- Currently in MVP phase - only essential features implemented

## 📁 Quick References

### Development & Code Quality
- **Code Standards**: [Docs/Standards/02-code-standards-base-rules.md](./Docs/Standards/02-code-standards-base-rules.md) - JavaScript coding conventions, Lua style guide, error handling patterns, logging standards, naming conventions, function design principles, comment guidelines, import organization
- **TDD Strategy**: [Docs/Standards/01-tdd-strategy-guide.md](./Docs/Standards/01-tdd-strategy-guide.md) - test-driven development methodology, red-green-refactor cycle, test structure patterns, mock strategies, coverage requirements, integration testing, unit test best practices
- **JSDoc Type Safety**: [Docs/Standards/09-jsdoc-type-safety-guide.md](./Docs/Standards/09-jsdoc-type-safety-guide.md) - type annotation requirements, parameter documentation, return type definitions, complex type examples, generic patterns, interface definitions, VS Code integration
- **Quality Assurance**: [Docs/Standards/04-code-quality-assurance.md](./Docs/Standards/04-code-quality-assurance.md) - code review checklist, quality metrics, static analysis tools, performance benchmarks, security validation, continuous improvement

### Architecture & Infrastructure
- **Project Guidelines**: [Docs/Standards/03-project-development-guidelines.md](./Docs/Standards/03-project-development-guidelines.md) - project structure standards, module organization, dependency management, configuration patterns, environment setup, development workflow
- **Service Stability**: [Docs/Standards/05-service-stability-strategy.md](./Docs/Standards/05-service-stability-strategy.md) - error recovery patterns, graceful degradation, circuit breakers, retry strategies, health checks, monitoring setup
- **VS Code Setup**: [Docs/Standards/10-vscode-type-check-setup-guide.md](./Docs/Standards/10-vscode-type-check-setup-guide.md) - editor configuration, JSDoc intellisense, type checking settings, recommended extensions, workspace settings

### Operations & Deployment  
- **CI/CD Pipeline**: [Docs/Standards/06-ci-cd-pipeline-guide.md](./Docs/Standards/06-ci-cd-pipeline-guide.md) - GitHub Actions workflow, automated testing, build optimization, deployment stages, rollback procedures, environment promotion
- **Deployment Strategy**: [Docs/Standards/07-deployment-rollback-strategy.md](./Docs/Standards/07-deployment-rollback-strategy.md) - blue-green deployment, canary releases, rollback triggers, health validation, traffic management, disaster recovery
- **Documentation Standards**: [Docs/Standards/08-documentation-standards-readme-template.md](./Docs/Standards/08-documentation-standards-readme-template.md) - README structure, API documentation, code comments, changelog format, contribution guidelines

### Migration & Planning
- **TypeScript Roadmap**: [Docs/Standards/11-typescript-migration-roadmap.md](./Docs/Standards/11-typescript-migration-roadmap.md) - migration phases, priority components, type definition strategy, tooling updates, team training plan
- **Comprehensive Checklist**: [Docs/Standards/00-comprehensive-summary-checklist.md](./Docs/Standards/00-comprehensive-summary-checklist.md) - project readiness, security audit, performance validation, documentation completeness, deployment verification

### Kong AWS Masking Specific
- **Kong Plugin Development**: [Docs/Standards/17-kong-plugin-development-guide.md](./Docs/Standards/17-kong-plugin-development-guide.md) - Lua plugin architecture, handler lifecycle, pattern matching, testing strategies, debugging techniques, performance optimization, deployment guidelines
- **AWS Resource Masking**: [Docs/Standards/18-aws-resource-masking-patterns.md](./Docs/Standards/18-aws-resource-masking-patterns.md) - AWS resource taxonomy, masking patterns, regex validation, security principles, implementation examples, edge cases, troubleshooting guide
- **Docker Compose Best Practices**: [Docs/Standards/19-docker-compose-best-practices.md](./Docs/Standards/19-docker-compose-best-practices.md) - service configuration, environment management, networking setup, volume optimization, security hardening, performance tuning, multi-stage deployment

## 📋 Planning System

### Plan Management
The project uses a structured planning system to track feature development and tasks:

```
Plan/
├── active/          # Currently active plans being worked on
│   └── feature-name.md   # Active plan documents
└── complete/        # Completed plans for reference
    └── feature-name.md   # Archived completed plans
```

### Planning Workflow
1. **Create New Plan**: Create a markdown file in `Plan/active/` with the feature/task name
2. **Plan Structure**: Use the following template:
   ```markdown
   # Plan: [Feature Name]
   
   ## Objective
   Clear description of what needs to be achieved
   
   ## Tasks
   - [ ] Task 1 with specific details
   - [ ] Task 2 with acceptance criteria
   - [ ] Task 3 with dependencies
   
   ## Success Criteria
   - Measurable outcome 1
   - Measurable outcome 2
   
   ## Timeline
   Estimated completion: X days
   ```
3. **During Development**: Update task checkboxes as work progresses
4. **Completion**: Move the plan file from `Plan/active/` to `Plan/complete/` when done
5. **Reference**: Completed plans serve as documentation for implemented features

### Active Plans
Check `Plan/active/` directory for current work in progress.

## Current Status
**Documentation Phase**: The project has comprehensive specifications in the `/Docs` folder but implementation files need to be created based on the PRD.