/**
 * @fileoverview Authentication and API key management routes
 * @module routes/auth
 */

const express = require('express');
const router = express.Router();
const apiKeyService = require('../services/auth/apiKeyService');
const jwtService = require('../services/auth/jwtService');
const { authenticateRequest, requireRole } = require('../middlewares/auth');
const logger = require('../utils/logger');

/**
 * @route POST /api/v1/auth/keys
 * @description Create a new API key
 * @access Protected - requires authentication
 */
router.post('/keys', authenticateRequest, async (req, res) => {
  try {
    const { name, tier = 'standard', scopes = ['read'] } = req.body;
    
    // Validate input
    if (!name) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Key name is required',
        code: 'MISSING_NAME'
      });
    }

    // Validate tier
    const validTiers = ['standard', 'premium', 'enterprise'];
    if (!validTiers.includes(tier)) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Invalid tier. Must be one of: standard, premium, enterprise',
        code: 'INVALID_TIER'
      });
    }

    // Create API key
    const apiKey = await apiKeyService.createApiKey(req.auth.username, {
      name,
      tier,
      scopes
    });

    logger.info('API key created via API', {
      consumerId: req.auth.consumerId,
      keyId: apiKey.id,
      tier
    });

    res.status(201).json({
      id: apiKey.id,
      key: apiKey.key, // Only shown once on creation
      name: apiKey.metadata.name,
      tier: apiKey.metadata.tier,
      scopes: apiKey.metadata.scopes,
      createdAt: apiKey.createdAt,
      status: apiKey.status,
      message: 'API key created successfully. Please save the key securely as it will not be shown again.'
    });
  } catch (error) {
    logger.error('Failed to create API key', {
      error: error.message,
      consumerId: req.auth.consumerId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to create API key',
      code: 'KEY_CREATION_FAILED'
    });
  }
});

/**
 * @route GET /api/v1/auth/keys
 * @description List all API keys for the authenticated user
 * @access Protected - requires authentication
 */
router.get('/keys', authenticateRequest, async (req, res) => {
  try {
    const keys = await apiKeyService.listApiKeys(req.auth.username);
    
    res.json({
      keys,
      count: keys.length
    });
  } catch (error) {
    logger.error('Failed to list API keys', {
      error: error.message,
      consumerId: req.auth.consumerId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to list API keys',
      code: 'KEY_LIST_FAILED'
    });
  }
});

/**
 * @route GET /api/v1/auth/keys/:keyId
 * @description Get specific API key details
 * @access Protected - requires authentication
 */
router.get('/keys/:keyId', authenticateRequest, async (req, res) => {
  try {
    const { keyId } = req.params;
    
    const key = await apiKeyService.getApiKey(keyId);
    
    // Verify ownership
    if (key.username !== req.auth.username && !req.auth.isAdmin) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Access denied to this API key',
        code: 'ACCESS_DENIED'
      });
    }
    
    // Get usage stats
    const usage = await apiKeyService.getKeyUsageStats(keyId);
    
    res.json({
      ...key,
      usage
    });
  } catch (error) {
    if (error.message === 'API key not found') {
      return res.status(404).json({
        error: 'Not Found',
        message: 'API key not found',
        code: 'KEY_NOT_FOUND'
      });
    }
    
    logger.error('Failed to get API key', {
      error: error.message,
      keyId: req.params.keyId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to get API key',
      code: 'KEY_GET_FAILED'
    });
  }
});

/**
 * @route PUT /api/v1/auth/keys/:keyId
 * @description Update API key (rate limit tier)
 * @access Protected - requires authentication
 */
router.put('/keys/:keyId', authenticateRequest, async (req, res) => {
  try {
    const { keyId } = req.params;
    const { tier } = req.body;
    
    if (!tier) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Tier is required',
        code: 'MISSING_TIER'
      });
    }

    // Validate tier
    const validTiers = ['standard', 'premium', 'enterprise'];
    if (!validTiers.includes(tier)) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Invalid tier. Must be one of: standard, premium, enterprise',
        code: 'INVALID_TIER'
      });
    }

    // Check ownership
    const key = await apiKeyService.getApiKey(keyId);
    if (key.username !== req.auth.username && !req.auth.isAdmin) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Access denied to this API key',
        code: 'ACCESS_DENIED'
      });
    }

    // Update rate limit
    const updatedKey = await apiKeyService.updateRateLimit(keyId, tier);
    
    logger.info('API key updated via API', {
      consumerId: req.auth.consumerId,
      keyId,
      newTier: tier
    });

    res.json({
      message: 'API key updated successfully',
      key: updatedKey
    });
  } catch (error) {
    if (error.message === 'API key not found') {
      return res.status(404).json({
        error: 'Not Found',
        message: 'API key not found',
        code: 'KEY_NOT_FOUND'
      });
    }
    
    logger.error('Failed to update API key', {
      error: error.message,
      keyId: req.params.keyId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to update API key',
      code: 'KEY_UPDATE_FAILED'
    });
  }
});

