/**
 * Redis Service Module Exports
 * @module redis
 */

const RedisService = require('./redisService');
const MaskingDataOptimizer = require('./maskingDataOptimizer');

// Create singleton instance
let redisServiceInstance = null;

/**
 * Get or create Redis service instance
 * @param {Object} config - Optional configuration
 * @returns {RedisService} Redis service instance
 */
function getRedisService(config) {
  if (!redisServiceInstance) {
    redisServiceInstance = new RedisService(config);
  }
  return redisServiceInstance;
}

module.exports = {
  RedisService,
  MaskingDataOptimizer,
  getRedisService
};