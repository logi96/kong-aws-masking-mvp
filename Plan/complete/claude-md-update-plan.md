# Plan: CLAUDE.md Update for Kong API Gateway Focus

## Objective
Update CLAUDE.md to prioritize Kong API Gateway documentation references and emphasize testing requirements for better project understanding and adherence to test guidelines.

## Current Situation Analysis
Based on the two README files reviewed:

1. **Kong Plugin Documentation** (`/kong/plugins/aws-masker/docs/README.md`):
   - Comprehensive 8-document technical series
   - Covers implementation, configuration, testing, architecture
   - 1,300+ lines of dependency documentation
   - Mermaid diagrams and detailed technical guides

2. **Test Suite Documentation** (`/tests/README.md`):
   - **MUST Rules**: Test report generation, script duplication prevention
   - 10 active production-ready test scripts
   - Clear usage scenarios for each test category
   - Test report directory structure (`test-report/`)

## Tasks
- [x] Analyze current CLAUDE.md structure and identify update areas
- [x] Review Kong plugin documentation structure and key references
- [x] Review test documentation and MUST rules
- [ ] Create new section structure for CLAUDE.md
- [ ] Add Kong API Gateway documentation section at the top
- [ ] Add Testing MUST Rules section with emphasis
- [ ] Update Quick References to prioritize Kong docs
- [ ] Add test report generation requirements
- [ ] Review and finalize the updated CLAUDE.md

## Implementation Plan

### 1. New Structure for CLAUDE.md
```
# CLAUDE.md - Kong AWS Masking MVP Guidelines

## 🏛️ Kong API Gateway Documentation (MUST READ FIRST)
[New section with links to Kong plugin docs]

## 🧪 Testing Requirements (CRITICAL COMPLIANCE)
[New section with MUST rules from tests/README.md]

## 🚨 Critical Rules (MUST FOLLOW)
[Existing rules with test compliance additions]

[Rest of existing content...]
```

### 2. Kong Documentation Section Content
- Direct link to `/kong/plugins/aws-masker/docs/README.md`
- Highlight 8 key technical documents
- Emphasize reading order for developers
- Quick navigation to critical docs

### 3. Testing Requirements Section Content
- MUST Rule #1: Test report generation (`test-report/` directory)
- MUST Rule #2: Script duplication prevention
- Test execution guidelines
- Links to active test scripts

### 4. Updates to Existing Sections
- Add test commands to "Key Commands" section
- Update "Quick References" to include Kong docs first
- Add test report requirements to development workflow

## Success Criteria
- Kong API Gateway documentation is prominently featured at the top
- Test MUST rules are clearly emphasized and unavoidable
- All Kong technical documents are easily accessible via links
- Test report generation is mandatory for all test executions
- No duplication of information - use links to existing docs

## Timeline
Estimated completion: 30 minutes

## Notes
- Maintain existing CLAUDE.md structure while adding new priority sections
- Use clear visual hierarchy with emojis for sections
- Ensure all links are relative and working
- Keep the document concise by linking to detailed documentation rather than duplicating content