/**
 * @fileoverview Specialized Redis service for AWS masking data management
 * @module services/redis/maskingRedisService
 * Designed by database-specialist agent for high-performance masking operations
 */

const redisService = require('./redisService');
const logger = require('../../utils/logger');

class MaskingRedisService {
  constructor() {
    this.MASKING_PREFIX = 'aws:mask:';
    this.UNMASK_PREFIX = 'aws:unmask:';
    this.STATS_PREFIX = 'aws:stats:';
    this.LOCK_PREFIX = 'aws:lock:';
    this.CACHE_PREFIX = 'aws:cache:';
    
    // Default TTL values
    this.DEFAULT_MAPPING_TTL = 604800; // 7 days
    this.DEFAULT_CACHE_TTL = 3600; // 1 hour
    this.LOCK_TTL = 30; // 30 seconds
  }

  /**
   * Store bidirectional masking mapping
   * @param {string} original - Original AWS resource identifier
   * @param {string} masked - Masked identifier
   * @param {number} [ttl] - Time to live in seconds
   * @returns {Promise<boolean>} Success status
   */
  async storeMaskingMapping(original, masked, ttl = this.DEFAULT_MAPPING_TTL) {
    try {
      await redisService.ensureConnected();
      
      // Use pipeline for atomic operations
      const results = await redisService.pipeline(async (pipeline) => {
        // Store bidirectional mappings
        pipeline.set(this.MASKING_PREFIX + original, masked, 'EX', ttl);
        pipeline.set(this.UNMASK_PREFIX + masked, original, 'EX', ttl);
        
        // Update statistics
        pipeline.hincrby(this.STATS_PREFIX + 'counts', 'total_mappings', 1);
        pipeline.hincrby(
          this.STATS_PREFIX + 'counts:' + new Date().toISOString().slice(0, 10),
          'daily_mappings',
          1
        );
      });
      
      logger.debug(`Stored mapping: ${original} -> ${masked} with TTL ${ttl}s`);
      return true;
    } catch (error) {
      logger.error('Failed to store masking mapping:', error);
      throw error;
    }
  }

  /**
   * Batch store multiple mappings
   * @param {Object} mappings - Object with original as key, masked as value
   * @param {number} [ttl] - Time to live in seconds
   * @returns {Promise<number>} Number of mappings stored
   */
  async batchStoreMappings(mappings, ttl = this.DEFAULT_MAPPING_TTL) {
    try {
      await redisService.ensureConnected();
      
      const mappingEntries = Object.entries(mappings);
      if (mappingEntries.length === 0) return 0;
      
      const results = await redisService.pipeline(async (pipeline) => {
        for (const [original, masked] of mappingEntries) {
          pipeline.set(this.MASKING_PREFIX + original, masked, 'EX', ttl);
          pipeline.set(this.UNMASK_PREFIX + masked, original, 'EX', ttl);
        }
        
        // Update statistics
        pipeline.hincrby(this.STATS_PREFIX + 'counts', 'total_mappings', mappingEntries.length);
        pipeline.hincrby(
          this.STATS_PREFIX + 'counts:' + new Date().toISOString().slice(0, 10),
          'daily_mappings',
          mappingEntries.length
        );
      });
      
      logger.debug(`Batch stored ${mappingEntries.length} mappings with TTL ${ttl}s`);
      return mappingEntries.length;
    } catch (error) {
      logger.error('Failed to batch store mappings:', error);
      throw error;
    }
  }

  /**
   * Get masked value for original identifier
   * @param {string} original - Original AWS resource identifier
   * @returns {Promise<string|null>} Masked value or null
   */
  async getMaskedValue(original) {
    try {
      const masked = await redisService.get(this.MASKING_PREFIX + original);
      return masked;
    } catch (error) {
      logger.error('Failed to get masked value:', error);
      throw error;
    }
  }

  /**
   * Get original value from masked identifier
   * @param {string} masked - Masked identifier
   * @returns {Promise<string|null>} Original value or null
   */
  async getOriginalValue(masked) {
    try {
      const original = await redisService.get(this.UNMASK_PREFIX + masked);
      return original;
    } catch (error) {
      logger.error('Failed to get original value:', error);
      throw error;
    }
  }

