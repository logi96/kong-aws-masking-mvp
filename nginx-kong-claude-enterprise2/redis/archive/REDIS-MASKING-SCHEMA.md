# Redis Masking Data Schema Design

## Overview
This document defines the Redis data schema optimized for AWS resource masking operations, including key patterns, data structures, TTL strategies, and database organization.

## Database Organization

### DB 0: Active Masking Mappings (Short TTL)
**Purpose**: Store current masking mappings for active requests
**Default TTL**: 1 hour

```
Key Pattern: mask:active:{request_id}:{resource_type}:{masked_id}
Value: JSON object with original value and metadata
Example: mask:active:req123:ec2:EC2_001
Value: {
  "original": "i-1234567890abcdef0",
  "resource_type": "ec2",
  "masked_at": "2025-01-28T10:30:00Z",
  "request_id": "req123",
  "ttl": 3600
}
```

### DB 1: Historical Masking Data (Long TTL)
**Purpose**: Store masking history for audit and debugging
**Default TTL**: 7 days

```
Key Pattern: mask:history:{date}:{resource_type}:{hash}
Value: Compressed JSON with full masking context
Example: mask:history:20250128:s3:a1b2c3d4
Value: {
  "mappings": [...],
  "request_count": 15,
  "first_seen": "2025-01-28T09:00:00Z",
  "last_seen": "2025-01-28T15:00:00Z"
}
```

### DB 2: Unmasking Reverse Mappings (Permanent)
**Purpose**: Enable reverse lookup from masked to original values
**Default TTL**: None (permanent until explicitly deleted)

```
Key Pattern: unmask:{masked_id}
Value: Original value with metadata
Example: unmask:EC2_001
Value: {
  "original": "i-1234567890abcdef0",
  "resource_type": "ec2",
  "created_at": "2025-01-28T10:30:00Z",
  "access_count": 42
}
```

### DB 3: Metrics and Monitoring (Medium TTL)
**Purpose**: Store performance metrics and monitoring data
**Default TTL**: 24 hours

```
Key Pattern: metrics:{metric_type}:{timestamp}
Value: Numeric or JSON metrics data
Example: metrics:masking_rate:20250128:10
Value: {
  "requests": 1500,
  "masked_resources": 4500,
  "avg_latency_ms": 2.3,
  "errors": 0
}
```

## Key Naming Conventions

### Hierarchical Structure
```
{namespace}:{type}:{identifier}:{sub-identifier}
```

### Namespaces
- `mask`: Forward masking mappings
- `unmask`: Reverse masking mappings
- `metrics`: Performance and monitoring data
- `config`: Configuration and settings
- `session`: Session-based temporary data

## Data Structures

### 1. Simple Key-Value Pairs
For direct mappings:
```redis
SET mask:active:req123:ec2:EC2_001 "i-1234567890abcdef0" EX 3600
```

### 2. Hash Sets
For complex objects with multiple fields:
```redis
HSET unmask:EC2_001 
  original "i-1234567890abcdef0"
  resource_type "ec2"
  created_at "2025-01-28T10:30:00Z"
  access_count 0
```

### 3. Sorted Sets
For time-series data and rankings:
```redis
ZADD metrics:top_masked_resources 1516 "ec2"
ZADD metrics:top_masked_resources 892 "s3"
ZADD metrics:top_masked_resources 651 "rds"
```

### 4. Lists
For queues and recent items:
```redis
LPUSH recent:masked_resources "EC2_001:i-1234567890abcdef0"
LTRIM recent:masked_resources 0 999
```

### 5. Sets
For unique collections:
```redis
SADD active:request_ids "req123"
SADD masked:resource_types "ec2" "s3" "rds"
```

## TTL Management Strategy

### Automatic Expiration Rules
1. **Active Mappings**: 1 hour default, extendable to 4 hours
2. **Session Data**: 30 minutes, refreshed on access
3. **Historical Data**: 7 days, compressed after 1 day
4. **Metrics**: 24 hours for detailed, 30 days for aggregated

### TTL Commands
```redis
# Set TTL on creation
SET key value EX 3600

# Update TTL
EXPIRE key 7200

# Remove TTL (make permanent)
PERSIST key

# Check remaining TTL
TTL key
```

## Memory Optimization

### 1. Key Compression
Use short prefixes and numeric IDs:
```
Bad:  masking:active:request:12345:amazon_ec2_instance:EC2_INSTANCE_001
Good: m:a:r12345:ec2:EC2_001
```

### 2. Value Compression
Store only essential data:
```json
// Full format (historical data)
{
  "original": "i-1234567890abcdef0",
  "resource_type": "ec2",
  "region": "us-east-1",
  "account_id": "123456789012",
  "tags": {...},
  "metadata": {...}
}

// Compressed format (active data)
{
  "o": "i-1234567890abcdef0",
  "t": "ec2",
  "r": "us-east-1"
}
```

