/**
 * @fileoverview Analyze routes for AWS resource analysis
 * @module routes/analyze
 */

const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const awsService = require('../services/aws/awsService');
const claudeService = require('../services/claude/claudeService');
const maskingService = require('../services/masking/maskingService');
const logger = require('../utils/logger');
const { asyncHandler, ApiError } = require('../middlewares/errorHandler');
const { authenticateRequest, requireScope } = require('../middlewares/auth');

/**
 * Validation middleware for analyze request
 */
const validateAnalyzeRequest = [
  body('resources')
    .isArray()
    .withMessage('Resources must be an array')
    .notEmpty()
    .withMessage('Resources array cannot be empty'),
  body('resources.*')
    .isString()
    .withMessage('Each resource must be a string')
    .isIn(['ec2', 's3', 'rds', 'lambda', 'iam', 'vpc'])
    .withMessage('Invalid resource type'),
  body('options')
    .optional()
    .isObject()
    .withMessage('Options must be an object'),
  body('options.analysisType')
    .optional()
    .isIn(['security', 'cost', 'performance', 'all'])
    .withMessage('Invalid analysis type')
];

/**
 * @api {post} /analyze Analyze AWS resources
 * @apiName AnalyzeResources
 * @apiGroup Analyze
 * @apiDescription Analyze AWS resources using Claude API
 * 
 * @apiBody {String[]} resources Array of resource types to analyze
 * @apiBody {Object} [options] Analysis options
 * @apiBody {String} [options.analysisType="all"] Type of analysis
 * 
 * @apiSuccess {Object} analysis Analysis results
 * @apiSuccess {String} requestId Unique request identifier
 * @apiSuccess {Object} metadata Request metadata
 */
router.post('/', authenticateRequest, requireScope(['read:aws', 'analyze']), validateAnalyzeRequest, asyncHandler(async (req, res) => {
  // Check validation results
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    throw new ApiError(400, 'Validation failed', errors.array());
  }

  const { resources, options = {} } = req.body;
  const requestId = req.id || require('uuid').v4();

  logger.info('Analysis request received', { requestId, resources, options });

  try {
    // 1. Fetch AWS resources
    const awsData = await awsService.fetchResources(resources);
    
    // 2. Send to Kong for masking (Kong will forward to Claude)
    const analysisResult = await claudeService.analyzeResources(awsData, options);
    
    // 3. Return results
    res.json({
      requestId,
      analysis: analysisResult,
      metadata: {
        resources: resources,
        timestamp: new Date().toISOString(),
        processingTime: analysisResult.processingTime || null
      }
    });
  } catch (error) {
    logger.error('Analysis failed', { requestId, error: error.message });
    throw new ApiError(
      error.statusCode || 500,
      error.message || 'Analysis failed',
      error.details
    );
  }
}));

/**
 * @api {get} /analyze/status/:requestId Get analysis status
 * @apiName GetAnalysisStatus
 * @apiGroup Analyze
 * @apiDescription Get status of a previous analysis request
 * 
 * @apiParam {String} requestId Request identifier
 * 
 * @apiSuccess {String} requestId Request identifier
 * @apiSuccess {String} status Analysis status
 * @apiSuccess {Object} [result] Analysis result if completed
 */
router.get('/status/:requestId', authenticateRequest, asyncHandler(async (req, res) => {
  const { requestId } = req.params;
  
  // This would typically check a cache or database
  // For now, return a mock response
  res.json({
    requestId,
    status: 'completed',
    message: 'Analysis status tracking not yet implemented'
  });
}));

/**
 * @api {get} /analyze/resources List supported resources
 * @apiName ListSupportedResources
 * @apiGroup Analyze
 * @apiDescription Get list of supported AWS resource types
 * 
 * @apiSuccess {String[]} resources List of supported resource types
 * @apiSuccess {Object} details Resource type descriptions
 */
router.get('/resources', (req, res) => {
  res.json({
    resources: ['ec2', 's3', 'rds', 'lambda', 'iam', 'vpc'],
    details: {
      ec2: 'EC2 instances and related resources',
      s3: 'S3 buckets and objects',
      rds: 'RDS databases',
      lambda: 'Lambda functions',
      iam: 'IAM roles and policies',
      vpc: 'VPC and networking resources'
    }
  });
});

/**
 * @api {get} /analyze/masking/stats Get masking statistics
 * @apiName GetMaskingStats
 * @apiGroup Analyze
 * @apiDescription Get current masking statistics from Redis
 * 
 * @apiSuccess {Object} statistics Masking statistics
 * @apiSuccess {Object} statistics.total Total masking counts
 * @apiSuccess {Object} statistics.daily Daily masking counts
 * @apiSuccess {Object} statistics.cache Cache hit/miss statistics
 */
router.get('/masking/stats', authenticateRequest, asyncHandler(async (req, res) => {
  try {
    const stats = await maskingService.getStatistics();
    res.json({
      success: true,
      statistics: stats,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Failed to get masking statistics', { error: error.message });
    throw new ApiError(500, 'Failed to retrieve masking statistics');
  }
}));

/**
 * @api {post} /analyze/masking/validate Validate masking
 * @apiName ValidateMasking
 * @apiGroup Analyze
 * @apiDescription Validate masking consistency between original and masked text
 * 
 * @apiBody {String} original Original text with AWS resources
 * @apiBody {String} masked Masked text to validate
 * 
 * @apiSuccess {Boolean} valid Whether masking is valid
 * @apiSuccess {Object} details Validation details
 */
router.post('/masking/validate', [
  body('original').isString().notEmpty().withMessage('Original text is required'),
  body('masked').isString().notEmpty().withMessage('Masked text is required')
], asyncHandler(async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    throw new ApiError(400, 'Validation failed', errors.array());
  }

  const { original, masked } = req.body;
  
  try {
    const validation = await maskingService.validateMasking(original, masked);
    res.json({
      success: true,
      validation,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Masking validation failed', { error: error.message });
    throw new ApiError(500, 'Masking validation failed');
  }
}));

/**
 * @api {post} /analyze/masking/cleanup Cleanup expired mappings
 * @apiName CleanupMappings
 * @apiGroup Analyze
 * @apiDescription Clean up expired masking mappings from Redis
 * 
 * @apiSuccess {Number} cleaned Number of cleaned mappings
 */
router.post('/masking/cleanup', asyncHandler(async (req, res) => {
  try {
    const cleaned = await maskingService.cleanupExpiredMappings();
    logger.info('Cleaned up expired mappings', { count: cleaned });
    
    res.json({
      success: true,
      cleaned,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Cleanup failed', { error: error.message });
    throw new ApiError(500, 'Failed to cleanup expired mappings');
  }
}));

module.exports = router;