/**
 * @route DELETE /api/v1/auth/keys/:keyId
 * @description Revoke an API key
 * @access Protected - requires authentication
 */
router.delete('/keys/:keyId', authenticateRequest, async (req, res) => {
  try {
    const { keyId } = req.params;
    
    // Check ownership
    const key = await apiKeyService.getApiKey(keyId);
    if (key.username !== req.auth.username && !req.auth.isAdmin) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Access denied to this API key',
        code: 'ACCESS_DENIED'
      });
    }

    await apiKeyService.revokeApiKey(keyId);
    
    logger.info('API key revoked via API', {
      consumerId: req.auth.consumerId,
      keyId
    });

    res.json({
      message: 'API key revoked successfully',
      keyId
    });
  } catch (error) {
    if (error.message === 'API key not found') {
      return res.status(404).json({
        error: 'Not Found',
        message: 'API key not found',
        code: 'KEY_NOT_FOUND'
      });
    }
    
    logger.error('Failed to revoke API key', {
      error: error.message,
      keyId: req.params.keyId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to revoke API key',
      code: 'KEY_REVOKE_FAILED'
    });
  }
});

/**
 * @route POST /api/v1/auth/keys/:keyId/rotate
 * @description Rotate an API key (create new, revoke old)
 * @access Protected - requires authentication
 */
router.post('/keys/:keyId/rotate', authenticateRequest, async (req, res) => {
  try {
    const { keyId } = req.params;
    
    // Check ownership
    const key = await apiKeyService.getApiKey(keyId);
    if (key.username !== req.auth.username && !req.auth.isAdmin) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Access denied to this API key',
        code: 'ACCESS_DENIED'
      });
    }

    const newKey = await apiKeyService.rotateApiKey(keyId);
    
    logger.info('API key rotated via API', {
      consumerId: req.auth.consumerId,
      oldKeyId: keyId,
      newKeyId: newKey.id
    });

    res.json({
      message: 'API key rotated successfully',
      oldKeyId: keyId,
      newKey: {
        id: newKey.id,
        key: newKey.key, // Only shown once
        name: newKey.metadata.name,
        tier: newKey.metadata.tier,
        scopes: newKey.metadata.scopes,
        createdAt: newKey.createdAt,
        status: newKey.status
      }
    });
  } catch (error) {
    if (error.message === 'API key not found') {
      return res.status(404).json({
        error: 'Not Found',
        message: 'API key not found',
        code: 'KEY_NOT_FOUND'
      });
    }
    
    logger.error('Failed to rotate API key', {
      error: error.message,
      keyId: req.params.keyId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to rotate API key',
      code: 'KEY_ROTATE_FAILED'
    });
  }
});

/**
 * @route GET /api/v1/auth/validate
 * @description Validate current authentication
 * @access Protected - requires authentication
 */
router.get('/validate', authenticateRequest, async (req, res) => {
  res.json({
    valid: true,
    consumer: {
      id: req.auth.consumerId,
      username: req.auth.username,
      customId: req.auth.customId
    },
    authMethod: req.auth.authMethod,
    rateLimit: req.auth.rateLimit
  });
});

/**
 * @route GET /api/v1/auth/admin/keys
 * @description List all API keys (admin only)
 * @access Protected - requires admin role
 */
router.get('/admin/keys', authenticateRequest, requireRole(['admin']), async (req, res) => {
  try {
    // This would list all keys across all consumers
    // Implementation depends on specific admin requirements
    res.json({
      message: 'Admin endpoint - implementation pending',
      endpoint: '/admin/keys'
    });
  } catch (error) {
    logger.error('Failed to list all keys', {
      error: error.message,
      adminId: req.auth.consumerId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to list all keys',
      code: 'ADMIN_LIST_FAILED'
    });
  }
});

