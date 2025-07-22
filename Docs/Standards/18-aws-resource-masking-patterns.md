# 🔐 **AWS Resource Masking Patterns - Security & Implementation Guide**

<!-- Tags: #aws #masking #security #patterns #regex #privacy -->

> **PURPOSE**: Comprehensive patterns and strategies for masking AWS resource identifiers  
> **SCOPE**: Resource identification, masking patterns, security considerations, implementation guidelines  
> **COMPLEXITY**: ⭐⭐⭐ Intermediate | **DURATION**: 2-3 hours for pattern implementation  
> **CRITICAL**: Proper masking prevents sensitive data exposure while maintaining data utility

---

## ⚡ **QUICK REFERENCE - Essential Patterns**

### 🎯 **Core AWS Resource Patterns**
```javascript
// Essential masking patterns
const awsPatterns = {
  ec2Instance: /i-[0-9a-f]{8,17}/g,
  privateIP: /10\.\d{1,3}\.\d{1,3}\.\d{1,3}/g,
  s3Bucket: /[a-z0-9][a-z0-9-]{1,61}[a-z0-9](?=\.s3)/g,
  rdsInstance: /[a-z][a-z0-9-]{0,62}/g,
  lambdaFunction: /arn:aws:lambda:[^:]+:[^:]+:function:[^:]+/g,
  iamRole: /arn:aws:iam::\d{12}:role\/[^,\s]+/g
};
```

### 🔍 **Quick Masking Example**
```javascript
// Before masking
"Instance i-1234567890abcdef0 at 10.0.1.23"

// After masking  
"Instance EC2_001 at PRIVATE_IP_001"
```

---

## 📋 **AWS RESOURCE TAXONOMY**

### **Compute Resources**
| Resource | Pattern | Example | Masked Format |
|----------|---------|---------|---------------|
| EC2 Instance | `i-[0-9a-f]{8,17}` | i-1234567890abcdef0 | EC2_001 |
| AMI | `ami-[0-9a-f]{8,17}` | ami-0abcdef1234567890 | AMI_001 |
| EBS Volume | `vol-[0-9a-f]{8,17}` | vol-049df61146f12c45a | VOL_001 |
| Snapshot | `snap-[0-9a-f]{8,17}` | snap-066877671789bd71b | SNAP_001 |
| Security Group | `sg-[0-9a-f]{8,17}` | sg-0123456789abcdef0 | SG_001 |

### **Networking Resources**
| Resource | Pattern | Example | Masked Format |
|----------|---------|---------|---------------|
| VPC | `vpc-[0-9a-f]{8,17}` | vpc-12345678 | VPC_001 |
| Subnet | `subnet-[0-9a-f]{8,17}` | subnet-12345678 | SUBNET_001 |
| Private IP | `10\.\d{1,3}\.\d{1,3}\.\d{1,3}` | 10.0.1.23 | PRIVATE_IP_001 |
| Private IP Alt | `172\.(1[6-9]|2[0-9]|3[01])\.\d{1,3}\.\d{1,3}` | 172.16.0.1 | PRIVATE_IP_002 |
| Private IP RFC | `192\.168\.\d{1,3}\.\d{1,3}` | 192.168.1.1 | PRIVATE_IP_003 |

### **Storage Resources**
| Resource | Pattern | Example | Masked Format |
|----------|---------|---------|---------------|
| S3 Bucket | `[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\.s3` | my-bucket-name.s3 | BUCKET_001 |
| S3 ARN | `arn:aws:s3:::([^/]+)` | arn:aws:s3:::my-bucket | S3_ARN_001 |
| EFS | `fs-[0-9a-f]{8,17}` | fs-0123456789abcdef0 | EFS_001 |

### **Database Resources**
| Resource | Pattern | Example | Masked Format |
|----------|---------|---------|---------------|
| RDS Instance | Custom validation needed | mydb-instance-1 | RDS_001 |
| RDS Cluster | `[a-z][a-z0-9-]*cluster` | prod-cluster | RDS_CLUSTER_001 |
| DynamoDB Table | `[a-zA-Z0-9_.-]{3,255}` | UserTable | DYNAMO_001 |
| Redshift Cluster | `[a-z][a-z0-9-]{0,62}` | analytics-cluster | REDSHIFT_001 |

