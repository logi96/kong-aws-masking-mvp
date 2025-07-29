# Test Fixtures Directory

**Purpose**: Test data and mocking files for Kong AWS Masking MVP testing  
**Location**: `/tests/fixtures/`  
**Category**: Supporting Test Infrastructure

---

## 📁 Directory Overview

This directory contains **test fixtures** - static test data, sample AWS resource configurations, and mock data used across the test suite to ensure consistent and reproducible testing.

### 🎯 **Primary Functions**
- **AWS Resource Samples**: Predefined AWS resource data for pattern testing
- **Test Case Definitions**: Structured test scenarios and expected outcomes
- **Mock Data**: Simulated API responses and data structures
- **Reference Data**: Golden master files for comparison testing

---

## 📋 **Content Categories**

### **AWS Resource Fixtures**
- EC2 instance sample data
- S3 bucket naming examples
- RDS instance configurations
- VPC and network resource samples
- IAM role and policy examples

### **Test Scenario Data**
- Pattern matching test cases
- Masking/unmasking validation data
- Edge case scenarios
- Boundary value test inputs

### **Mock Responses**
- Claude API response templates
- Kong Gateway response mocks
- Redis key-value pair samples
- Error response templates

---

## 🔧 **Usage in Tests**

### **Pattern Testing**
```bash
# Tests load fixtures for consistent pattern validation
./comprehensive-flow-test.sh          # Uses AWS resource fixtures
./security-masking-test.sh           # Uses security scenario fixtures
./production-comprehensive-test.sh   # Uses production data fixtures
```

### **Integration Testing**
```bash
# Integration tests rely on fixtures for data consistency
../integration/kong-gateway-test.sh  # Loads API fixtures
../integration/redis-mapping-test.sh # Uses Redis fixtures
```

---

## 📊 **Data Organization**

### **Structure Principles**
- **Categorized by AWS Service**: EC2, S3, RDS, VPC, IAM
- **Grouped by Test Type**: Security, Performance, Integration
- **Version Controlled**: Consistent data across test runs
- **Environment Agnostic**: No hardcoded environment-specific values

### **File Naming Convention**
```
{service}-{resource}-{scenario}.{format}
Example: ec2-instances-production.json
         s3-buckets-security-test.yaml
         rds-clusters-performance.json
```

---

## 🛡️ **Security Considerations**

### ✅ **Safe Test Data**
- **No Real AWS Resources**: All fixtures use synthetic data
- **No Sensitive Information**: Mock data only, no actual secrets
- **Sanitized Content**: Production data is anonymized
- **Isolated Environment**: Fixtures don't connect to real services

### 🔒 **Data Protection**
- Test fixtures contain only **mock AWS resource identifiers**
- No actual AWS account information
- No production secrets or keys
- Safe for version control and sharing

---

## 🧪 **Integration with Test Suite**

### **Active Test Dependencies**
| Test Script | Fixture Usage | Purpose |
|-------------|---------------|---------|
| `comprehensive-flow-test.sh` | AWS resource samples | End-to-end validation |
| `security-masking-test.sh` | Security scenarios | Pattern security testing |
| `performance-test.sh` | Load test data | Performance benchmarking |
| `production-comprehensive-test.sh` | Production samples | Full system validation |

### **Test Data Flow**
```
fixtures/ → Test Scripts → Pattern Engine → Validation
    ↓           ↓              ↓             ↓
Mock Data → Load Fixtures → Apply Patterns → Compare Results
```

---

## 📈 **Maintenance Guidelines**

### **Adding New Fixtures**
1. **Follow naming conventions** for consistency
2. **Validate data format** before adding
3. **Document usage** in relevant test scripts
4. **Keep data realistic** but synthetic

### **Updating Existing Fixtures**
1. **Verify backward compatibility** with existing tests
2. **Update dependent tests** if fixture structure changes
3. **Document changes** in test documentation
4. **Test validation** after updates

---

## 🔗 **Related Components**

### **Test Directories**
- **`../unit/`**: Uses fixtures for unit test validation
- **`../integration/`**: Loads fixtures for integration scenarios
- **`../security/`**: References security test fixtures
- **`../performance/`**: Uses performance benchmarking data

### **Core Test Scripts**
- **Main Test Suite**: All 10 active test scripts
- **Archive Tests**: Historical test development fixtures
- **Backup Tests**: Unused fixture references

---

*This fixtures directory provides the foundation for consistent, reliable, and comprehensive testing of the Kong AWS Masking MVP system.*