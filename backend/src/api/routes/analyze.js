/**
 * @fileoverview /analyze 엔드포인트 라우트 핸들러
 * @description AWS 리소스 분석 및 Claude API 통합 (TDD GREEN 단계)
 */

'use strict';

const express = require('express');
const claudeService = require('../../services/claude/claudeService');
const { AppError } = require('../middlewares/errorHandler');

const router = express.Router();

/**
 * @typedef {Object} AnalyzeRequest
 * @property {string[]} resources - AWS resource types to collect
 * @property {Object} [options] - Analysis options
 * @property {string} [options.analysisType] - Type of analysis to perform
 * @property {string} [options.region] - AWS region override
 * @property {boolean} [options.skipCache] - Skip cached results
 * @property {number} [options.timeout] - Request timeout in milliseconds
 */

/**
 * @typedef {Object} AnalyzeResponse
 * @property {boolean} success - Request success status
 * @property {Object} data - Analysis results
 * @property {Object} data.awsResources - Collected AWS resources
 * @property {Object} data.analysis - Claude analysis results
 * @property {string} timestamp - Response timestamp
 * @property {number} duration - Request duration in milliseconds
 */

/**
 * @typedef {Object} ErrorResponse
 * @property {boolean} success - Always false for errors
 * @property {string} error - Error message
 */

/**
 * Request validation middleware for /analyze endpoint
 * @param {express.Request<{}, {}, AnalyzeRequest>} req - Express request object
 * @param {express.Response<AnalyzeResponse | ErrorResponse>} res - Express response object  
 * @param {express.NextFunction} next - Express next function
 */
function validateAnalyzeRequest(req, res, next) {
  const { resources, options = {} } = req.body;

  // Validate resources array
  if (!resources) {
    return res.status(400).json({
      success: false,
      error: 'Resources array is required'
    });
  }

  if (!Array.isArray(resources)) {
    return res.status(400).json({
      success: false,
      error: 'Resources must be an array'
    });
  }

  if (resources.length === 0) {
    return res.status(400).json({
      success: false,
      error: 'At least one resource type is required'
    });
  }

  // Validate supported resource types
  const supportedResources = ['ec2', 's3', 'rds', 'vpc', 'iam'];
  const invalidResources = resources.filter(r => !supportedResources.includes(r));
  
  if (invalidResources.length > 0) {
    return res.status(400).json({
      success: false,
      error: `Unsupported resource types: ${invalidResources.join(', ')}`
    });
  }

  // Validate analysis type if provided
  if (options.analysisType) {
    const validTypes = ['security_and_optimization', 'security_only', 'cost_only'];
    if (!validTypes.includes(options.analysisType)) {
      return res.status(400).json({
        success: false,
        error: `Invalid analysis type. Must be one of: ${validTypes.join(', ')}`
      });
    }
  }

  next();
}

/**
 * Handle AWS resource analysis requests
 * @param {express.Request<{}, {}, AnalyzeRequest>} req - Express request object
 * @param {express.Response<AnalyzeResponse>} res - Express response object
 * @param {express.NextFunction} next - Express next function
 */
async function handleAnalyzeRequest(req, res, next) {
  const startTime = Date.now();
  
  try {
    const { resources, context, options = {} } = req.body;
    
    // Set timeout to 30 seconds for Claude API
    const timeout = Math.min(options.timeout || 30000, 30000);
    const timeoutId = setTimeout(() => {
      throw new AppError('Request timeout after 30 seconds', 500, 'TIMEOUT_ERROR');
    }, timeout);

    let analysis;

    try {
      // MODIFIED: Skip AWS CLI execution - use context text directly
      // This follows user directive: "AWS CLI 실행하라고 한적이 없고"
      console.log('Analyzing context text with resource types:', resources);
      
      // Step 1: Analyze context text with Claude API (data will be masked by Kong Gateway)
      console.log('Sending data to Claude API for analysis');
      analysis = await claudeService.analyzeAwsData({
        contextText: context || 'No context provided',
        requestedResourceTypes: resources
      }, {
        analysisType: options.analysisType,
        maxTokens: 2048,
        systemPrompt: options.systemPrompt
      });

      clearTimeout(timeoutId);

    } catch (error) {
      clearTimeout(timeoutId);
      
      // Handle specific service errors
      if (error.message.includes('timeout')) {
        throw new AppError('Request timeout after 30 seconds', 500, 'TIMEOUT_ERROR');
      }
      
      if (error.message.includes('Claude') || error.message.includes('API')) {
        throw new AppError(`Claude API error: ${error.message}`, 500, 'CLAUDE_ERROR');
      }
      
      throw error;
    }

    const duration = Date.now() - startTime;

    // Success response - Only return analysis (no AWS resource collection)
    const response = {
      success: true,
      data: {
        analysis
      },
      metadata: {
        contextLength: context ? context.length : 0,
        analysisType: options.analysisType || 'security_and_optimization',
        timestamp: new Date().toISOString()
      },
      timestamp: new Date().toISOString(),
      duration
    };

    res.status(200).json(response);

  } catch (error) {
    next(error);
  }
}

// Route definition
router.post('/', validateAnalyzeRequest, handleAnalyzeRequest);

module.exports = { 
  router,
  validateAnalyzeRequest,
  handleAnalyzeRequest
};