---

## 🏗️ **IMPLEMENTATION PATTERNS**

### **JavaScript/TypeScript Implementation**
```typescript
interface MaskingRule {
  pattern: RegExp;
  resourceType: string;
  maskPrefix: string;
  validate?: (match: string) => boolean;
}

class AWSResourceMasker {
  private rules: MaskingRule[] = [
    {
      pattern: /i-[0-9a-f]{8,17}/g,
      resourceType: 'ec2',
      maskPrefix: 'EC2_',
      validate: (match) => match.length >= 10
    },
    {
      pattern: /10\.\d{1,3}\.\d{1,3}\.\d{1,3}/g,
      resourceType: 'privateIp',
      maskPrefix: 'PRIVATE_IP_'
    }
  ];
  
  private mappings = new Map<string, string>();
  private counters = new Map<string, number>();
  
  mask(text: string): string {
    let maskedText = text;
    
    for (const rule of this.rules) {
      maskedText = maskedText.replace(rule.pattern, (match) => {
        // Return existing mapping if available
        if (this.mappings.has(match)) {
          return this.mappings.get(match)!;
        }
        
        // Validate if validator exists
        if (rule.validate && !rule.validate(match)) {
          return match;
        }
        
        // Generate new mask
        const counter = this.getNextCounter(rule.resourceType);
        const masked = `${rule.maskPrefix}${String(counter).padStart(3, '0')}`;
        
        // Store mapping
        this.mappings.set(match, masked);
        
        return masked;
      });
    }
    
    return maskedText;
  }
  
  private getNextCounter(resourceType: string): number {
    const current = this.counters.get(resourceType) || 0;
    const next = current + 1;
    this.counters.set(resourceType, next);
    return next;
  }
}
```

### **Lua Implementation (Kong Plugin)**
```lua
local patterns = {
  {
    name = "ec2_instance",
    pattern = "i%-[0-9a-f]+",
    prefix = "EC2_"
  },
  {
    name = "private_ip", 
    pattern = "10%.%d+%.%d+%.%d+",
    prefix = "PRIVATE_IP_"
  },
  {
    name = "s3_bucket",
    pattern = "[a-z0-9][a-z0-9%-]*[a-z0-9]%.s3",
    prefix = "BUCKET_"
  }
}

local function mask_aws_resources(text)
  local mappings = {}
  local counters = {}
  local masked = text
  
  for _, pattern_config in ipairs(patterns) do
    local counter = 1
    
    masked = ngx.re.gsub(masked, pattern_config.pattern, 
      function(match)
        local key = match[0]
        
        -- Check existing mapping
        if mappings[key] then
          return mappings[key]
        end
        
        -- Create new mapping
        local masked_value = pattern_config.prefix .. 
                           string.format("%03d", counter)
        mappings[key] = masked_value
        counter = counter + 1
        
        return masked_value
      end, "jo")
  end
  
  return masked, mappings
end
```

---

## 🔒 **SECURITY CONSIDERATIONS**

### **Masking Principles**
```typescript
// 1. Consistency - Same resource always gets same mask
const maskingPrinciples = {
  consistency: "i-abc123 → EC2_001 (always)",
  uniqueness: "Each unique resource gets unique mask",
  reversibility: "Maintain mapping for potential unmask",
  security: "Never log or persist original values"
};

// 2. Scope Isolation - Separate mappings per request/session
class ScopedMasker {
  private scopedMappings = new WeakMap<object, Map<string, string>>();
  
  maskWithScope(text: string, scope: object): string {
    if (!this.scopedMappings.has(scope)) {
      this.scopedMappings.set(scope, new Map());
    }
    
    const mappings = this.scopedMappings.get(scope)!;
    // Masking logic using scoped mappings
    return this.applyMasking(text, mappings);
  }
}
```

