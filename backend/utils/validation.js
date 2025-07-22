/**
 * @fileoverview Environment and input validation utilities
 * @description Validates environment variables and request inputs
 * @author Infrastructure Team
 */

'use strict';

const { body, param, query, validationResult } = require('express-validator');

/**
 * @typedef {Object} ValidationError
 * @property {string} field - Field name with validation error
 * @property {string} message - Error message
 * @property {string} value - Invalid value
 */

/**
 * Required environment variables
 * @type {string[]}
 */
const REQUIRED_ENV_VARS = [
  'ANTHROPIC_API_KEY',
  'AWS_REGION'
];

/**
 * Optional environment variables with defaults
 * @type {Object<string, string>}
 */
const OPTIONAL_ENV_VARS = {
  NODE_ENV: 'development',
  PORT: '3000',
  LOG_LEVEL: 'info',
  REQUEST_TIMEOUT: '5000',
  MAX_RETRIES: '3',
  RETRY_DELAY: '1000'
};

/**
 * Validates required environment variables
 * @throws {Error} If required environment variables are missing
 */
function validateEnvironment() {
  const missing = REQUIRED_ENV_VARS.filter(varName => !process.env[varName]);
  
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}\n` +
      'Please check your .env file or environment configuration.'
    );
  }

  // Set defaults for optional variables
  Object.entries(OPTIONAL_ENV_VARS).forEach(([varName, defaultValue]) => {
    if (!process.env[varName]) {
      process.env[varName] = defaultValue;
    }
  });

  // Validate specific formats
  validateEnvironmentFormats();
}

/**
 * Validates environment variable formats
 * @throws {Error} If environment variables have invalid formats
 */
function validateEnvironmentFormats() {
  // Validate Anthropic API key format
  if (!process.env.ANTHROPIC_API_KEY.startsWith('sk-ant-api03-')) {
    throw new Error('Invalid ANTHROPIC_API_KEY format. Expected format: sk-ant-api03-...');
  }

  // Validate AWS region format
  const awsRegionPattern = /^[a-z]{2}-[a-z]+-\d$/;
  if (!awsRegionPattern.test(process.env.AWS_REGION)) {
    throw new Error(`Invalid AWS_REGION format: ${process.env.AWS_REGION}`);
  }

  // Validate numeric environment variables
  const numericVars = ['PORT', 'REQUEST_TIMEOUT', 'MAX_RETRIES', 'RETRY_DELAY'];
  numericVars.forEach(varName => {
    const value = parseInt(process.env[varName], 10);
    if (isNaN(value) || value < 0) {
      throw new Error(`Invalid ${varName}: must be a positive number`);
    }
  });
}

/**
 * Express middleware to handle validation errors
 * @param {import('express').Request} req - Express request object
 * @param {import('express').Response} res - Express response object
 * @param {import('express').NextFunction} next - Express next function
 */
function handleValidationErrors(req, res, next) {
  const errors = validationResult(req);
  
  if (!errors.isEmpty()) {
    const formattedErrors = errors.array().map(error => ({
      field: error.path || error.param,
      message: error.msg,
      value: error.value
    }));

    return res.status(400).json({
      error: 'Validation failed',
      message: 'Request contains invalid data',
      details: formattedErrors,
      requestId: req.id
    });
  }
  
  next();
}

/**
 * Validation rules for analyze endpoint
 * @type {import('express-validator').ValidationChain[]}
 */
const validateAnalyzeRequest = [
  body('awsCommand')
    .optional()
    .isString()
    .isLength({ min: 1, max: 500 })
    .withMessage('AWS command must be a string between 1 and 500 characters'),
  
  body('includeResources')
    .optional()
    .isArray()
    .withMessage('includeResources must be an array'),
  
  body('includeResources.*')
    .isIn(['ec2', 's3', 'rds', 'vpc', 'iam'])
    .withMessage('Invalid resource type'),
  
  body('options.skipCache')
    .optional()
    .isBoolean()
    .withMessage('skipCache must be boolean'),
  
  body('options.maxTokens')
    .optional()
    .isInt({ min: 1, max: 4000 })
    .withMessage('maxTokens must be between 1 and 4000')
];

/**
 * Validation rules for health check
 * @type {import('express-validator').ValidationChain[]}
 */
const validateHealthRequest = [
  query('detailed')
    .optional()
    .isBoolean()
    .withMessage('detailed parameter must be boolean')
];

/**
 * Validation rules for AWS resource queries
 * @type {import('express-validator').ValidationChain[]}
 */
const validateAwsRequest = [
  param('resourceType')
    .isIn(['ec2', 's3', 'rds', 'vpc', 'iam'])
    .withMessage('Invalid resource type'),
  
  query('region')
    .optional()
    .matches(/^[a-z]{2}-[a-z]+-\d$/)
    .withMessage('Invalid AWS region format'),
  
  query('limit')
    .optional()
    .isInt({ min: 1, max: 1000 })
    .withMessage('Limit must be between 1 and 1000')
];

/**
 * Sanitizes string input to prevent injection attacks
 * @param {string} input - Input string to sanitize
 * @returns {string} Sanitized string
 */
function sanitizeString(input) {
  if (typeof input !== 'string') {
    return '';
  }
  
  return input
    .replace(/[<>\"']/g, '') // Remove potential HTML/script injection chars
    .replace(/[`${}]/g, '') // Remove potential template/command injection chars
    .trim();
}

/**
 * Validates and sanitizes AWS CLI command
 * @param {string} command - AWS CLI command to validate
 * @returns {string} Sanitized command
 * @throws {Error} If command is invalid or potentially dangerous
 */
function validateAwsCommand(command) {
  if (typeof command !== 'string') {
    throw new Error('Command must be a string');
  }
  
  // Trim whitespace
  command = command.trim();
  
  // Must start with 'aws '
  if (!command.startsWith('aws ')) {
    throw new Error('Command must start with "aws "');
  }
  
  // Forbidden commands/operations
  const forbiddenPatterns = [
    /\b(delete|remove|terminate|destroy)\b/i,
    /\b(put|create|run)\b/i,
    /[;&|`$()]/,
    /\-\-force/i,
    /\-\-yes/i,
    /rm\s+\-rf/i
  ];
  
  const hasForbiddenPattern = forbiddenPatterns.some(pattern => pattern.test(command));
  if (hasForbiddenPattern) {
    throw new Error('Command contains forbidden operations');
  }
  
  // Allowed AWS services for read-only operations
  const allowedServices = ['ec2', 's3', 'rds', 'iam', 'vpc', 'cloudformation', 'cloudwatch'];
  const serviceMatch = command.match(/^aws\s+([a-z0-9-]+)/);
  
  if (!serviceMatch || !allowedServices.includes(serviceMatch[1])) {
    throw new Error(`AWS service "${serviceMatch?.[1] || 'unknown'}" not allowed`);
  }
  
  return command;
}

module.exports = {
  validateEnvironment,
  handleValidationErrors,
  validateAnalyzeRequest,
  validateHealthRequest,
  validateAwsRequest,
  sanitizeString,
  validateAwsCommand
};