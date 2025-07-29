/**
 * @fileoverview Express application setup and configuration
 * @module app
 */

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const path = require('path');

const logger = require('./utils/logger');
const { errorHandler } = require('./middlewares/errorHandler');
const healthRoutes = require('./routes/health');
const analyzeRoutes = require('./routes/analyze');
const monitoringRoutes = require('./routes/monitoring');
const authRoutes = require('./routes/auth');

/**
 * Create Express application
 * @returns {express.Application} Express app instance
 */
const createApp = () => {
  const app = express();
  
  // Security middleware
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
        imgSrc: ["'self'", "data:", "https:"],
      },
    },
  }));
  
  // CORS configuration
  app.use(cors({
    origin: process.env.CORS_ORIGIN || '*',
    credentials: true,
  }));
  
  // Compression
  app.use(compression());
  
  // Body parsing
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));
  
  // Request logging
  if (process.env.NODE_ENV !== 'test') {
    app.use(morgan('combined', {
      stream: { write: (message) => logger.info(message.trim()) }
    }));
  }
  
  // Rate limiting
  const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: 'Too many requests from this IP, please try again later.',
  });
  
  app.use('/api/', limiter);
  
  // Static files
  app.use('/static', express.static(path.join(__dirname, '../public')));
  
  // API Routes
  app.use('/health', healthRoutes);
  app.use('/analyze', analyzeRoutes);
  app.use('/monitoring', monitoringRoutes);
  app.use('/api/v1/auth', authRoutes);
  
  // Root endpoint
  app.get('/', (req, res) => {
    res.json({
      name: 'nginx-kong-claude-enterprise2 Backend API',
      version: '1.0.0',
      status: 'operational',
      endpoints: {
        health: '/health',
        analyze: '/analyze',
        monitoring: '/monitoring/metrics',
        auth: '/api/v1/auth'
      }
    });
  });
  
  // 404 handler
  app.use((req, res) => {
    res.status(404).json({
      error: 'Not Found',
      message: `Cannot ${req.method} ${req.path}`,
      status: 404
    });
  });
  
  // Error handling middleware (must be last)
  app.use(errorHandler);
  
  return app;
};

module.exports = createApp();