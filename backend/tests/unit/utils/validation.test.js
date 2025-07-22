/**
 * @fileoverview Comprehensive validation utilities tests
 * @description 100% 테스트 커버리지를 위한 완전한 validation.js 테스트
 */

const {
  validateEnvironment,
  handleValidationErrors,
  validateAnalyzeRequest,
  validateHealthRequest,
  validateAwsRequest,
  sanitizeString,
  validateAwsCommand
} = require('../../../utils/validation');

// Import constants for testing
const OPTIONAL_ENV_VARS = {
  NODE_ENV: 'development',
  PORT: '3000',
  LOG_LEVEL: 'info',
  REQUEST_TIMEOUT: '5000',
  MAX_RETRIES: '3',
  RETRY_DELAY: '1000'
};

// Mock express-validator
jest.mock('express-validator', () => {
  const mockValidationResult = jest.fn();
  return {
  body: jest.fn(() => ({
    optional: () => ({
      isString: () => ({
        isLength: () => ({
          withMessage: () => ({})
        })
      }),
      isArray: () => ({
        withMessage: () => ({})
      }),
      isBoolean: () => ({
        withMessage: () => ({})
      }),
      isInt: () => ({
        withMessage: () => ({})
      })
    }),
    isIn: () => ({
      withMessage: () => ({})
    })
  })),
  param: jest.fn(() => ({
    isIn: () => ({
      withMessage: () => ({})
    })
  })),
  query: jest.fn(() => ({
    optional: () => ({
      isBoolean: () => ({
        withMessage: () => ({})
      }),
      matches: () => ({
        withMessage: () => ({})
      }),
      isInt: () => ({
        withMessage: () => ({})
      })
    })
  })),
  validationResult: mockValidationResult
  };
});

// Get the mocked validation result function
const { validationResult } = require('express-validator');

