/**
 * @fileoverview Masking service for managing AWS resource masking/unmasking
 * @module services/masking/maskingService
 * Integrates with Kong plugin through Redis for consistent mapping
 */

const maskingRedisService = require('../redis/maskingRedisService');
const logger = require('../../utils/logger');
const crypto = require('crypto');

class MaskingService {
  constructor() {
    this.patterns = {
      ec2_instance: /i-[0-9a-f]{17}/g,
      vpc: /vpc-[0-9a-f]+/g,
      subnet: /subnet-[0-9a-f]+/g,
      security_group: /sg-[0-9a-f]+/g,
      s3_bucket: /[a-z0-9.-]{3,63}\.s3(?:-[a-z0-9-]+)?\.amazonaws\.com/g,
      rds_instance: /[a-z][a-z0-9-]{0,62}\.rds\.amazonaws\.com/g,
      private_ip: /(?:10\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|192\.168\.)\d+\.\d+/g,
      iam_role: /arn:aws:iam::\d{12}:role\/[A-Za-z0-9+=,.@\-_]+/g,
      access_key: /AKIA[0-9A-Z]{16}/g
    };
    
    this.counters = new Map();
  }

  /**
   * Generate masked identifier
   * @param {string} type - Resource type
   * @param {number} counter - Counter value
   * @returns {string} Masked identifier
   */
  generateMaskedId(type, counter) {
    const typeMap = {
      ec2_instance: 'EC2',
      vpc: 'VPC',
      subnet: 'SUBNET',
      security_group: 'SG',
      s3_bucket: 'BUCKET',
      rds_instance: 'RDS',
      private_ip: 'PRIVATE_IP',
      iam_role: 'IAM_ROLE',
      access_key: 'ACCESS_KEY'
    };
    
    const prefix = typeMap[type] || 'RESOURCE';
    return `${prefix}_${String(counter).padStart(3, '0')}`;
  }

  /**
   * Mask sensitive AWS resources in text
   * @param {string} text - Text containing AWS resources
   * @param {Object} options - Masking options
   * @returns {Promise<Object>} Masking result
   */
  async maskText(text, options = {}) {
    const startTime = Date.now();
    const mappings = {};
    let maskedText = text;
    let totalCount = 0;
    const patternCounts = {};
    
    try {
      // Process each pattern type
      for (const [patternType, pattern] of Object.entries(this.patterns)) {
        if (options[`mask_${patternType}`] === false) {
          continue;
        }
        
        const matches = text.match(pattern) || [];
        const uniqueMatches = [...new Set(matches)];
        
        if (uniqueMatches.length > 0) {
          patternCounts[patternType] = uniqueMatches.length;
          
          // Check Redis for existing mappings
          const existingMappings = await maskingRedisService.batchGetMappings(uniqueMatches);
          
          // Process each unique match
          for (const match of uniqueMatches) {
            let maskedValue = existingMappings[match];
            
            if (!maskedValue) {
              // Generate new masked value
              const counter = this.counters.get(patternType) || 0;
              this.counters.set(patternType, counter + 1);
              maskedValue = this.generateMaskedId(patternType, counter + 1);
              
              // Store in Redis
              await maskingRedisService.storeMaskingMapping(
                match,
                maskedValue,
                options.ttl
              );
            }
            
            // Store mapping
            mappings[match] = maskedValue;
            
            // Replace in text
            maskedText = maskedText.replace(new RegExp(this.escapeRegex(match), 'g'), maskedValue);
            totalCount++;
          }
        }
      }
      
      const processingTime = Date.now() - startTime;
      
      return {
        success: true,
        original: text,
        masked: maskedText,
        mappings,
        statistics: {
          totalMasked: totalCount,
          patternCounts,
          processingTimeMs: processingTime
        }
      };
    } catch (error) {
      logger.error('Masking failed:', error);
      throw error;
    }
  }

