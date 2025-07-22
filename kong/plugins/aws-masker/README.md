# AWS Masker Plugin for Kong Gateway

A security-focused Kong plugin that automatically masks sensitive AWS resource identifiers before sending data to external APIs like Claude API for analysis.

## 🎯 Features

- **Automatic AWS Resource Detection**: Identifies and masks EC2 instances, S3 buckets, RDS instances, and private IPs
- **Bidirectional Masking**: Masks outbound requests and unmasks inbound responses
- **Consistency Guaranteed**: Same AWS resource always gets the same masked identifier
- **Performance Optimized**: < 100ms masking processing time
- **TTL-based Cleanup**: Automatic cleanup of old mappings
- **Memory Efficient**: Configurable limits per CLAUDE.md requirements

## 🏗️ Architecture

```
Request  → AWS Masker → External API (e.g. Claude)
         mask_data()
         
Response ← AWS Masker ← External API  
         unmask_data()
```

## 🚀 Installation

1. Copy plugin files to Kong plugins directory:
```bash
cp -r kong/plugins/aws-masker /usr/local/share/lua/5.1/kong/plugins/
```

2. Enable plugin in Kong configuration:
```yaml
# kong.yml
plugins:
- name: aws-masker
  service: your-service
  config:
    mask_ec2_instances: true
    mask_s3_buckets: true
    mask_rds_instances: true
    mask_private_ips: true
```

## ⚙️ Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mask_ec2_instances` | boolean | `true` | Enable masking of EC2 instance IDs |
| `mask_s3_buckets` | boolean | `true` | Enable masking of S3 bucket names |
| `mask_rds_instances` | boolean | `true` | Enable masking of RDS instances |
| `mask_private_ips` | boolean | `true` | Enable masking of private IP addresses |
| `preserve_structure` | boolean | `true` | Preserve structure of masked identifiers |
| `log_masked_requests` | boolean | `false` | Log requests with masked content |

## 🧪 Testing

```bash
# Run all tests
make test

# Run unit tests only  
make test-unit

# Run with coverage
busted --coverage

# TDD workflow
make tdd    # Watch mode for TDD
make red    # Create failing test
make green  # Make tests pass
make refactor # Quality check after refactor
```

## 🔧 Development

This plugin follows strict TDD (Red-Green-Refactor) methodology and code quality standards:

- **TDD Required**: All code must be test-driven
- **Quality Standards**: 04-code-quality-assurance.md compliance
- **Performance**: < 100ms masking, < 5s total response time
- **Type Safety**: JSDoc annotations throughout

### Quality Checks

```bash
# Full quality check
make quality-check

# Static analysis
make lint

# Performance test
make test-performance
```

## 📊 AWS Resource Patterns

| Resource Type | Pattern | Example | Masked As |
|---------------|---------|---------|-----------|
| EC2 Instance | `i-[0-9a-f]{8,17}` | `i-1234567890abcdef0` | `EC2_001` |
| Private IP | `10\.\d+\.\d+\.\d+` | `10.0.1.100` | `PRIVATE_IP_001` |
| S3 Bucket | DNS-compliant names | `my-bucket.s3.amazonaws.com` | `BUCKET_001` |
| RDS Instance | `[a-zA-Z][a-zA-Z0-9-]{0,62}` | `prod-database` | `RDS_001` |

## 🛡️ Security

- **No Data Leakage**: All sensitive AWS identifiers are masked before external API calls
- **Mapping Isolation**: Each request gets isolated mapping store
- **TTL Cleanup**: Automatic cleanup prevents memory leaks
- **Read-only AWS**: Uses read-only AWS credentials

## ⚡ Performance

- **Masking Time**: < 100ms (per CLAUDE.md requirements)
- **Total Response**: < 5 seconds end-to-end
- **Memory Limit**: Configurable per-store limits
- **Concurrent Safe**: Thread-safe mapping operations

## 🔗 Integration Example

```lua
-- Kong configuration
local masker = require("kong.plugins.aws-masker.masker")

-- Create mapping store
local mapping_store = masker.create_mapping_store()

-- Mask AWS resources
local original = "EC2 instance i-1234567890abcdef0 has IP 10.0.1.100"
local result = masker.mask_data(original, mapping_store)
-- result.masked = "EC2 instance EC2_001 has IP PRIVATE_IP_001"

-- Unmask for response
local unmasked = masker.unmask_data(result.masked, mapping_store)
-- unmasked = "EC2 instance i-1234567890abcdef0 has IP 10.0.1.100"
```

## 📝 License

MIT License - See LICENSE file for details.

## 🤝 Contributing

1. Follow TDD methodology (Red-Green-Refactor)
2. Maintain > 80% test coverage
3. Use JSDoc annotations for all functions
4. Follow 04-code-quality-assurance.md standards
5. Run `make quality-check` before committing

## 📞 Support

For issues and questions, see project documentation in `/Docs/Standards/`.