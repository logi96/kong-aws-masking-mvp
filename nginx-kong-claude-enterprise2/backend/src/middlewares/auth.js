/**
 * @fileoverview Authentication middleware for Kong-proxied requests
 * @module middlewares/auth
 */

const logger = require('../utils/logger');

/**
 * @typedef {Object} AuthInfo
 * @property {string} consumerId - Kong consumer ID
 * @property {string} credentialId - API key or JWT identifier
 * @property {string} username - Consumer username
 * @property {string} customId - Consumer custom ID
 * @property {string} authMethod - Authentication method used (key-auth or jwt)
 * @property {Object} rateLimit - Rate limit information
 * @property {number} rateLimit.limit - Rate limit per minute
 * @property {number} rateLimit.remaining - Remaining requests
 * @property {number} rateLimit.reset - Reset timestamp
 */

/**
 * Extract rate limit information from Kong headers
 * @param {Object} headers - Request headers
 * @returns {Object} Rate limit information
 */
const extractRateLimit = (headers) => {
  return {
    limit: parseInt(headers['x-ratelimit-limit-minute'] || '100', 10),
    remaining: parseInt(headers['x-ratelimit-remaining-minute'] || '100', 10),
    reset: parseInt(headers['x-ratelimit-reset'] || '0', 10)
  };
};

/**
 * Authentication middleware that verifies Kong authentication headers
 * @param {import('express').Request} req - Express request object
 * @param {import('express').Response} res - Express response object
 * @param {import('express').NextFunction} next - Express next function
 * @returns {void}
 */
const authenticateRequest = async (req, res, next) => {
  try {
    // Check if request is coming through Kong
    const kongRoute = req.headers['x-kong-route'];
    
    if (!kongRoute) {
      logger.warn('Request received without Kong routing headers', {
        path: req.path,
        method: req.method,
        ip: req.ip
      });
      
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Direct access not allowed. Please use the API gateway.',
        code: 'DIRECT_ACCESS_FORBIDDEN'
      });
    }

    // Extract Kong consumer information
    const kongConsumer = req.headers['x-consumer-id'];
    const kongCredential = req.headers['x-credential-identifier'];
    const kongUsername = req.headers['x-consumer-username'];
    const kongCustomId = req.headers['x-consumer-custom-id'];
    const authMethod = req.headers['x-authenticated-scope'] || 'key-auth';

    // Verify authentication headers
    if (!kongConsumer || !kongCredential) {
      logger.warn('Missing Kong authentication headers', {
        path: req.path,
        hasConsumer: !!kongConsumer,
        hasCredential: !!kongCredential
      });
      
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Valid API credentials required',
        code: 'MISSING_CREDENTIALS'
      });
    }

    // Extract rate limit information
    const rateLimit = extractRateLimit(req.headers);

    // Attach authentication info to request
    req.auth = {
      consumerId: kongConsumer,
      credentialId: kongCredential,
      username: kongUsername || 'anonymous',
      customId: kongCustomId || null,
      authMethod,
      rateLimit
    };

    // Log successful authentication
    logger.info('Request authenticated', {
      consumerId: kongConsumer,
      username: kongUsername,
      method: req.method,
      path: req.path,
      authMethod,
      remainingRequests: rateLimit.remaining
    });

    // Add rate limit headers to response
    res.set({
      'X-RateLimit-Limit': rateLimit.limit.toString(),
      'X-RateLimit-Remaining': rateLimit.remaining.toString(),
      'X-RateLimit-Reset': rateLimit.reset.toString()
    });

    next();
  } catch (error) {
    logger.error('Authentication middleware error', {
      error: error.message,
      stack: error.stack,
      path: req.path
    });
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Authentication processing failed',
      code: 'AUTH_ERROR'
    });
  }
};

/**
 * Optional authentication middleware (allows anonymous access)
 * @param {import('express').Request} req - Express request object
 * @param {import('express').Response} res - Express response object
 * @param {import('express').NextFunction} next - Express next function
 * @returns {void}
 */
const optionalAuth = async (req, res, next) => {
  const kongConsumer = req.headers['x-consumer-id'];
  
  if (kongConsumer) {
    // If authentication headers present, validate them
    return authenticateRequest(req, res, next);
  }
  
  // Allow anonymous access
  req.auth = {
    consumerId: 'anonymous',
    credentialId: 'anonymous',
    username: 'anonymous',
    customId: null,
    authMethod: 'none',
    rateLimit: {
      limit: 10, // Lower limit for anonymous
      remaining: 10,
      reset: 0
    }
  };
  
  next();
};

/**
 * Role-based access control middleware
 * @param {string[]} allowedRoles - Array of allowed roles
 * @returns {Function} Express middleware function
 */
const requireRole = (allowedRoles) => {
  return async (req, res, next) => {
    if (!req.auth) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Authentication required',
        code: 'AUTH_REQUIRED'
      });
    }

    // Extract groups from Kong ACL headers
    const userGroups = req.headers['x-consumer-groups'];
    
    if (!userGroups) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'No roles assigned to user',
        code: 'NO_ROLES'
      });
    }

    const groups = userGroups.split(',').map(g => g.trim());
    const hasRole = allowedRoles.some(role => groups.includes(role));

    if (!hasRole) {
      logger.warn('Access denied - insufficient roles', {
        consumerId: req.auth.consumerId,
        requiredRoles: allowedRoles,
        userGroups: groups
      });
      
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Insufficient permissions',
        code: 'INSUFFICIENT_PERMISSIONS'
      });
    }

    next();
  };
};

/**
 * API scope validation middleware
 * @param {string[]} requiredScopes - Array of required scopes
 * @returns {Function} Express middleware function
 */
const requireScope = (requiredScopes) => {
  return async (req, res, next) => {
    if (!req.auth) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Authentication required',
        code: 'AUTH_REQUIRED'
      });
    }

    // For JWT auth, check scopes
    if (req.auth.authMethod === 'jwt') {
      const tokenScopes = req.headers['x-authenticated-scope'];
      
      if (!tokenScopes) {
        return res.status(403).json({
          error: 'Forbidden',
          message: 'No scopes in token',
          code: 'NO_SCOPES'
        });
      }

      const scopes = tokenScopes.split(' ');
      const hasScope = requiredScopes.every(scope => scopes.includes(scope));

      if (!hasScope) {
        logger.warn('Access denied - insufficient scopes', {
          consumerId: req.auth.consumerId,
          requiredScopes,
          tokenScopes: scopes
        });
        
        return res.status(403).json({
          error: 'Forbidden',
          message: 'Insufficient scopes',
          code: 'INSUFFICIENT_SCOPES',
          required: requiredScopes,
          provided: scopes
        });
      }
    }

    next();
  };
};

module.exports = {
  authenticateRequest,
  optionalAuth,
  requireRole,
  requireScope
};