/**
 * JWT Token Endpoints
 */

/**
 * @route POST /api/v1/auth/token
 * @description Issue a new JWT token
 * @access Protected - requires API key authentication
 */
router.post('/token', authenticateRequest, async (req, res) => {
  try {
    const { scopes = ['read'], expiresIn } = req.body;
    
    // Issue JWT token for the authenticated user
    const tokenData = await jwtService.issueToken(req.auth.username, {
      scopes,
      expiresIn,
      custom: {
        consumerId: req.auth.consumerId,
        issuedVia: 'api'
      }
    });

    logger.info('JWT token issued via API', {
      consumerId: req.auth.consumerId,
      jti: tokenData.jti,
      scopes
    });

    res.json({
      access_token: tokenData.token,
      token_type: tokenData.tokenType,
      expires_in: tokenData.expiresIn,
      issued_at: tokenData.issuedAt,
      expires_at: tokenData.expiresAt,
      jti: tokenData.jti,
      scopes: tokenData.scopes
    });
  } catch (error) {
    logger.error('Failed to issue JWT token', {
      error: error.message,
      consumerId: req.auth.consumerId
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to issue token',
      code: 'TOKEN_ISSUE_FAILED'
    });
  }
});

/**
 * @route POST /api/v1/auth/token/refresh
 * @description Refresh a JWT token
 * @access Public - requires valid JWT token in body
 */
router.post('/token/refresh', async (req, res) => {
  try {
    const { token } = req.body;
    
    if (!token) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Token is required',
        code: 'MISSING_TOKEN'
      });
    }

    const newTokenData = await jwtService.refreshToken(token);

    logger.info('JWT token refreshed', {
      jti: newTokenData.jti
    });

    res.json({
      access_token: newTokenData.token,
      token_type: newTokenData.tokenType,
      expires_in: newTokenData.expiresIn,
      issued_at: newTokenData.issuedAt,
      expires_at: newTokenData.expiresAt,
      jti: newTokenData.jti,
      scopes: newTokenData.scopes
    });
  } catch (error) {
    if (error.message === 'Token expired' || error.message === 'Invalid token') {
      return res.status(401).json({
        error: 'Unauthorized',
        message: error.message,
        code: 'INVALID_TOKEN'
      });
    }
    
    logger.error('Failed to refresh JWT token', {
      error: error.message
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to refresh token',
      code: 'TOKEN_REFRESH_FAILED'
    });
  }
});

/**
 * @route POST /api/v1/auth/token/verify
 * @description Verify a JWT token
 * @access Public
 */
router.post('/token/verify', async (req, res) => {
  try {
    const { token } = req.body;
    
    if (!token) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Token is required',
        code: 'MISSING_TOKEN'
      });
    }

    const decoded = await jwtService.verifyToken(token);

    res.json({
      valid: true,
      payload: {
        sub: decoded.sub,
        iss: decoded.iss,
        exp: decoded.exp,
        iat: decoded.iat,
        jti: decoded.jti,
        scopes: decoded.scope
      }
    });
  } catch (error) {
    res.status(401).json({
      valid: false,
      error: error.message,
      code: 'INVALID_TOKEN'
    });
  }
});

/**
 * @route POST /api/v1/auth/token/revoke
 * @description Revoke a JWT token
 * @access Protected - requires authentication
 */
router.post('/token/revoke', authenticateRequest, async (req, res) => {
  try {
    const { jti } = req.body;
    
    if (!jti) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'JTI (JWT ID) is required',
        code: 'MISSING_JTI'
      });
    }

    await jwtService.revokeToken(jti);

    logger.info('JWT token revoked via API', {
      consumerId: req.auth.consumerId,
      jti
    });

    res.json({
      message: 'Token revoked successfully',
      jti
    });
  } catch (error) {
    logger.error('Failed to revoke JWT token', {
      error: error.message,
      jti: req.body.jti
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to revoke token',
      code: 'TOKEN_REVOKE_FAILED'
    });
  }
});

/**
 * @route GET /api/v1/auth/token/config
 * @description Get JWT public configuration
 * @access Public
 */
router.get('/token/config', (req, res) => {
  const config = jwtService.getPublicConfig();
  res.json(config);
});

module.exports = router;