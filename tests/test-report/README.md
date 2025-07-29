# Test Report Directory

**Purpose**: Automated test execution result reports for Kong AWS Masking MVP  
**Location**: `/tests/test-report/`  
**Category**: Test Result Documentation (Auto-generated)

---

## 📁 Directory Overview

This directory contains **automatically generated test result reports** created whenever any `.sh` test script is executed. This is a **MUST 규칙** (mandatory rule) for all test executions in the Kong AWS Masking MVP system.

### 🎯 **Primary Functions**
- **Automatic Report Generation**: Every test execution creates a detailed report
- **Test Result Archival**: Historical record of all test executions
- **Debugging Support**: Detailed logs for troubleshooting test failures
- **Audit Trail**: Complete record of testing activities

---

## 📋 **Report Generation Rules (MUST 규칙)**

### **1. Mandatory Report Creation**
- **모든 `.sh` 테스트 실행 시 반드시 리포트 생성**
- **No Exceptions**: Every test script execution must generate a report
- **Automatic Process**: Reports are generated automatically by test scripts
- **Failure Handling**: Reports are created even if tests fail

### **2. Naming Convention**
```bash
# Report naming format
{shell-name}_{순번}.md

# Examples
redis-connection-test-001.md        # First execution of redis-connection-test.sh
redis-connection-test-002.md        # Second execution
comprehensive-flow-test-001.md      # First execution of comprehensive-flow-test.sh
performance-test-simple-003.md      # Third execution of performance-test-simple.sh
```

### **3. Sequential Numbering**
- **순번 관리**: 동일 스크립트 재실행 시 001, 002, 003... 순차 증가
- **Automatic Increment**: Scripts automatically determine next sequence number
- **No Overwrites**: Previous reports are preserved, never overwritten
- **Continuous Sequence**: Numbers continue from last execution

---

## 📊 **Report Content Structure**

### **Standard Report Format**
Each generated report follows this standard structure:

```markdown
# Test Execution Report: {Script Name}

**Test Script**: {script-name}.sh  
**Execution Date**: {YYYY-MM-DD HH:MM:SS}  
**Execution Number**: {sequence-number}  
**Duration**: {execution-time}  
**Result**: ✅ PASS / ❌ FAIL

---

## Test Environment
- Kong Gateway Status: {status}
- Backend API Status: {status}  
- Redis Status: {status}
- Environment Variables: {verification}

## Test Execution Log
{detailed-execution-log}

## Test Results Summary
{results-summary}

## Performance Metrics
{performance-data}

## Issues Identified
{issues-and-errors}

## Recommendations
{recommendations-for-fixes}
```

---

## 🔧 **Report Categories by Test Type**

### **Comprehensive Tests**
```bash
comprehensive-flow-test-{nnn}.md        # Full system flow testing reports
comprehensive-security-test-{nnn}.md    # Security comprehensive reports
```

### **Production Tests**
```bash
production-comprehensive-test-{nnn}.md  # Production validation reports
production-security-test-{nnn}.md       # Production security reports
```

### **Performance Tests**
```bash
performance-test-{nnn}.md               # Full performance benchmark reports
performance-test-simple-{nnn}.md        # Quick performance test reports
```

### **Redis Tests**
```bash
redis-connection-test-{nnn}.md          # Redis connection test reports
redis-performance-test-{nnn}.md         # Redis performance test reports
redis-persistence-test-{nnn}.md         # Redis persistence test reports
```

### **Security Tests**
```bash
security-masking-test-{nnn}.md          # AWS masking security reports
```

---

## 📈 **Report Usage Guidelines**

### **For Test Analysis**
- **Immediate Review**: Check latest report after test execution
- **Trend Analysis**: Compare sequential reports for performance trends
- **Failure Investigation**: Use detailed logs for troubleshooting
- **Historical Reference**: Review past reports for regression analysis

### **For Debugging**
- **Error Location**: Reports contain exact error locations and contexts
- **Environment State**: Complete environment snapshot at test time
- **Execution Flow**: Step-by-step execution trace
- **Resource Usage**: Memory, CPU, and network usage during tests

### **For Audit and Compliance**
- **Test Coverage**: Evidence of comprehensive testing
- **Security Validation**: Detailed security test results
- **Performance Tracking**: Historical performance data
- **Change Impact**: Before/after comparison data

---

## 🛠️ **Report Management**

### **Automatic Cleanup (Recommended)**
```bash
# Keep last 10 reports per test script
find test-report/ -name "*-???.md" | sort | head -n -10 | xargs rm

# Archive old reports (older than 30 days)
find test-report/ -name "*.md" -mtime +30 -exec mv {} archive/ \;
```

### **Report Analysis Tools**
```bash
# Find all failed test reports
grep -l "❌ FAIL" test-report/*.md

# Get latest report for specific test
ls -t test-report/redis-connection-test-*.md | head -1

# Count test executions by type
ls test-report/ | cut -d'-' -f1-2 | sort | uniq -c
```

---

## 📊 **Report Statistics & Monitoring**

### **Key Metrics to Track**
- **Test Execution Frequency**: How often each test runs
- **Success Rate**: Pass/fail ratio over time
- **Performance Trends**: Response time changes over time
- **Error Patterns**: Common failure modes and frequency

### **Report Analysis Examples**
```bash
# Generate test execution summary
echo "=== Test Execution Summary ==="
for test_type in comprehensive production performance redis security; do
  count=$(ls test-report/${test_type}-*-???.md 2>/dev/null | wc -l)
  echo "${test_type}: ${count} executions"
done

# Find performance degradation
grep "Duration:" test-report/performance-test-*.md | sort -k3 -n
```

---

## 🔒 **Report Security & Privacy**

### **Security Considerations**
- **No Sensitive Data**: Reports must not contain actual AWS resource IDs
- **Masked Content**: Only masked IDs should appear in reports
- **Environment Safety**: No credentials or secrets in reports
- **Safe Sharing**: Reports can be safely shared for analysis

### **Data Sanitization**
- All AWS resource identifiers are masked in reports
- No actual API keys or passwords stored
- Only performance metrics and masked test data included
- Safe for version control and team sharing

---

## 📋 **Integration with Test Scripts**

### **Report Generation Implementation**
Each test script must include report generation code:

```bash
# Example report generation in test scripts
SCRIPT_NAME="redis-connection-test"
REPORT_DIR="/Users/tw.kim/Documents/AGA/test/Kong/tests/test-report"
SEQUENCE=$(printf "%03d" $(($(ls ${REPORT_DIR}/${SCRIPT_NAME}-*.md 2>/dev/null | wc -l) + 1)))
REPORT_FILE="${REPORT_DIR}/${SCRIPT_NAME}-${SEQUENCE}.md"

# Generate report
{
  echo "# Test Execution Report: ${SCRIPT_NAME}"
  echo "**Execution Date**: $(date)"
  echo "**Result**: ${TEST_RESULT}"
  # ... detailed report content
} > "${REPORT_FILE}"
```

---

## 🔗 **Related Test Components**

### **Test Directory Integration**
- **Main Test Scripts**: All 10 active test scripts generate reports here
- **Archive Tests**: Historical tests may reference old report formats
- **Debugging**: Reports provide detailed debugging information

### **Documentation References**
- **Main README**: [../README.md](../README.md) - Test suite overview
- **Test Documentation**: Referenced in technical documentation
- **Issue Tracking**: Reports linked to issue resolution

---

*This test-report directory serves as the central repository for all test execution results, providing comprehensive documentation of testing activities and supporting debugging, analysis, and audit requirements.*