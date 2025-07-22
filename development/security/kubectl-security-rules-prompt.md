# 🔒 **Kubectl Security Rules - Claude Code 보안 지침**

<!-- Tags: #kubectl #security #whitelist #readonly #command-validation -->

> **목표**: kubectl 명령어 실행 시 Claude Code가 준수해야 할 절대적 보안 규칙  
> **적용 상황**: 모든 kubectl 명령어 실행, Kubernetes API 호출 시 필수 적용  
> **보안 등급**: Critical - 보안 위반 시 즉시 시스템 차단  
> **검증 방법**: CommandValidator 통과 여부로 허용/차단 결정

---

## 🚨 **CRITICAL SECURITY RULES - 보안 절대 규칙**

### **ABSOLUTE REQUIREMENTS (NO EXCEPTIONS)**
- ✅ **MUST validate ALL kubectl commands** against whitelist before execution
- ✅ **MUST use CommandValidator class** for every kubectl operation - no bypassing
- ✅ **MUST restrict to read-only operations** only - no create/update/delete allowed
- ✅ **MUST log ALL kubectl commands** for security audit trail
- ✅ **MUST check namespace whitelist** before accessing any Kubernetes resources

### **FORBIDDEN ACTIONS (IMMEDIATE FAILURE)**
- ❌ **NEVER execute kubectl delete** commands - immediate security violation
- ❌ **NEVER execute kubectl create/apply/patch** commands - system modification forbidden
- ❌ **NEVER access unauthorized namespaces** - only whitelisted namespaces allowed
- ❌ **NEVER execute user-provided kubectl commands** without validation
- ❌ **NEVER ignore CommandValidator failures** - security validation is mandatory

---

## ⚡ **IMMEDIATE EXECUTION - 즉시 실행**

### **🚀 Copy & Paste Security Templates - 복사 붙여넣기 보안 템플릿**

#### **Safe Kubectl Execution Template (30초 구현)**
```typescript
// ✅ CORRECT IMPLEMENTATION - 필수 보안 패턴
import { CommandValidator, SecurityError } from '@src-shared/validators/command-validator';

export class SafeKubectlExecutor {
  private readonly validator = new CommandValidator();
  private readonly logger = createLogger('KubectlExecutor');
  
  async executeKubectlCommand(command: string, namespace: string): Promise<string> {
    // MUST: Validate command before execution
    const validationResult = this.validator.validate(command);
    if (!validationResult.isSafe) {
      this.logger.error('Blocked unsafe kubectl command', { command, reason: validationResult.reason });
      throw new SecurityError(`Kubectl command blocked: ${validationResult.reason}`);
    }
    
    // MUST: Check namespace whitelist
    if (!this.isNamespaceAllowed(namespace)) {
      this.logger.error('Blocked access to unauthorized namespace', { namespace, command });
      throw new SecurityError(`Namespace '${namespace}' not in whitelist`);
    }
    
    // MUST: Log for audit trail
    this.logger.info('Executing validated kubectl command', { command, namespace });
    
    // MUST: Add namespace constraint to command
    const namespacedCommand = this.addNamespaceConstraint(command, namespace);
    
    return await this.executeValidatedCommand(namespacedCommand);
  }
}
```

#### **Command Validation Template (45초 구현)**
```typescript
// ✅ CORRECT: CommandValidator usage pattern
export class CommandValidator {
  private readonly ALLOWED_OPERATIONS = [
    'get', 'describe', 'logs', 'top', 'events'
  ] as const;
  
  private readonly FORBIDDEN_OPERATIONS = [
    'delete', 'create', 'apply', 'patch', 'edit', 'scale', 'rollout'
  ] as const;
  
  validate(command: string): ValidationResult {
    // MUST: Parse and validate command structure
    const parsed = this.parseKubectlCommand(command);
    
    // MUST: Check against forbidden operations
    if (this.FORBIDDEN_OPERATIONS.some(op => parsed.operation === op)) {
      return {
        isSafe: false,
        reason: `Operation '${parsed.operation}' is forbidden - read-only access only`,
        severity: 'critical'
      };
    }
    
    // MUST: Check against allowed operations
    if (!this.ALLOWED_OPERATIONS.includes(parsed.operation as any)) {
      return {
        isSafe: false,
        reason: `Operation '${parsed.operation}' not in whitelist`,
        severity: 'high'
      };
    }
    
    return { isSafe: true, reason: 'Command validated successfully' };
  }
}
```

