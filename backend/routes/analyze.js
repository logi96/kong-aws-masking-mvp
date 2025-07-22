/**
 * @fileoverview AWS resource analysis routes for Kong AWS Masking MVP
 * @description Handles AWS resource analysis requests with Claude API integration
 * @author Infrastructure Team
 * @version 1.0.0
 */

'use strict';

const express = require('express');
const { body, validationResult } = require('express-validator');
const logger = require('../utils/logger');
const awsService = require('../src/services/aws/awsService');
const claudeService = require('../src/services/claude/claudeService');
const { handleValidationErrors } = require('../utils/validation');

const router = express.Router();

/**
 * @typedef {Object} AnalysisRequest
 * @property {string[]} [resources] - AWS resource types to analyze
 * @property {string} [command] - Custom AWS CLI command
 * @property {Object} [options] - Analysis options
 * @property {boolean} [options.skipCache] - Skip cached results
 * @property {number} [options.maxTokens] - Max Claude API tokens
 */

/**
 * @typedef {Object} AnalysisResponse
 * @property {string} status - Response status (success/error)
 * @property {Object} analysis - Claude API analysis results
 * @property {Object} [metadata] - Request metadata
 * @property {string} timestamp - Response timestamp
 * @property {string} requestId - Request correlation ID
 */

/**
 * Validation rules for analysis requests
 * @type {import('express-validator').ValidationChain[]}
 */
const validateAnalysisRequest = [
  body('resources')
    .optional()
    .isArray()
    .withMessage('Resources must be an array')
    .custom((resources) => {
      const validResources = ['ec2', 's3', 'rds', 'vpc', 'iam'];
      const invalid = resources.filter(r => !validResources.includes(r));
      if (invalid.length > 0) {
        throw new Error(`Invalid resource types: ${invalid.join(', ')}`);
      }
      return true;
    }),
    
  body('command')
    .optional()
    .isString()
    .isLength({ min: 1, max: 500 })
    .withMessage('Command must be 1-500 characters')
    .matches(/^aws\s+/)
    .withMessage('Command must start with "aws "'),
    
  body('options.skipCache')
    .optional()
    .isBoolean()
    .withMessage('skipCache must be boolean'),
    
  body('options.maxTokens')
    .optional()
    .isInt({ min: 100, max: 4000 })
    .withMessage('maxTokens must be between 100 and 4000')
];

/**
 * Analyze AWS resources endpoint
 * @description Main endpoint for AWS resource analysis
 * @route POST /analyze
 * @param {AnalysisRequest} req.body - Analysis request parameters
 * @returns {AnalysisResponse} Analysis results from Claude API
 */
router.post('/', validateAnalysisRequest, handleValidationErrors, async (req, res) => {
  const startTime = Date.now();
  
  logger.info('Analysis request received', {
    requestId: req.id,
    resources: req.body.resources,
    hasCustomCommand: !!req.body.command
  });
  
  try {
    /** @type {AnalysisRequest} */
    const analysisRequest = {
      resources: req.body.resources || ['ec2', 's3', 'rds'],
      command: req.body.command,
      options: {
        skipCache: req.body.options?.skipCache || false,
        maxTokens: req.body.options?.maxTokens || 2048,
        ...req.body.options
      }
    };
    
    // Step 1: Collect AWS resource data
    logger.debug('Collecting AWS resources', { requestId: req.id });
    const awsData = await awsService.collectResources(analysisRequest);
    
    // Step 2: Send to Claude API through Kong (masking handled by Kong plugin)
    logger.debug('Sending data to Claude API', { requestId: req.id });
    const claudeAnalysis = await claudeService.analyzeAwsData(awsData, analysisRequest.options);
    
    const duration = Date.now() - startTime;
    
    logger.performance('analysis_request', duration, {
      requestId: req.id,
      resourceTypes: analysisRequest.resources,
      tokenCount: claudeAnalysis.usage?.total_tokens || 0
    });
    
    /** @type {AnalysisResponse} */
    const response = {
      status: 'success',
      analysis: claudeAnalysis,
      metadata: {
        resourceTypes: analysisRequest.resources,
        duration,
        timestamp: new Date().toISOString()
      },
      timestamp: new Date().toISOString(),
      requestId: req.id
    };
    
    res.json(response);
    
  } catch (error) {
    const duration = Date.now() - startTime;
    
    logger.error('Analysis request failed', {
      requestId: req.id,
      error: error.message,
      stack: error.stack,
      duration
    });
    
    // Determine appropriate error status code
    let statusCode = 500;
    if (error.name === 'ValidationError') {
      statusCode = 400;
    } else if (error.name === 'UnauthorizedError') {
      statusCode = 401;
    } else if (error.name === 'TimeoutError') {
      statusCode = 504;
    }
    
    res.status(statusCode).json({
      status: 'error',
      error: {
        message: error.message,
        type: error.name || 'UnknownError'
      },
      timestamp: new Date().toISOString(),
      requestId: req.id
    });
  }
});

