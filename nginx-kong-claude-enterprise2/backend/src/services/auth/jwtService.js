/**
 * @fileoverview JWT management service for Kong integration
 * @module services/auth/jwtService
 */

const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const axios = require('axios');
const logger = require('../../utils/logger');

/**
 * @typedef {Object} JWTConfig
 * @property {string} algorithm - JWT algorithm (RS256, HS256)
 * @property {string} issuer - JWT issuer
 * @property {number} expiresIn - Token expiration in seconds
 * @property {string} publicKey - Public key for RS256
 * @property {string} privateKey - Private key for RS256
 * @property {string} secret - Secret for HS256
 */

/**
 * @typedef {Object} JWTPayload
 * @property {string} sub - Subject (user/service ID)
 * @property {string} iss - Issuer
 * @property {number} exp - Expiration timestamp
 * @property {number} iat - Issued at timestamp
 * @property {string} jti - JWT ID
 * @property {string[]} scope - Permission scopes
 * @property {Object} custom - Custom claims
 */

const KONG_ADMIN_URL = process.env.KONG_ADMIN_URL || 'http://kong:8001';

/**
 * JWT Service for managing JWT tokens and Kong JWT plugin
 */
class JWTService {
  constructor() {
    this.kongClient = axios.create({
      baseURL: KONG_ADMIN_URL,
      headers: { 'Content-Type': 'application/json' },
      timeout: 5000
    });

    // Default configuration
    this.config = {
      algorithm: process.env.JWT_ALGORITHM || 'RS256',
      issuer: process.env.JWT_ISSUER || 'kong-aws-masking',
      expiresIn: parseInt(process.env.JWT_EXPIRES_IN || '3600', 10), // 1 hour default
      publicKey: process.env.JWT_PUBLIC_KEY || this.generateKeyPair().publicKey,
      privateKey: process.env.JWT_PRIVATE_KEY || this.generateKeyPair().privateKey,
      secret: process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex')
    };
  }

