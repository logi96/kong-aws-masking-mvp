/**
 * @fileoverview AWS service - DISABLED per user directive
 * @description AWS CLI execution is STRICTLY PROHIBITED
 * @author Infrastructure Team
 * @version 2.0.0 - SECURITY COMPLIANT
 */

'use strict';

const logger = require('../../../utils/logger');

/**
 * AWS service class - SECURITY DISABLED VERSION
 * @class
 */
class AwsService {
  constructor() {
    // AWS CLI execution is STRICTLY PROHIBITED
    logger.warn('AWS Service initialized - AWS CLI execution is DISABLED');
  }
  
  /**
   * DISABLED: AWS CLI execution is prohibited
   * @param {Object} options - Collection options (ignored)
   * @returns {Promise<Object>} Error response
   */
  async collectResources(options) {
    const error = new Error('AWS CLI execution is STRICTLY PROHIBITED. Backend API is test-only proxy.');
    logger.error('Attempted AWS CLI execution blocked', { 
      reason: 'SECURITY_VIOLATION',
      options 
    });
    throw error;
  }
  
  /**
   * DISABLED: AWS CLI execution is prohibited
   * @param {string} command - Command (ignored)
   * @param {Object} options - Options (ignored) 
   * @returns {Promise<Object>} Error response
   */
  async executeCustomCommand(command, options = {}) {
    const error = new Error('AWS CLI execution is STRICTLY PROHIBITED');
    logger.error('Attempted custom AWS command blocked', { 
      reason: 'SECURITY_VIOLATION',
      command,
      options 
    });
    throw error;
  }
  
  /**
   * Clear cache - safe operation
   * @param {string} resourceType - Resource type
   */
  clearCache(resourceType) {
    logger.info('Cache clear requested (no-op)', { resourceType });
  }
  
  /**
   * Get cache stats - safe operation
   * @returns {Object} Empty stats
   */
  getCacheStats() {
    return {
      totalEntries: 0,
      maxAge: 0,
      entries: {},
      status: 'AWS_CLI_DISABLED'
    };
  }
}

// Export singleton instance
module.exports = new AwsService();