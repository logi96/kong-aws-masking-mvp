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
 * @returns {HealthResponse} 표준 헬스 응답
 */
function createHealthResponse() {
  const packageJson = require('../../../package.json');
  
  return {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: packageJson.version,
    details: {
      uptime: Math.round(process.uptime()),
      memory: process.memoryUsage(),
      pid: process.pid
    }
  };
}

/**
 * 시스템 상태 확인
 * @returns {boolean} 시스템이 정상 상태인지 여부
 */
function checkSystemHealth() {
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
  const isHealthy = checkSystemHealth();
  const response = createHealthResponse();
  
  if (!isHealthy) {
    response.status = 'unhealthy';
    return res.status(503).json(response);
  }
  
  res.json(response);
};

// 라우트 등록
router.get('/', healthCheck);

module.exports = { router, createHealthResponse, checkSystemHealth };