/**
 * @fileoverview Centralized logging utility with Winston
 * @description Provides structured logging with different transports for development and production
 * @author Infrastructure Team
 */

'use strict';

const winston = require('winston');
const DailyRotateFile = require('winston-daily-rotate-file');

/**
 * @typedef {Object} LoggerConfig
 * @property {string} level - Log level (error, warn, info, debug)
 * @property {string} format - Log format
 * @property {boolean} colorize - Enable colorization for console output
 */

/**
 * Custom log format for structured logging
 * @type {winston.Logform.Format}
 */
const customFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.json(),
  winston.format.printf((info) => {
    const { timestamp, level, message, ...meta } = info;
    return JSON.stringify({
      timestamp,
      level: level.toUpperCase(),
      message,
      ...meta
    });
  })
);

/**
 * Console format for development
 * @type {winston.Logform.Format}
 */
const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: 'HH:mm:ss' }),
  winston.format.printf((info) => {
    const { timestamp, level, message, ...meta } = info;
    const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
    return `${timestamp} ${level}: ${message}${metaStr}`;
  })
);

/**
 * Create Winston transports based on environment configuration
 * @returns {winston.transport[]} Array of winston transports
 * @description Creates appropriate transports for different environments:
 * - Development: Console transport with colored output
 * - Production: File-based transports with rotation
 * - Test: Console transport with minimal output
 * @example
 * const transports = createTransports();
 * // Returns [ConsoleTransport, DailyRotateFileTransport, ...]
 */
function createTransports() {
  const transports = [];
  const isProduction = process.env.NODE_ENV === 'production';
  const logLevel = process.env.LOG_LEVEL || (isProduction ? 'info' : 'debug');

  // Console transport (always enabled in development)
  if (!isProduction || process.env.ENABLE_CONSOLE_LOG === 'true') {
    transports.push(
      new winston.transports.Console({
        level: logLevel,
        format: isProduction ? customFormat : consoleFormat
      })
    );
  }

  // File transports (production and if explicitly enabled in development)
  if (isProduction || process.env.ENABLE_FILE_LOG === 'true') {
    // Error log file
    transports.push(
      new DailyRotateFile({
        level: 'error',
        filename: '/app/logs/error-%DATE%.log',
        datePattern: 'YYYY-MM-DD',
        maxSize: '20m',
        maxFiles: '14d',
        format: customFormat
      })
    );

    // Combined log file
    transports.push(
      new DailyRotateFile({
        level: logLevel,
        filename: '/app/logs/combined-%DATE%.log',
        datePattern: 'YYYY-MM-DD',
        maxSize: '20m',
        maxFiles: '7d',
        format: customFormat
      })
    );
  }

  return transports;
}

/**
 * Create exception and rejection handlers for Winston logger
 * @returns {Object} Handlers configuration object
 * @returns {winston.transport[]} returns.exceptionHandlers - Array of transports for uncaught exceptions
 * @returns {winston.transport[]} returns.rejectionHandlers - Array of transports for unhandled promise rejections
 * @description Creates handlers to capture uncaught exceptions and unhandled promise rejections
 * @example
 * const handlers = createHandlers();
 * // Returns {
 * //   exceptionHandlers: [FileTransport],
 * //   rejectionHandlers: [FileTransport]
 * // }
 */
function createHandlers() {
  const isProduction = process.env.NODE_ENV === 'production';
  const enableFileLog = process.env.ENABLE_FILE_LOG === 'true';
  
  if (isProduction || enableFileLog) {
    return {
      exceptionHandlers: [
        new winston.transports.File({ filename: '/app/logs/exceptions.log' })
      ],
      rejectionHandlers: [
        new winston.transports.File({ filename: '/app/logs/rejections.log' })
      ]
    };
  }
  
  // Use console handlers for development/test
  return {
    exceptionHandlers: [
      new winston.transports.Console({ format: consoleFormat })
    ],
    rejectionHandlers: [
      new winston.transports.Console({ format: consoleFormat })
    ]
  };
}

/**
 * Winston logger instance
 * @type {winston.Logger}
 */
const handlers = createHandlers();
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: customFormat,
  transports: createTransports(),
  exitOnError: false,
  ...handlers
});

/**
 * Add request context to logger
 * @param {string} requestId - Request ID for correlation
 * @returns {winston.Logger} Logger with request context
 * @description Creates a child logger instance with request ID for tracing
 * @example
 * const requestLogger = logger.withRequestId('req-12345');
 * requestLogger.info('Processing request');
 */
logger.withRequestId = function(requestId) {
  return logger.child({ requestId });
};

/**
 * Log performance metrics
 * @param {string} operation - Operation name
 * @param {number} duration - Duration in milliseconds
 * @param {Object} [metadata={}] - Additional metadata
 */
logger.performance = function(operation, duration, metadata = {}) {
  this.info('Performance metric', {
    metric: 'performance',
    operation,
    duration,
    unit: 'ms',
    ...metadata
  });
};

/**
 * Log security events
 * @param {string} event - Security event type
 * @param {Object} details - Event details
 */
logger.security = function(event, details) {
  this.warn('Security event', {
    metric: 'security',
    event,
    ...details
  });
};

/**
 * Log business metrics
 * @param {string} metric - Metric name
 * @param {number|string} value - Metric value
 * @param {Object} [metadata={}] - Additional metadata
 */
logger.metric = function(metric, value, metadata = {}) {
  this.info('Business metric', {
    metric: 'business',
    name: metric,
    value,
    ...metadata
  });
};

module.exports = logger;