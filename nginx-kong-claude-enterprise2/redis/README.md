# Redis Integration - Kong AWS Masking MVP

**Project**: nginx-kong-claude-enterprise2  
**Purpose**: Redis data persistence for AWS resource masking operations  
**Last Updated**: 2025-07-30

## 🎯 Overview

This Redis instance serves as the central data persistence layer for AWS resource masking operations, providing bidirectional mapping storage and real-time event communication between Kong Gateway and Backend services.

## 📂 Current Structure

```
redis/
├── README.md                    # This documentation
├── data/                        # Redis data persistence (ACTIVE)
│   └── dump.rdb                 # Redis database file (mounted to container)
└── archive/                     # Development files (ARCHIVED)
    ├── Dockerfile               # Custom Redis Dockerfile (unused)
    ├── docker-entrypoint.sh     # Custom entrypoint script (unused)
    ├── redis.conf.template      # Redis configuration template (unused)
    ├── redis-kong-optimization.lua # Lua optimization script (unused)
    ├── backup-restore-strategy.sh  # Backup script (unused - replaced by scripts/backup/)
    └── REDIS-MASKING-SCHEMA.md  # Data schema documentation (archived)
```

## 🔗 Actual Redis Integration Points

### **1. Docker Compose Configuration** ⭐
**Location**: `docker-compose.yml`  
**Image**: `redis:7-alpine` (standard image, no custom Dockerfile)  
**Connection**: Direct image usage with command line configuration

```yaml
services:
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ./redis/data:/data          # Only this volume mount is used
```

### **2. Kong Plugin Integration** ⭐
**Location**: `kong/plugins/aws-masker/redis_integration.lua`  
**Purpose**: Primary Redis client for masking/unmasking operations  
**Library**: `resty.redis` (Lua Redis client)

**Key Functions**:
- Bidirectional mapping storage (original ↔ masked)
- TTL-based expiration (24 hours default)
- Connection pooling (100 connections, 60s keepalive)
- Pipeline operations for performance

**Data Patterns**:
```lua
-- Forward mapping
aws:mask:i-1234567890abcdef0 → AWS_EC2_001

-- Reverse mapping  
aws:unmask:AWS_EC2_001 → i-1234567890abcdef0

-- Statistics
aws:stats:counts → {"total_mappings": 1500}
```

### **3. Backend Service Integration** ⭐
**Location**: `backend/src/services/redis/`  
**Purpose**: Redis event subscription and monitoring  
**Library**: `ioredis` (Node.js Redis client)

**Active Services**:
- `redisService.js` - Core Redis connection management
- `maskingEventSubscriber.js` - Kong event subscription via Redis Pub/Sub
- `maskingRedisService.js` - Masking-specific Redis operations
- `maskingDataOptimizer.js` - Performance optimization

**Event Subscription**:
```javascript
Channels:
- aws-masker:events:masking   // Masking events from Kong
- aws-masker:events:unmasking // Unmasking events from Kong
```

## 🔄 Redis Data Flow

```
[Kong Plugin] ←→ [Redis] ←→ [Backend Services]
      ↑              ↑              ↑
  Masking Ops    Data Store    Event Monitor
```

### **Masking Operation Flow**:
1. **Kong Plugin**: Receives request with AWS resources
2. **Redis Storage**: Stores original → masked mapping with TTL
3. **Event Publish**: Kong publishes masking event to Redis channel
4. **Backend Subscription**: Backend receives event for monitoring
5. **Response Processing**: Kong retrieves mapping for unmasking
6. **Statistics Update**: Metrics stored in Redis for monitoring

## 📊 Key Redis Features Used

### **Data Structures**:
- **Strings**: Simple key-value mappings with TTL
- **Hashes**: Complex objects with multiple fields
- **Pub/Sub**: Real-time event communication
- **Pipelines**: Atomic multi-command operations

### **Performance Optimizations**:
- Connection pooling (Kong: 100 connections, Backend: configurable)
- TTL-based automatic cleanup (24 hours for mappings)
- Pipeline operations for bulk updates
- Keepalive connections to reduce overhead

