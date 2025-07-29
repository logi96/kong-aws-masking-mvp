/**
 * @fileoverview Health check routes with comprehensive system status monitoring
 * @module routes/health
 */

const express = require('express');
const router = express.Router();
const healthCheckService = require('../services/health/healthCheckService');
const logger = require('../utils/logger');

/**
 * @api {get} /health Basic health check
 * @apiName GetHealth
 * @apiGroup Health
 * @apiDescription Returns basic health status of the backend service
 * 
 * @apiSuccess {String} status Service status (healthy/unhealthy)
 * @apiSuccess {String} timestamp Current timestamp
 * @apiSuccess {Object} service Service information
 * @apiSuccess {Number} uptime Service uptime in seconds
 */
router.get('/', async (req, res) => {
  try {
    const health = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      service: {
        name: 'nginx-kong-claude-enterprise2-backend',
        version: '1.0.0',
        environment: process.env.NODE_ENV || 'development'
      },
      uptime: process.uptime()
    };
    
    res.json(health);
  } catch (error) {
    logger.error('Health check error:', error);
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

/**
 * @api {get} /health/detailed Detailed health check
 * @apiName GetDetailedHealth
 * @apiGroup Health
 * @apiDescription Returns comprehensive health status including all dependencies
 * 
 * @apiSuccess {String} status Overall service status
 * @apiSuccess {Object} dependencies Status of each dependency
 * @apiSuccess {Object} system System information
 * @apiSuccess {Object} metrics Service metrics
 */
router.get('/detailed', async (req, res) => {
  try {
    const detailedHealth = await healthCheckService.getDetailedHealth();
    
    // Determine overall status
    const overallStatus = detailedHealth.dependencies.every(dep => dep.status === 'healthy') 
      ? 'healthy' 
      : 'degraded';
    
    res.status(overallStatus === 'healthy' ? 200 : 503).json({
      status: overallStatus,
      timestamp: new Date().toISOString(),
      ...detailedHealth
    });
  } catch (error) {
    logger.error('Detailed health check error:', error);
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message,
      dependencies: []
    });
  }
});

/**
 * @api {get} /health/live Kubernetes liveness probe
 * @apiName GetLiveness
 * @apiGroup Health
 * @apiDescription Simple liveness check for Kubernetes
 * 
 * @apiSuccess {String} status Always returns "ok" if service is alive
 */
router.get('/live', (req, res) => {
  res.json({ status: 'ok' });
});

/**
 * @api {get} /health/ready Kubernetes readiness probe
 * @apiName GetReadiness
 * @apiGroup Health
 * @apiDescription Readiness check for Kubernetes - checks critical dependencies
 * 
 * @apiSuccess {String} status Returns "ready" if all critical services are available
 */
router.get('/ready', async (req, res) => {
  try {
    const isReady = await healthCheckService.checkReadiness();
    
    if (isReady) {
      res.json({ status: 'ready' });
    } else {
      res.status(503).json({ status: 'not ready' });
    }
  } catch (error) {
    logger.error('Readiness check error:', error);
    res.status(503).json({ 
      status: 'not ready',
      error: error.message 
    });
  }
});

/**
 * @api {get} /health/dependencies Check specific dependency
 * @apiName GetDependencyHealth
 * @apiGroup Health
 * @apiDescription Check health of a specific dependency
 * 
 * @apiParam {String} name Dependency name (kong, redis, claude)
 * 
 * @apiSuccess {String} name Dependency name
 * @apiSuccess {String} status Dependency status
 * @apiSuccess {Object} details Additional details
 */
router.get('/dependencies/:name', async (req, res) => {
  const { name } = req.params;
  const validDependencies = ['kong', 'redis', 'claude'];
  
  if (!validDependencies.includes(name)) {
    return res.status(400).json({
      error: 'Invalid dependency name',
      validDependencies
    });
  }
  
  try {
    const dependencyHealth = await healthCheckService.checkDependency(name);
    res.json(dependencyHealth);
  } catch (error) {
    logger.error(`Dependency health check error for ${name}:`, error);
    res.status(503).json({
      name,
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * @api {get} /health/metrics Service metrics
 * @apiName GetHealthMetrics
 * @apiGroup Health
 * @apiDescription Returns service performance metrics
 * 
 * @apiSuccess {Object} memory Memory usage statistics
 * @apiSuccess {Object} cpu CPU usage statistics
 * @apiSuccess {Object} requests Request statistics
 */
router.get('/metrics', async (req, res) => {
  try {
    const metrics = await healthCheckService.getMetrics();
    res.json(metrics);
  } catch (error) {
    logger.error('Metrics collection error:', error);
    res.status(500).json({
      error: 'Failed to collect metrics',
      message: error.message
    });
  }
});

module.exports = router;