### **Data Leakage Prevention**
```javascript
// ✅ Secure practices
function secureMask(data) {
  const masked = maskSensitiveData(data);
  
  // Never log original data
  logger.info('Processed request', { 
    length: data.length,
    masked: true 
  });
  
  return masked;
}

// ❌ Avoid these patterns
function insecureMask(data) {
  console.log('Original:', data);  // Logs sensitive data
  const mappings = {};
  
  // Storing mappings in global scope
  globalMappings[data] = masked;  // Security risk
  
  return masked;
}
```

---

## 🎯 **ADVANCED PATTERNS**

### **Context-Aware Masking**
```typescript
interface MaskingContext {
  preserveStructure: boolean;
  maskingLevel: 'partial' | 'full';
  resourceTypes: string[];
}

function contextualMask(text: string, context: MaskingContext): string {
  if (context.maskingLevel === 'partial') {
    // Partial masking: i-1234567890abcdef0 → i-****cdef0
    return text.replace(/i-([0-9a-f]{4})[0-9a-f]+([0-9a-f]{4})/, 'i-$1****$2');
  }
  
  // Full masking
  return fullMask(text);
}
```

### **Pattern Validation**
```javascript
// Validate AWS resource formats
const validators = {
  ec2Instance: (id) => {
    return /^i-[0-9a-f]{8}([0-9a-f]{9})?$/.test(id);
  },
  
  s3Bucket: (name) => {
    // S3 bucket naming rules
    if (name.length < 3 || name.length > 63) return false;
    if (!/^[a-z0-9]/.test(name)) return false;
    if (!/[a-z0-9]$/.test(name)) return false;
    if (/\.\./.test(name)) return false;
    if (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(name)) return false;
    
    return true;
  },
  
  iamRole: (arn) => {
    return /^arn:aws:iam::\d{12}:role\/[\w+=,.@-]{1,64}$/.test(arn);
  }
};
```

### **Composite Resource Handling**
```typescript
// Handle complex AWS resource strings
function maskCompositeResources(text: string): string {
  // ARN format: arn:partition:service:region:account:resource
  const arnPattern = /arn:aws:([^:]+):([^:]*):(\d{12}):(.+)/g;
  
  return text.replace(arnPattern, (match, service, region, account, resource) => {
    const maskedAccount = 'ACCOUNT_MASKED';
    const maskedResource = maskResourceByType(service, resource);
    
    return `arn:aws:${service}:${region}:${maskedAccount}:${maskedResource}`;
  });
}

function maskResourceByType(service: string, resource: string): string {
  switch(service) {
    case 'ec2':
      return resource.replace(/i-[0-9a-f]+/g, 'EC2_MASKED');
    case 's3':
      return resource.replace(/[^/]+/, 'BUCKET_MASKED');
    case 'lambda':
      return resource.replace(/function:(.+)/, 'function:LAMBDA_MASKED');
    default:
      return 'RESOURCE_MASKED';
  }
}
```

---

## 📊 **PERFORMANCE OPTIMIZATION**

### **Efficient Pattern Matching**
```javascript
// Pre-compile patterns for performance
class OptimizedMasker {
  private compiledPatterns: Array<{
    regex: RegExp;
    replacer: (match: string, index: number) => string;
  }>;
  
  constructor() {
    this.compiledPatterns = [
      {
        regex: new RegExp('i-[0-9a-f]{8,17}', 'g'),
        replacer: (match, index) => `EC2_${String(index).padStart(3, '0')}`
      }
    ];
  }
  
  mask(text: string): string {
    let result = text;
    
    for (const pattern of this.compiledPatterns) {
      let index = 1;
      result = result.replace(pattern.regex, (match) => {
        return pattern.replacer(match, index++);
      });
    }
    
    return result;
  }
}
```