### **Security Features**:
- Password authentication (`REDIS_PASSWORD` environment variable)
- Network isolation within Docker network
- No external port exposure (internal Docker communication only)

## 🏗️ Architecture Decisions

### **Why Standard Redis Image?**
- Simplified deployment and maintenance
- Reliable, battle-tested configuration
- No custom modifications needed for current use case
- Easy updates and security patches

### **Why Two Redis Clients?**
- **Kong (Lua)**: High-performance masking operations in request path
- **Backend (Node.js)**: Event monitoring and administrative operations
- Different runtime environments require different client libraries

### **Why TTL-Based Storage?**
- Automatic cleanup prevents memory bloat
- Masking mappings are request-scoped (short-lived)
- Reduces manual maintenance overhead
- Provides natural data expiration

## 🔧 Configuration Details

### **Connection Settings**:
```bash
# Environment variables
REDIS_HOST=redis              # Docker service name
REDIS_PORT=6379               # Standard Redis port
REDIS_PASSWORD=<secure-pass>  # Authentication password
REDIS_DB=0                    # Default database
```

### **Kong Plugin Configuration**:
```lua
-- Connection pool settings
POOL_SIZE = 100
KEEPALIVE_TIMEOUT = 60000     -- 60 seconds
CONNECTION_TIMEOUT = 2000     -- 2 seconds

-- Data organization
MASKING_PREFIX = "aws:mask:"
UNMASK_PREFIX = "aws:unmask:"
STATS_PREFIX = "aws:stats:"
```

### **Backend Service Configuration**:
```javascript
// Redis connection settings
{
  host: 'redis',
  port: 6379,
  password: process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: 3,
  connectTimeout: 10000,
  commandTimeout: 5000
}
```

## 📈 Monitoring & Metrics

### **Built-in Metrics**:
- Total masking operations
- Daily masking counts
- Average processing time
- Success/failure rates
- Active connection counts

### **Health Checks**:
- Docker Compose health check: `redis-cli ping`
- Backend service: Connection validation on startup
- Kong plugin: Fail-secure mode if Redis unavailable

## 🗂️ Archive Information

### **Archived Development Files**:
The `archive/` folder contains development-stage files that are no longer used but preserved for reference:

- **Custom Dockerfile**: Attempted custom Redis build (replaced by standard image)
- **Configuration Templates**: Static config files (replaced by environment variables)
- **Optimization Scripts**: Lua performance scripts (not loaded)
- **Backup Strategies**: Custom backup scripts (replaced by `scripts/backup/`)
- **Schema Documentation**: Detailed data schema design (reference only)

### **Why Archived?**
These files represent the development process where various approaches were explored. The final production system uses a simpler, more reliable approach with the standard Redis image and environment-based configuration.

## 🚀 Operational Guidelines

### **Data Persistence**:
- Redis data is persisted via `./redis/data:/data` volume mount
- Automatic RDB snapshots based on Redis defaults
- Manual backup available via `scripts/backup/redis-backup.sh`

### **Troubleshooting**:
```bash
# Check Redis connectivity
docker exec claude-redis redis-cli -a "$REDIS_PASSWORD" ping

# Monitor active connections
docker exec claude-redis redis-cli -a "$REDIS_PASSWORD" info clients

# View masking statistics
docker exec claude-redis redis-cli -a "$REDIS_PASSWORD" hgetall aws:stats:counts
```

### **Performance Monitoring**:
- Monitor memory usage: `INFO memory`
- Check connection counts: `INFO clients`
- View slow queries: `SLOWLOG GET 10`
- Monitor key expiration: `INFO keyspace`

---

## 📞 Support

For Redis-related issues:
1. Check container health: `docker-compose ps`
2. Verify authentication: `redis-cli ping`
3. Review connection logs in Kong and Backend services
4. Consult Docker Compose logs: `docker-compose logs redis`

**Redis Version**: 7-alpine  
**Client Libraries**: lua-resty-redis (Kong), ioredis (Backend)  
**Data Persistence**: Volume-mounted RDB files