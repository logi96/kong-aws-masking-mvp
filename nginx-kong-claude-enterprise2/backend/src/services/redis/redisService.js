/**
 * Redis Service for AWS Masker
 * Manages all Redis operations with optimized data structures
 * @module redisService
 */

const Redis = require('ioredis');
const MaskingDataOptimizer = require('./maskingDataOptimizer');

/**
 * @typedef {import('./maskingDataOptimizer').MaskingEntry} MaskingEntry
 * @typedef {import('./maskingDataOptimizer').OptimizedMaskingData} OptimizedMaskingData
 */

class RedisService {
  constructor(config = {}) {
    this.config = {
      host: config.host || process.env.REDIS_HOST || 'localhost',
      port: config.port || process.env.REDIS_PORT || 6379,
      password: config.password || process.env.REDIS_PASSWORD || 'CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL',
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      enableOfflineQueue: false,
      connectTimeout: 10000,
      disconnectTimeout: 2000,
      commandTimeout: 5000,
      keyPrefix: config.keyPrefix || '',
      ...config
    };
    
    this.optimizer = new MaskingDataOptimizer();
    this.clients = {};
    this.initialized = false;
  }

  /**
   * Initialize Redis connections for all databases
   */
  async initialize() {
    if (this.initialized) return;
    
    try {
      // Create clients for each database
      this.clients = {
        active: new Redis({ ...this.config, db: 0 }),
        history: new Redis({ ...this.config, db: 1 }),
        unmask: new Redis({ ...this.config, db: 2 }),
        metrics: new Redis({ ...this.config, db: 3 })
      };
      
      // Set up error handlers
      Object.entries(this.clients).forEach(([name, client]) => {
        client.on('error', (err) => {
          console.error(`Redis ${name} client error:`, err);
        });
        
        client.on('connect', () => {
          console.log(`Redis ${name} client connected`);
        });
      });
      
      // Test connections
      await Promise.all(
        Object.values(this.clients).map(client => client.ping())
      );
      
      this.initialized = true;
      console.log('Redis service initialized successfully');
    } catch (error) {
      console.error('Failed to initialize Redis service:', error);
      throw error;
    }
  }

  /**
   * Store masking data with optimization
   * @param {string} requestId - Request identifier
   * @param {Array<MaskingEntry>} entries - Masking entries
   * @returns {Promise<void>}
   */
  async storeMaskingData(requestId, entries) {
    await this.ensureInitialized();
    
    // Prepare batch operations
    const batches = this.optimizer.prepareBatchOperations(entries, requestId);
    
    // Process each batch
    for (const batch of batches) {
      const pipelines = {
        active: this.clients.active.pipeline(),
        unmask: this.clients.unmask.pipeline()
      };
      
      batch.forEach(optimizedData => {
        const { key, value, ttl, db } = optimizedData;
        const clientName = Object.keys(this.clients)[db];
        const pipeline = pipelines[clientName];
        
        if (pipeline) {
          if (optimizedData.type === 'zadd') {
            pipeline.zadd(key, value.score, value.member);
          } else {
            pipeline.set(key, value);
            if (ttl > 0) {
              pipeline.expire(key, ttl);
            }
          }
        }
      });
      
      // Execute pipelines
      await Promise.all(
        Object.values(pipelines).map(pipeline => pipeline.exec())
      );
    }
  }

  /**
   * Get original value from masked ID
   * @param {string} maskedId - Masked identifier
   * @returns {Promise<string|null>} Original value or null
   */
  async getOriginalValue(maskedId) {
    await this.ensureInitialized();
    
    const key = `u:${maskedId}`;
    const data = await this.clients.unmask.get(key);
    
    if (!data) return null;
    
    try {
      const parsed = JSON.parse(data);
      
      // Increment access count atomically
      await this.clients.unmask.hincrby(`${key}:meta`, 'access_count', 1);
      
      return parsed.o; // Return original value
    } catch (error) {
      console.error('Error parsing unmask data:', error);
      return null;
    }
  }

  /**
   * Get masking mappings for a request
   * @param {string} requestId - Request identifier
   * @returns {Promise<Object>} Mapping of masked to original values
   */
  async getMaskingMappings(requestId) {
    await this.ensureInitialized();
    
    const pattern = `a:${this.optimizer.compactIdentifier(requestId)}:*`;
    const keys = await this.clients.active.keys(pattern);
    
    if (keys.length === 0) return {};
    
    const values = await this.clients.active.mget(keys);
    const mappings = {};
    
    keys.forEach((key, index) => {
      if (values[index]) {
        try {
          const data = JSON.parse(values[index]);
          const maskedId = key.split(':').pop();
          mappings[maskedId] = data.o;
        } catch (error) {
          console.error(`Error parsing mapping for key ${key}:`, error);
        }
      }
    });
    
    return mappings;
  }

  /**
   * Store metrics data
   * @param {string} metricType - Type of metric
   * @param {Object} metrics - Metrics data
   * @returns {Promise<void>}
   */
  async storeMetrics(metricType, metrics) {
    await this.ensureInitialized();
    
    const timestamp = Date.now();
    const optimized = this.optimizer.optimizeMetricsData(
      metrics,
      metricType,
      timestamp
    );
    
    if (optimized.type === 'zadd') {
      await this.clients.metrics.zadd(
        optimized.key,
        optimized.value.score,
        optimized.value.member
      );
    } else {
      await this.clients.metrics.set(
        optimized.key,
        optimized.value,
        'EX',
        optimized.ttl
      );
    }
  }

