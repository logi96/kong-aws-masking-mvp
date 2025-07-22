# Kong AWS Masking MVP - Basic Service Stability Guide

## Overview
Practical stability measures for MVP phase focusing on essential error handling and health monitoring.

## 1. Stability Goals for MVP

### 1.1 Simple Stability Targets
- **Availability**: Basic health checks
- **Error Handling**: Graceful error responses
- **Recovery**: Manual restart procedures
- **Response Time**: Best effort (target < 5 seconds)

### 1.2 MVP Focus Areas
1. Basic error handling
2. Simple health checks
3. Structured logging
4. Manual recovery procedures

## 2. Error Handling

### 2.1 Basic Error Handler
```javascript
// backend/middleware/errorHandler.js

/**
 * Global error handler middleware
 * @param {Error} error - Error object
 * @param {Request} req - Express request
 * @param {Response} res - Express response
 * @param {Function} next - Next middleware
 */
function errorHandler(error, req, res, next) {
  // Log error
  console.error('Error occurred:', {
    message: error.message,
    path: req.path,
    method: req.method,
    timestamp: new Date().toISOString()
  });

  // Send appropriate response
  if (error.name === 'ValidationError') {
    return res.status(400).json({
      success: false,
      error: 'Invalid request data'
    });
  }

  if (error.code === 'ECONNREFUSED') {
    return res.status(503).json({
      success: false,
      error: 'Service temporarily unavailable'
    });
  }

  // Default error response
  res.status(500).json({
    success: false,
    error: 'Internal server error'
  });
}

module.exports = errorHandler;
```

### 2.2 Simple Retry Logic
```javascript
// backend/utils/retry.js

/**
 * Simple retry wrapper for external API calls
 * @param {Function} fn - Function to retry
 * @param {number} maxRetries - Maximum retry attempts
 * @returns {Promise} Result of function
 */
async function retryOperation(fn, maxRetries = 3) {
  let lastError;
  
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      console.log(`Retry attempt ${i + 1}/${maxRetries}`);
      
      // Don't retry client errors
      if (error.response && error.response.status < 500) {
        throw error;
      }
      
      // Wait before retry (simple backoff)
      if (i < maxRetries - 1) {
        await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)));
      }
    }
  }
  
  throw lastError;
}

module.exports = { retryOperation };
```

## 3. Health Checks

### 3.1 Basic Health Endpoint
```javascript
// backend/routes/health.js
const express = require('express');
const router = express.Router();

/**
 * Basic health check endpoint
 */
router.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'backend-api'
  });
});

/**
 * Readiness check with dependency verification
 */
router.get('/health/ready', async (req, res) => {
  const checks = {
    api: 'ok',
    environment: process.env.ANTHROPIC_API_KEY ? 'ok' : 'missing'
  };
  
  const isReady = Object.values(checks).every(status => status === 'ok');
  
  res.status(isReady ? 200 : 503).json({
    status: isReady ? 'ready' : 'not ready',
    checks,
    timestamp: new Date().toISOString()
  });
});

module.exports = router;
```

### 3.2 Docker Health Checks
```yaml
# docker-compose.yml health check configuration
services:
  backend:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  kong:
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## 4. Logging

### 4.1 Simple Structured Logging
```javascript
// backend/utils/logger.js

/**
 * Simple logger wrapper
 */
class Logger {
  static log(level, message, data = {}) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      ...data
    };
    
    console.log(JSON.stringify(logEntry));
  }
  
  static info(message, data) {
    this.log('info', message, data);
  }
  
  static error(message, data) {
    this.log('error', message, data);
  }
  
  static warn(message, data) {
    this.log('warn', message, data);
  }
}

// Request logging middleware
function requestLogger(req, res, next) {
  const start = Date.now();
  
  res.on('finish', () => {
    Logger.info('HTTP Request', {
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      duration: Date.now() - start
    });
  });
  
  next();
}

module.exports = { Logger, requestLogger };
```

## 5. Resource Management

### 5.1 Basic Memory Management
```javascript
// backend/services/maskingService.js

