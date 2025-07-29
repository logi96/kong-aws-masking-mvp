/**
 * @fileoverview Express error handling middleware
 * @module middlewares/errorHandler
 */

const logger = require('../utils/logger');

/**
 * Custom API Error class
 */
class ApiError extends Error {
  constructor(statusCode, message, details = null) {
    super(message);
    this.statusCode = statusCode;
    this.details = details;
    this.timestamp = new Date().toISOString();
  }
}

/**
 * Error handler middleware
 * @param {Error} err - Error object
 * @param {express.Request} req - Express request object
 * @param {express.Response} res - Express response object
 * @param {express.NextFunction} next - Express next function
 */
const errorHandler = (err, req, res, next) => {
  // Log error details
  logger.error('Error occurred:', {
    error: err.message,
    stack: err.stack,
    url: req.url,
    method: req.method,
    ip: req.ip,
    userAgent: req.get('user-agent')
  });

  // Default error values
  let statusCode = err.statusCode || 500;
  let message = err.message || 'Internal Server Error';
  let details = err.details || null;

  // Handle specific error types
  if (err.name === 'ValidationError') {
    statusCode = 400;
    message = 'Validation Error';
    details = err.errors;
  } else if (err.name === 'UnauthorizedError') {
    statusCode = 401;
    message = 'Unauthorized';
  } else if (err.name === 'CastError') {
    statusCode = 400;
    message = 'Invalid ID format';
  } else if (err.code === 'ECONNREFUSED') {
    statusCode = 503;
    message = 'Service Unavailable';
    details = 'Unable to connect to required service';
  } else if (err.code === 'ETIMEDOUT') {
    statusCode = 504;
    message = 'Gateway Timeout';
    details = 'Request timed out';
  }

  // Prepare error response
  const errorResponse = {
    error: {
      status: statusCode,
      message: message,
      timestamp: new Date().toISOString(),
      path: req.path,
      method: req.method
    }
  };

  // Add details if available
  if (details) {
    errorResponse.error.details = details;
  }

  // Add stack trace in development
  if (process.env.NODE_ENV === 'development') {
    errorResponse.error.stack = err.stack;
  }

  // Add request ID if available
  if (req.id) {
    errorResponse.error.requestId = req.id;
  }

  // Send error response
  res.status(statusCode).json(errorResponse);
};

/**
 * Async error wrapper
 * @param {Function} fn - Async function to wrap
 * @returns {Function} Wrapped function
 */
const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};

/**
 * Not found handler
 * @param {express.Request} req - Express request object
 * @param {express.Response} res - Express response object
 * @param {express.NextFunction} next - Express next function
 */
const notFoundHandler = (req, res, next) => {
  const error = new ApiError(404, `Cannot ${req.method} ${req.path}`);
  next(error);
};

module.exports = {
  errorHandler,
  asyncHandler,
  notFoundHandler,
  ApiError
};