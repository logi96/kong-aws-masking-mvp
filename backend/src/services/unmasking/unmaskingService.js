/**
 * @fileoverview Unmasking service for Backend API - WORKAROUND
 * @description Kong body_filter 문제로 인한 임시 해결책
 * @author Infrastructure Team
 * @version 1.0.0
 */

'use strict';

const logger = require('../../../utils/logger');

/**
 * Unmasking service class - Backend에서 직접 언마스킹 수행
 * @class
 */
class UnmaskingService {
  constructor() {
    /** @type {Map<string, string>} In-memory mapping storage */
    this.maskingMap = new Map();
    
    /** @type {number} */
    this.maxMapSize = 10000;
  }

  /**
   * Extract masking mappings from request context
   * @param {Object} req - Express request object
   * @returns {Map<string, string>} Masking mappings
   */
  extractMappingsFromRequest(req) {
    const mappings = new Map();
    
    // Kong adds masking info in headers during request phase
    const maskingHeader = req.headers['x-aws-masking-map'];
    if (maskingHeader) {
      try {
        const mappingData = JSON.parse(Buffer.from(maskingHeader, 'base64').toString());
        Object.entries(mappingData).forEach(([masked, original]) => {
          mappings.set(masked, original);
          // Also store in local map for future use
          this.storeMasking(masked, original);
        });
      } catch (error) {
        logger.error('Failed to parse masking header', { error: error.message });
      }
    }
    
    return mappings;
  }

  /**
   * Store masking mapping
   * @param {string} maskedId - Masked identifier
   * @param {string} originalValue - Original value
   */
  storeMasking(maskedId, originalValue) {
    // Limit map size to prevent memory issues
    if (this.maskingMap.size >= this.maxMapSize) {
      const firstKey = this.maskingMap.keys().next().value;
      this.maskingMap.delete(firstKey);
    }
    
    this.maskingMap.set(maskedId, originalValue);
    
    logger.debug('Stored masking mapping', {
      maskedId,
      originalValue,
      mapSize: this.maskingMap.size
    });
  }

  /**
   * Unmask Claude API response text
   * @param {string} text - Text to unmask
   * @param {Map<string, string>} [mappings] - Optional specific mappings to use
   * @returns {string} Unmasked text
   */
  unmaskText(text, mappings = null) {
    if (!text || typeof text !== 'string') {
      return text;
    }

    const mappingsToUse = mappings || this.maskingMap;
    let unmaskedText = text;
    let unmaskCount = 0;

    // Apply all mappings
    mappingsToUse.forEach((originalValue, maskedId) => {
      // Escape special regex characters in masked ID
      const escapedMaskedId = maskedId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const regex = new RegExp(escapedMaskedId, 'g');
      
      const newText = unmaskedText.replace(regex, originalValue);
      if (newText !== unmaskedText) {
        unmaskCount++;
        unmaskedText = newText;
      }
    });

    if (unmaskCount > 0) {
      logger.debug('Unmasked text in Backend API', {
        unmaskCount,
        textLength: text.length,
        mappingsUsed: mappingsToUse.size
      });
    }

    return unmaskedText;
  }

  /**
   * Unmask Claude API response
   * @param {Object} response - Claude API response object
   * @param {Map<string, string>} [mappings] - Optional specific mappings to use
   * @returns {Object} Unmasked response
   */
  unmaskResponse(response, mappings = null) {
    if (!response || !response.content || !Array.isArray(response.content)) {
      return response;
    }

    const unmaskedResponse = JSON.parse(JSON.stringify(response)); // Deep clone
    
    // Process each content item
    unmaskedResponse.content.forEach(item => {
      if (item.type === 'text' && item.text) {
        item.text = this.unmaskText(item.text, mappings);
      }
    });

    return unmaskedResponse;
  }

  /**
   * Clear all mappings
   */
  clearMappings() {
    const size = this.maskingMap.size;
    this.maskingMap.clear();
    
    logger.info('Cleared unmasking mappings', { clearedCount: size });
  }

  /**
   * Get current mapping statistics
   * @returns {Object} Mapping statistics
   */
  getStats() {
    return {
      mappingCount: this.maskingMap.size,
      maxMapSize: this.maxMapSize
    };
  }
}

// Export singleton instance
module.exports = new UnmaskingService();