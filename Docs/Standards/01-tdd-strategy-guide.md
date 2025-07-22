# 🧪 **TDD Strategy Guide - Kong AWS Masking MVP Test-Driven Development**

<!-- Tags: #tdd #testing #jest #quality #mvp #red-green-refactor -->

> **PURPOSE**: Practical TDD approach ensuring quality while maintaining MVP development speed  
> **SCOPE**: Testing strategy, patterns, coverage goals, and implementation guidelines  
> **COMPLEXITY**: ⭐⭐⭐ Intermediate | **DURATION**: 1-2 hours implementation  
> **NAVIGATION**: Quick access to TDD principles, test patterns, and MVP-focused testing

---

## 🎯 **TDD PRINCIPLES (RED-GREEN-REFACTOR)**

### **1.1 RED Phase - Write Failing Test First**
```javascript
// test/masking.test.js
describe('AWS Resource Masking', () => {
  it('should mask EC2 instance ID', () => {
    const input = { instance: 'i-0a1b2c3d4e5f' };
    const result = maskAWSResources(input);
    expect(result.instance).toBe('EC2_001');
  });
});
```

### **1.2 GREEN Phase - Minimal Code to Pass**
```javascript
// src/masking.js
function maskAWSResources(data) {
  if (data.instance && data.instance.startsWith('i-')) {
    data.instance = 'EC2_001';
  }
  return data;
}
```

### **1.3 REFACTOR Phase - Keep it Simple for MVP**
- Remove code duplication
- Use clear variable names
- Maintain simple structure

---

## 📋 **MVP TESTING STRATEGY**

### **2.1 Test Scope Priority**
```yaml
Priority 1 (Required):
  - Core masking logic
  - API endpoints
  - Error handling

Priority 2 (Recommended):
  - Integration tests
  - Edge cases

Priority 3 (Post-MVP):
  - Performance tests
  - Load testing
```

### **2.2 Test Structure**
```
tests/
├── unit/
│   ├── masking.test.js      # Masking logic
│   ├── patterns.test.js     # Pattern matching
│   └── mapping.test.js      # Map save/restore
├── integration/
│   ├── api.test.js          # API endpoints
│   └── kong-plugin.test.js  # Kong plugin
└── e2e/
    └── full-flow.test.js    # Complete flow
```

---

## 🚀 **PRACTICAL TDD IMPLEMENTATION**

### **3.1 Node.js Setup (Jest)**
```javascript
// package.json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "supertest": "^6.3.0"
  }
}
```

### **3.2 Base Test Template**
```javascript
// tests/unit/masking.test.js
const { maskData, unmaskData } = require('../../src/masking');

describe('Masking Module', () => {
  describe('maskData', () => {
    it('should mask EC2 instance IDs', () => {
      const input = 'Instance i-1234567890abcdef0 is running';
      const expected = 'Instance EC2_001 is running';
      expect(maskData(input)).toBe(expected);
    });

    it('should mask multiple IPs', () => {
      const input = 'IPs: 10.0.1.100, 10.0.2.200';
      const result = maskData(input);
      expect(result).toContain('PRIVATE_IP_001');
      expect(result).toContain('PRIVATE_IP_002');
    });

    it('should handle empty input gracefully', () => {
      expect(maskData('')).toBe('');
      expect(maskData(null)).toBe('');
    });
  });

  describe('unmaskData', () => {
    it('should restore original values', () => {
      const input = 'Instance i-1234567890abcdef0';
      const masked = maskData(input);
      const restored = unmaskData(masked);
      expect(restored).toBe(input);
    });
  });
});
```

### **3.3 Kong Plugin Testing (Lua)**
```lua
-- tests/unit/handler_spec.lua
local handler = require "kong.plugins.aws-masker.handler"

describe("AWS Masker Handler", function()
  it("masks EC2 instance IDs", function()
    local input = 'i-1234567890abcdef0'
    local result = handler.mask_pattern(input, "i%-[0-9a-f]+", "EC2_")
    assert.equal("EC2_001", result)
  end)
end)
```

---

## 🎯 **TEST PRIORITY FOR MVP**

### **4.1 Essential Tests (Day 1)**
```typescript
interface EssentialTests {
  maskingPatterns: {
    ec2InstanceId: "i-[0-9a-f]+",
    privateIP: "10.\\d+.\\d+.\\d+",
    s3Bucket: "[a-z0-9-]+-bucket",
    rdsInstance: "prod-[a-z]+-[0-9]+"
  };
  apiBasics: ["health check", "masking request/response", "error handling"];
}
```