  /**
   * Get metrics for a time range
   * @param {string} metricType - Type of metric
   * @param {number} startTime - Start timestamp
   * @param {number} endTime - End timestamp
   * @returns {Promise<Array>} Array of metrics
   */
  async getMetrics(metricType, startTime, endTime) {
    await this.ensureInitialized();
    
    const startBucket = Math.floor(startTime / 3600) * 3600;
    const endBucket = Math.floor(endTime / 3600) * 3600;
    const metrics = [];
    
    // Query each hourly bucket
    for (let bucket = startBucket; bucket <= endBucket; bucket += 3600) {
      const key = `m:${metricType}:${bucket}`;
      const data = await this.clients.metrics.zrangebyscore(
        key,
        startTime,
        endTime,
        'WITHSCORES'
      );
      
      // Parse results
      for (let i = 0; i < data.length; i += 2) {
        try {
          const metric = JSON.parse(data[i]);
          const timestamp = parseInt(data[i + 1]);
          metrics.push({ ...metric, timestamp });
        } catch (error) {
          console.error('Error parsing metric:', error);
        }
      }
    }
    
    return metrics;
  }

  /**
   * Store historical data
   * @param {Array<MaskingEntry>} entries - Masking entries
   * @returns {Promise<void>}
   */
  async storeHistoricalData(entries) {
    await this.ensureInitialized();
    
    const date = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const optimizedData = this.optimizer.optimizeHistoricalData(entries, date);
    
    const pipeline = this.clients.history.pipeline();
    
    optimizedData.forEach(data => {
      pipeline.set(data.key, data.value, 'EX', data.ttl);
    });
    
    await pipeline.exec();
  }

  /**
   * Clean up expired data
   * @returns {Promise<Object>} Cleanup statistics
   */
  async cleanupExpiredData() {
    await this.ensureInitialized();
    
    const stats = {
      scanned: 0,
      expired: 0,
      errors: 0
    };
    
    // Redis handles TTL expiration automatically
    // This method is for manual cleanup if needed
    
    try {
      // Check active mappings
      const activeKeys = await this.clients.active.keys('a:*');
      stats.scanned += activeKeys.length;
      
      // Check each key's TTL
      for (const key of activeKeys) {
        const ttl = await this.clients.active.ttl(key);
        if (ttl === -2) {
          // Key doesn't exist (already expired)
          stats.expired++;
        }
      }
      
      // Force expiration check
      await this.clients.active.eval(
        `return redis.call('DBSIZE')`,
        0
      );
      
    } catch (error) {
      console.error('Error during cleanup:', error);
      stats.errors++;
    }
    
    return stats;
  }

  /**
   * Get memory usage statistics
   * @returns {Promise<Object>} Memory usage stats
   */
  async getMemoryStats() {
    await this.ensureInitialized();
    
    const stats = {};
    
    for (const [name, client] of Object.entries(this.clients)) {
      try {
        const info = await client.info('memory');
        const used = info.match(/used_memory:(\d+)/);
        const peak = info.match(/used_memory_peak:(\d+)/);
        
        stats[name] = {
          used: used ? parseInt(used[1]) : 0,
          peak: peak ? parseInt(peak[1]) : 0,
          usedHuman: used ? this.formatBytes(parseInt(used[1])) : '0B',
          peakHuman: peak ? this.formatBytes(parseInt(peak[1])) : '0B'
        };
      } catch (error) {
        console.error(`Error getting memory stats for ${name}:`, error);
        stats[name] = { error: error.message };
      }
    }
    
    return stats;
  }

  /**
   * Health check for all Redis connections
   * @returns {Promise<Object>} Health status
   */
  async healthCheck() {
    const health = {
      status: 'healthy',
      databases: {},
      timestamp: new Date().toISOString()
    };
    
    for (const [name, client] of Object.entries(this.clients)) {
      try {
        const start = Date.now();
        await client.ping();
        const latency = Date.now() - start;
        
        health.databases[name] = {
          status: 'connected',
          latency: `${latency}ms`,
          db: client.options.db
        };
      } catch (error) {
        health.status = 'unhealthy';
        health.databases[name] = {
          status: 'disconnected',
          error: error.message
        };
      }
    }
    
    return health;
  }

  /**
   * Ensure service is initialized
   * @private
   */
  async ensureInitialized() {
    if (!this.initialized) {
      await this.initialize();
    }
  }

  /**
   * Format bytes to human readable
   * @private
   */
  formatBytes(bytes) {
    const sizes = ['B', 'KB', 'MB', 'GB'];
    if (bytes === 0) return '0B';
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
  }

  /**
   * Gracefully disconnect all clients
   */
  async disconnect() {
    await Promise.all(
      Object.values(this.clients).map(client => client.quit())
    );
    this.initialized = false;
    console.log('Redis service disconnected');
  }
}

module.exports = RedisService;