  /**
   * Batch get multiple mappings
   * @param {string[]} keys - Array of keys to look up
   * @param {boolean} [isUnmask=false] - Whether to look up unmask mappings
   * @returns {Promise<Object>} Object with key-value mappings
   */
  async batchGetMappings(keys, isUnmask = false) {
    try {
      if (!keys || keys.length === 0) return {};
      
      await redisService.ensureConnected();
      
      const prefix = isUnmask ? this.UNMASK_PREFIX : this.MASKING_PREFIX;
      const prefixedKeys = keys.map(key => prefix + key);
      
      // Use MGET for batch retrieval
      const values = await redisService.client.mget(...prefixedKeys);
      
      // Build result object
      const result = {};
      keys.forEach((key, index) => {
        if (values[index] !== null) {
          result[key] = values[index];
        }
      });
      
      return result;
    } catch (error) {
      logger.error('Failed to batch get mappings:', error);
      throw error;
    }
  }

  /**
   * Check if mapping exists
   * @param {string} key - Key to check
   * @param {boolean} [isUnmask=false] - Whether to check unmask mapping
   * @returns {Promise<boolean>} True if exists
   */
  async mappingExists(key, isUnmask = false) {
    try {
      const prefix = isUnmask ? this.UNMASK_PREFIX : this.MASKING_PREFIX;
      return await redisService.exists(prefix + key);
    } catch (error) {
      logger.error('Failed to check mapping existence:', error);
      throw error;
    }
  }

  /**
   * Delete mapping (both directions)
   * @param {string} original - Original identifier
   * @param {string} masked - Masked identifier
   * @returns {Promise<number>} Number of keys deleted
   */
  async deleteMapping(original, masked) {
    try {
      await redisService.ensureConnected();
      
      const results = await redisService.pipeline(async (pipeline) => {
        pipeline.del(this.MASKING_PREFIX + original);
        pipeline.del(this.UNMASK_PREFIX + masked);
        pipeline.hincrby(this.STATS_PREFIX + 'counts', 'total_mappings', -1);
      });
      
      return 2; // Both keys deleted
    } catch (error) {
      logger.error('Failed to delete mapping:', error);
      throw error;
    }
  }

  /**
   * Get TTL for a mapping
   * @param {string} key - Key to check
   * @param {boolean} [isUnmask=false] - Whether to check unmask mapping
   * @returns {Promise<number>} TTL in seconds, -1 if no TTL, -2 if not exists
   */
  async getMappingTTL(key, isUnmask = false) {
    try {
      await redisService.ensureConnected();
      const prefix = isUnmask ? this.UNMASK_PREFIX : this.MASKING_PREFIX;
      return await redisService.client.ttl(prefix + key);
    } catch (error) {
      logger.error('Failed to get mapping TTL:', error);
      throw error;
    }
  }

  /**
   * Extend TTL for existing mapping
   * @param {string} original - Original identifier
   * @param {string} masked - Masked identifier
   * @param {number} [ttl] - New TTL in seconds
   * @returns {Promise<boolean>} Success status
   */
  async extendMappingTTL(original, masked, ttl = this.DEFAULT_MAPPING_TTL) {
    try {
      await redisService.ensureConnected();
      
      const results = await redisService.pipeline(async (pipeline) => {
        pipeline.expire(this.MASKING_PREFIX + original, ttl);
        pipeline.expire(this.UNMASK_PREFIX + masked, ttl);
      });
      
      return results.every(result => result === 1);
    } catch (error) {
      logger.error('Failed to extend mapping TTL:', error);
      throw error;
    }
  }

  /**
   * Cache Claude API response
   * @param {string} key - Cache key
   * @param {any} value - Value to cache
   * @param {number} [ttl] - TTL in seconds
   * @returns {Promise<boolean>} Success status
   */
  async cacheResponse(key, value, ttl = this.DEFAULT_CACHE_TTL) {
    try {
      const cacheKey = this.CACHE_PREFIX + key;
      const serialized = JSON.stringify(value);
      await redisService.set(cacheKey, serialized, ttl);
      
      // Update cache statistics
      await redisService.incr(this.STATS_PREFIX + 'cache:hits');
      
      return true;
    } catch (error) {
      logger.error('Failed to cache response:', error);
      throw error;
    }
  }

  /**
   * Get cached response
   * @param {string} key - Cache key
   * @returns {Promise<any|null>} Cached value or null
   */
  async getCachedResponse(key) {
    try {
      const cacheKey = this.CACHE_PREFIX + key;
      const cached = await redisService.get(cacheKey);
      
      if (cached) {
        await redisService.incr(this.STATS_PREFIX + 'cache:hits');
        return JSON.parse(cached);
      }
      
      await redisService.incr(this.STATS_PREFIX + 'cache:misses');
      return null;
    } catch (error) {
      logger.error('Failed to get cached response:', error);
      throw error;
    }
  }

