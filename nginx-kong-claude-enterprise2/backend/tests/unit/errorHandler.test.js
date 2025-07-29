/**
 * @fileoverview Unit tests for error handler middleware
 * @module tests/unit/errorHandler
 */

const { errorHandler, asyncHandler, notFoundHandler, ApiError } = require('../../src/middlewares/errorHandler');
const logger = require('../../src/utils/logger');

// Mock logger
jest.mock('../../src/utils/logger');

describe('Error Handler Middleware', () => {
  let req, res, next;

  beforeEach(() => {
    jest.clearAllMocks();
    
    req = {
      url: '/test',
      method: 'GET',
      ip: '127.0.0.1',
      path: '/test',
      get: jest.fn().mockReturnValue('Mozilla/5.0'),
      id: 'req-123'
    };
    
    res = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn()
    };
    
    next = jest.fn();
  });

  describe('ApiError class', () => {
    it('should create error with all properties', () => {
      const error = new ApiError(400, 'Bad Request', { field: 'invalid' });

      expect(error.statusCode).toBe(400);
      expect(error.message).toBe('Bad Request');
      expect(error.details).toEqual({ field: 'invalid' });
      expect(error.timestamp).toBeDefined();
    });

    it('should create error without details', () => {
      const error = new ApiError(500, 'Internal Error');

      expect(error.statusCode).toBe(500);
      expect(error.details).toBeNull();
    });
  });

  describe('errorHandler middleware', () => {
    it('should handle generic errors', () => {
      const error = new Error('Something went wrong');

      errorHandler(error, req, res, next);

      expect(logger.error).toHaveBeenCalledWith('Error occurred:', expect.objectContaining({
        error: 'Something went wrong',
        url: '/test',
        method: 'GET'
      }));

      expect(res.status).toHaveBeenCalledWith(500);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 500,
          message: 'Something went wrong',
          path: '/test',
          requestId: 'req-123'
        })
      });
    });

    it('should handle ApiError instances', () => {
      const error = new ApiError(400, 'Validation failed', { field: 'required' });

      errorHandler(error, req, res, next);

      expect(res.status).toHaveBeenCalledWith(400);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 400,
          message: 'Validation failed',
          details: { field: 'required' }
        })
      });
    });

    it('should handle ValidationError', () => {
      const error = new Error('Validation failed');
      error.name = 'ValidationError';
      error.errors = { email: 'Invalid email format' };

      errorHandler(error, req, res, next);

      expect(res.status).toHaveBeenCalledWith(400);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 400,
          message: 'Validation Error',
          details: { email: 'Invalid email format' }
        })
      });
    });

    it('should handle UnauthorizedError', () => {
      const error = new Error('Access denied');
      error.name = 'UnauthorizedError';

      errorHandler(error, req, res, next);

      expect(res.status).toHaveBeenCalledWith(401);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 401,
          message: 'Unauthorized'
        })
      });
    });

    it('should handle CastError', () => {
      const error = new Error('Cast to ObjectId failed');
      error.name = 'CastError';

      errorHandler(error, req, res, next);

      expect(res.status).toHaveBeenCalledWith(400);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 400,
          message: 'Invalid ID format'
        })
      });
    });

    it('should handle ECONNREFUSED errors', () => {
      const error = new Error('Connection refused');
      error.code = 'ECONNREFUSED';

      errorHandler(error, req, res, next);

      expect(res.status).toHaveBeenCalledWith(503);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 503,
          message: 'Service Unavailable',
          details: 'Unable to connect to required service'
        })
      });
    });

    it('should handle ETIMEDOUT errors', () => {
      const error = new Error('Request timeout');
      error.code = 'ETIMEDOUT';

      errorHandler(error, req, res, next);

      expect(res.status).toHaveBeenCalledWith(504);
      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          status: 504,
          message: 'Gateway Timeout',
          details: 'Request timed out'
        })
      });
    });

    it('should include stack trace in development', () => {
      process.env.NODE_ENV = 'development';
      const error = new Error('Dev error');
      error.stack = 'Error: Dev error\n    at test.js:10:5';

      errorHandler(error, req, res, next);

      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          stack: error.stack
        })
      });

      process.env.NODE_ENV = 'test';
    });

    it('should not include stack trace in production', () => {
      process.env.NODE_ENV = 'production';
      const error = new Error('Prod error');

      errorHandler(error, req, res, next);

      expect(res.json).toHaveBeenCalledWith({
        error: expect.not.objectContaining({
          stack: expect.anything()
        })
      });

      process.env.NODE_ENV = 'test';
    });

    it('should handle errors without message', () => {
      const error = new Error();
      error.statusCode = 400;

      errorHandler(error, req, res, next);

      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          message: 'Internal Server Error'
        })
      });
    });

    it('should include request ID when available', () => {
      const error = new Error('Test error');

      errorHandler(error, req, res, next);

      expect(res.json).toHaveBeenCalledWith({
        error: expect.objectContaining({
          requestId: 'req-123'
        })
      });
    });

    it('should handle missing request ID', () => {
      delete req.id;
      const error = new Error('Test error');

      errorHandler(error, req, res, next);

      expect(res.json).toHaveBeenCalledWith({
        error: expect.not.objectContaining({
          requestId: expect.anything()
        })
      });
    });
  });

  describe('asyncHandler wrapper', () => {
    it('should handle successful async functions', async () => {
      const asyncFn = jest.fn().mockResolvedValue('success');
      const wrapped = asyncHandler(asyncFn);

      await wrapped(req, res, next);

      expect(asyncFn).toHaveBeenCalledWith(req, res, next);
      expect(next).not.toHaveBeenCalled();
    });

    it('should catch async errors', async () => {
      const error = new Error('Async error');
      const asyncFn = jest.fn().mockRejectedValue(error);
      const wrapped = asyncHandler(asyncFn);

      await wrapped(req, res, next);

      expect(next).toHaveBeenCalledWith(error);
    });

    it('should handle sync errors in async functions', async () => {
      const error = new Error('Sync error');
      const asyncFn = jest.fn(() => {
        throw error;
      });
      const wrapped = asyncHandler(asyncFn);

      await wrapped(req, res, next);

      expect(next).toHaveBeenCalledWith(error);
    });
  });

  describe('notFoundHandler middleware', () => {
    it('should create 404 error', () => {
      notFoundHandler(req, res, next);

      expect(next).toHaveBeenCalledWith(
        expect.objectContaining({
          statusCode: 404,
          message: 'Cannot GET /test'
        })
      );
    });

    it('should handle different HTTP methods', () => {
      req.method = 'POST';
      req.path = '/api/users';

      notFoundHandler(req, res, next);

      expect(next).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Cannot POST /api/users'
        })
      );
    });
  });
});