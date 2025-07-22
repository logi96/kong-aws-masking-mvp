/**
 * @fileoverview Health check routes for Kong AWS Masking MVP
 * @description Provides health check endpoints for system monitoring
 * @author Infrastructure Team
 * @version 1.0.0
 */

'use strict';

const express = require('express');
const logger = require('../utils/logger');

const router = express.Router();

/**
 * @typedef {Object} HealthResponse
 * @property {string} status - Health status (healthy/unhealthy)
 * @property {string} timestamp - ISO timestamp of health check
 * @property {string} service - Service identifier
 * @property {Object} [details] - Additional health details for detailed checks
 */

/**
 * Basic health check endpoint
 * @description Returns simple health status for load balancer checks
 * @route GET /health
 * @returns {HealthResponse} Health status response
 */
router.get('/', (req, res) => {
  logger.debug('Health check requested', { requestId: req.id });
  
  /** @type {HealthResponse} */
  const healthResponse = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'kong-aws-masking-backend'
  };
  
  res.json(healthResponse);
});

/**
 * Detailed health check endpoint
 * @description Returns comprehensive health information including dependencies
 * @route GET /health/detailed
 * @returns {HealthResponse} Detailed health status with dependency checks
 */
router.get('/detailed', async (req, res) => {
  logger.debug('Detailed health check requested', { requestId: req.id });
  
  try {
    /** @type {Object} */
    const details = await performHealthChecks();
    
    /** @type {HealthResponse} */
    const healthResponse = {
      status: details.allHealthy ? 'healthy' : 'degraded',
      timestamp: new Date().toISOString(),
      service: 'kong-aws-masking-backend',
      details
    };
    
    const statusCode = details.allHealthy ? 200 : 503;
    res.status(statusCode).json(healthResponse);
    
  } catch (error) {
    logger.error('Health check failed', { 
      requestId: req.id, 
      error: error.message 
    });
    
    res.status(500).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      service: 'kong-aws-masking-backend',
      error: error.message
    });
  }
});

/**
 * Perform comprehensive health checks
 * @description Checks all system dependencies and external services
 * @returns {Promise<Object>} Health check results
 * @private
 */
async function performHealthChecks() {
  const checks = {
    memory: checkMemoryUsage(),
    environment: checkEnvironmentVariables(),
    aws: await checkAWSConnectivity(),
    claude: checkClaudeAPIConfiguration()
  };
  
  const allHealthy = Object.values(checks).every(check => check.healthy);
  
  return {
    allHealthy,
    checks,
    timestamp: new Date().toISOString()
  };
}

/**
 * Check memory usage
 * @description Monitors current memory usage against limits
 * @returns {Object} Memory health status
 * @private
 */
function checkMemoryUsage() {
  const memUsage = process.memoryUsage();
  const memLimitMB = 256; // MB limit from docker config
  const currentMB = memUsage.heapUsed / 1024 / 1024;
  
  return {
    healthy: currentMB < memLimitMB * 0.8, // 80% threshold
    details: {
      currentMB: Math.round(currentMB),
      limitMB: memLimitMB,
      percentage: Math.round((currentMB / memLimitMB) * 100)
    }
  };
}

/**
 * Check required environment variables
 * @description Validates all required environment variables are present
 * @returns {Object} Environment variable health status
 * @private
 */
function checkEnvironmentVariables() {
  const required = ['ANTHROPIC_API_KEY', 'AWS_REGION'];
  const missing = required.filter(key => !process.env[key]);
  
  return {
    healthy: missing.length === 0,
    details: {
      required: required.length,
      missing: missing.length,
      missingVars: missing
    }
  };
}

/**
 * Check AWS connectivity
 * @description Tests basic AWS CLI functionality
 * @returns {Promise<Object>} AWS connectivity status
 * @private
 */
async function checkAWSConnectivity() {
  try {
    // Simple AWS STS call to verify credentials
    const { exec } = require('child_process');
    const { promisify } = require('util');
    const execAsync = promisify(exec);
    
    await execAsync('aws sts get-caller-identity', { timeout: 5000 });
    
    return {
      healthy: true,
      details: { message: 'AWS credentials valid' }
    };
  } catch (error) {
    return {
      healthy: false,
      details: { 
        message: 'AWS credentials check failed',
        error: error.message 
      }
    };
  }
}

/**
 * Check Claude API configuration
 * @description Validates Claude API key format and configuration
 * @returns {Object} Claude API configuration status
 * @private
 */
function checkClaudeAPIConfiguration() {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  
  if (!apiKey) {
    return {
      healthy: false,
      details: { message: 'Anthropic API key not configured' }
    };
  }
  
  if (!apiKey.startsWith('sk-ant-api03-')) {
    return {
      healthy: false,
      details: { message: 'Invalid Anthropic API key format' }
    };
  }
  
  return {
    healthy: true,
    details: { 
      message: 'Claude API key configured',
      keyLength: apiKey.length
    }
  };
}

module.exports = router;