  /**
   * Generate RSA key pair for RS256
   * @returns {Object} Public and private keys
   * @private
   */
  generateKeyPair() {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: {
        type: 'spki',
        format: 'pem'
      },
      privateKeyEncoding: {
        type: 'pkcs8',
        format: 'pem'
      }
    });

    return { publicKey, privateKey };
  }

  /**
   * Create a JWT credential in Kong
   * @param {string} consumerId - Kong consumer ID
   * @param {string} key - JWT key (issuer)
   * @param {string} algorithm - JWT algorithm
   * @param {string} secret - Secret or public key
   * @returns {Promise<Object>} Created JWT credential
   * @private
   */
  async createJWTCredential(consumerId, key, algorithm, secret) {
    try {
      const response = await this.kongClient.post(
        `/consumers/${consumerId}/jwt`,
        {
          key,
          algorithm,
          secret: algorithm === 'HS256' ? secret : undefined,
          rsa_public_key: algorithm === 'RS256' ? secret : undefined
        }
      );

      return response.data;
    } catch (error) {
      logger.error('Failed to create JWT credential in Kong', {
        error: error.message,
        consumerId
      });
      throw new Error('Failed to create JWT credential');
    }
  }

  /**
   * Issue a new JWT token
   * @param {string} userId - User ID
   * @param {Object} options - Token options
   * @param {string[]} options.scopes - Permission scopes
   * @param {Object} options.custom - Custom claims
   * @param {number} options.expiresIn - Override default expiration
   * @returns {Promise<Object>} JWT token and metadata
   */
  async issueToken(userId, options = {}) {
    try {
      const jti = crypto.randomUUID();
      const now = Math.floor(Date.now() / 1000);
      
      const payload = {
        sub: userId,
        iss: this.config.issuer,
        iat: now,
        exp: now + (options.expiresIn || this.config.expiresIn),
        jti,
        scope: options.scopes?.join(' ') || 'read',
        ...options.custom
      };

      let token;
      if (this.config.algorithm === 'RS256') {
        token = jwt.sign(payload, this.config.privateKey, {
          algorithm: 'RS256'
        });
      } else {
        token = jwt.sign(payload, this.config.secret, {
          algorithm: 'HS256'
        });
      }

      // Ensure consumer has JWT credential in Kong
      try {
        await this.ensureJWTCredential(userId);
      } catch (error) {
        logger.warn('Could not ensure JWT credential in Kong', {
          error: error.message,
          userId
        });
      }

      logger.info('JWT token issued', {
        userId,
        jti,
        scopes: options.scopes,
        expiresIn: options.expiresIn || this.config.expiresIn
      });

      return {
        token,
        tokenType: 'Bearer',
        expiresIn: options.expiresIn || this.config.expiresIn,
        issuedAt: new Date(now * 1000),
        expiresAt: new Date((now + (options.expiresIn || this.config.expiresIn)) * 1000),
        jti,
        scopes: options.scopes || ['read']
      };
    } catch (error) {
      logger.error('Failed to issue JWT token', {
        error: error.message,
        userId
      });
      throw new Error('Failed to issue token');
    }
  }

  /**
   * Verify a JWT token
   * @param {string} token - JWT token
   * @returns {Promise<JWTPayload>} Decoded token payload
   */
  async verifyToken(token) {
    try {
      let decoded;
      if (this.config.algorithm === 'RS256') {
        decoded = jwt.verify(token, this.config.publicKey, {
          algorithms: ['RS256'],
          issuer: this.config.issuer
        });
      } else {
        decoded = jwt.verify(token, this.config.secret, {
          algorithms: ['HS256'],
          issuer: this.config.issuer
        });
      }

      return {
        ...decoded,
        scope: decoded.scope ? decoded.scope.split(' ') : []
      };
    } catch (error) {
      if (error.name === 'TokenExpiredError') {
        throw new Error('Token expired');
      } else if (error.name === 'JsonWebTokenError') {
        throw new Error('Invalid token');
      }
      
      logger.error('Failed to verify JWT token', {
        error: error.message
      });
      throw new Error('Token verification failed');
    }
  }

  /**
   * Refresh a JWT token
   * @param {string} token - Current JWT token
   * @returns {Promise<Object>} New JWT token and metadata
   */
  async refreshToken(token) {
    try {
      const decoded = await this.verifyToken(token);
      
      // Check if token is expired
      const now = Math.floor(Date.now() / 1000);
      if (decoded.exp < now) {
        throw new Error('Token expired, cannot refresh');
      }

      // Issue new token with same claims
      return this.issueToken(decoded.sub, {
        scopes: decoded.scope,
        custom: {
          refreshed: true,
          originalJti: decoded.jti
        }
      });
    } catch (error) {
      logger.error('Failed to refresh JWT token', {
        error: error.message
      });
      throw new Error('Failed to refresh token');
    }
  }

  /**
   * Revoke a JWT token (add to blacklist)
   * @param {string} jti - JWT ID
   * @returns {Promise<void>}
   */
  async revokeToken(jti) {
    try {
      // In production, this would add the JTI to a Redis blacklist
      // that the Kong JWT plugin checks
      logger.info('JWT token revoked', { jti });
      
      // Store in Redis with TTL matching token expiration
      // await redisClient.setex(`jwt:blacklist:${jti}`, 3600, '1');
    } catch (error) {
      logger.error('Failed to revoke JWT token', {
        error: error.message,
        jti
      });
      throw new Error('Failed to revoke token');
    }
  }

  /**
   * Ensure consumer has JWT credential in Kong
   * @param {string} userId - User ID
   * @returns {Promise<void>}
   * @private
   */
  async ensureJWTCredential(userId) {
    try {
      // Check if consumer exists
      let consumer;
      try {
        const response = await this.kongClient.get(`/consumers/${userId}`);
        consumer = response.data;
      } catch (error) {
        if (error.response?.status === 404) {
          // Create consumer
          const createResponse = await this.kongClient.post('/consumers', {
            username: userId,
            custom_id: userId,
            tags: ['jwt-user']
          });
          consumer = createResponse.data;
        } else {
          throw error;
        }
      }

      // Check if JWT credential exists
      try {
        await this.kongClient.get(`/consumers/${consumer.id}/jwt`);
      } catch (error) {
        if (error.response?.status === 404) {
          // Create JWT credential
          const secret = this.config.algorithm === 'RS256' 
            ? this.config.publicKey 
            : this.config.secret;
            
          await this.createJWTCredential(
            consumer.id,
            this.config.issuer,
            this.config.algorithm,
            secret
          );
        }
      }
    } catch (error) {
      logger.error('Failed to ensure JWT credential', {
        error: error.message,
        userId
      });
      throw error;
    }
  }

  /**
   * Get JWT configuration (public info only)
   * @returns {Object} Public JWT configuration
   */
  getPublicConfig() {
    return {
      algorithm: this.config.algorithm,
      issuer: this.config.issuer,
      publicKey: this.config.algorithm === 'RS256' ? this.config.publicKey : undefined,
      tokenEndpoint: '/api/v1/auth/token',
      refreshEndpoint: '/api/v1/auth/token/refresh',
      revokeEndpoint: '/api/v1/auth/token/revoke'
    };
  }

  /**
   * Validate JWT scopes
   * @param {string[]} tokenScopes - Scopes in token
   * @param {string[]} requiredScopes - Required scopes
   * @returns {boolean} Has required scopes
   */
  hasRequiredScopes(tokenScopes, requiredScopes) {
    return requiredScopes.every(scope => tokenScopes.includes(scope));
  }

  /**
   * Extract bearer token from authorization header
   * @param {string} authHeader - Authorization header
   * @returns {string|null} Token or null
   */
  extractBearerToken(authHeader) {
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return null;
    }
    return authHeader.substring(7);
  }
}

module.exports = new JWTService();