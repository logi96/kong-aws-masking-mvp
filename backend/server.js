#!/usr/bin/env node

/**
 * Kong AWS Masking Backend API Server
 * @description CLAUDE.md 지침 준수 - Node.js 20.x LTS, Type Safety, Performance < 5s
 */

require('dotenv').config();
const app = require('./src/app');
const PORT = process.env.PORT || 3000;

/**
 * 환경 변수 검증
 * @returns {boolean} 필수 환경 변수가 모두 설정되었는지 여부
 */
function validateEnvironment() {
  const required = ['NODE_ENV'];
  const missing = required.filter(key => !process.env[key]);
  
  if (missing.length > 0) {
    console.error(`Missing required environment variables: ${missing.join(', ')}`);
    return false;
  }
  
  return true;
}

/**
 * 서버 graceful shutdown 처리
 * @param {import('http').Server} server - HTTP 서버 인스턴스
 */
function setupGracefulShutdown(server) {
  const shutdown = (signal) => {
    console.log(`Received ${signal}. Starting graceful shutdown...`);
    
    server.close((err) => {
      if (err) {
        console.error('Error during server shutdown:', err);
        process.exit(1);
      }
      
      console.log('Server closed successfully');
      process.exit(0);
    });
    
    // 강제 종료 타이머 (10초)
    setTimeout(() => {
      console.error('Forceful shutdown after timeout');
      process.exit(1);
    }, 10000);
  };
  
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

/**
 * 서버 시작
 */
function startServer() {
  // 환경 변수 검증
  if (!validateEnvironment()) {
    process.exit(1);
  }
  
  const NODE_ENV = process.env.NODE_ENV || 'development';
  
  // 서버 시작
  const server = app.listen(PORT, () => {
    console.log('🚀 Kong AWS Masking Backend API Server');
    console.log('=====================================');
    console.log(`Environment: ${NODE_ENV}`);
    console.log(`Port: ${PORT}`);
    console.log(`Process ID: ${process.pid}`);
    console.log(`Node Version: ${process.version}`);
    console.log(`Started at: ${new Date().toISOString()}`);
    console.log('=====================================');
    console.log('🔗 Available endpoints:');
    console.log(`  GET  http://localhost:${PORT}/health - Health check`);
    console.log('=====================================');
    
    if (NODE_ENV === 'development') {
      console.log('💡 Development Tips:');
      console.log('  - Use npm run dev for auto-reload');
      console.log('  - Run npm run quality:check before commits');
      console.log('  - Check logs for request/response details');
    }
  });
  
  // Graceful shutdown 설정
  setupGracefulShutdown(server);
  
  // 서버 에러 처리
  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.error(`Port ${PORT} is already in use`);
    } else {
      console.error('Server error:', err);
    }
    process.exit(1);
  });
  
  return server;
}

// 메인 실행 (모듈로 require된 경우는 실행하지 않음)
if (require.main === module) {
  startServer();
}

module.exports = { startServer, validateEnvironment };