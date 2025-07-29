/**
 * @fileoverview Health check service for monitoring system dependencies
 * @module services/health/healthCheckService
 */

const axios = require('axios');
const Redis = require('ioredis');
const Anthropic = require('@anthropic-ai/sdk');
const os = require('os');
const logger = require('../../utils/logger');

class HealthCheckService {
  constructor() {
    this.checks = new Map();
    this.lastCheckResults = new Map();
    this.checkInterval = parseInt(process.env.HEALTH_CHECK_INTERVAL) || 30000;
    this.checkTimeout = parseInt(process.env.HEALTH_CHECK_TIMEOUT) || 5000;
    this.isMonitoring = false;
  }

  /**
   * Start background health monitoring
   */
  startMonitoring() {
    if (this.isMonitoring) return;
    
    this.isMonitoring = true;
    this.runHealthChecks();
    
    // Schedule periodic health checks
    this.healthCheckTimer = setInterval(() => {
      this.runHealthChecks();
    }, this.checkInterval);
    
    logger.info(`Health monitoring started with interval: ${this.checkInterval}ms`);
  }

  /**
   * Stop background health monitoring
   */
  stopMonitoring() {
    if (this.healthCheckTimer) {
      clearInterval(this.healthCheckTimer);
      this.healthCheckTimer = null;
    }
    this.isMonitoring = false;
    logger.info('Health monitoring stopped');
  }

  /**
   * Run all health checks
   */
  async runHealthChecks() {
    const checks = [
      this.checkKong(),
      this.checkRedis(),
      this.checkClaude()
    ];
    
    const results = await Promise.allSettled(checks);
    
    results.forEach((result, index) => {
      const checkName = ['kong', 'redis', 'claude'][index];
      if (result.status === 'fulfilled') {
        this.lastCheckResults.set(checkName, {
          ...result.value,
          lastChecked: new Date().toISOString()
        });
      } else {
        this.lastCheckResults.set(checkName, {
          status: 'unhealthy',
          error: result.reason.message,
          lastChecked: new Date().toISOString()
        });
      }
    });
  }

  /**
   * Check Kong Gateway health
   * @returns {Promise<Object>} Kong health status
   */
  async checkKong() {
    const startTime = Date.now();
    
    try {
      // Check Kong Admin API
      const adminUrl = process.env.KONG_ADMIN_URL || 'http://kong:8001';
      const adminResponse = await axios.get(`${adminUrl}/status`, {
        timeout: this.checkTimeout
      });
      
      // Check Kong Proxy
      const proxyUrl = process.env.KONG_PROXY_URL || 'http://kong:8000';
      const proxyResponse = await axios.get(`${proxyUrl}/`, {
        timeout: this.checkTimeout,
        validateStatus: (status) => status < 500
      });
      
      const responseTime = Date.now() - startTime;
      
      return {
        name: 'kong',
        status: 'healthy',
        responseTime,
        details: {
          admin: {
            status: 'healthy',
            database: adminResponse.data.database,
            server: adminResponse.data.server
          },
          proxy: {
            status: proxyResponse.status < 400 ? 'healthy' : 'degraded',
            statusCode: proxyResponse.status
          }
        }
      };
    } catch (error) {
      const responseTime = Date.now() - startTime;
      logger.error('Kong health check failed:', error);
      
      return {
        name: 'kong',
        status: 'unhealthy',
        responseTime,
        error: error.message,
        details: {
          admin: { status: 'unhealthy' },
          proxy: { status: 'unhealthy' }
        }
      };
    }
  }

  /**
   * Check Redis health
   * @returns {Promise<Object>} Redis health status
   */
  async checkRedis() {
    const startTime = Date.now();
    const redis = new Redis({
      host: process.env.REDIS_HOST || 'redis',
      port: parseInt(process.env.REDIS_PORT) || 6379,
      password: process.env.REDIS_PASSWORD,
      db: parseInt(process.env.REDIS_DB) || 0,
      connectTimeout: this.checkTimeout,
      lazyConnect: true
    });
    
    try {
      await redis.connect();
      const pingResponse = await redis.ping();
      const info = await redis.info('server');
      await redis.quit();
      
      const responseTime = Date.now() - startTime;
      
      // Parse Redis version from info
      const versionMatch = info.match(/redis_version:(.+)/);
      const version = versionMatch ? versionMatch[1].trim() : 'unknown';
      
      return {
        name: 'redis',
        status: 'healthy',
        responseTime,
        details: {
          ping: pingResponse,
          version,
          connected: true
        }
      };
    } catch (error) {
      const responseTime = Date.now() - startTime;
      logger.error('Redis health check failed:', error);
      
      try {
        await redis.quit();
      } catch (e) {
        // Ignore quit errors
      }
      
      return {
        name: 'redis',
        status: 'unhealthy',
        responseTime,
        error: error.message,
        details: {
          connected: false
        }
      };
    }
  }