### **Caching Strategy**
```typescript
class CachedMasker {
  private cache = new LRUCache<string, string>({ max: 1000 });
  
  mask(text: string): string {
    const cacheKey = this.generateCacheKey(text);
    
    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey)!;
    }
    
    const masked = this.performMasking(text);
    this.cache.set(cacheKey, masked);
    
    return masked;
  }
  
  private generateCacheKey(text: string): string {
    // Use hash for long texts
    if (text.length > 100) {
      return crypto.createHash('md5').update(text).digest('hex');
    }
    return text;
  }
}
```

---

## 🧪 **TESTING PATTERNS**

### **Pattern Test Cases**
```javascript
describe('AWS Resource Masking', () => {
  const masker = new AWSResourceMasker();
  
  describe('EC2 Instances', () => {
    test('masks standard instance IDs', () => {
      expect(masker.mask('i-1234567890abcdef0')).toBe('EC2_001');
    });
    
    test('masks multiple instances consistently', () => {
      const text = 'i-abc123 connects to i-def456 and i-abc123';
      expect(masker.mask(text))
        .toBe('EC2_001 connects to EC2_002 and EC2_001');
    });
    
    test('handles invalid formats', () => {
      expect(masker.mask('i-123')).toBe('i-123'); // Too short
      expect(masker.mask('i_1234567890')).toBe('i_1234567890'); // Wrong separator
    });
  });
  
  describe('IP Addresses', () => {
    test('masks private IPs only', () => {
      const text = '10.0.1.1 and 8.8.8.8 and 192.168.1.1';
      expect(masker.mask(text))
        .toBe('PRIVATE_IP_001 and 8.8.8.8 and PRIVATE_IP_002');
    });
  });
});
```

### **Edge Cases**
```javascript
const edgeCases = [
  // Embedded in JSON
  {
    input: '{"instance":"i-1234567890abcdef0"}',
    expected: '{"instance":"EC2_001"}'
  },
  
  // URL encoded
  {
    input: 'instance%3Di-1234567890abcdef0',
    expected: 'instance%3DEC2_001'
  },
  
  // Mixed resources
  {
    input: 'EC2 i-abc123 in subnet-def456 at 10.0.1.1',
    expected: 'EC2 EC2_001 in SUBNET_001 at PRIVATE_IP_001'
  }
];
```

---

## 💡 **BEST PRACTICES**

### **Do's**
```javascript
// ✅ Recommended practices
- Use consistent masking across the application
- Maintain mappings only in memory
- Implement TTL for mapping cleanup
- Validate patterns before masking
- Test with real AWS resource formats
- Monitor masking performance
- Document masked formats clearly
```

### **Don'ts**
```javascript
// ❌ Avoid these
- Don't persist original values in logs
- Don't use reversible hashing (MD5/SHA1)
- Don't mask public resources (regions, AZs)
- Don't create predictable patterns
- Don't ignore edge cases
- Don't mask already-masked values
```

---

## 🔧 **TROUBLESHOOTING GUIDE**

### **Common Issues**

| Issue | Symptom | Solution |
|-------|---------|----------|
| Over-masking | Public IPs masked | Refine IP patterns to exclude public ranges |
| Under-masking | Some resources exposed | Add missing patterns, validate regex |
| Inconsistent masking | Same resource different masks | Check mapping persistence |
| Performance degradation | Slow response times | Pre-compile patterns, implement caching |
| Memory growth | Increasing memory usage | Implement TTL, limit mapping size |

### **Debugging Techniques**
```javascript
// Debug mode for pattern matching
function debugMask(text, options = { verbose: true }) {
  const matches = [];
  
  patterns.forEach(pattern => {
    const regex = new RegExp(pattern.pattern, 'g');
    let match;
    
    while ((match = regex.exec(text)) !== null) {
      matches.push({
        pattern: pattern.name,
        match: match[0],
        index: match.index,
        masked: pattern.mask(match[0])
      });
    }
  });
  
  if (options.verbose) {
    console.table(matches);
  }
  
  return matches;
}
```

---

**🔑 Key Message**: Effective AWS resource masking requires comprehensive pattern coverage, consistent implementation, and careful security considerations. Always validate patterns against real AWS resources and maintain strict security practices to prevent data leakage.