#### **Golden Command Sets Template (60초 구현)**
```typescript
// ✅ CORRECT: Pre-validated safe commands for alert investigation
export const GOLDEN_COMMANDS = {
  PodCrashLoopBackOff: [
    'kubectl logs {pod} -n {namespace} --previous --tail=100',
    'kubectl describe pod {pod} -n {namespace}',
    'kubectl get events -n {namespace} --field-selector involvedObject.name={pod} --sort-by=.firstTimestamp'
  ],
  HighMemory: [
    'kubectl top pods -n {namespace} --sort-by=memory',
    'kubectl describe pod {pod} -n {namespace} | grep -A 5 "Limits\\|Requests"',
    'kubectl get pods -n {namespace} -o jsonpath="{.items[*].spec.containers[*].resources}"'
  ],
  NetworkLatency: [
    'kubectl get svc -n {namespace}',
    'kubectl get endpoints -n {namespace}',
    'kubectl describe svc {service} -n {namespace}'
  ]
} as const;
```

### **⚠️ Security Violations to Avoid - 피해야 할 보안 위반**

#### **Forbidden Commands (즉시 차단)**
```bash
# ❌ NEVER EXECUTE THESE - Immediate security violation
kubectl delete pod api-server -n production           # BLOCKED: Delete operation
kubectl create deployment test -n default             # BLOCKED: Create operation  
kubectl apply -f dangerous-config.yaml               # BLOCKED: Apply operation
kubectl patch pod api-server -p '{"spec":{}}'        # BLOCKED: Patch operation
kubectl edit deployment api-server -n production     # BLOCKED: Edit operation

# ❌ NEVER ACCESS THESE - Unauthorized namespaces
kubectl get pods -n kube-system                      # BLOCKED: System namespace
kubectl get secrets -n production                    # BLOCKED: Secrets access
kubectl get pods --all-namespaces                    # BLOCKED: Global access
```

#### **Unsafe Patterns (보안 위험)**
```typescript
// ❌ NEVER DO THIS - Bypassing validation
async function unsafeExecution(command: string): Promise<string> {
  // Direct execution without validation - SECURITY RISK!
  return await exec(command);
}

// ❌ NEVER DO THIS - User input without sanitization
async function processUserCommand(userInput: string): Promise<string> {
  const command = `kubectl ${userInput}`; // Command injection risk!
  return await this.execute(command);
}

// ❌ NEVER DO THIS - Hardcoded credentials
const kubeConfig = {
  server: 'https://k8s-cluster.com',
  token: 'hardcoded-secret-token'  // Credential exposure!
};
```

---

## 📋 **DETAILED RULES - 상세 규칙**

### **MUST Requirements - 필수 요구사항**

#### **1. Command Validation (100% Enforcement)**
- **MUST validate every kubectl command** through CommandValidator before execution
  - 검증 방법: All kubectl calls go through `CommandValidator.validate()` method
  - 실패 시: SecurityError thrown, command blocked, security event logged

- **MUST use only whitelisted operations** - get, describe, logs, top, events
  - 검증 방법: Command parser checks operation against ALLOWED_OPERATIONS array
  - 실패 시: Command rejected with "operation not whitelisted" error

- **MUST add namespace constraints** to all commands to prevent cross-namespace access
  - 검증 방법: All executed commands include `-n {namespace}` parameter
  - 실패 시: Namespace validation error, command execution blocked

#### **2. Namespace Security (Zero Exceptions)**
- **MUST check namespace whitelist** before any Kubernetes API access
  - 검증 방법: Namespace exists in K8S_NAMESPACE_WHITELIST environment variable
  - 실패 시: Access denied, unauthorized namespace access logged

- **MUST restrict to read-only namespaces** - default, aida-test, production, observability only
  - 검증 방법: Hardcoded whitelist in security configuration
  - 실패 시: Namespace access blocked, security alert triggered

#### **3. Audit and Logging (Mandatory)**
- **MUST log all kubectl command attempts** with full context for security audit
  - 검증 방법: Security logger captures all command validation attempts
  - 실패 시: Audit trail incomplete, compliance violation

- **MUST record security violations** with detailed information for investigation
  - 검증 방법: Security events include command, user, timestamp, violation type
  - 실패 시: Security incident tracking incomplete

### **NEVER Rules - 금지 규칙**

#### **1. Destructive Operations (Absolute Prohibition)**
- **NEVER allow delete operations** under any circumstances or use case
  - 위반 결과: Immediate security violation, system integrity compromise
  - 대안: Use read-only analysis to identify issues, delegate fixes to authorized operators

- **NEVER allow create/apply/patch operations** that modify cluster state
  - 위반 결과: Unauthorized system modification, potential security breach
  - 대안: Generate recommended actions for manual review and execution

