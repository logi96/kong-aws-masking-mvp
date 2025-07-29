# Redis Integration Guide for Kong AWS Masker

## Overview

This guide documents the Redis integration between Kong AWS Masker plugin and the Backend service, designed by the database-specialist, kong-plugin-developer, and kong-integration-validator agents.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Backend   │────▶│     Kong     │────▶│   Claude    │
│   Service   │     │   Gateway    │     │     API     │
└──────┬──────┘     └──────┬───────┘     └─────────────┘
       │                   │
       │      ┌────────────┴────────────┐
       └──────│        Redis            │
              │  (Masking Mappings)     │
              └─────────────────────────┘
```

## Key Components

### 1. Backend Redis Services

#### MaskingRedisService (`src/services/redis/maskingRedisService.js`)
- Specialized service for AWS masking data management
- Handles bidirectional mapping storage (original ↔ masked)
- Implements TTL management for automatic cleanup
- Provides batch operations for performance
- Includes distributed locking for concurrent access
- Cache management for Claude API responses

#### MaskingService (`src/services/masking/maskingService.js`)
- High-level masking/unmasking operations
- Pattern-based AWS resource detection
- Integration with Redis for persistent mappings
- Validation and statistics tracking

### 2. Kong Plugin Integration

#### Redis Integration Module (`kong/plugins/aws-masker/redis_integration.lua`)
- Connection pool management
- High-performance Lua-based Redis operations
- Pipeline support for atomic operations
- Health checking and circuit breaker pattern

#### Handler Updates (`kong/plugins/aws-masker/handler.lua`)
- Redis client initialization
- Fail-secure mode when Redis unavailable
- Mapping store integration
- Performance monitoring

### 3. API Endpoints

#### Masking Statistics
```bash
GET /analyze/masking/stats
```
Returns current masking statistics from Redis.

#### Masking Validation
```bash
POST /analyze/masking/validate
{
  "original": "Instance i-1234567890abcdef0",
  "masked": "Instance EC2_001"
}
```
Validates masking consistency.

#### Cleanup Expired Mappings
```bash
POST /analyze/masking/cleanup
```
Removes expired mappings from Redis.

## Configuration

### Environment Variables

Create `.env` file with Redis settings:

```bash
# Redis Connection
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your_password_here
REDIS_DB=0

# Masking Settings
MASKING_TTL=604800  # 7 days
MASKING_MAX_ENTRIES=10000
USE_REDIS=true
REDIS_FALLBACK=true
```

### Kong Plugin Configuration

In `kong.yml`:

```yaml
plugins:
  - name: aws-masker
    config:
      use_redis: true
      redis_host: redis
      redis_port: 6379
      redis_password: ${REDIS_PASSWORD}
      mapping_ttl: 604800
      redis_timeout: 2000
      redis_keepalive_pool_size: 100
```

## Data Flow

### Masking Flow
1. Backend receives AWS resource data
2. Kong plugin intercepts request
3. Plugin checks Redis for existing mappings
4. New mappings created with atomic counters
5. Bidirectional mappings stored with TTL
6. Masked data sent to Claude API

### Unmasking Flow
1. Claude API response received
2. Kong plugin extracts masked identifiers
3. Redis lookup for original values
4. Response transformed with original values
5. Backend receives unmasked response

## Redis Data Structure

### Namespaces
- `aws:mask:*` - Original to masked mappings
- `aws:unmask:*` - Masked to original mappings
- `aws:stats:*` - Usage statistics
- `aws:lock:*` - Distributed locks
- `aws:cache:*` - Response cache

### Example Data
```
aws:mask:i-1234567890abcdef0 → EC2_001
aws:unmask:EC2_001 → i-1234567890abcdef0
aws:stats:counts → {total_mappings: 150, ...}
```

## Performance Considerations

### Connection Pooling
- Backend: ioredis with connection pooling
- Kong: lua-resty-redis with keepalive pools
- Pool size: 100 connections
- Keepalive timeout: 60 seconds

### Batch Operations
- Use pipeline for multiple operations
- Batch get/set for bulk mappings
- Atomic counters for ID generation

### TTL Management
- Default TTL: 7 days
- Automatic cleanup of expired keys
- Manual cleanup endpoint available

## Security Features

### Fail-Secure Mode
- Kong blocks requests if Redis unavailable
- Prevents AWS data exposure
- Circuit breaker pattern implementation

### Data Protection
- Bidirectional mapping for consistency
- No sensitive data in logs
- Secure Redis password handling

## Monitoring and Health

### Health Checks
- Redis connectivity monitoring
- Latency tracking
- Memory usage statistics
- Circuit breaker status

### Metrics
- Total mappings count
- Daily mapping statistics
- Cache hit/miss rates
- Processing time tracking

## Testing

### Unit Tests
```bash
npm test tests/unit/redisService.test.js
```

### Integration Tests
```bash
npm test tests/integration/redis-masking-integration.test.js
```

### Validation Script
```bash
./tests/integration/validate-kong-redis-integration.sh
```

## Troubleshooting

### Common Issues

1. **Redis Connection Failed**
   - Check Redis host/port configuration
   - Verify Redis is running
   - Check network connectivity

2. **Mappings Not Persisting**
   - Verify TTL settings
   - Check Redis memory limits
   - Monitor eviction policies

3. **Performance Degradation**
   - Check connection pool exhaustion
   - Monitor Redis CPU/memory
   - Review pipeline usage

### Debug Commands

```bash
# Check Redis connectivity
redis-cli ping

# Monitor Redis commands
redis-cli monitor

# Check mapping counts
redis-cli --scan --pattern "aws:mask:*" | wc -l

# View statistics
redis-cli hgetall aws:stats:counts
```

## Best Practices

1. **Always use batch operations** for multiple mappings
2. **Set appropriate TTLs** to prevent memory bloat
3. **Monitor Redis memory usage** regularly
4. **Use distributed locks** for critical sections
5. **Implement circuit breakers** for resilience
6. **Cache frequently accessed data** to reduce latency

## Future Enhancements

1. **Redis Cluster Support** for horizontal scaling
2. **Pub/Sub for Real-time Events** 
3. **Advanced Analytics** with time-series data
4. **Automatic Scaling** based on load
5. **Multi-region Replication** for global deployments

## References

- [Redis Documentation](https://redis.io/documentation)
- [Kong Plugin Development](https://docs.konghq.com/gateway/latest/plugin-development/)
- [lua-resty-redis](https://github.com/openresty/lua-resty-redis)
- [ioredis Documentation](https://github.com/luin/ioredis)