# 📋 **Planning System - Kong AWS Masking MVP**

<!-- Tags: #planning #workflow #documentation #project-management -->

> **PURPOSE**: Structured planning system for tracking feature development and task management  
> **SCOPE**: Active plans, completed plans, workflow guidelines, and best practices  
> **COMPLEXITY**: ⭐⭐ Easy | **DURATION**: 5 minutes to understand  
> **NAVIGATION**: Quick guide to using the planning system effectively

---

## 📁 **DIRECTORY STRUCTURE**

```
Plan/
├── active/              # Currently active plans being worked on
│   ├── feature-1.md     # Active feature plan
│   └── bugfix-2.md      # Active bugfix plan
├── complete/            # Completed plans for reference
│   ├── feature-0.md     # Completed feature
│   └── setup-mvp.md     # Completed setup plan
└── README.md           # This file
```

---

## 📝 **PLAN TEMPLATE**

Use this template when creating new plans:

```markdown
# Plan: [Feature/Task Name]

**Created**: YYYY-MM-DD  
**Author**: [Your Name]  
**Status**: Active  
**Priority**: High/Medium/Low  

## 📎 Objective
Clear, concise description of what needs to be achieved.

## ✅ Tasks
- [ ] Task 1: Specific implementation detail
  - Acceptance criteria: What defines completion
  - Dependencies: Any prerequisites
- [ ] Task 2: Another implementation step
  - Acceptance criteria: Measurable outcome
  - Dependencies: Task 1
- [ ] Task 3: Final implementation step
  - Acceptance criteria: Integration complete
  - Dependencies: Task 2

## 🎯 Success Criteria
1. **Functional**: Feature works as specified
2. **Testing**: 70%+ test coverage achieved
3. **Documentation**: README and inline docs updated
4. **Performance**: Response time < 5 seconds

## 📅 Timeline
- **Start Date**: YYYY-MM-DD
- **Target Completion**: X days
- **Actual Completion**: [Update when done]

## 📊 Progress Updates
### YYYY-MM-DD
- Completed Task 1
- Started Task 2
- Blocker: [Any issues]

### YYYY-MM-DD
- Resolved blocker
- Completed Task 2
- Task 3 in progress

## 🔗 Related Documents
- [PRD](../Docs/kong-aws-masking-mvp-prd.md)
- [Technical Spec](../Docs/04-kong-plugin-improvements.md)
- [Test Plan](../tests/README.md)

## 📝 Notes
Any additional context, decisions made, or lessons learned.
```

---

## 🔄 **WORKFLOW**

### **1. Creating a New Plan**
```bash
# Navigate to active plans directory
cd Plan/active/

# Create new plan using template
cp ../template.md feature-aws-masking.md

# Edit the plan
vim feature-aws-masking.md
```

### **2. During Development**
- Update task checkboxes as you progress
- Add progress updates with dates
- Document any blockers or changes
- Keep the plan in sync with actual work

### **3. Completing a Plan**
```bash
# Mark completion date in the plan
echo "**Completed**: $(date +%Y-%m-%d)" >> feature-aws-masking.md

# Move to complete directory
mv Plan/active/feature-aws-masking.md Plan/complete/

# Update any references in documentation
```

### **4. Referencing Completed Plans**
- Use completed plans as documentation
- Reference them in PRs and commits
- Learn from timeline estimates for future planning

---

## 🎯 **BEST PRACTICES**

### **Plan Naming Convention**
```
feature-[name].md       # New features
bugfix-[issue-number].md   # Bug fixes
refactor-[component].md    # Refactoring tasks
docs-[topic].md           # Documentation updates
test-[feature].md         # Test implementation
```

### **Priority Guidelines**
- **High**: MVP critical, blocking other work
- **Medium**: Important but not blocking
- **Low**: Nice to have, can be deferred

### **Task Breakdown**
- Keep tasks small (< 1 day of work)
- Make them specific and measurable
- Include clear acceptance criteria
- Note dependencies explicitly

### **Progress Tracking**
- Update daily for active plans
- Use checkboxes for visual progress
- Document blockers immediately
- Add timestamp to updates

---

## 📊 **EXAMPLE PLANS**

### **Active Plan Example**
`Plan/active/feature-kong-masking.md`:
```markdown
# Plan: Kong AWS Resource Masking Plugin

**Created**: 2025-01-22  
**Author**: Developer  
**Status**: Active  
**Priority**: High  

## 📎 Objective
Implement Lua plugin for Kong to mask AWS resource identifiers.

## ✅ Tasks
- [x] Research Kong plugin structure
- [x] Implement basic masking patterns
- [ ] Add mapping storage mechanism
- [ ] Implement unmask functionality
- [ ] Write plugin tests

[... rest of plan ...]
```

### **Completed Plan Example**
`Plan/complete/setup-docker-env.md`:
```markdown
# Plan: Docker Environment Setup

**Created**: 2025-01-20  
**Author**: DevOps  
**Status**: Complete  
**Priority**: High  
**Completed**: 2025-01-21  

## 📎 Objective
Set up Docker Compose environment for Kong MVP.

## ✅ Tasks
- [x] Create docker-compose.yml
- [x] Configure Kong DB-less mode
- [x] Set up backend service
- [x] Configure networking
- [x] Add health checks

[... rest of plan ...]
```

---

## 🔍 **QUICK COMMANDS**

```bash
# List active plans
ls -la Plan/active/

# Search for specific plan
grep -r "masking" Plan/

# Count active plans
ls Plan/active/*.md | wc -l

# View plan progress
grep -E "\[.\]" Plan/active/feature-name.md

# Archive old completed plans (> 30 days)
find Plan/complete -name "*.md" -mtime +30 -exec mv {} Plan/archive/ \;
```

---

## 📚 **RELATED DOCUMENTATION**

- **[CLAUDE.md](../CLAUDE.md)** - Planning system integration
- **[Project README](../README.md)** - Overall project structure
- **[Development Guide](../development/README.md)** - Development workflow
- **[Standards](../Docs/Standards/README.md)** - Coding and documentation standards

---

**🔑 Key Message**: Use the planning system to maintain clear visibility of work in progress and create a historical record of completed features for future reference.