#### **2. Access Control Violations (System Protection)**
- **NEVER access system namespaces** like kube-system, kube-public, metallb-system
  - 위반 결과: Critical system exposure, potential cluster compromise
  - 대안: Focus analysis on application namespaces only

- **NEVER read secrets or sensitive resources** through kubectl commands
  - 위반 결과: Credential exposure, data privacy violation
  - 대안: Use resource description and status information only

#### **3. Input Validation Bypass (Security Breach)**
- **NEVER execute user-provided commands** without going through CommandValidator
  - 위반 결과: Command injection vulnerability, arbitrary code execution
  - 대안: Always sanitize and validate through security layer

---

## 🔍 **VERIFICATION CHECKLIST - 검증 체크리스트**

### **Pre-Execution Security Check (MUST PASS ALL)**
- [ ] **Command validated**: `CommandValidator.validate()` returns `{ isSafe: true }`
- [ ] **Namespace authorized**: Target namespace in K8S_NAMESPACE_WHITELIST
- [ ] **Operation whitelisted**: Command operation in ALLOWED_OPERATIONS array
- [ ] **No destructive actions**: Command contains no delete/create/apply/patch operations
- [ ] **Audit logging enabled**: Security logger capturing all validation attempts

### **Runtime Security Monitoring (CONTINUOUS)**
- [ ] **All commands logged**: Security audit trail shows complete command history
- [ ] **No validation bypasses**: Zero direct kubectl executions without validation
- [ ] **Namespace boundaries respected**: No cross-namespace access attempts
- [ ] **Error handling secure**: Failed commands don't expose sensitive information
- [ ] **Rate limiting active**: Protection against command flood attacks

### **Security Compliance Verification (MANDATORY)**
- [ ] **Whitelist current**: ALLOWED_OPERATIONS list matches security policy
- [ ] **Forbidden list complete**: All dangerous operations in FORBIDDEN_OPERATIONS
- [ ] **Namespace list updated**: K8S_NAMESPACE_WHITELIST reflects current environment
- [ ] **Logging functional**: Security events reach monitoring system
- [ ] **Validation coverage**: 100% kubectl commands go through security validation

---

## 🚨 **IMMEDIATE FAILURE CONDITIONS - 즉시 실패 조건**

### **Critical Security Violations (Zero Tolerance)**
```bash
# These patterns cause immediate system shutdown:

# 1. Delete operations
kubectl delete pod api-server -n production          # SYSTEM BLOCKED

# 2. Destructive modifications  
kubectl apply -f new-deployment.yaml                 # SYSTEM BLOCKED

# 3. Unauthorized namespace access
kubectl get pods -n kube-system                      # ACCESS DENIED

# 4. Validation bypass attempts
exec('kubectl get pods --all-namespaces')            # SECURITY VIOLATION
```

### **Security Alert Triggers (Immediate Investigation)**
```typescript
// These patterns trigger security alerts:

// 1. Multiple validation failures
CommandValidator.validate() returns isSafe: false    // ALERT: Potential attack

// 2. Unauthorized namespace attempts  
isNamespaceAllowed('kube-system') returns false     // ALERT: Privilege escalation

// 3. Direct command execution
exec(`kubectl ${userInput}`)                        // ALERT: Validation bypass

// 4. Hardcoded credentials
const token = 'sk-1234567890abcdef'                 // ALERT: Credential exposure
```

---

## 🎯 **SUCCESS METRICS - 성공 지표**

### **Security Effectiveness Indicators**
- ✅ **100% command validation** - zero kubectl executions bypass CommandValidator
- ✅ **0 security violations** - no unauthorized operations attempted or executed
- ✅ **Complete audit trail** - every command logged with full security context
- ✅ **Namespace isolation** - perfect adherence to whitelist boundaries
- ✅ **Golden command usage** - 90%+ investigations use pre-validated command sets

### **System Protection Indicators**
- ✅ **Zero system modifications** - no create/delete/patch operations executed
- ✅ **Read-only compliance** - only get/describe/logs/top/events operations used
- ✅ **Credential protection** - no secrets or sensitive data accessed
- ✅ **Rapid violation detection** - security violations detected within 1 second
- ✅ **Automated blocking** - dangerous commands blocked before execution

**VERIFICATION COMMAND**: `npm run test:security && npm run validate:kubectl-commands`

**SUCCESS CRITERIA**: Zero security violations, 100% validation coverage, complete audit trail

### **Emergency Response Protocol**
```bash
# If security violation detected:
1. IMMEDIATELY block all kubectl access
2. Log security incident with full context  
3. Alert security team via monitoring system
4. Preserve audit trail for investigation
5. Require manual security review before resuming operations
```