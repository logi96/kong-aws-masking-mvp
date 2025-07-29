const express = require('express');
const router = express.Router();

/**
 * @typedef {Object} HealthResponse
 * @property {string} status - 서비스 상태 ('healthy' | 'unhealthy')
 * @property {string} timestamp - ISO 8601 형식 타임스탬프
 * @property {string} version - 애플리케이션 버전
 * @property {Object} [details] - 상세 헬스 정보
 */

/**
 * @typedef {Object} HealthDetails
 * @property {number} uptime - 프로세스 업타임 (초)
 * @property {NodeJS.MemoryUsage} memory - 메모리 사용량
 * @property {number} pid - 프로세스 ID
 */

/**
 * 헬스 응답 객체 생성
 * @param {express.Request} req - Express 요청 객체 (app.locals 접근용)
 * @returns {HealthResponse} 표준 헬스 응답
 */
function createHealthResponse(req) {
  const packageJson = require('../../../package.json');
  
  // Redis Event Subscriber 상태 확인
  let redisSubscriberStatus = null;
  if (req && req.app.locals.redisSubscriber) {
    const stats = req.app.locals.redisSubscriber.getStats();
    redisSubscriberStatus = {
      connection_status: stats.connection_status,
      total_events: stats.totalEvents,
      uptime: stats.uptime_formatted,
      events_per_minute: Math.round(stats.events_per_minute * 100) / 100,
      // 배치 처리 및 레이트 리미팅 정보
      current_batch_size: stats.current_batch_size,
      rate_limit_remaining: stats.rate_limit_remaining,
      // 재연결 관리 정보  
      reconnect_attempts: stats.reconnect_attempts,
      max_reconnect_attempts: stats.max_reconnect_attempts,
      is_reconnect_scheduled: stats.is_reconnect_scheduled,
      // 상세 이벤트 통계
      masking_events: stats.maskingEvents,
      unmasking_events: stats.unmaskingEvents,
      connection_errors: stats.connectionErrors
    };
  } else if (process.env.ENABLE_REDIS_EVENTS === 'true') {
    redisSubscriberStatus = {
      connection_status: 'initializing',
      total_events: 0,
      uptime: '0s',
      events_per_minute: 0,
      current_batch_size: 0,
      rate_limit_remaining: 100,
      reconnect_attempts: 0,
      max_reconnect_attempts: 10,
      is_reconnect_scheduled: false,
      masking_events: 0,
      unmasking_events: 0,
      connection_errors: 0
    };
  }
  
  const response = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: packageJson.version,
    details: {
      uptime: Math.round(process.uptime()),
      memory: process.memoryUsage(),
      pid: process.pid
    }
  };
  
  // Redis 구독 상태 추가 (활성화된 경우에만)
  if (redisSubscriberStatus) {
    response.details.redis_events = redisSubscriberStatus;
  }
  
  return response;
}

/**
 * 시스템 상태 확인
 * @param {express.Request} req - Express 요청 객체 (app.locals 접근용)
 * @returns {boolean} 시스템이 정상 상태인지 여부
 */
function checkSystemHealth(req) {
  try {
    // 기본적인 시스템 상태 확인
    const memoryUsage = process.memoryUsage();
    const heapUsedMB = memoryUsage.heapUsed / 1024 / 1024;
    
    // 메모리 사용량이 1GB를 초과하면 unhealthy
    if (heapUsedMB > 1024) {
      return false;
    }
    
    // 업타임이 너무 짧으면 (시작한 지 1초 미만) 아직 준비되지 않음
    if (process.uptime() < 1) {
      return false;
    }
    
    // Redis Event Subscriber 상태 확인 (활성화된 경우에만)
    if (process.env.ENABLE_REDIS_EVENTS === 'true' && req && req.app.locals.redisSubscriber) {
      const stats = req.app.locals.redisSubscriber.getStats();
      
      // Redis 연결이 끊어져 있고 연결 에러가 많으면 unhealthy
      if (stats.connection_status === 'disconnected' && stats.connectionErrors > 5) {
        return false;
      }
    }
    
    return true;
  } catch (error) {
    console.error('Health check failed:', error);
    return false;
  }
}

/**
 * 헬스체크 엔드포인트
 * @route GET /health
 * @returns {HealthResponse} 헬스 상태
 * @description CLAUDE.md 성능 요구사항 준수 (<5초)
 */
const healthCheck = (req, res) => {
  const isHealthy = checkSystemHealth(req);
  const response = createHealthResponse(req);
  
  if (!isHealthy) {
    response.status = 'unhealthy';
    return res.status(503).json(response);
  }
  
  res.json(response);
};

// 라우트 등록
router.get('/', healthCheck);

module.exports = { router, createHealthResponse, checkSystemHealth };