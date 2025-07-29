/**
 * @fileoverview API Key management service for Kong integration
 * @module services/auth/apiKeyService
 */

const axios = require('axios');
const crypto = require('crypto');
const logger = require('../../utils/logger');

/**
 * @typedef {Object} ApiKey
 * @property {string} id - API key ID
 * @property {string} key - API key value
 * @property {string} consumerId - Associated consumer ID
 * @property {string} username - Consumer username
 * @property {Object} metadata - Key metadata
 * @property {string} metadata.name - Key name/description
 * @property {string} metadata.tier - Rate limit tier
 * @property {string[]} metadata.scopes - Allowed scopes
 * @property {Date} createdAt - Creation timestamp
 * @property {Date} lastUsed - Last usage timestamp
 * @property {string} status - Key status (active/revoked)
 */

/**
 * Kong Admin API configuration
 */
const KONG_ADMIN_URL = process.env.KONG_ADMIN_URL || 'http://kong:8001';
const KONG_ADMIN_HEADERS = {
  'Content-Type': 'application/json'
};

/**
 * API Key Service for managing Kong consumers and credentials
 */
class ApiKeyService {
  constructor() {
    this.kongClient = axios.create({
      baseURL: KONG_ADMIN_URL,
      headers: KONG_ADMIN_HEADERS,
      timeout: 5000
    });
  }

  /**
   * Generate a secure API key
   * @returns {string} Generated API key
   * @private
   */
  generateApiKey() {
    return crypto.randomUUID();
  }

  /**
   * Create a new consumer in Kong
   * @param {Object} userData - User data
   * @param {string} userData.username - Username
   * @param {string} userData.customId - Custom ID
   * @param {string[]} userData.tags - Tags
   * @returns {Promise<Object>} Created consumer
   * @private
   */
  async createConsumer(userData) {
    try {
      const response = await this.kongClient.post('/consumers', {
        username: userData.username,
        custom_id: userData.customId,
        tags: userData.tags || ['api-user']
      });
      
      return response.data;
    } catch (error) {
      logger.error('Failed to create Kong consumer', {
        error: error.message,
        userData
      });
      throw new Error('Failed to create consumer');
    }
  }

  /**
   * Create a new API key for a user
   * @param {string} userId - User ID
   * @param {Object} metadata - Key metadata
   * @param {string} metadata.name - Key name/description
   * @param {string} metadata.tier - Rate limit tier (standard/premium/enterprise)
   * @param {string[]} metadata.scopes - Allowed scopes
   * @returns {Promise<ApiKey>} Created API key
   */
  async createApiKey(userId, metadata) {
    try {
      // Check if consumer exists
      let consumer;
      try {
        const response = await this.kongClient.get(`/consumers/${userId}`);
        consumer = response.data;
      } catch (error) {
        if (error.response?.status === 404) {
          // Create consumer if doesn't exist
          consumer = await this.createConsumer({
            username: userId,
            customId: userId,
            tags: [metadata.tier || 'standard']
          });
        } else {
          throw error;
        }
      }

      // Generate API key
      const apiKey = this.generateApiKey();
      
      // Create key-auth credential in Kong
      const credentialResponse = await this.kongClient.post(
        `/consumers/${consumer.id}/key-auth`,
        {
          key: apiKey,
          tags: [metadata.tier || 'standard', ...metadata.scopes || []]
        }
      );

      // Store metadata in Redis (through our Redis service)
      const keyMetadata = {
        id: credentialResponse.data.id,
        key: apiKey,
        consumerId: consumer.id,
        username: consumer.username,
        metadata: {
          name: metadata.name || 'API Key',
          tier: metadata.tier || 'standard',
          scopes: metadata.scopes || ['read']
        },
        createdAt: new Date(),
        lastUsed: null,
        status: 'active'
      };

      logger.info('API key created', {
        consumerId: consumer.id,
        keyId: credentialResponse.data.id,
        tier: metadata.tier
      });

      return keyMetadata;
    } catch (error) {
      logger.error('Failed to create API key', {
        error: error.message,
        userId,
        metadata
      });
      throw new Error('Failed to create API key');
    }
  }

  /**
   * List all API keys for a user
   * @param {string} userId - User ID
   * @returns {Promise<ApiKey[]>} List of API keys
   */
  async listApiKeys(userId) {
    try {
      // Get consumer
      const consumerResponse = await this.kongClient.get(`/consumers/${userId}`);
      const consumer = consumerResponse.data;

      // Get key-auth credentials
      const credentialsResponse = await this.kongClient.get(
        `/consumers/${consumer.id}/key-auth`
      );

      // Transform to our format (hiding actual keys)
      const keys = credentialsResponse.data.data.map(cred => ({
        id: cred.id,
        key: `${cred.key.substring(0, 8)}...${cred.key.substring(cred.key.length - 4)}`,
        consumerId: consumer.id,
        username: consumer.username,
        metadata: {
          tier: cred.tags?.includes('premium') ? 'premium' : 'standard',
          scopes: cred.tags?.filter(tag => !['standard', 'premium', 'enterprise'].includes(tag)) || []
        },
        createdAt: new Date(cred.created_at * 1000),
        status: 'active'
      }));

      return keys;
    } catch (error) {
      if (error.response?.status === 404) {
        return [];
      }
      
      logger.error('Failed to list API keys', {
        error: error.message,
        userId
      });
      throw new Error('Failed to list API keys');
    }
  }

