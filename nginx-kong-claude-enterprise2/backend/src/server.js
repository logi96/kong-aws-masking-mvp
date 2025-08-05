/**
 * @fileoverview Main server entry point for nginx-kong-claude-enterprise2 backend
 * @module server
 */

require('dotenv').config();
const app = require('./app');
const logger = require('./utils/logger');
const { startHealthChecks } = require('./services/health/healthCheckService');
const maskingEventSubscriber = require('./services/redis/maskingEventSubscriber');

const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

/**
 * Start the server
 */
const server = app.listen(PORT, async () => {
  logger.info(`Server running in ${NODE_ENV} mode on port ${PORT}`);
  logger.info(`Health check endpoint: http://localhost:${PORT}/health`);
  
  // Start background health checks
  if (process.env.ENABLE_MONITORING === 'true') {
    startHealthChecks();
  }
  
  // Start Kong masking event subscription (실시간 마스킹 검증)
  if (process.env.ENABLE_KONG_EVENTS === 'true') {
    try {
      await maskingEventSubscriber.startSubscription();
      logger.info('🎯 Kong masking event subscription started successfully');
    } catch (error) {
      logger.error('Failed to start Kong masking event subscription:', error);
    }
  }
});

/**
 * Graceful shutdown handler
 */
const gracefulShutdown = () => {
  logger.info('Received shutdown signal, starting graceful shutdown...');
  
  server.close(async () => {
    logger.info('HTTP server closed');
    
    // Stop Kong masking event subscription
    try {
      await maskingEventSubscriber.stopSubscription();
      logger.info('Kong masking event subscription stopped');
    } catch (error) {
      logger.error('Error stopping Kong masking event subscription:', error);
    }
    
    // Close Redis connections
    const redisService = require('./services/redis/redisService');
    redisService.disconnect().then(() => {
      logger.info('Redis connection closed');
      process.exit(0);
    }).catch((err) => {
      logger.error('Error closing Redis connection:', err);
      process.exit(1);
    });
  });
  
  // Force shutdown after 30 seconds
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 30000);
};

// Handle shutdown signals
process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
  process.exit(1);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

module.exports = server;