/**
 * @fileoverview Unmasking utility for restoring AWS resources from Kong masked data
 * @description Retrieves masking mappings from Redis and applies reverse mapping
 * @author Backend Team
 * @version 1.0.0
 */

'use strict';

const Redis = require('ioredis');
const logger = require('../../utils/logger');

/**
 * @typedef {Object} UnmaskingResult
 * @property {boolean} success - Whether unmasking was successful
 * @property {string} unmaskedText - Text with AWS resources restored
 * @property {number} replacements - Number of replacements made
 * @property {Object} mappings - Mappings used for unmasking
 */

/**
 * Unmasking utility class for Backend API
 * @class
 */
class UnmaskingService {
  constructor() {
    /** @type {Redis.RedisClientType|null} */
    this.redisClient = null;
    
    /** @type {boolean} */
    this.isConnected = false;
  }
  
  /**
   * Initialize Redis connection for unmasking
   * @returns {Promise<boolean>} Connection success
   */
  async initialize() {
    try {
      if (this.redisClient && this.isConnected) {
        return true;
      }
      
      this.redisClient = new Redis({
        host: process.env.REDIS_HOST || 'redis',
        port: parseInt(process.env.REDIS_PORT, 10) || 6379,
        password: process.env.REDIS_PASSWORD || '',
        db: parseInt(process.env.REDIS_DB, 10) || 0
      });
      
      this.isConnected = true;
      
      logger.debug('UnmaskingService: Redis connection established');
      return true;
      
    } catch (error) {
      logger.error('UnmaskingService: Redis connection failed', { error: error.message });
      return false;
    }
  }
  
  /**
   * Retrieve masking mappings from Redis based on patterns found in text
   * @param {string} text - Text containing masked values
   * @returns {Promise<Object>} Mapping from masked to original values
   * @private
   */
  async getMaskingMappings(text) {
    if (!this.isConnected) {
      await this.initialize();
    }
    
    const mappings = {};
    
    try {
      // Find all masked patterns in the text
      const maskedPatterns = [
        /EC2_\d{3}/g,
        /VPC_\d{3}/g,
        /SUBNET_\d{3}/g,
        /SG_\d{3}/g,
        /BUCKET_\d{3}/g,
        /RDS_\d{3}/g,
        /PRIVATE_IP_\d{3}/g,
        /PUBLIC_IP_\d{3}/g,
        /AMI_\d{3}/g,
        /EBS_VOL_\d{3}/g,
        /SNAPSHOT_\d{3}/g,
        /IGW_\d{3}/g,
        /NAT_GW_\d{3}/g,
        /VPN_\d{3}/g,
        /TGW_\d{3}/g,
        /EFS_\d{3}/g,
        /ELASTICACHE_\d{3}/g,
        /ACCOUNT_\d{3}/g,
        /ACCESS_KEY_\d{3}/g,
        /SESSION_TOKEN_\d{3}/g,
        /IAM_ROLE_\d{3}/g,
        /IAM_USER_\d{3}/g,
        /KMS_KEY_\d{3}/g,
        /CERT_ARN_\d{3}/g,
        /SECRET_ARN_\d{3}/g,
        /LAMBDA_ARN_\d{3}/g,
        /ECS_TASK_\d{3}/g,
        /EKS_CLUSTER_\d{3}/g,
        /API_GW_\d{3}/g,
        /ELB_ARN_\d{3}/g,
        /SNS_TOPIC_\d{3}/g,
        /SQS_QUEUE_\d{3}/g,
        /DYNAMODB_TABLE_\d{3}/g,
        /LOG_GROUP_\d{3}/g,
        /ROUTE53_ZONE_\d{3}/g,
        /STACK_ID_\d{3}/g,
        /CODECOMMIT_\d{3}/g,
        /ECR_URI_\d{3}/g,
        /PARAM_ARN_\d{3}/g,
        /GLUE_JOB_\d{3}/g,
        /IPV6_\d{3}/g
      ];
      
      const foundMasked = new Set();
      
      // Extract all masked values from text
      maskedPatterns.forEach(pattern => {
        const matches = text.match(pattern);
        if (matches) {
          matches.forEach(match => foundMasked.add(match));
        }
      });
      
      // Get original values from Redis for each masked value
      logger.debug(`Found ${foundMasked.size} masked values: ${Array.from(foundMasked).join(', ')}`);
      
      for (const maskedValue of foundMasked) {
        try {
          const originalValue = await this.redisClient.get(`aws_masker:map:${maskedValue}`);
          logger.debug(`Redis lookup: aws_masker:map:${maskedValue} -> ${originalValue || 'null'}`);
          if (originalValue) {
            mappings[maskedValue] = originalValue;
            logger.debug(`Retrieved mapping: ${maskedValue} -> ${originalValue}`);
          }
        } catch (error) {
          logger.warn(`Failed to retrieve mapping for ${maskedValue}`, { error: error.message });
        }
      }
      
    } catch (error) {
      logger.error('Failed to retrieve masking mappings', { error: error.message });
    }
    
    return mappings;
  }
  
  /**
   * Unmask AWS resources in Claude API response text
   * @param {string} text - Text containing masked AWS resources
   * @returns {Promise<UnmaskingResult>} Unmasking result
   */
  async unmaskText(text) {
    const startTime = Date.now();
    
    try {
      if (!text || typeof text !== 'string') {
        return {
          success: false,
          unmaskedText: text,
          replacements: 0,
          mappings: {}
        };
      }
      
      // Get mappings from Redis
      const mappings = await this.getMaskingMappings(text);
      
      if (Object.keys(mappings).length === 0) {
        logger.debug('No masking mappings found for text');
        return {
          success: true,
          unmaskedText: text,
          replacements: 0,
          mappings: {}
        };
      }
      
      // Apply reverse mappings (masked -> original)
      let unmaskedText = text;
      let replacements = 0;
      
      for (const [maskedValue, originalValue] of Object.entries(mappings)) {
        const regex = new RegExp(maskedValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
        const matches = unmaskedText.match(regex);
        if (matches) {
          unmaskedText = unmaskedText.replace(regex, originalValue);
          replacements += matches.length;
        }
      }
      
      const duration = Date.now() - startTime;
      
      logger.debug('Unmasking completed', {
        duration,
        replacements,
        mappingsCount: Object.keys(mappings).length
      });
      
      return {
        success: true,
        unmaskedText: unmaskedText,
        replacements: replacements,
        mappings: mappings
      };
      
    } catch (error) {
      logger.error('Unmasking failed', { error: error.message });
      
      return {
        success: false,
        unmaskedText: text,
        replacements: 0,
        mappings: {}
      };
    }
  }
  
  /**
   * Close Redis connection
   * @returns {Promise<void>}
   */
  async close() {
    if (this.redisClient && this.isConnected) {
      await this.redisClient.disconnect();
      this.isConnected = false;
      logger.debug('UnmaskingService: Redis connection closed');
    }
  }
}

// Export singleton instance
module.exports = new UnmaskingService();