  /**
   * Check Claude API health
   * @returns {Promise<Object>} Claude API health status
   */
  async checkClaude() {
    const startTime = Date.now();
    
    try {
      if (!process.env.ANTHROPIC_API_KEY) {
        throw new Error('ANTHROPIC_API_KEY not configured');
      }
      
      const anthropic = new Anthropic({
        apiKey: process.env.ANTHROPIC_API_KEY,
      });
      
      // Simple test to verify API key validity
      // We'll use a minimal request to check connectivity
      const response = await anthropic.messages.create({
        model: 'claude-3-haiku-20240307',
        max_tokens: 10,
        messages: [{
          role: 'user',
          content: 'Hi'
        }],
        timeout: this.checkTimeout
      });
      
      const responseTime = Date.now() - startTime;
      
      return {
        name: 'claude',
        status: 'healthy',
        responseTime,
        details: {
          apiKeyConfigured: true,
          model: response.model,
          usage: response.usage
        }
      };
    } catch (error) {
      const responseTime = Date.now() - startTime;
      logger.error('Claude API health check failed:', error);
      
      return {
        name: 'claude',
        status: 'unhealthy',
        responseTime,
        error: error.message,
        details: {
          apiKeyConfigured: !!process.env.ANTHROPIC_API_KEY
        }
      };
    }
  }

  /**
   * Get detailed health status
   * @returns {Promise<Object>} Detailed health information
   */
  async getDetailedHealth() {
    // Run fresh health checks if not monitoring
    if (!this.isMonitoring) {
      await this.runHealthChecks();
    }
    
    const dependencies = [];
    for (const [name, result] of this.lastCheckResults) {
      dependencies.push(result);
    }
    
    // If no cached results, run checks now
    if (dependencies.length === 0) {
      await this.runHealthChecks();
      for (const [name, result] of this.lastCheckResults) {
        dependencies.push(result);
      }
    }
    
    const system = {
      hostname: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
      uptime: os.uptime(),
      memory: {
        total: os.totalmem(),
        free: os.freemem(),
        used: os.totalmem() - os.freemem(),
        usagePercent: ((os.totalmem() - os.freemem()) / os.totalmem() * 100).toFixed(2)
      },
      cpu: {
        cores: os.cpus().length,
        model: os.cpus()[0]?.model || 'unknown',
        loadAverage: os.loadavg()
      }
    };
    
    const process_info = {
      pid: process.pid,
      version: process.version,
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      cpu: process.cpuUsage()
    };
    
    return {
      dependencies,
      system,
      process: process_info
    };
  }

  /**
   * Check if service is ready
   * @returns {Promise<boolean>} True if all critical services are available
   */
  async checkReadiness() {
    try {
      const [kong, redis] = await Promise.all([
        this.checkKong(),
        this.checkRedis()
      ]);
      
      return kong.status === 'healthy' && redis.status === 'healthy';
    } catch (error) {
      logger.error('Readiness check failed:', error);
      return false;
    }
  }

  /**
   * Check specific dependency
   * @param {string} name - Dependency name
   * @returns {Promise<Object>} Dependency health status
   */
  async checkDependency(name) {
    switch (name) {
      case 'kong':
        return await this.checkKong();
      case 'redis':
        return await this.checkRedis();
      case 'claude':
        return await this.checkClaude();
      default:
        throw new Error(`Unknown dependency: ${name}`);
    }
  }

  /**
   * Get service metrics
   * @returns {Object} Service performance metrics
   */
  async getMetrics() {
    const memoryUsage = process.memoryUsage();
    const cpuUsage = process.cpuUsage();
    
    return {
      timestamp: new Date().toISOString(),
      memory: {
        rss: memoryUsage.rss,
        heapTotal: memoryUsage.heapTotal,
        heapUsed: memoryUsage.heapUsed,
        external: memoryUsage.external,
        arrayBuffers: memoryUsage.arrayBuffers
      },
      cpu: {
        user: cpuUsage.user,
        system: cpuUsage.system
      },
      process: {
        uptime: process.uptime(),
        pid: process.pid,
        ppid: process.ppid,
        version: process.version,
        versions: process.versions
      },
      requests: {
        // This would be populated by actual request tracking middleware
        total: 0,
        success: 0,
        error: 0,
        latency: {
          p50: 0,
          p95: 0,
          p99: 0
        }
      }
    };
  }
}

// Create singleton instance
const healthCheckService = new HealthCheckService();

// Export functions for external use
module.exports = {
  startHealthChecks: () => healthCheckService.startMonitoring(),
  stopHealthChecks: () => healthCheckService.stopMonitoring(),
  getDetailedHealth: () => healthCheckService.getDetailedHealth(),
  checkReadiness: () => healthCheckService.checkReadiness(),
  checkDependency: (name) => healthCheckService.checkDependency(name),
  getMetrics: () => healthCheckService.getMetrics()
};