describe('Validation Utilities Tests', () => {
  // Store original environment
  const originalEnv = process.env;

  beforeEach(() => {
    // Reset environment for each test
    process.env = { ...originalEnv };
    jest.clearAllMocks();
  });

  afterAll(() => {
    // Restore original environment
    process.env = originalEnv;
  });

  describe('validateEnvironment', () => {
    test('should pass with all required environment variables', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      process.env.AWS_REGION = 'us-east-1';

      expect(() => validateEnvironment()).not.toThrow();
    });

    test('should throw error when ANTHROPIC_API_KEY is missing', () => {
      delete process.env.ANTHROPIC_API_KEY;
      process.env.AWS_REGION = 'us-east-1';

      expect(() => validateEnvironment()).toThrow(
        'Missing required environment variables: ANTHROPIC_API_KEY'
      );
    });

    test('should throw error when AWS_REGION is missing', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      delete process.env.AWS_REGION;

      expect(() => validateEnvironment()).toThrow(
        'Missing required environment variables: AWS_REGION'
      );
    });

    test('should throw error when multiple required variables are missing', () => {
      delete process.env.ANTHROPIC_API_KEY;
      delete process.env.AWS_REGION;

      expect(() => validateEnvironment()).toThrow(
        'Missing required environment variables: ANTHROPIC_API_KEY, AWS_REGION'
      );
    });

    test('should set default values for optional variables', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      process.env.AWS_REGION = 'us-east-1';
      delete process.env.NODE_ENV;
      delete process.env.PORT;
      delete process.env.LOG_LEVEL;
      delete process.env.REQUEST_TIMEOUT;
      delete process.env.MAX_RETRIES;
      delete process.env.RETRY_DELAY;

      validateEnvironment();

      expect(process.env.NODE_ENV).toBe('development');
      expect(process.env.PORT).toBe('3000');
      expect(process.env.LOG_LEVEL).toBe('info');
      expect(process.env.REQUEST_TIMEOUT).toBe('5000');
      expect(process.env.MAX_RETRIES).toBe('3');
      expect(process.env.RETRY_DELAY).toBe('1000');
    });

    test('should not override existing optional variables', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      process.env.AWS_REGION = 'us-east-1';
      process.env.NODE_ENV = 'production';
      process.env.PORT = '8080';

      validateEnvironment();

      expect(process.env.NODE_ENV).toBe('production');
      expect(process.env.PORT).toBe('8080');
    });

    test('should validate ANTHROPIC_API_KEY format', () => {
      process.env.ANTHROPIC_API_KEY = 'invalid-key-format';
      process.env.AWS_REGION = 'us-east-1';

      expect(() => validateEnvironment()).toThrow(
        'Invalid ANTHROPIC_API_KEY format. Expected format: sk-ant-api03-...'
      );
    });

    test('should validate AWS_REGION format', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      process.env.AWS_REGION = 'invalid-region';

      expect(() => validateEnvironment()).toThrow(
        'Invalid AWS_REGION format: invalid-region'
      );
    });

    test('should validate numeric environment variables', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      process.env.AWS_REGION = 'us-east-1';
      process.env.PORT = 'not-a-number';

      expect(() => validateEnvironment()).toThrow(
        'Invalid PORT: must be a positive number'
      );
    });

    test('should validate negative numbers', () => {
      process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-123';
      process.env.AWS_REGION = 'us-east-1';
      process.env.MAX_RETRIES = '-1';

      expect(() => validateEnvironment()).toThrow(
        'Invalid MAX_RETRIES: must be a positive number'
      );
    });
  });

  describe('handleValidationErrors middleware', () => {
    let mockReq, mockRes, mockNext;

    beforeEach(() => {
      mockReq = { id: 'test-request-id' };
      mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };
      mockNext = jest.fn();
    });

    test('should call next() when no validation errors', () => {
      validationResult.mockReturnValue({ isEmpty: () => true });

      handleValidationErrors(mockReq, mockRes, mockNext);

      expect(mockNext).toHaveBeenCalled();
      expect(mockRes.status).not.toHaveBeenCalled();
    });

    test('should return 400 with formatted errors when validation fails', () => {
      const mockErrors = [
        { path: 'field1', msg: 'Field1 is required', value: null },
        { param: 'field2', msg: 'Field2 is invalid', value: 'invalid-value' }
      ];

      validationResult.mockReturnValue({
        isEmpty: () => false,
        array: () => mockErrors
      });

      handleValidationErrors(mockReq, mockRes, mockNext);

      expect(mockRes.status).toHaveBeenCalledWith(400);
      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Validation failed',
        message: 'Request contains invalid data',
        details: [
          { field: 'field1', message: 'Field1 is required', value: null },
          { field: 'field2', message: 'Field2 is invalid', value: 'invalid-value' }
        ],
        requestId: 'test-request-id'
      });
      expect(mockNext).not.toHaveBeenCalled();
    });
  });

  describe('sanitizeString', () => {
    test('should remove HTML injection characters', () => {
      const input = '<script>alert("xss")</script>';
      const result = sanitizeString(input);
      expect(result).toBe('scriptalert(xss)/script');
    });

    test('should remove template injection characters', () => {
      const input = '${process.env.SECRET}';
      const result = sanitizeString(input);
      expect(result).toBe('process.env.SECRET');
    });

    test('should remove command injection characters', () => {
      const input = '`rm -rf /`';
      const result = sanitizeString(input);
      expect(result).toBe('rm -rf /');
    });

    test('should trim whitespace', () => {
      const input = '  normal text  ';
      const result = sanitizeString(input);
      expect(result).toBe('normal text');
    });

    test('should handle non-string input', () => {
      expect(sanitizeString(123)).toBe('');
      expect(sanitizeString(null)).toBe('');
      expect(sanitizeString(undefined)).toBe('');
      expect(sanitizeString({})).toBe('');
      expect(sanitizeString([])).toBe('');
    });

    test('should handle empty string', () => {
      expect(sanitizeString('')).toBe('');
    });

    test('should handle normal text unchanged', () => {
      const input = 'normal text without special chars';
      const result = sanitizeString(input);
      expect(result).toBe(input);
    });
  });

  describe('validateAwsCommand', () => {
    test('should validate correct AWS command', () => {
      const command = 'aws ec2 describe-instances';
      const result = validateAwsCommand(command);
      expect(result).toBe(command);
    });

    test('should trim whitespace from command', () => {
      const command = '  aws s3 ls  ';
      const result = validateAwsCommand(command);
      expect(result).toBe('aws s3 ls');
    });

    test('should throw error for non-string command', () => {
      expect(() => validateAwsCommand(123)).toThrow('Command must be a string');
      expect(() => validateAwsCommand(null)).toThrow('Command must be a string');
      expect(() => validateAwsCommand(undefined)).toThrow('Command must be a string');
    });

    test('should throw error for command not starting with "aws "', () => {
      expect(() => validateAwsCommand('docker ps')).toThrow('Command must start with "aws "');
      expect(() => validateAwsCommand('awsec2 describe-instances')).toThrow('Command must start with "aws "');
    });

    test('should reject dangerous delete operations', () => {
      const dangerousCommands = [
        'aws ec2 delete-instance',
        'aws s3 remove bucket',
        'aws rds terminate-db-instance',
        'aws ec2 destroy-instances'
      ];

      dangerousCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).toThrow('Command contains forbidden operations');
      });
    });

    test('should reject dangerous create operations', () => {
      const dangerousCommands = [
        'aws ec2 create-instance',
        'aws s3 put-object',
        'aws rds run-instances'
      ];

      dangerousCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).toThrow('Command contains forbidden operations');
      });
    });

    test('should reject command injection patterns', () => {
      const injectionCommands = [
        'aws ec2 describe-instances; rm -rf /',
        'aws s3 ls | grep secret',
        'aws ec2 describe-instances && cat /etc/passwd',
        'aws ec2 describe-instances `whoami`',
        'aws ec2 describe-instances $(id)',
        'aws ec2 describe-instances --query="something"()'
      ];

      injectionCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).toThrow('Command contains forbidden operations');
      });
    });

    test('should reject force and confirmation flags', () => {
      const forceCommands = [
        'aws s3 ls --force',
        'aws ec2 describe-instances --yes'
      ];

      forceCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).toThrow('Command contains forbidden operations');
      });
    });

    test('should reject rm -rf patterns', () => {
      const rmCommands = [
        'aws s3 ls && rm -rf /',
        'aws ec2 describe-instances; rm -rf /tmp'
      ];

      rmCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).toThrow('Command contains forbidden operations');
      });
    });

    test('should reject disallowed AWS services', () => {
      const disallowedCommands = [
        'aws lambda invoke',
        'aws dynamodb scan',
        'aws unknown-service list'
      ];

      disallowedCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).toThrow(/AWS service ".*" not allowed/);
      });
    });

    test('should allow safe read-only AWS services', () => {
      const allowedCommands = [
        'aws ec2 describe-instances',
        'aws s3 ls',
        'aws rds describe-db-instances',
        'aws iam list-users',
        'aws vpc describe-vpcs',
        'aws cloudformation describe-stacks',
        'aws cloudwatch get-metric-statistics'
      ];

      allowedCommands.forEach(cmd => {
        expect(() => validateAwsCommand(cmd)).not.toThrow();
      });
    });

    test('should handle malformed service names', () => {
      expect(() => validateAwsCommand('aws')).toThrow('Command must start with "aws "');
      expect(() => validateAwsCommand('aws unknown-service list')).toThrow('AWS service "unknown-service" not allowed');
      expect(() => validateAwsCommand('aws xyz describe')).toThrow('AWS service "xyz" not allowed');
    });
  });

  describe('Validation chains', () => {
    test('validateAnalyzeRequest should be defined', () => {
      expect(validateAnalyzeRequest).toBeDefined();
      expect(Array.isArray(validateAnalyzeRequest)).toBe(true);
    });

    test('validateHealthRequest should be defined', () => {
      expect(validateHealthRequest).toBeDefined();
      expect(Array.isArray(validateHealthRequest)).toBe(true);
    });

    test('validateAwsRequest should be defined', () => {
      expect(validateAwsRequest).toBeDefined();
      expect(Array.isArray(validateAwsRequest)).toBe(true);
    });
  });

  describe('Edge cases and error conditions', () => {
    test('should handle undefined validationResult errors', () => {
      validationResult.mockReturnValue({
        isEmpty: () => false,
        array: () => [
          { msg: 'Error without path or param', value: 'test' }
        ]
      });

      const mockReq = { id: 'test-id' };
      const mockRes = {
        status: jest.fn().mockReturnThis(),
        json: jest.fn()
      };
      const mockNext = jest.fn();

      handleValidationErrors(mockReq, mockRes, mockNext);

      expect(mockRes.json).toHaveBeenCalledWith({
        error: 'Validation failed',
        message: 'Request contains invalid data',
        details: [
          { field: undefined, message: 'Error without path or param', value: 'test' }
        ],
        requestId: 'test-id'
      });
    });

    test('should handle empty AWS command', () => {
      expect(() => validateAwsCommand('')).toThrow('Command must start with "aws "');
    });

    test('should handle whitespace-only command', () => {
      expect(() => validateAwsCommand('   ')).toThrow('Command must start with "aws "');
    });
  });
});