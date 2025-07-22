// 환경 변수 로딩 (독립 실행 및 테스트 환경 지원)
require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const compression = require('compression');

// 라우트 및 미들웨어 import
const { router: healthRouter } = require('./api/routes/health');
const { router: analyzeRouter } = require('./api/routes/analyze');
const { notFoundHandler, globalErrorHandler } = require('./api/middlewares/errorHandler');

/**
 * Express 애플리케이션 생성 및 설정
 * @returns {express.Application} 설정된 Express 앱
 * @description REFACTOR Phase - 모듈화되고 구조화된 구현
 */
function createApp() {
  const app = express();
  
  // 1. 보안 미들웨어 (CLAUDE.md 보안 요구사항)
  app.use(helmet({
    frameguard: { action: 'deny' },
    xssFilter: false // 최신 브라우저에서 deprecated
  }));
  
  // 2. CORS 미들웨어 (개발 환경 고려)
  app.use(cors({
    origin: process.env.NODE_ENV === 'production' 
      ? process.env.ALLOWED_ORIGINS?.split(',') 
      : true,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
  }));
  
  // 3. JSON 파싱 미들웨어 (CLAUDE.md 요구사항: 10MB)
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));
  
  // 4. 압축 미들웨어 (성능 최적화)
  app.use(compression());
  
  // 5. 로깅 미들웨어 (환경별 로그 형식)
  const logFormat = process.env.NODE_ENV === 'production' ? 'combined' : 'dev';
  app.use(morgan(logFormat));
  
  // 6. API 라우트 등록
  app.use('/health', healthRouter);
  app.use('/analyze', analyzeRouter);
  
  // 7. 404 에러 핸들러
  app.use('*', notFoundHandler);
  
  // 8. 글로벌 에러 핸들러
  app.use(globalErrorHandler);
  
  return app;
}

module.exports = createApp();