/**
 * Get analysis status endpoint
 * @description Check status of long-running analysis requests
 * @route GET /analyze/:requestId/status
 * @param {string} req.params.requestId - Request ID to check
 * @returns {Object} Analysis status information
 */
router.get('/:requestId/status', (req, res) => {
  const { requestId } = req.params;
  
  logger.debug('Status check requested', { 
    requestId: req.id,
    targetRequestId: requestId 
  });
  
  // Note: In MVP, we don't support async analysis
  // This endpoint is placeholder for future enhancement
  res.json({
    requestId,
    status: 'not_supported',
    message: 'Async analysis not supported in MVP',
    timestamp: new Date().toISOString()
  });
});

/**
 * List supported AWS resource types endpoint
 * @description Returns available AWS resource types for analysis
 * @route GET /analyze/resources
 * @returns {Object} Supported resource types and their descriptions
 */
router.get('/resources', (req, res) => {
  logger.debug('Resource types requested', { requestId: req.id });
  
  const resourceTypes = {
    ec2: {
      name: 'EC2 Instances',
      description: 'Virtual server instances',
      maskingPattern: 'i-[0-9a-f]+ -> EC2_001, EC2_002...'
    },
    s3: {
      name: 'S3 Buckets',
      description: 'Object storage buckets',
      maskingPattern: 'bucket-name -> BUCKET_001, BUCKET_002...'
    },
    rds: {
      name: 'RDS Instances',
      description: 'Relational database instances',
      maskingPattern: 'db-instance -> RDS_001, RDS_002...'
    },
    vpc: {
      name: 'VPC Networks',
      description: 'Virtual private clouds',
      maskingPattern: 'vpc-[0-9a-f]+ -> VPC_001, VPC_002...'
    },
    iam: {
      name: 'IAM Resources',
      description: 'Identity and access management',
      maskingPattern: 'role/user names -> IAM_ROLE_001...'
    }
  };
  
  res.json({
    supported: Object.keys(resourceTypes),
    details: resourceTypes,
    timestamp: new Date().toISOString()
  });
});

/**
 * Validate AWS command endpoint
 * @description Test and validate AWS CLI commands before execution
 * @route POST /analyze/validate-command
 * @param {Object} req.body - Command validation request
 * @param {string} req.body.command - AWS CLI command to validate
 * @returns {Object} Command validation results
 */
router.post('/validate-command', 
  body('command')
    .isString()
    .isLength({ min: 1, max: 500 })
    .matches(/^aws\s+/)
    .withMessage('Command must start with "aws "'),
  handleValidationErrors,
  (req, res) => {
    logger.debug('Command validation requested', { requestId: req.id });
    
    try {
      const { validateAwsCommand } = require('../utils/validation');
      const sanitizedCommand = validateAwsCommand(req.body.command);
      
      res.json({
        valid: true,
        command: sanitizedCommand,
        message: 'Command validation passed',
        timestamp: new Date().toISOString()
      });
      
    } catch (error) {
      logger.warning('Command validation failed', {
        requestId: req.id,
        command: req.body.command,
        error: error.message
      });
      
      res.status(400).json({
        valid: false,
        error: error.message,
        timestamp: new Date().toISOString()
      });
    }
  }
);

module.exports = router;