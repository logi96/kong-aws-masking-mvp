/**
 * @fileoverview Error Handler 완전한 테스트 커버리지
 * @description 100% 테스트 커버리지를 위한 errorHandler.js 테스트
 */

const { AppError, notFoundHandler, globalErrorHandler } = require('../../../../src/api/middlewares/errorHandler');

describe('Error Handler Tests', () => {
  describe('AppError Class', () => {
    test('should create AppError with custom message and status', () => {
      const error = new AppError('Custom error', 400, 'CUSTOM_ERROR');
      
      expect(error.name).toBe('AppError');
      expect(error.message).toBe('Custom error');
      expect(error.statusCode).toBe(400);
      expect(error.code).toBe('CUSTOM_ERROR');
      expect(error.isOperational).toBe(true);
    });

    test('should use default values when not provided', () => {
      const error = new AppError('Default error');
      
      expect(error.statusCode).toBe(500);
      expect(error.code).toBe('INTERNAL_ERROR');
      expect(error.isOperational).toBe(true);
    });

    test('should capture stack trace', () => {
      const error = new AppError('Stack trace test');
      expect(error.stack).toBeDefined();
      expect(error.stack).toContain('Stack trace test');
    });
  });

  describe('notFoundHandler', () => {
    let mockReq, mockRes;

    beforeEach(() => {
      mockReq = {
        method: 'GET',
        originalUrl: '/test/route'
      };
      mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };
    });

    test('should handle 404 with proper error response', () => {
      notFoundHandler(mockReq, mockRes);

      expect(mockRes.status).toHaveBeenCalledWith(404);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Not Found',
        message: 'Route GET /test/route not found',
        timestamp: expect.any(String)
      });
    });

    test('should handle POST request 404', () => {
      mockReq.method = 'POST';
      mockReq.originalUrl = '/api/nonexistent';

      notFoundHandler(mockReq, mockRes);

      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Not Found',
        message: 'Route POST /api/nonexistent not found',
        timestamp: expect.any(String)
      });
    });
  });

  describe('globalErrorHandler', () => {
    let mockReq, mockRes, mockNext;

    beforeEach(() => {
      mockReq = {
        id: 'test-request-123',
        method: 'POST',
        originalUrl: '/test',
        ip: '127.0.0.1'
      };
      mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };
      mockNext = jest.fn();
    });

    test('should handle AppError with custom status', () => {
      const appError = new AppError('Validation failed', 400, 'VALIDATION_ERROR');

      globalErrorHandler(appError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(400);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Bad Request',
        message: 'Validation failed',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
      expect(mockNext).not.toHaveBeenCalled();
    });

    test('should handle regular Error as 500', () => {
      const regularError = new Error('Database connection failed');

      globalErrorHandler(regularError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(500);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Internal Server Error',
        message: expect.any(String), // Production vs development message
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle 401 Unauthorized status', () => {
      const authError = new AppError('Invalid token', 401, 'AUTH_ERROR');

      globalErrorHandler(authError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(401);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Unauthorized',
        message: 'Invalid token',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle 403 Forbidden status', () => {
      const forbiddenError = new AppError('Insufficient permissions', 403, 'PERMISSION_ERROR');

      globalErrorHandler(forbiddenError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Forbidden',
        message: 'Insufficient permissions',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle 404 Not Found status', () => {
      const notFoundError = new AppError('Resource not found', 404, 'NOT_FOUND');

      globalErrorHandler(notFoundError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(404);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Not Found',
        message: 'Resource not found',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle 429 Too Many Requests status', () => {
      const rateLimitError = new AppError('Rate limit exceeded', 429, 'RATE_LIMIT');

      globalErrorHandler(rateLimitError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(429);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Too Many Requests',
        message: 'Rate limit exceeded',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle 502 Bad Gateway status', () => {
      const gatewayError = new AppError('Upstream server error', 502, 'GATEWAY_ERROR');

      globalErrorHandler(gatewayError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(502);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Bad Gateway',
        message: 'Upstream server error',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle 503 Service Unavailable status', () => {
      const serviceError = new AppError('Service temporarily unavailable', 503, 'SERVICE_ERROR');

      globalErrorHandler(serviceError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(503);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Service Unavailable',
        message: 'Service temporarily unavailable',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should handle unknown status codes', () => {
      const unknownError = new AppError('Unknown error', 418, 'TEAPOT_ERROR');

      globalErrorHandler(unknownError, mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(418);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Error',
        message: 'Unknown error',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should use generic message in production for client errors', () => {
      const originalNodeEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';

      const clientError = new Error('Detailed client error');
      clientError.statusCode = 400;

      globalErrorHandler(clientError, mockReq, mockRes, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Bad Request',
        message: 'Client error occurred',
        timestamp: expect.any(String)
      });

      process.env.NODE_ENV = originalNodeEnv;
    });

    test('should use generic message in production for server errors', () => {
      const originalNodeEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';

      const serverError = new Error('Detailed server error');

      globalErrorHandler(serverError, mockReq, mockRes, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Internal Server Error',
        message: 'Something went wrong',
        timestamp: expect.any(String)
      });

      process.env.NODE_ENV = originalNodeEnv;
    });

    test('should include error details in development', () => {
      const originalNodeEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'development';

      const devError = new Error('Detailed development error');

      globalErrorHandler(devError, mockReq, mockRes, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Internal Server Error',
        message: 'Detailed development error',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });

      process.env.NODE_ENV = originalNodeEnv;
    });

    test('should handle errors without request ID', () => {
      delete mockReq.id;

      const error = new AppError('No request ID', 400);

      globalErrorHandler(error, mockReq, mockRes, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Bad Request',
        message: 'No request ID',
        timestamp: expect.any(String),
        stack: expect.any(String)
      });
    });

    test('should log error details in console', () => {
      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

      const error = new Error('Test logging error');

      globalErrorHandler(error, mockReq, mockRes, mockNext);

      expect(consoleSpy).toHaveBeenCalledWith('Global error handler:', {
        message: 'Test logging error',
        stack: expect.any(String),
        url: '/test',
        method: 'POST',
        ip: '127.0.0.1',
        timestamp: expect.any(String)
      });

      consoleSpy.mockRestore();
    });
  });

  describe('Edge cases and error conditions', () => {
    test('should handle malformed request objects', () => {
      const malformedReq = {}; // No method, originalUrl, etc.
      const mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };

      notFoundHandler(malformedReq, mockRes);

      expect(mockRes.status).toHaveBeenCalledWith(404);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Not Found',
        message: 'Route undefined undefined not found',
        timestamp: expect.any(String)
      });
    });

    test('should handle errors with circular references', () => {
      const circularError = new Error('Circular reference error');
      circularError.circular = circularError; // Create circular reference

      const mockReq = { method: 'GET', originalUrl: '/test', ip: '127.0.0.1' };
      const mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };

      // Should not throw when logging circular references
      expect(() => {
        globalErrorHandler(circularError, mockReq, mockRes, jest.fn());
      }).not.toThrow();
    });

    test('should handle null/undefined error objects', () => {
      const mockReq = { method: 'GET', originalUrl: '/test', ip: '127.0.0.1' };
      const mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };

      globalErrorHandler(null, mockReq, mockRes, jest.fn());

      expect(mockRes.status).toHaveBeenCalledWith(500);
      expect(mockRes.json).toHaveBeenCalled();
    });
  });
});