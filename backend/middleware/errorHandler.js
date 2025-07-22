/**
 * @fileoverview Global error handling middleware for Kong AWS Masking MVP
 * @description Centralized error handling with logging and response formatting
 * @author Infrastructure Team
 * @version 1.0.0
 */

'use strict';

const logger = require('../utils/logger');

/**
 * @typedef {Object} ErrorResponse
 * @property {string} error - Error type/name
 * @property {string} message - Human-readable error message
 * @property {string} [details] - Additional error details
 * @property {string} timestamp - ISO timestamp of error
 * @property {string} requestId - Request correlation ID
 * @property {string} [stack] - Error stack trace (development only)
 */

/**
 * Global error handling middleware
 * @description Catches all errors and formats them into consistent responses
 * @param {Error} err - The error object
 * @param {import('express').Request} req - Express request object
 * @param {import('express').Response} res - Express response object
 * @param {import('express').NextFunction} next - Express next function
 * @returns {void}
 */
function errorHandler(err, req, res, next) {
  // If response already sent, delegate to Express default handler
  if (res.headersSent) {
    logger.warning('Error occurred after headers sent', {
      requestId: req.id,
      error: err.message,
      url: req.url,
      method: req.method
    });
    return next(err);
  }
  
  // Determine error type and status code
  const errorInfo = categorizeError(err);
  
  // Log the error with appropriate level
  logError(err, req, errorInfo);
  
  // Build error response
  /** @type {ErrorResponse} */
  const errorResponse = {
    error: errorInfo.type,
    message: errorInfo.message,
    timestamp: new Date().toISOString(),
    requestId: req.id || 'unknown'
  };
  
  // Add details if available
  if (errorInfo.details) {
    errorResponse.details = errorInfo.details;
  }
  
  // Add stack trace in development
  if (process.env.NODE_ENV === 'development' && err.stack) {
    errorResponse.stack = err.stack;
  }
  
  // Set security headers
  res.set({
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY'
  });
  
  // Send error response
  res.status(errorInfo.statusCode).json(errorResponse);
}

/**
 * Categorize error and determine appropriate response
 * @param {Error} err - The error to categorize
 * @returns {Object} Error categorization results
 * @private
 */
function categorizeError(err) {
  // Validation errors
  if (err.name === 'ValidationError' || err.statusCode === 400) {
    return {
      type: 'ValidationError',
      message: err.message || 'Invalid request data',
      statusCode: 400,
      details: err.details || err.errors
    };
  }
  
  // Authentication errors
  if (err.name === 'UnauthorizedError' || err.statusCode === 401) {
    return {
      type: 'AuthenticationError',
      message: 'Authentication required',
      statusCode: 401
    };
  }
  
  // Authorization errors
  if (err.name === 'ForbiddenError' || err.statusCode === 403) {
    return {
      type: 'AuthorizationError', 
      message: 'Insufficient permissions',
      statusCode: 403
    };
  }
  
  // Not found errors
  if (err.name === 'NotFoundError' || err.statusCode === 404) {
    return {
      type: 'NotFoundError',
      message: 'Resource not found',
      statusCode: 404
    };
  }
  
  // Rate limiting errors
  if (err.name === 'TooManyRequestsError' || err.statusCode === 429) {
    return {
      type: 'RateLimitError',
      message: 'Rate limit exceeded',
      statusCode: 429,
      details: 'Please wait before making more requests'
    };
  }
  
  // Timeout errors
  if (err.name === 'TimeoutError' || err.code === 'TIMEOUT' || err.code === 'ETIMEDOUT') {
    return {
      type: 'TimeoutError',
      message: 'Request timeout',
      statusCode: 504,
      details: 'The operation took too long to complete'
    };
  }
  
  // AWS CLI errors
  if (err.message && err.message.includes('AWS CLI')) {
    return {
      type: 'AWSError',
      message: 'AWS operation failed',
      statusCode: 502,
      details: sanitizeAwsError(err.message)
    };
  }
  
  // Claude API errors
  if (err.message && (err.message.includes('Claude API') || err.message.includes('Anthropic'))) {
    return {
      type: 'ClaudeAPIError',
      message: 'AI analysis service unavailable',
      statusCode: 502,
      details: 'Please try again later'
    };
  }
  
  // JSON parsing errors
  if (err.name === 'SyntaxError' && err.message.includes('JSON')) {
    return {
      type: 'JSONParseError',
      message: 'Invalid JSON in request body',
      statusCode: 400
    };
  }
  
  // Payload too large errors
  if (err.name === 'PayloadTooLargeError' || err.statusCode === 413) {
    return {
      type: 'PayloadTooLargeError',
      message: 'Request payload too large',
      statusCode: 413,
      details: 'Maximum payload size is 10MB'
    };
  }
  
  // Database errors (if we add database later)
  if (err.name === 'SequelizeError' || err.name === 'MongoError') {
    return {
      type: 'DatabaseError',
      message: 'Database operation failed',
      statusCode: 500,
      details: 'Please try again later'
    };
  }
  
  // Network errors
  if (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND' || err.code === 'EAI_AGAIN') {
    return {
      type: 'NetworkError',
      message: 'Network connectivity error',
      statusCode: 502,
      details: 'Unable to connect to external service'
    };
  }
  
  // Generic server errors
  return {
    type: 'InternalServerError',
    message: process.env.NODE_ENV === 'production' 
      ? 'An unexpected error occurred' 
      : err.message || 'Internal server error',
    statusCode: 500
  };
}