  /**
   * Get API key details
   * @param {string} keyId - API key ID
   * @returns {Promise<ApiKey>} API key details
   */
  async getApiKey(keyId) {
    try {
      // Find the credential across all consumers
      const consumersResponse = await this.kongClient.get('/consumers');
      
      for (const consumer of consumersResponse.data.data) {
        try {
          const credResponse = await this.kongClient.get(
            `/consumers/${consumer.id}/key-auth/${keyId}`
          );
          
          const cred = credResponse.data;
          return {
            id: cred.id,
            key: `${cred.key.substring(0, 8)}...`,
            consumerId: consumer.id,
            username: consumer.username,
            metadata: {
              tier: cred.tags?.includes('premium') ? 'premium' : 'standard',
              scopes: cred.tags?.filter(tag => !['standard', 'premium', 'enterprise'].includes(tag)) || []
            },
            createdAt: new Date(cred.created_at * 1000),
            status: 'active'
          };
        } catch (error) {
          // Continue to next consumer if not found
          if (error.response?.status !== 404) {
            throw error;
          }
        }
      }
      
      throw new Error('API key not found');
    } catch (error) {
      logger.error('Failed to get API key', {
        error: error.message,
        keyId
      });
      throw new Error('Failed to get API key');
    }
  }

  /**
   * Update API key rate limit
   * @param {string} keyId - API key ID
   * @param {string} newTier - New rate limit tier
   * @returns {Promise<ApiKey>} Updated API key
   */
  async updateRateLimit(keyId, newTier) {
    try {
      // Find the key and its consumer
      const key = await this.getApiKey(keyId);
      
      // Update consumer tags to reflect new tier
      await this.kongClient.patch(`/consumers/${key.consumerId}`, {
        tags: [newTier]
      });

      // Update credential tags
      await this.kongClient.patch(
        `/consumers/${key.consumerId}/key-auth/${keyId}`,
        {
          tags: [newTier, ...key.metadata.scopes]
        }
      );

      logger.info('API key rate limit updated', {
        keyId,
        consumerId: key.consumerId,
        oldTier: key.metadata.tier,
        newTier
      });

      key.metadata.tier = newTier;
      return key;
    } catch (error) {
      logger.error('Failed to update rate limit', {
        error: error.message,
        keyId,
        newTier
      });
      throw new Error('Failed to update rate limit');
    }
  }

  /**
   * Revoke an API key
   * @param {string} keyId - API key ID
   * @returns {Promise<void>}
   */
  async revokeApiKey(keyId) {
    try {
      // Find the key and its consumer
      const key = await this.getApiKey(keyId);
      
      // Delete the credential from Kong
      await this.kongClient.delete(
        `/consumers/${key.consumerId}/key-auth/${keyId}`
      );

      logger.info('API key revoked', {
        keyId,
        consumerId: key.consumerId
      });
    } catch (error) {
      logger.error('Failed to revoke API key', {
        error: error.message,
        keyId
      });
      throw new Error('Failed to revoke API key');
    }
  }

  /**
   * Rotate an API key (create new, revoke old)
   * @param {string} keyId - API key ID to rotate
   * @returns {Promise<ApiKey>} New API key
   */
  async rotateApiKey(keyId) {
    try {
      // Get existing key details
      const oldKey = await this.getApiKey(keyId);
      
      // Create new key with same metadata
      const newKey = await this.createApiKey(oldKey.username, {
        name: `${oldKey.metadata.name} (rotated)`,
        tier: oldKey.metadata.tier,
        scopes: oldKey.metadata.scopes
      });

      // Revoke old key
      await this.revokeApiKey(keyId);

      logger.info('API key rotated', {
        oldKeyId: keyId,
        newKeyId: newKey.id,
        consumerId: oldKey.consumerId
      });

      return newKey;
    } catch (error) {
      logger.error('Failed to rotate API key', {
        error: error.message,
        keyId
      });
      throw new Error('Failed to rotate API key');
    }
  }

  /**
   * Validate API key format
   * @param {string} apiKey - API key to validate
   * @returns {boolean} Is valid
   */
  isValidApiKey(apiKey) {
    // UUID v4 format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(apiKey);
  }

  /**
   * Get usage statistics for an API key
   * @param {string} keyId - API key ID
   * @returns {Promise<Object>} Usage statistics
   */
  async getKeyUsageStats(keyId) {
    try {
      // This would integrate with monitoring/analytics service
      // For now, return mock data
      return {
        keyId,
        totalRequests: 0,
        requestsToday: 0,
        requestsThisHour: 0,
        lastRequestAt: null,
        averageResponseTime: 0,
        errorRate: 0
      };
    } catch (error) {
      logger.error('Failed to get usage stats', {
        error: error.message,
        keyId
      });
      throw new Error('Failed to get usage statistics');
    }
  }
}

module.exports = new ApiKeyService();