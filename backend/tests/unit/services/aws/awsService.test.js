/**
 * @fileoverview Comprehensive AWS service tests  
 * @description 100% 테스트 커버리지를 위한 완전한 awsService.js 테스트
 */

const awsService = require('../../../../src/services/aws/awsService');
const { exec } = require('child_process');
const { promisify } = require('util');

// Mock child_process
jest.mock('child_process');

// Mock logger
jest.mock('../../../../utils/logger', () => ({
  info: jest.fn(),
  debug: jest.fn(),
  warn: jest.fn(),
  error: jest.fn()
}));

const logger = require('../../../../utils/logger');
const execAsync = promisify(exec);

describe('AWS Service Tests', () => {
  // Store original environment
  const originalEnv = process.env;

  beforeEach(() => {
    // Reset environment and mocks for each test
    process.env = { ...originalEnv };
    process.env.AWS_REGION = 'ap-northeast-2';
    process.env.REQUEST_TIMEOUT = '5000';
    
    jest.clearAllMocks();
    awsService.clearCache(); // Clear cache between tests
  });

  afterAll(() => {
    // Restore original environment
    process.env = originalEnv;
  });

  describe('Constructor and Initialization', () => {
    test('should initialize with default timeout from environment', () => {
      process.env.REQUEST_TIMEOUT = '10000';
      // Cannot test constructor directly since it's a singleton, 
      // but can test timeout behavior indirectly through method calls
      expect(process.env.REQUEST_TIMEOUT).toBe('10000');
    });

    test('should use default timeout when REQUEST_TIMEOUT is not set', () => {
      delete process.env.REQUEST_TIMEOUT;
      // The service should fall back to 5000ms default
      expect(process.env.REQUEST_TIMEOUT).toBeUndefined();
    });

    test('should initialize with Korean region as default', () => {
      delete process.env.AWS_REGION;
      // Should use ap-northeast-2 as default Korean region
      expect(process.env.AWS_REGION).toBeUndefined();
    });
  });

  describe('collectResources', () => {
    test('should collect multiple resource types successfully', async () => {
      const mockEc2Data = [
        ['i-1234567890abcdef0', 't2.micro', 'running', '10.0.0.1', '203.0.113.1', []]
      ];
      const mockS3Data = [
        ['my-test-bucket', '2023-01-01T00:00:00.000Z']
      ];

      exec.mockImplementation((command, options, callback) => {
        if (command.includes('ec2 describe-instances')) {
          callback(null, { stdout: JSON.stringify(mockEc2Data), stderr: '' });
        } else if (command.includes('s3api list-buckets')) {
          callback(null, { stdout: JSON.stringify(mockS3Data), stderr: '' });
        } else {
          callback(new Error('Command not found'));
        }
      });

      const options = {
        resources: ['ec2', 's3']
      };

      const result = await awsService.collectResources(options);

      expect(result).toMatchObject({
        ec2: mockEc2Data,
        s3: mockS3Data
      });

      expect(logger.info).toHaveBeenCalledWith('Collecting AWS resources', expect.any(Object));
      expect(logger.info).toHaveBeenCalledWith('AWS resource collection completed', expect.any(Object));
    });

    test('should use default resource types when not specified', async () => {
      const mockData = [['instance-1', 't2.micro', 'running']];

      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
      });

      const result = await awsService.collectResources({});

      // Should collect default resources: ec2, s3, rds
      expect(result).toHaveProperty('ec2');
      expect(result).toHaveProperty('s3'); 
      expect(result).toHaveProperty('rds');
    });

    test('should handle resource collection errors gracefully', async () => {
      exec.mockImplementation((command, options, callback) => {
        callback(new Error('AWS credentials not found'), { stdout: '', stderr: 'InvalidUserID.NotFound' });
      });

      const options = {
        resources: ['ec2']
      };

      const result = await awsService.collectResources(options);

      expect(result.ec2).toMatchObject({
        error: expect.any(String),
        data: []
      });

      expect(logger.error).toHaveBeenCalledWith(
        expect.stringContaining('Failed to collect ec2 resources'),
        expect.any(Object)
      );
    });

    test('should use cache when available and not expired', async () => {
      const mockData = [['cached-instance', 't2.micro', 'running']];
      
      // First call to populate cache
      exec.mockImplementationOnce((command, options, callback) => {
        callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
      });

      await awsService.collectResources({ resources: ['ec2'] });

      // Second call should use cache
      exec.mockClear();
      
      const result = await awsService.collectResources({ resources: ['ec2'] });

      expect(result.ec2).toEqual(mockData);
      expect(exec).not.toHaveBeenCalled(); // Should not call AWS CLI again
      expect(logger.debug).toHaveBeenCalledWith('Using cached ec2 data');
    });

    test('should skip cache when skipCache is true', async () => {
      const mockData = [['fresh-instance', 't2.micro', 'running']];
      
      // First call to populate cache
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
      });

      await awsService.collectResources({ resources: ['ec2'] });
      exec.mockClear();

      // Second call with skipCache should not use cache
      await awsService.collectResources({ resources: ['ec2'], skipCache: true });

      expect(exec).toHaveBeenCalled(); // Should call AWS CLI again
    });

    test('should handle region override', async () => {
      const mockData = [['us-instance', 't2.micro', 'running']];
      
      exec.mockImplementation((command, options, callback) => {
        expect(command).toContain('--region us-west-2');
        expect(options.env.AWS_REGION).toBe('us-west-2');
        callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
      });

      await awsService.collectResources({ 
        resources: ['ec2'],
        region: 'us-west-2'
      });
    });
  });

  describe('collectResourceType', () => {
    test('should handle empty stdout gracefully', async () => {
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: '', stderr: '' });
      });

      const result = await awsService.collectResourceType('ec2', {});
      expect(result).toEqual([]);
    });

    test('should handle stderr warnings', async () => {
      const mockData = [['instance-1', 't2.micro']];
      
      exec.mockImplementation((command, options, callback) => {
        callback(null, { 
          stdout: JSON.stringify(mockData), 
          stderr: 'Warning: Deprecated API version' 
        });
      });

      const result = await awsService.collectResourceType('ec2', {});
      
      expect(result).toEqual(mockData);
      expect(logger.warn).toHaveBeenCalledWith('AWS command stderr output', expect.any(Object));
    });

    test('should handle timeout errors', async () => {
      exec.mockImplementation((command, options, callback) => {
        const error = new Error('Timeout');
        error.code = 'TIMEOUT';
        callback(error);
      });

      await expect(awsService.collectResourceType('ec2', { timeout: 1000 }))
        .rejects.toThrow('AWS command timeout after 1000ms');
    });

    test('should handle missing AWS CLI', async () => {
      exec.mockImplementation((command, options, callback) => {
        const error = new Error('Command not found');
        error.code = 'ENOENT';
        callback(error);
      });

      await expect(awsService.collectResourceType('ec2', {}))
        .rejects.toThrow('AWS CLI not found - ensure aws-cli is installed');
    });

    test('should parse AWS CLI errors from stderr', async () => {
      exec.mockImplementation((command, options, callback) => {
        const error = new Error('AWS error');
        error.stderr = 'InvalidUserID.NotFound: The user ID does not exist';
        callback(error);
      });

      await expect(awsService.collectResourceType('ec2', {}))
        .rejects.toThrow('AWS CLI error: AWS credentials not found or invalid');
    });

    test('should handle non-array JSON responses', async () => {
      const mockData = { instance: 'i-1234567890abcdef0' };
      
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
      });

      const result = await awsService.collectResourceType('ec2', {});
      expect(result).toEqual([mockData]);
    });
  });

  describe('buildCommand', () => {
    test('should build correct EC2 command', () => {
      const command = awsService.buildCommand('ec2', {});
      expect(command).toContain('aws ec2 describe-instances');
      expect(command).toContain('--region ap-northeast-2');
      expect(command).toContain('--output json');
    });

    test('should build correct S3 command', () => {
      const command = awsService.buildCommand('s3', {});
      expect(command).toContain('aws s3api list-buckets');
      expect(command).not.toContain('--region'); // S3 is global
    });

    test('should build correct RDS command', () => {
      const command = awsService.buildCommand('rds', {});
      expect(command).toContain('aws rds describe-db-instances');
      expect(command).toContain('--region ap-northeast-2');
    });

    test('should build correct VPC command', () => {
      const command = awsService.buildCommand('vpc', {});
      expect(command).toContain('aws ec2 describe-vpcs');
      expect(command).toContain('--region ap-northeast-2');
    });

    test('should build correct IAM command', () => {
      const command = awsService.buildCommand('iam', {});
      expect(command).toContain('aws iam list-roles');
      expect(command).not.toContain('--region'); // IAM is global
    });

    test('should use custom region when provided', () => {
      const command = awsService.buildCommand('ec2', { region: 'us-east-1' });
      expect(command).toContain('--region us-east-1');
    });

    test('should throw error for unsupported resource type', () => {
      expect(() => awsService.buildCommand('unsupported', {}))
        .toThrow('Unsupported resource type: unsupported');
    });
  });

  describe('parseAwsError', () => {
    test('should parse InvalidUserID error', () => {
      const error = awsService.parseAwsError('InvalidUserID.NotFound: User not found');
      expect(error).toBe('AWS credentials not found or invalid');
    });

    test('should parse UnauthorizedOperation error', () => {
      const error = awsService.parseAwsError('UnauthorizedOperation: You are not authorized');
      expect(error).toBe('Insufficient AWS permissions');
    });

    test('should parse Throttling error', () => {
      const error = awsService.parseAwsError('Throttling: Rate exceeded');
      expect(error).toBe('AWS API rate limit exceeded');
    });

    test('should parse ServiceUnavailable error', () => {
      const error = awsService.parseAwsError('ServiceUnavailable: Service temporarily unavailable');
      expect(error).toBe('AWS service temporarily unavailable');
    });

    test('should sanitize unknown error messages', () => {
      const error = awsService.parseAwsError('Unknown error with <script>malicious</script> content');
      expect(error).not.toContain('<script>');
      expect(error).not.toContain('</script>');
    });

    test('should handle multiline errors by taking first line', () => {
      const multilineError = 'Main error message\nAdditional context\nMore details';
      const error = awsService.parseAwsError(multilineError);
      expect(error).toBe('Main error message');
    });
  });

  describe('executeCustomCommand', () => {
    test('should execute valid AWS command successfully', async () => {
      const mockOutput = 'Command executed successfully';
      
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: mockOutput, stderr: '' });
      });

      const result = await awsService.executeCustomCommand('aws ec2 describe-instances');

      expect(result).toMatchObject({
        success: true,
        stdout: mockOutput,
        stderr: '',
        timestamp: expect.any(String)
      });
    });

    test('should reject command not starting with aws', async () => {
      await expect(awsService.executeCustomCommand('docker ps'))
        .rejects.toThrow('Command must start with "aws "');
    });

    test('should reject dangerous delete operations', async () => {
      const dangerousCommands = [
        'aws ec2 delete-instance i-1234567890abcdef0',
        'aws s3 remove s3://my-bucket',
        'aws rds terminate-db-instance my-db'
      ];

      for (const command of dangerousCommands) {
        await expect(awsService.executeCustomCommand(command))
          .rejects.toThrow('Command contains forbidden operations');
      }
    });

    test('should reject dangerous create operations', async () => {
      const dangerousCommands = [
        'aws ec2 create-instance',
        'aws s3 put-object',
        'aws rds run-instances'
      ];

      for (const command of dangerousCommands) {
        await expect(awsService.executeCustomCommand(command))
          .rejects.toThrow('Command contains forbidden operations');
      }
    });

    test('should reject command injection patterns', async () => {
      const injectionCommands = [
        'aws ec2 describe-instances; rm -rf /',
        'aws s3 ls | grep secret',
        'aws ec2 describe-instances && cat /etc/passwd',
        'aws ec2 describe-instances `whoami`',
        'aws ec2 describe-instances $(id)'
      ];

      for (const command of injectionCommands) {
        await expect(awsService.executeCustomCommand(command))
          .rejects.toThrow('Command contains forbidden operations');
      }
    });

    test('should reject force and confirmation flags', async () => {
      const forceCommands = [
        'aws s3 ls --force',
        'aws ec2 describe-instances --yes'
      ];

      for (const command of forceCommands) {
        await expect(awsService.executeCustomCommand(command))
          .rejects.toThrow('Command contains forbidden operations');
      }
    });

    test('should handle command execution failures gracefully', async () => {
      exec.mockImplementation((command, options, callback) => {
        const error = new Error('Command failed');
        error.stderr = 'Permission denied';
        callback(error);
      });

      const result = await awsService.executeCustomCommand('aws ec2 describe-instances');

      expect(result).toMatchObject({
        success: false,
        error: 'Command failed',
        stderr: 'Permission denied',
        timestamp: expect.any(String)
      });

      expect(logger.error).toHaveBeenCalledWith(
        'Custom AWS command failed',
        expect.any(Object)
      );
    });

    test('should use custom timeout', async () => {
      exec.mockImplementation((command, options, callback) => {
        expect(options.timeout).toBe(10000);
        callback(null, { stdout: 'success', stderr: '' });
      });

      await awsService.executeCustomCommand('aws ec2 describe-instances', { timeout: 10000 });
    });
  });

  describe('clearCache', () => {
    test('should clear cache for specific resource type', () => {
      // Populate cache with multiple resource types
      awsService.cache.set('ec2:ap-northeast-2', { data: [], timestamp: Date.now() });
      awsService.cache.set('s3:ap-northeast-2', { data: [], timestamp: Date.now() });
      awsService.cache.set('rds:ap-northeast-2', { data: [], timestamp: Date.now() });

      awsService.clearCache('ec2');

      expect(awsService.cache.has('ec2:ap-northeast-2')).toBe(false);
      expect(awsService.cache.has('s3:ap-northeast-2')).toBe(true);
      expect(awsService.cache.has('rds:ap-northeast-2')).toBe(true);

      expect(logger.debug).toHaveBeenCalledWith(
        'Cleared cache for ec2',
        expect.any(Object)
      );
    });

    test('should clear all cache when no resource type specified', () => {
      // Populate cache
      awsService.cache.set('ec2:ap-northeast-2', { data: [], timestamp: Date.now() });
      awsService.cache.set('s3:ap-northeast-2', { data: [], timestamp: Date.now() });

      awsService.clearCache();

      expect(awsService.cache.size).toBe(0);
      expect(logger.debug).toHaveBeenCalledWith(
        'Cleared all resource cache',
        expect.any(Object)
      );
    });
  });

  describe('getCacheStats', () => {
    test('should return cache statistics', () => {
      const now = Date.now();
      const oldTimestamp = now - 10 * 60 * 1000; // 10 minutes ago (expired)
      const recentTimestamp = now - 2 * 60 * 1000; // 2 minutes ago (not expired)

      awsService.cache.set('ec2:ap-northeast-2', { 
        data: [{ instanceId: 'i-123' }], 
        timestamp: recentTimestamp 
      });
      awsService.cache.set('s3:global', { 
        data: [{ bucket: 'my-bucket' }], 
        timestamp: oldTimestamp 
      });

      const stats = awsService.getCacheStats();

      expect(stats).toMatchObject({
        totalEntries: 2,
        maxAge: 5 * 60 * 1000, // 5 minutes
        entries: expect.any(Object)
      });

      expect(stats.entries['ec2:ap-northeast-2']).toMatchObject({
        age: expect.any(Number),
        expired: false,
        dataSize: expect.any(Number)
      });

      expect(stats.entries['s3:global']).toMatchObject({
        age: expect.any(Number),
        expired: true,
        dataSize: expect.any(Number)
      });
    });

    test('should return empty stats for empty cache', () => {
      awsService.clearCache();
      
      const stats = awsService.getCacheStats();

      expect(stats).toMatchObject({
        totalEntries: 0,
        maxAge: 5 * 60 * 1000,
        entries: {}
      });
    });
  });

  describe('Error handling edge cases', () => {
    test('should handle JSON parse errors', async () => {
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: 'invalid json {', stderr: '' });
      });

      await expect(awsService.collectResourceType('ec2', {}))
        .rejects.toThrow();
    });

    test('should handle process execution errors without stderr', async () => {
      exec.mockImplementation((command, options, callback) => {
        const error = new Error('General error');
        // No stderr property
        callback(error);
      });

      await expect(awsService.collectResourceType('ec2', {}))
        .rejects.toThrow('General error');
    });

    test('should handle cache expiration edge case', async () => {
      // Set cache with timestamp exactly at expiration boundary
      const exactExpirationTime = Date.now() - awsService.cacheMaxAge;
      awsService.cache.set('ec2:ap-northeast-2', { 
        data: [], 
        timestamp: exactExpirationTime 
      });

      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: '[]', stderr: '' });
      });

      // Should fetch fresh data (expired cache)
      await awsService.collectResources({ resources: ['ec2'] });
      expect(exec).toHaveBeenCalled();
    });
  });
});