/**
 * Log error with appropriate level based on severity
 * @param {Error} err - The error to log
 * @param {import('express').Request} req - Express request object
 * @param {Object} errorInfo - Error categorization info
 * @private
 */
function logError(err, req, errorInfo) {
  const logContext = {
    requestId: req.id,
    method: req.method,
    url: req.originalUrl || req.url,
    userAgent: req.get('User-Agent'),
    ip: req.ip,
    errorType: errorInfo.type,
    statusCode: errorInfo.statusCode
  };
  
  // Log with appropriate level based on error type
  if (errorInfo.statusCode >= 500) {
    // Server errors - log as error with full details
    logger.error('Server error occurred', {
      ...logContext,
      error: err.message,
      stack: err.stack,
      details: errorInfo.details
    });
  } else if (errorInfo.statusCode >= 400) {
    // Client errors - log as warning
    logger.warning('Client error occurred', {
      ...logContext,
      error: err.message,
      details: errorInfo.details
    });
  } else {
    // Other errors - log as info
    logger.info('Error handled', {
      ...logContext,
      error: err.message
    });
  }
  
  // Security event logging for certain error types
  if (errorInfo.type === 'AuthenticationError' || 
      errorInfo.type === 'AuthorizationError' ||
      errorInfo.type === 'RateLimitError') {
    
    logger.security(errorInfo.type, {
      requestId: req.id,
      ip: req.ip,
      userAgent: req.get('User-Agent'),
      url: req.originalUrl,
      timestamp: new Date().toISOString()
    });
  }
}

/**
 * Sanitize AWS error messages to remove sensitive information
 * @param {string} errorMessage - Raw AWS error message
 * @returns {string} Sanitized error message
 * @private
 */
function sanitizeAwsError(errorMessage) {
  return errorMessage
    // Remove account IDs
    .replace(/\b\d{12}\b/g, '[ACCOUNT-ID]')
    // Remove access keys
    .replace(/AKIA[0-9A-Z]{16}/g, '[ACCESS-KEY]')
    // Remove secret keys patterns
    .replace(/[A-Za-z0-9/+=]{40}/g, '[SECRET-KEY]')
    // Remove role ARNs with account IDs
    .replace(/arn:aws:iam::\d{12}:role\/[^\\s]+/g, '[ROLE-ARN]')
    // Keep only the first line for brevity
    .split('\n')[0]
    .trim();
}

/**
 * Handle unhandled promise rejections
 * @description Global handler for unhandled promise rejections
 * @param {any} reason - Rejection reason
 * @param {Promise} promise - The rejected promise
 */
function handleUnhandledRejection(reason, promise) {
  logger.error('Unhandled promise rejection', {
    reason: reason instanceof Error ? reason.message : reason,
    stack: reason instanceof Error ? reason.stack : undefined,
    promise: promise.toString()
  });
  
  // In production, we might want to exit gracefully
  if (process.env.NODE_ENV === 'production') {
    setTimeout(() => {
      process.exit(1);
    }, 1000);
  }
}

/**
 * Handle uncaught exceptions
 * @description Global handler for uncaught exceptions
 * @param {Error} error - The uncaught exception
 */
function handleUncaughtException(error) {
  logger.error('Uncaught exception', {
    error: error.message,
    stack: error.stack
  });
  
  // Exit immediately on uncaught exceptions
  process.exit(1);
}

// Set up global error handlers
process.on('unhandledRejection', handleUnhandledRejection);
process.on('uncaughtException', handleUncaughtException);

module.exports = errorHandler;