### 3. Data Structure Selection
- Use Hashes for objects with < 100 fields
- Use Strings for simple mappings
- Use Sorted Sets for time-series data
- Avoid large nested structures

## Query Patterns

### 1. Get Original Value from Masked ID
```redis
GET unmask:EC2_001
```

### 2. Get All Maskings for a Request
```redis
KEYS mask:active:req123:*
```

### 3. Get Masking Rate Metrics
```redis
ZREVRANGE metrics:masking_rate:20250128 0 -1 WITHSCORES
```

### 4. Clean Up Expired Sessions
```redis
# Handled automatically by Redis TTL
# Manual cleanup if needed:
DEL session:expired_session_id
```

## Backup and Recovery

### Backup Strategy
1. **RDB Snapshots**: Every 5 minutes for active data
2. **AOF Persistence**: Every second for durability
3. **External Backup**: Daily export to S3

### Recovery Priority
1. DB 2 (Unmasking mappings) - Critical
2. DB 0 (Active mappings) - High
3. DB 1 (Historical data) - Medium
4. DB 3 (Metrics) - Low

## Performance Considerations

### 1. Pipeline Operations
```javascript
// Use pipeline for batch operations
const pipeline = redis.pipeline();
maskings.forEach(m => {
  pipeline.set(`mask:${m.id}`, m.value, 'EX', 3600);
});
await pipeline.exec();
```

### 2. Lua Scripts
For atomic operations:
```lua
-- Atomic increment with limit
local current = redis.call('GET', KEYS[1])
if not current then current = 0 end
if tonumber(current) < tonumber(ARGV[1]) then
  return redis.call('INCR', KEYS[1])
else
  return nil
end
```

### 3. Connection Pooling
- Min connections: 5
- Max connections: 50
- Idle timeout: 30 seconds

## Monitoring and Alerts

### Key Metrics to Monitor
1. **Memory Usage**: Alert at 80% of maxmemory
2. **Eviction Rate**: Alert if > 100 keys/second
3. **Connection Count**: Alert if > 40 concurrent
4. **Command Latency**: Alert if > 10ms average
5. **Key Expiration**: Track expired vs total keys

### Health Check Keys
```redis
# Write heartbeat
SET health:heartbeat "OK" EX 60

# Check specific databases
SELECT 0
DBSIZE

SELECT 2
EXISTS unmask:EC2_001
```

## Security Considerations

### 1. Key Access Patterns
- Use ACLs to restrict access by key pattern
- Separate read/write permissions by database
- Audit all unmask operations

### 2. Data Encryption
- Enable TLS for client connections
- Use encrypted RDB snapshots
- Rotate passwords regularly

### 3. Command Restrictions
Already configured in redis.conf:
- FLUSHDB disabled
- FLUSHALL disabled  
- CONFIG disabled
- EVAL disabled (use EVALSHA with pre-loaded scripts)

## Migration and Scaling

### Scaling Strategy
1. **Vertical**: Increase memory up to 8GB
2. **Read Replicas**: For read-heavy unmask operations
3. **Sharding**: By resource type if needed

### Data Migration
```bash
# Export specific database
redis-cli -n 2 --rdb unmask-backup.rdb

# Import to new instance
redis-cli -h new-host --pipe < unmask-backup.rdb
```

## Usage Examples

### Node.js Integration
```javascript
const Redis = require('ioredis');

class MaskingCache {
  constructor() {
    this.clients = {
      active: new Redis({ db: 0 }),
      history: new Redis({ db: 1 }),
      unmask: new Redis({ db: 2 }),
      metrics: new Redis({ db: 3 })
    };
  }

  async storeMasking(requestId, resourceType, maskedId, original, ttl = 3600) {
    const key = `mask:active:${requestId}:${resourceType}:${maskedId}`;
    const value = JSON.stringify({
      original,
      resource_type: resourceType,
      masked_at: new Date().toISOString(),
      request_id: requestId,
      ttl
    });
    
    await this.clients.active.set(key, value, 'EX', ttl);
    await this.clients.unmask.set(`unmask:${maskedId}`, JSON.stringify({
      original,
      resource_type: resourceType,
      created_at: new Date().toISOString(),
      access_count: 0
    }));
  }

  async getOriginal(maskedId) {
    const data = await this.clients.unmask.get(`unmask:${maskedId}`);
    if (data) {
      const parsed = JSON.parse(data);
      // Increment access count
      await this.clients.unmask.hincrby(`unmask:${maskedId}:meta`, 'access_count', 1);
      return parsed.original;
    }
    return null;
  }
}
```

## Best Practices

1. **Always set TTL** for non-permanent data
2. **Use appropriate data structures** for your access patterns
3. **Monitor memory usage** and eviction policies
4. **Implement circuit breakers** for Redis failures
5. **Use Redis transactions** for atomic operations
6. **Compress large values** before storage
7. **Batch operations** when possible
8. **Implement retry logic** with exponential backoff
9. **Use connection pooling** for better performance
10. **Regular backup testing** and recovery drills