### **4.2 Recommended Tests (Day 2)**
```typescript
interface RecommendedTests {
  integration: ["Kong + Backend", "AWS CLI integration", "Claude API calls"];
  edgeCases: ["large data", "invalid format", "concurrent requests"];
}
```

### **4.3 Optional Tests (Post-MVP)**
```typescript
interface PostMVPTests {
  performance: "Response time benchmarks";
  load: "Concurrent user simulation";
  security: "Vulnerability scanning";
}
```

---

## 🔧 **TEST EXECUTION GUIDE**

### **5.1 Local Development**
```bash
# Unit tests
npm test

# Watch mode (TDD cycle)
npm run test:watch

# Coverage check
npm run test:coverage

# Specific test file
npm test masking.test.js
```

### **5.2 CI/CD Integration**
```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
      - run: npm ci
      - run: npm test
      - run: npm run test:coverage
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

---

## 📊 **TEST COVERAGE GOALS**

### **6.1 MVP Targets**
| Metric | MVP Target | Ideal Target |
|--------|------------|--------------|
| **Overall Coverage** | 70% | 90% |
| **Core Features** | 90% | 100% |
| **Error Handling** | 80% | 95% |
| **API Endpoints** | 70% | 85% |

### **6.2 Coverage Configuration**
```javascript
// jest.config.js
module.exports = {
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 70,
      lines: 70,
      statements: 70
    },
    './src/masking.js': {
      branches: 90,
      functions: 90,
      lines: 90,
      statements: 90
    }
  }
};
```

---

## 💡 **TDD BEST PRACTICES**

### **7.1 Start Small**
1. Test one pattern
2. Implement minimal code
3. Move to next pattern

### **7.2 Fast Feedback Loop**
```bash
# Auto-test on file save
npm run test:watch

# Focus on specific test
npm test -- --testNamePattern="mask EC2"
```

### **7.3 Test Naming Convention**
```javascript
// ✅ Good - Descriptive and specific
it('should mask EC2 instance ID format i-xxxx')
it('should return 400 when API key is missing')
it('should handle concurrent masking requests')

// ❌ Bad - Vague and unclear
it('test masking')
it('works')
it('error case')
```

---

## 📅 **IMPLEMENTATION TIMELINE**

### **Day 1: Foundation**
```bash
□ Test environment setup (1 hour)
□ Masking logic TDD (3 hours)
□ Basic API tests (2 hours)
□ Coverage check (30 min)
```

### **Day 2: Integration**
```bash
□ Kong plugin tests (2 hours)
□ E2E tests (2 hours)
□ Error scenarios (1 hour)
□ Edge cases (1 hour)
```

### **Day 3: Completion**
```bash
□ Coverage gaps (2 hours)
□ Documentation (1 hour)
□ CI/CD setup (1 hour)
□ Final validation (1 hour)
```

---

## 🚀 **QUICK TDD WORKFLOW**

```bash
# 1. Create test file
touch tests/unit/new-feature.test.js

# 2. Write failing test
npm test new-feature

# 3. Implement feature
vim src/new-feature.js

# 4. Run tests
npm test

# 5. Refactor if needed
npm run test:watch
```

---

## 📚 **RELATED DOCUMENTATION**

### **Testing Resources**
- **[Jest Documentation](https://jestjs.io/)** - Testing framework reference
- **[Supertest Guide](https://github.com/visionmedia/supertest)** - API testing library
- **[Code Coverage Standards](./04-code-quality-assurance.md)** - Quality metrics

### **Project Standards**
- **[Code Standards](./02-code-standards-base-rules.md)** - Coding conventions
- **[Development Guidelines](./03-project-development-guidelines.md)** - Best practices
- **[Quality Assurance](./04-code-quality-assurance.md)** - Quality systems

### **Implementation References**
- **[Backend Tests](../../tests/)** - Example test implementations
- **[API Documentation](../../backend/README.md)** - API specifications
- **[Kong Plugin Tests](../../kong/plugins/aws-masker/tests/)** - Plugin test examples

---

## 🎯 **KEY TAKEAWAYS**

### **MVP TDD Focus**
1. **Practical**: Core functionality first
2. **Fast**: Quick feedback loops
3. **Sufficient**: 70% coverage to start

### **Success Metrics**
```typescript
const tddSuccess = {
  redGreenCycle: "< 30 minutes per feature",
  testExecution: "< 1 minute for all tests",
  coverageGoal: "70% minimum, 90% core",
  bugReduction: "50% fewer production issues"
};
```

---

**🔑 Key Message**: "Code without tests is legacy code" - But in MVP, balance is key. Focus on critical paths, maintain 70% coverage, and iterate quickly with confidence.