/**
 * @fileoverview Simple Claude API proxy routes for Kong AWS Masking MVP
 * @description Backend API serves as simple proxy - Kong handles masking/unmasking
 * @author Infrastructure Team
 * @version 2.0.0 - SECURITY COMPLIANT (AWS CLI DISABLED)
 */

'use strict';

const express = require('express');
const { body, validationResult } = require('express-validator');
const logger = require('../../../utils/logger');
const claudeService = require('../../services/claude/claudeService');
const { handleValidationErrors } = require('../../../utils/validation');

const router = express.Router();

/**
 * @typedef {Object} AnalysisRequest
 * @property {string} contextText - Text content containing AWS resources to analyze
 * @property {Object} [options] - Analysis options
 * @property {string} [options.analysisType] - Type of analysis (security_only, etc.)
 * @property {number} [options.maxTokens] - Max Claude API tokens
 */

/**
 * @typedef {Object} AnalysisResponse
 * @property {boolean} success - Response success status
 * @property {Object} [analysis] - Claude API analysis results
 * @property {string} [error] - Error message if failed
 * @property {string} timestamp - Response timestamp
 * @property {string} requestId - Request correlation ID
 */

/**
 * Validation rules for analysis requests
 * @type {import('express-validator').ValidationChain[]}
 */
const validateAnalysisRequest = [
  body('contextText')
    .optional()
    .isString()
    .isLength({ min: 1, max: 10000 })
    .withMessage('contextText must be 1-10000 characters'),
    
  body('options.analysisType')
    .optional()
    .isIn(['security_and_optimization', 'security_only', 'cost_only'])
    .withMessage('analysisType must be one of: security_and_optimization, security_only, cost_only'),
    
  body('options.maxTokens')
    .optional()
    .isInt({ min: 10, max: 5000 })
    .withMessage('maxTokens must be between 10 and 5000')
];

/**
 * Analyze AWS resources endpoint - SIMPLE CLAUDE API PROXY
 * @description Forwards text content to Claude API through Kong (masking handled by Kong)
 * @route POST /analyze
 * @param {AnalysisRequest} req.body - Analysis request parameters
 * @returns {AnalysisResponse} Analysis results from Claude API
 */
router.post('/', validateAnalysisRequest, handleValidationErrors, async (req, res) => {
  const startTime = Date.now();
  
  logger.info('Claude API proxy request received', {
    requestId: req.id,
    hasContextText: !!req.body.contextText,
    analysisType: req.body.options?.analysisType
  });
  
  try {
    // Use query or contextText from request, fallback to default
    const contextText = req.body.query || req.body.contextText || 
      'Please analyze this AWS infrastructure for security recommendations.';
    
    const analysisOptions = {
      analysisType: req.body.options?.analysisType || 'security_only',
      maxTokens: req.body.options?.maxTokens || 2048,
      ...req.body.options
    };
    
    // Forward to Claude API through Kong (Kong handles masking)
    logger.debug('Forwarding to Claude API through Kong', { requestId: req.id });
    const claudeAnalysis = await claudeService.analyzeAwsData({ 
      contextText: contextText 
    }, analysisOptions);
    
    
    const duration = Date.now() - startTime;
    
    logger.performance('claude_proxy_request', duration, {
      requestId: req.id,
      analysisType: analysisOptions.analysisType,
      tokenCount: claudeAnalysis.usage?.total_tokens || 0
    });
    
    /** @type {AnalysisResponse} */
    const response = {
      success: true,
      analysis: claudeAnalysis,
      metadata: {
        analysisType: analysisOptions.analysisType,
        duration,
        timestamp: new Date().toISOString()
      },
      timestamp: new Date().toISOString(),
      requestId: req.id
    };
    
    res.json(response);
    
  } catch (error) {
    const duration = Date.now() - startTime;
    
    logger.error('Claude API proxy request failed', {
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
      success: false,
      error: error.message,
      timestamp: new Date().toISOString(),
      requestId: req.id
    });
  }
});

/**
 * Get masking logs endpoint - Kong 마스킹 로그 조회
 * @description Kong에서 Redis로 발행한 마스킹 정보를 클라이언트에게 제공
 * @route GET /analyze/masking-logs
 * @param {number} [req.query.limit] - 조회할 로그 개수 (기본: 50)
 * @returns {Object} 마스킹 로그 목록과 통계
 */
router.get('/masking-logs', (req, res) => {
  const startTime = Date.now();
  
  logger.info('Masking logs request received', {
    requestId: req.id,
    limit: req.query.limit
  });
  
  try {
    // Redis Event Subscriber 인스턴스 가져오기
    const redisSubscriber = req.app.locals.redisSubscriber;
    
    if (!redisSubscriber) {
      return res.status(503).json({
        success: false,
        error: 'Redis Event Subscriber not available',
        timestamp: new Date().toISOString(),
        requestId: req.id
      });
    }
    
    // 로그 개수 제한 파싱
    const limit = req.query.limit ? parseInt(req.query.limit, 10) : 50;
    
    if (isNaN(limit) || limit < 0) {
      return res.status(400).json({
        success: false,
        error: 'Invalid limit parameter. Must be a non-negative number.',
        timestamp: new Date().toISOString(),
        requestId: req.id
      });
    }
    
    // 마스킹 로그 조회
    const maskingLogs = redisSubscriber.getMaskingLogs(limit);
    
    const duration = Date.now() - startTime;
    
    logger.performance('masking_logs_request', duration, {
      requestId: req.id,
      logsReturned: maskingLogs.logs.length,
      limit
    });
    
    res.json({
      success: true,
      data: maskingLogs,
      metadata: {
        duration,
        timestamp: new Date().toISOString()
      },
      requestId: req.id
    });
    
  } catch (error) {
    const duration = Date.now() - startTime;
    
    logger.error('Masking logs request failed', {
      requestId: req.id,
      error: error.message,
      stack: error.stack,
      duration
    });
    
    res.status(500).json({
      success: false,
      error: error.message,
      timestamp: new Date().toISOString(),
      requestId: req.id
    });
  }
});

module.exports = { 
  router
};