  /**
   * Acquire distributed lock
   * @param {string} resource - Resource to lock
   * @param {number} [timeout] - Lock timeout in seconds
   * @returns {Promise<string|null>} Lock token or null
   */
  async acquireLock(resource, timeout = this.LOCK_TTL) {
    try {
      await redisService.ensureConnected();
      
      const lockKey = this.LOCK_PREFIX + resource;
      const lockValue = `${process.pid}:${Date.now()}:${Math.random()}`;
      
      const result = await redisService.client.set(
        lockKey,
        lockValue,
        'NX',
        'EX',
        timeout
      );
      
      return result === 'OK' ? lockValue : null;
    } catch (error) {
      logger.error('Failed to acquire lock:', error);
      throw error;
    }
  }

  /**
   * Release distributed lock
   * @param {string} resource - Resource to unlock
   * @param {string} lockValue - Lock token
   * @returns {Promise<boolean>} Success status
   */
  async releaseLock(resource, lockValue) {
    try {
      await redisService.ensureConnected();
      
      const lockKey = this.LOCK_PREFIX + resource;
      
      // Use Lua script for atomic check and delete
      const script = `
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      `;
      
      const result = await redisService.client.eval(script, 1, lockKey, lockValue);
      return result === 1;
    } catch (error) {
      logger.error('Failed to release lock:', error);
      throw error;
    }
  }

  /**
   * Get masking statistics
   * @returns {Promise<Object>} Statistics object
   */
  async getStatistics() {
    try {
      await redisService.ensureConnected();
      
      const results = await redisService.pipeline(async (pipeline) => {
        pipeline.hgetall(this.STATS_PREFIX + 'counts');
        pipeline.hgetall(this.STATS_PREFIX + 'counts:' + new Date().toISOString().slice(0, 10));
        pipeline.get(this.STATS_PREFIX + 'cache:hits');
        pipeline.get(this.STATS_PREFIX + 'cache:misses');
        pipeline.dbsize();
      });
      
      const [totalCounts, dailyCounts, cacheHits, cacheMisses, dbSize] = await results;
      
      return {
        total: {
          mappings: parseInt(totalCounts?.total_mappings) || 0,
          ...totalCounts
        },
        daily: {
          mappings: parseInt(dailyCounts?.daily_mappings) || 0,
          ...dailyCounts
        },
        cache: {
          hits: parseInt(cacheHits) || 0,
          misses: parseInt(cacheMisses) || 0,
          hitRate: cacheHits && cacheMisses ? 
            (parseInt(cacheHits) / (parseInt(cacheHits) + parseInt(cacheMisses)) * 100).toFixed(2) + '%' : 
            '0%'
        },
        database: {
          totalKeys: dbSize || 0
        }
      };
    } catch (error) {
      logger.error('Failed to get statistics:', error);
      throw error;
    }
  }

  /**
   * Clean up expired mappings
   * @returns {Promise<number>} Number of cleaned mappings
   */
  async cleanupExpiredMappings() {
    try {
      await redisService.ensureConnected();
      
      let cleaned = 0;
      let cursor = '0';
      
      do {
        // Scan for masking keys
        const [nextCursor, keys] = await redisService.client.scan(
          cursor,
          'MATCH',
          this.MASKING_PREFIX + '*',
          'COUNT',
          100
        );
        
        cursor = nextCursor;
        
        if (keys.length > 0) {
          // Check TTL for each key
          const pipeline = redisService.client.pipeline();
          keys.forEach(key => pipeline.ttl(key));
          
          const ttls = await pipeline.exec();
          
          // Find keys with no TTL
          const keysToDelete = [];
          ttls.forEach(([err, ttl], index) => {
            if (!err && (ttl === -1 || ttl === -2)) {
              keysToDelete.push(keys[index]);
            }
          });
          
          // Delete keys with no TTL
          if (keysToDelete.length > 0) {
            const deleted = await redisService.client.del(...keysToDelete);
            cleaned += deleted;
          }
        }
      } while (cursor !== '0');
      
      logger.info(`Cleaned up ${cleaned} expired mappings`);
      return cleaned;
    } catch (error) {
      logger.error('Failed to cleanup expired mappings:', error);
      throw error;
    }
  }

  /**
   * Health check for masking Redis service
   * @returns {Promise<Object>} Health status
   */
  async healthCheck() {
    try {
      const baseHealth = await redisService.healthCheck();
      const stats = await this.getStatistics();
      
      return {
        ...baseHealth,
        masking: {
          totalMappings: stats.total.mappings,
          dailyMappings: stats.daily.mappings,
          cacheHitRate: stats.cache.hitRate
        }
      };
    } catch (error) {
      logger.error('Masking Redis health check failed:', error);
      return {
        status: 'unhealthy',
        error: error.message
      };
    }
  }
}

// Create singleton instance
const maskingRedisService = new MaskingRedisService();

module.exports = maskingRedisService;