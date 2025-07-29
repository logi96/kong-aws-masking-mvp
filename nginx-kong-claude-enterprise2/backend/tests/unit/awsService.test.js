/**
 * @fileoverview Unit tests for AWS service
 * @module tests/unit/awsService
 */

const { promisify } = require('util');
const awsService = require('../../src/services/aws/awsService');
const logger = require('../../src/utils/logger');

// Mock child_process exec
jest.mock('util', () => ({
  ...jest.requireActual('util'),
  promisify: jest.fn(() => jest.fn())
}));

jest.mock('../../src/utils/logger');

describe('AWS Service', () => {
  let mockExecAsync;

  beforeEach(() => {
    jest.clearAllMocks();
    mockExecAsync = jest.fn();
    promisify.mockReturnValue(mockExecAsync);
    
    // Reset environment
    process.env.AWS_REGION = 'ap-northeast-2';
  });

  describe('executeAwsCommand', () => {
    it('should execute AWS CLI command successfully', async () => {
      const mockOutput = JSON.stringify({
        Reservations: [{
          Instances: [{
            InstanceId: 'i-1234567890abcdef0',
            InstanceType: 't2.micro',
            State: { Name: 'running' }
          }]
        }]
      });

      mockExecAsync.mockResolvedValue({ stdout: mockOutput, stderr: '' });

      const result = await awsService.executeAwsCommand('ec2 describe-instances');

      expect(result).toEqual(JSON.parse(mockOutput));
      expect(mockExecAsync).toHaveBeenCalledWith(
        'aws ec2 describe-instances --region ap-northeast-2 --output json',
        expect.objectContaining({
          timeout: 30000,
          maxBuffer: 10 * 1024 * 1024
        })
      );
    });

    it('should handle AWS CLI errors', async () => {
      const error = new Error('Command failed');
      error.code = 1;
      mockExecAsync.mockRejectedValue(error);

      await expect(
        awsService.executeAwsCommand('ec2 describe-instances')
      ).rejects.toThrow('AWS CLI error');

      expect(logger.error).toHaveBeenCalledWith('AWS CLI command failed:', error);
    });

    it('should handle AWS CLI not found', async () => {
      const error = new Error('Command not found');
      error.code = 'ENOENT';
      mockExecAsync.mockRejectedValue(error);

      await expect(
        awsService.executeAwsCommand('ec2 describe-instances')
      ).rejects.toThrow('AWS CLI not found');
    });

    it('should handle command timeout', async () => {
      const error = new Error('Command timed out');
      error.killed = true;
      error.signal = 'SIGTERM';
      mockExecAsync.mockRejectedValue(error);

      await expect(
        awsService.executeAwsCommand('ec2 describe-instances')
      ).rejects.toThrow('AWS CLI command timed out');
    });

    it('should log stderr warnings', async () => {
      mockExecAsync.mockResolvedValue({ 
        stdout: '{}', 
        stderr: 'Warning: deprecated parameter' 
      });

      await awsService.executeAwsCommand('s3api list-buckets');

      expect(logger.warn).toHaveBeenCalledWith(
        'AWS CLI stderr: Warning: deprecated parameter'
      );
    });
  });

  describe('fetchResources', () => {
    beforeEach(() => {
      // Mock successful responses
      mockExecAsync.mockImplementation((command) => {
        if (command.includes('describe-instances')) {
          return Promise.resolve({
            stdout: JSON.stringify({ Reservations: [] }),
            stderr: ''
          });
        }
        if (command.includes('describe-security-groups')) {
          return Promise.resolve({
            stdout: JSON.stringify({ SecurityGroups: [] }),
            stderr: ''
          });
        }
        if (command.includes('describe-key-pairs')) {
          return Promise.resolve({
            stdout: JSON.stringify({ KeyPairs: [] }),
            stderr: ''
          });
        }
        if (command.includes('list-buckets')) {
          return Promise.resolve({
            stdout: JSON.stringify({ Buckets: [] }),
            stderr: ''
          });
        }
        if (command.includes('describe-db-instances')) {
          return Promise.resolve({
            stdout: JSON.stringify({ DBInstances: [] }),
            stderr: ''
          });
        }
        if (command.includes('describe-db-clusters')) {
          return Promise.resolve({
            stdout: JSON.stringify({ DBClusters: [] }),
            stderr: ''
          });
        }
        if (command.includes('describe-db-snapshots')) {
          return Promise.resolve({
            stdout: JSON.stringify({ DBSnapshots: [] }),
            stderr: ''
          });
        }
        return Promise.resolve({ stdout: '{}', stderr: '' });
      });
    });

    it('should fetch EC2 resources', async () => {
      const result = await awsService.fetchResources(['ec2']);

      expect(result.resources).toHaveProperty('ec2');
      expect(result.resources.ec2).toMatchObject({
        instances: [],
        securityGroups: [],
        keyPairs: []
      });
      expect(result.metadata).toMatchObject({
        region: 'ap-northeast-2',
        resourceTypes: ['ec2']
      });
    });

    it('should fetch S3 resources', async () => {
      mockExecAsync.mockImplementation((command) => {
        if (command.includes('list-buckets')) {
          return Promise.resolve({
            stdout: JSON.stringify({ 
              Buckets: [
                { Name: 'bucket-1', CreationDate: '2023-01-01' }
              ] 
            }),
            stderr: ''
          });
        }
        return Promise.resolve({ stdout: '{}', stderr: '' });
      });

      const result = await awsService.fetchResources(['s3']);

      expect(result.resources.s3).toMatchObject({
        buckets: expect.any(Array),
        totalBuckets: 1
      });
    });

    it('should fetch RDS resources', async () => {
      const result = await awsService.fetchResources(['rds']);

      expect(result.resources.rds).toMatchObject({
        instances: [],
        clusters: [],
        snapshots: []
      });
    });

    it('should handle multiple resource types', async () => {
      const result = await awsService.fetchResources(['ec2', 's3', 'rds']);

      expect(result.resources).toHaveProperty('ec2');
      expect(result.resources).toHaveProperty('s3');
      expect(result.resources).toHaveProperty('rds');
    });

    it('should handle unsupported resource types', async () => {
      const result = await awsService.fetchResources(['invalid']);

      expect(result.errors).toContainEqual({
        resource: 'invalid',
        error: 'Unsupported resource type'
      });
    });

    it('should handle partial failures', async () => {
      mockExecAsync.mockImplementation((command) => {
        if (command.includes('describe-instances')) {
          throw new Error('EC2 API error');
        }
        if (command.includes('list-buckets')) {
          return Promise.resolve({
            stdout: JSON.stringify({ Buckets: [] }),
            stderr: ''
          });
        }
        return Promise.resolve({ stdout: '{}', stderr: '' });
      });

      const result = await awsService.fetchResources(['ec2', 's3']);

      expect(result.resources).toHaveProperty('s3');
      expect(result.errors).toContainEqual({
        resource: 'ec2',
        error: expect.stringContaining('error')
      });
    });

    it('should throw error when all resources fail', async () => {
      mockExecAsync.mockRejectedValue(new Error('API error'));

      await expect(
        awsService.fetchResources(['ec2'])
      ).rejects.toThrow('Failed to fetch any resources');
    });
  });

  describe('fetchEC2Resources', () => {
    it('should fetch all EC2 resource types', async () => {
      mockExecAsync
        .mockResolvedValueOnce({
          stdout: JSON.stringify({ 
            Reservations: [{ Instances: [{ InstanceId: 'i-123' }] }] 
          }),
          stderr: ''
        })
        .mockResolvedValueOnce({
          stdout: JSON.stringify({ 
            SecurityGroups: [{ GroupId: 'sg-123' }] 
          }),
          stderr: ''
        })
        .mockResolvedValueOnce({
          stdout: JSON.stringify({ 
            KeyPairs: [{ KeyName: 'my-key' }] 
          }),
          stderr: ''
        });

      const result = await awsService.fetchEC2Resources();

      expect(result).toMatchObject({
        instances: [{ Instances: [{ InstanceId: 'i-123' }] }],
        securityGroups: [{ GroupId: 'sg-123' }],
        keyPairs: [{ KeyName: 'my-key' }]
      });
    });

    it('should handle empty EC2 responses', async () => {
      mockExecAsync.mockResolvedValue({ stdout: '{}', stderr: '' });

      const result = await awsService.fetchEC2Resources();

      expect(result).toMatchObject({
        instances: [],
        securityGroups: [],
        keyPairs: []
      });
    });
  });

  describe('fetchS3Resources', () => {
    it('should fetch bucket details for up to 10 buckets', async () => {
      const buckets = Array(15).fill(null).map((_, i) => ({
        Name: `bucket-${i}`,
        CreationDate: '2023-01-01'
      }));

      mockExecAsync
        .mockResolvedValueOnce({
          stdout: JSON.stringify({ Buckets: buckets }),
          stderr: ''
        })
        .mockResolvedValue({
          stdout: JSON.stringify({ LocationConstraint: 'ap-northeast-2' }),
          stderr: ''
        });

      const result = await awsService.fetchS3Resources();

      expect(result.totalBuckets).toBe(15);
      expect(result.buckets).toHaveLength(10); // Limited to 10
    });

    it('should handle bucket detail fetch errors gracefully', async () => {
      mockExecAsync
        .mockResolvedValueOnce({
          stdout: JSON.stringify({ 
            Buckets: [{ Name: 'bucket-1', CreationDate: '2023-01-01' }] 
          }),
          stderr: ''
        })
        .mockRejectedValue(new Error('Access denied'));

      const result = await awsService.fetchS3Resources();

      expect(result.buckets).toHaveLength(1);
      expect(logger.warn).toHaveBeenCalledWith(
        expect.stringContaining('Failed to get details'),
        expect.any(String)
      );
    });
  });

  describe('validateCredentials', () => {
    it('should return true when credentials are valid', async () => {
      mockExecAsync.mockResolvedValue({
        stdout: JSON.stringify({ UserId: 'user123' }),
        stderr: ''
      });

      const isValid = await awsService.validateCredentials();

      expect(isValid).toBe(true);
      expect(mockExecAsync).toHaveBeenCalledWith(
        expect.stringContaining('sts get-caller-identity'),
        expect.any(Object)
      );
    });

    it('should return false when credentials are invalid', async () => {
      mockExecAsync.mockRejectedValue(new Error('Invalid credentials'));

      const isValid = await awsService.validateCredentials();

      expect(isValid).toBe(false);
      expect(logger.error).toHaveBeenCalled();
    });
  });
});