class MaskingService {
  constructor() {
    this.mappings = new Map();
    this.maxMappings = 1000; // Limit memory usage
  }
  
  /**
   * Add mapping with size limit
   */
  addMapping(masked, original) {
    // Simple FIFO when limit reached
    if (this.mappings.size >= this.maxMappings) {
      const firstKey = this.mappings.keys().next().value;
      this.mappings.delete(firstKey);
    }
    
    this.mappings.set(masked, original);
  }
  
  /**
   * Get original value from masked
   */
  getOriginal(masked) {
    return this.mappings.get(masked);
  }
  
  /**
   * Clear all mappings
   */
  clear() {
    this.mappings.clear();
  }
}

module.exports = MaskingService;
```

### 5.2 Basic Rate Limiting
```javascript
// backend/middleware/rateLimiter.js
const rateLimit = require('express-rate-limit');

// Basic rate limiter
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 60, // 60 requests per minute
  message: 'Too many requests, please try again later',
  standardHeaders: true,
  legacyHeaders: false
});

// Stricter limit for analyze endpoint
const analyzeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10 // 10 requests per minute
});

module.exports = { limiter, analyzeLimiter };
```

## 6. Basic Monitoring

### 6.1 Simple Metrics Endpoint
```javascript
// backend/routes/metrics.js
const express = require('express');
const router = express.Router();

let metrics = {
  requests: 0,
  errors: 0,
  startTime: Date.now()
};

// Middleware to collect metrics
function collectMetrics(req, res, next) {
  metrics.requests++;
  
  res.on('finish', () => {
    if (res.statusCode >= 400) {
      metrics.errors++;
    }
  });
  
  next();
}

// Metrics endpoint
router.get('/metrics', (req, res) => {
  const uptime = Date.now() - metrics.startTime;
  
  res.json({
    requests: metrics.requests,
    errors: metrics.errors,
    errorRate: metrics.requests > 0 ? (metrics.errors / metrics.requests) * 100 : 0,
    uptimeMs: uptime,
    timestamp: new Date().toISOString()
  });
});

module.exports = { router, collectMetrics };
```

## 7. Recovery Procedures

### 7.1 Manual Recovery Steps
```bash
#!/bin/bash
# scripts/recover.sh

echo "Starting recovery procedure..."

# 1. Stop all services
docker-compose down

# 2. Clean up
docker system prune -f

# 3. Rebuild and start
docker-compose build
docker-compose up -d

# 4. Verify health
sleep 10
curl http://localhost:3000/health || echo "Backend not healthy!"
curl http://localhost:8001/status || echo "Kong not healthy!"

echo "Recovery complete"
```

### 7.2 Troubleshooting Guide

| Issue | Check | Solution |
|-------|-------|----------|
| Service down | `docker-compose ps` | Restart service |
| High memory | `docker stats` | Restart container |
| Errors spike | Check logs | Review error logs |
| Slow response | Check CPU/Memory | Scale resources |

## 8. Emergency Procedures

### 8.1 Quick Restart
```bash
# Restart specific service
docker-compose restart backend

# Restart all services
docker-compose restart

# Full restart with rebuild
docker-compose down
docker-compose up -d --build
```

### 8.2 Debug Commands
```bash
# View logs
docker-compose logs -f backend
docker-compose logs -f kong

# Check container health
docker inspect backend | grep -A 10 Health

# Access container shell
docker-compose exec backend sh
```

## 9. MVP Monitoring Checklist

Daily checks:
- [ ] Health endpoints responding
- [ ] Error rate below 5%
- [ ] No container restarts
- [ ] Disk space available
- [ ] Logs rotating properly

## 10. Post-MVP Improvements

For production (after MVP):
- Advanced monitoring (Prometheus/Grafana)
- Automated alerting
- Circuit breakers for external services
- Distributed tracing
- Auto-scaling

## Conclusion

This MVP stability guide provides:
- Essential error handling
- Basic health monitoring
- Simple recovery procedures
- Manual troubleshooting steps

Focus on reliability through simplicity during MVP phase. Advanced patterns can be added based on actual production needs.