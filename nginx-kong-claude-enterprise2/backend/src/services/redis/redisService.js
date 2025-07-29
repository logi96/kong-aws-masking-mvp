/**
 * @fileoverview Redis service for managing connections and operations
 * @module services/redis/redisService
 */

const Redis = require('ioredis');
const logger = require('../../utils/logger');

class RedisService {
  constructor() {
    this.config = {
      host: process.env.REDIS_HOST || 'redis',
      port: parseInt(process.env.REDIS_PORT) || 6379,
      password: process.env.REDIS_PASSWORD,
      db: parseInt(process.env.REDIS_DB) || 0,
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      enableOfflineQueue: false,
      connectTimeout: 10000,
      commandTimeout: 5000,
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      }
    };
    
    this.client = null;
    this.isConnected = false;
  }

  /**
   * Connect to Redis
   * @returns {Promise<void>}
   */
  async connect() {
    if (this.isConnected) return;
    
    try {
      this.client = new Redis(this.config);
      
      // Set up event handlers
      this.client.on('connect', () => {
        logger.info('Redis client connected');
        this.isConnected = true;
      });
      
      this.client.on('error', (err) => {
        logger.error('Redis client error:', err);
      });
      
      this.client.on('close', () => {
        logger.warn('Redis connection closed');
        this.isConnected = false;
      });
      
      // Test connection
      await this.client.ping();
      logger.info('Redis connection established successfully');
      
    } catch (error) {
      logger.error('Failed to connect to Redis:', error);
      throw error;
    }
  }

  /**
   * Ensure connection is established
   * @returns {Promise<void>}
   */
  async ensureConnected() {
    if (!this.isConnected) {
      await this.connect();
    }
  }

  /**
   * Get value by key
   * @param {string} key - Redis key
   * @returns {Promise<string|null>} Value or null
   */
  async get(key) {
    await this.ensureConnected();
    return await this.client.get(key);
  }

  /**
   * Set key-value pair
   * @param {string} key - Redis key
   * @param {string} value - Value to store
   * @param {number} [ttl] - Time to live in seconds
   * @returns {Promise<string>} Redis response
   */
  async set(key, value, ttl) {
    await this.ensureConnected();
    
    if (ttl) {
      return await this.client.set(key, value, 'EX', ttl);
    }
    return await this.client.set(key, value);
  }

  /**
   * Delete key
   * @param {string} key - Redis key
   * @returns {Promise<number>} Number of deleted keys
   */
  async del(key) {
    await this.ensureConnected();
    return await this.client.del(key);
  }

  /**
   * Check if key exists
   * @param {string} key - Redis key
   * @returns {Promise<boolean>} True if exists
   */
  async exists(key) {
    await this.ensureConnected();
    const result = await this.client.exists(key);
    return result === 1;
  }

  /**
   * Get all keys matching pattern
   * @param {string} pattern - Key pattern
   * @returns {Promise<string[]>} Array of keys
   */
  async keys(pattern) {
    await this.ensureConnected();
    return await this.client.keys(pattern);
  }

  /**
   * Increment counter
   * @param {string} key - Redis key
   * @returns {Promise<number>} New value
   */
  async incr(key) {
    await this.ensureConnected();
    return await this.client.incr(key);
  }

  /**
   * Add to sorted set
   * @param {string} key - Redis key
   * @param {number} score - Score
   * @param {string} member - Member value
   * @returns {Promise<number>} Number of added elements
   */
  async zadd(key, score, member) {
    await this.ensureConnected();
    return await this.client.zadd(key, score, member);
  }

  /**
   * Get sorted set members by score range
   * @param {string} key - Redis key
   * @param {number} min - Minimum score
   * @param {number} max - Maximum score
   * @param {Object} [options] - Query options
   * @returns {Promise<string[]>} Array of members
   */
  async zrangebyscore(key, min, max, options = {}) {
    await this.ensureConnected();
    
    const args = [key, min, max];
    if (options.withScores) {
      args.push('WITHSCORES');
    }
    if (options.limit) {
      args.push('LIMIT', options.limit.offset || 0, options.limit.count);
    }
    
    return await this.client.zrangebyscore(...args);
  }

  /**
   * Publish message to channel
   * @param {string} channel - Channel name
   * @param {string} message - Message to publish
   * @returns {Promise<number>} Number of subscribers
   */
  async publish(channel, message) {
    await this.ensureConnected();
    return await this.client.publish(channel, message);
  }

  /**
   * Subscribe to channel
   * @param {string} channel - Channel name
   * @param {Function} callback - Message handler
   * @returns {Promise<void>}
   */
  async subscribe(channel, callback) {
    await this.ensureConnected();
    
    const subscriber = new Redis(this.config);
    
    subscriber.on('message', (receivedChannel, message) => {
      if (receivedChannel === channel) {
        callback(message);
      }
    });
    
    await subscriber.subscribe(channel);
    
    return subscriber;
  }

  /**
   * Get Redis info
   * @param {string} [section] - Info section
   * @returns {Promise<string>} Redis info
   */
  async info(section) {
    await this.ensureConnected();
    return await this.client.info(section);
  }

  /**
   * Ping Redis server
   * @returns {Promise<string>} PONG response
   */
  async ping() {
    await this.ensureConnected();
    return await this.client.ping();
  }

  /**
   * Get database size
   * @returns {Promise<number>} Number of keys
   */
  async dbsize() {
    await this.ensureConnected();
    return await this.client.dbsize();
  }

  /**
   * Flush database
   * @returns {Promise<string>} OK response
   */
  async flushdb() {
    await this.ensureConnected();
    logger.warn('Flushing Redis database');
    return await this.client.flushdb();
  }

  /**
   * Execute pipeline
   * @param {Function} callback - Pipeline setup function
   * @returns {Promise<Array>} Pipeline results
   */
  async pipeline(callback) {
    await this.ensureConnected();
    
    const pipeline = this.client.pipeline();
    callback(pipeline);
    return await pipeline.exec();
  }

  /**
   * Get memory usage statistics
   * @returns {Promise<Object>} Memory stats
   */
  async getMemoryStats() {
    await this.ensureConnected();
    
    const info = await this.info('memory');
    const stats = {};
    
    // Parse memory info
    const lines = info.split('\r\n');
    lines.forEach(line => {
      if (line.includes(':')) {
        const [key, value] = line.split(':');
        stats[key] = value;
      }
    });
    
    return {
      used: parseInt(stats.used_memory) || 0,
      peak: parseInt(stats.used_memory_peak) || 0,
      rss: parseInt(stats.used_memory_rss) || 0,
      overhead: parseInt(stats.used_memory_overhead) || 0,
      dataset: parseInt(stats.used_memory_dataset) || 0,
      usedHuman: stats.used_memory_human || '0B',
      peakHuman: stats.used_memory_peak_human || '0B',
      rssHuman: stats.used_memory_rss_human || '0B'
    };
  }

  /**
   * Health check
   * @returns {Promise<Object>} Health status
   */
  async healthCheck() {
    const startTime = Date.now();
    
    try {
      await this.ping();
      const latency = Date.now() - startTime;
      const dbSize = await this.dbsize();
      const memoryStats = await this.getMemoryStats();
      
      return {
        status: 'healthy',
        connected: this.isConnected,
        latency: `${latency}ms`,
        dbSize,
        memory: memoryStats,
        config: {
          host: this.config.host,
          port: this.config.port,
          db: this.config.db
        }
      };
    } catch (error) {
      return {
        status: 'unhealthy',
        connected: false,
        error: error.message,
        config: {
          host: this.config.host,
          port: this.config.port,
          db: this.config.db
        }
      };
    }
  }

  /**
   * Disconnect from Redis
   * @returns {Promise<void>}
   */
  async disconnect() {
    if (this.client) {
      await this.client.quit();
      this.isConnected = false;
      logger.info('Redis connection closed gracefully');
    }
  }
}

// Create singleton instance
const redisService = new RedisService();

module.exports = redisService;