  /**
   * Unmask AWS resources back to original values
   * @param {string} text - Text containing masked identifiers
   * @returns {Promise<Object>} Unmasking result
   */
  async unmaskText(text) {
    const startTime = Date.now();
    let unmaskedText = text;
    let totalCount = 0;
    const restoredMappings = {};
    
    try {
      // Find all potential masked values
      const maskedPattern = /(?:EC2|VPC|SUBNET|SG|BUCKET|RDS|PRIVATE_IP|IAM_ROLE|ACCESS_KEY)_\d{3}/g;
      const matches = text.match(maskedPattern) || [];
      const uniqueMatches = [...new Set(matches)];
      
      if (uniqueMatches.length > 0) {
        // Batch get original values from Redis
        const originalValues = await maskingRedisService.batchGetMappings(uniqueMatches, true);
        
        // Replace each masked value
        for (const maskedValue of uniqueMatches) {
          const originalValue = originalValues[maskedValue];
          
          if (originalValue) {
            unmaskedText = unmaskedText.replace(
              new RegExp(this.escapeRegex(maskedValue), 'g'),
              originalValue
            );
            restoredMappings[maskedValue] = originalValue;
            totalCount++;
          }
        }
      }
      
      const processingTime = Date.now() - startTime;
      
      return {
        success: true,
        masked: text,
        unmasked: unmaskedText,
        restoredMappings,
        statistics: {
          totalUnmasked: totalCount,
          processingTimeMs: processingTime
        }
      };
    } catch (error) {
      logger.error('Unmasking failed:', error);
      throw error;
    }
  }

  /**
   * Get masking statistics
   * @returns {Promise<Object>} Statistics
   */
  async getStatistics() {
    try {
      const stats = await maskingRedisService.getStatistics();
      return {
        ...stats,
        currentCounters: Object.fromEntries(this.counters)
      };
    } catch (error) {
      logger.error('Failed to get masking statistics:', error);
      throw error;
    }
  }

  /**
   * Validate masking consistency
   * @param {string} original - Original text
   * @param {string} masked - Masked text
   * @returns {Promise<Object>} Validation result
   */
  async validateMasking(original, masked) {
    try {
      // Count AWS resources in original
      let originalCount = 0;
      for (const pattern of Object.values(this.patterns)) {
        const matches = original.match(pattern) || [];
        originalCount += matches.length;
      }
      
      // Count masked identifiers
      const maskedPattern = /(?:EC2|VPC|SUBNET|SG|BUCKET|RDS|PRIVATE_IP|IAM_ROLE|ACCESS_KEY)_\d{3}/g;
      const maskedMatches = masked.match(maskedPattern) || [];
      const maskedCount = maskedMatches.length;
      
      // Check for any remaining AWS resources
      let leakedResources = [];
      for (const [type, pattern] of Object.entries(this.patterns)) {
        const remainingMatches = masked.match(pattern) || [];
        if (remainingMatches.length > 0) {
          leakedResources.push({
            type,
            count: remainingMatches.length,
            examples: remainingMatches.slice(0, 3)
          });
        }
      }
      
      return {
        valid: leakedResources.length === 0,
        originalResourceCount: originalCount,
        maskedResourceCount: maskedCount,
        leakedResources,
        consistency: originalCount === maskedCount
      };
    } catch (error) {
      logger.error('Validation failed:', error);
      throw error;
    }
  }

  /**
   * Clean up expired mappings
   * @returns {Promise<number>} Number of cleaned mappings
   */
  async cleanupExpiredMappings() {
    return await maskingRedisService.cleanupExpiredMappings();
  }

  /**
   * Escape special regex characters
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  /**
   * Generate cache key for response
   * @param {Object} params - Request parameters
   * @returns {string} Cache key
   */
  generateCacheKey(params) {
    const normalized = JSON.stringify(params, Object.keys(params).sort());
    return crypto.createHash('sha256').update(normalized).digest('hex');
  }

  /**
   * Cache masked response
   * @param {string} key - Cache key
   * @param {Object} response - Response to cache
   * @param {number} [ttl] - TTL in seconds
   * @returns {Promise<boolean>} Success status
   */
  async cacheResponse(key, response, ttl) {
    return await maskingRedisService.cacheResponse(key, response, ttl);
  }

  /**
   * Get cached response
   * @param {string} key - Cache key
   * @returns {Promise<Object|null>} Cached response or null
   */
  async getCachedResponse(key) {
    return await maskingRedisService.getCachedResponse(key);
  }
}

// Create singleton instance
const maskingService = new MaskingService();

module.exports = maskingService;