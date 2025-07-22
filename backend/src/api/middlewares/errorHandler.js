/**
 * @typedef {Object} ErrorResponse
 * @property {string} error - 에러 타입
 * @property {string} message - 에러 메시지  
 * @property {string} timestamp - 에러 발생 시간
 * @property {string} [requestId] - 요청 ID (향후 추가)
 */

/**
 * 커스텀 애플리케이션 에러 클래스
 * @extends Error
 */
class AppError extends Error {
  /**
   * @param {string} message - 에러 메시지
   * @param {number} statusCode - HTTP 상태 코드
   * @param {string} code - 에러 코드
   */
  constructor(message, statusCode = 500, code = 'INTERNAL_ERROR') {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.isOperational = true; // 운영 에러 (버그가 아닌 예상된 에러)
    
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * 404 Not Found 핸들러
 * @param {import('express').Request} req - Express 요청 객체
 * @param {import('express').Response} res - Express 응답 객체
 * @description 모든 정의되지 않은 라우트에 대한 처리
 */
const notFoundHandler = (req, res) => {
  /** @type {ErrorResponse} */
  const errorResponse = {
    error: 'Not Found',
    message: `Route ${req.method} ${req.originalUrl} not found`,
    timestamp: new Date().toISOString()
  };
  
  res.status(404).json(errorResponse);
};

/**
 * 글로벌 에러 핸들러
 * @param {Error|AppError} error - 발생한 에러
 * @param {import('express').Request} req - Express 요청 객체  
 * @param {import('express').Response} res - Express 응답 객체
 * @param {import('express').NextFunction} _next - Express next 함수 (사용하지 않음)
 * @description CLAUDE.md 보안 요구사항 준수 - 프로덕션에서 에러 정보 노출 제한
 */
const globalErrorHandler = (error, req, res, _next) => {
  // Handle null/undefined errors
  if (!error) {
    error = new Error('Unknown error occurred');
  }
  
  // 에러 로깅 (실제 구현에서는 winston 사용)
  console.error('Global error handler:', {
    message: error.message || 'Unknown error',
    stack: error.stack,
    url: req.originalUrl,
    method: req.method,
    ip: req.ip,
    timestamp: new Date().toISOString()
  });
  
  let statusCode = 500;
  let message = 'Internal Server Error';
  
  // AppError인 경우 상태 코드와 메시지 사용
  if (error instanceof AppError) {
    statusCode = error.statusCode;
    message = error.message;
  } else if (error.statusCode) {
    // Regular Error with statusCode property
    statusCode = error.statusCode;
    message = error.message;
  }
  
  // 개발 환경에서만 상세 에러 정보 제공
  const isDevelopment = process.env.NODE_ENV !== 'production';
  
  /** @type {ErrorResponse} */
  const errorResponse = {
    error: getErrorType(statusCode),
    message: isDevelopment ? message : getGenericMessage(statusCode),
    timestamp: new Date().toISOString()
  };
  
  // 개발 환경에서는 스택 트레이스도 포함
  if (isDevelopment && error.stack) {
    errorResponse.stack = error.stack;
  }
  
  res.status(statusCode).json(errorResponse);
};

/**
 * HTTP 상태 코드에 따른 에러 타입 반환
 * @param {number} statusCode - HTTP 상태 코드
 * @returns {string} 에러 타입
 */
function getErrorType(statusCode) {
  switch (statusCode) {
  case 400: return 'Bad Request';
  case 401: return 'Unauthorized';
  case 403: return 'Forbidden';
  case 404: return 'Not Found';
  case 429: return 'Too Many Requests';
  case 500: return 'Internal Server Error';
  case 502: return 'Bad Gateway';
  case 503: return 'Service Unavailable';
  default: return 'Error';
  }
}

/**
 * 프로덕션에서 사용할 제네릭 에러 메시지
 * @param {number} statusCode - HTTP 상태 코드
 * @returns {string} 제네릭 메시지
 */
function getGenericMessage(statusCode) {
  if (statusCode >= 400 && statusCode < 500) {
    return 'Client error occurred';
  }
  return 'Something went wrong';
}

module.exports = {
  AppError,
  notFoundHandler,
  globalErrorHandler
};