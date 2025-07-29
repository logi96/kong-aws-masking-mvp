/**
 * @fileoverview Unit tests for analyze routes
 * @module tests/unit/analyze
 */

const request = require('supertest');
const app = require('../../src/app');
const awsService = require('../../src/services/aws/awsService');
const claudeService = require('../../src/services/claude/claudeService');
const logger = require('../../src/utils/logger');

// Mock dependencies
jest.mock('../../src/services/aws/awsService');
jest.mock('../../src/services/claude/claudeService');
jest.mock('../../src/utils/logger');

describe('Analyze Routes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('POST /analyze', () => {
    it('should analyze AWS resources successfully', async () => {
      const mockAWSData = {
        resources: {
          ec2: {
            instances: [{ InstanceId: 'i-123' }],
            securityGroups: [],
            keyPairs: []
          },
          s3: {
            buckets: [{ Name: 'bucket-1' }],
            totalBuckets: 1
          }
        },
        metadata: {
          region: 'ap-northeast-2',
          timestamp: new Date().toISOString(),
          resourceTypes: ['ec2', 's3']
        }
      };

      const mockAnalysis = {
        analysis: 'Security analysis complete. No issues found.',
        model: 'claude-3-5-sonnet-20241022',
        usage: { input_tokens: 100, output_tokens: 200 },
        processingTime: 1500,
        metadata: {
          maskedResources: '5',
          requestId: 'req-123'
        }
      };

      awsService.fetchResources.mockResolvedValue(mockAWSData);
      claudeService.analyzeResources.mockResolvedValue(mockAnalysis);

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 's3'],
          options: {
            analysisType: 'security'
          }
        })
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'success',
        data: {
          awsResources: mockAWSData,
          analysis: mockAnalysis,
          requestId: expect.any(String),
          timestamp: expect.any(String)
        }
      });

      expect(awsService.fetchResources).toHaveBeenCalledWith(['ec2', 's3']);
      expect(claudeService.analyzeResources).toHaveBeenCalledWith(
        mockAWSData,
        expect.objectContaining({
          analysisType: 'security'
        })
      );
    });

    it('should validate required resources parameter', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({})
        .expect(400);

      expect(response.body.error.details).toContainEqual(
        expect.objectContaining({
          path: 'resources',
          msg: 'Resources must be an array'
        })
      );
    });

    it('should validate resources array is not empty', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({ resources: [] })
        .expect(400);

      expect(response.body.error.details).toContainEqual(
        expect.objectContaining({
          path: 'resources',
          msg: 'Resources array cannot be empty'
        })
      );
    });

    it('should validate invalid resource types', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({ resources: ['invalid-resource'] })
        .expect(400);

      expect(response.body.error.details).toContainEqual(
        expect.objectContaining({
          path: 'resources[0]',
          msg: 'Invalid resource type'
        })
      );
    });

    it('should handle AWS service errors', async () => {
      awsService.fetchResources.mockRejectedValue(
        new Error('AWS credentials not configured')
      );

      const response = await request(app)
        .post('/analyze')
        .send({ resources: ['ec2'] })
        .expect(500);

      expect(response.body.error.message).toContain('AWS credentials not configured');
      expect(logger.error).toHaveBeenCalled();
    });

    it('should handle Claude service errors', async () => {
      awsService.fetchResources.mockResolvedValue({ resources: { ec2: {} } });
      claudeService.analyzeResources.mockRejectedValue(
        new Error('Claude API rate limit exceeded')
      );

      const response = await request(app)
        .post('/analyze')
        .send({ resources: ['ec2'] })
        .expect(500);

      expect(response.body.error.message).toContain('Claude API rate limit exceeded');
    });

    it('should support all valid resource types', async () => {
      awsService.fetchResources.mockResolvedValue({
        resources: { ec2: {}, s3: {}, rds: {}, lambda: {}, iam: {}, vpc: {} }
      });
      claudeService.analyzeResources.mockResolvedValue({
        analysis: 'Analysis complete',
        metadata: {}
      });

      const response = await request(app)
        .post('/analyze')
        .send({ resources: ['ec2', 's3', 'rds', 'lambda', 'iam', 'vpc'] })
        .expect(200);

      expect(awsService.fetchResources).toHaveBeenCalledWith(['ec2', 's3', 'rds', 'lambda', 'iam', 'vpc']);
    });

    it('should validate analysis type options', async () => {
      awsService.fetchResources.mockResolvedValue({ resources: {} });
      claudeService.analyzeResources.mockResolvedValue({ analysis: 'ok' });

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2'],
          options: {
            analysisType: 'invalid-type'
          }
        })
        .expect(400);

      expect(response.body.error.details).toContainEqual(
        expect.objectContaining({
          path: 'options.analysisType',
          msg: 'Invalid analysis type'
        })
      );
    });

    it('should handle valid analysis types', async () => {
      awsService.fetchResources.mockResolvedValue({ resources: {} });
      claudeService.analyzeResources.mockResolvedValue({ analysis: 'ok' });

      const validTypes = ['security', 'cost', 'performance', 'all'];
      
      for (const type of validTypes) {
        await request(app)
          .post('/analyze')
          .send({
            resources: ['ec2'],
            options: { analysisType: type }
          })
          .expect(200);
      }

      expect(claudeService.analyzeResources).toHaveBeenCalledTimes(validTypes.length);
    });

    it('should include request metadata in response', async () => {
      awsService.fetchResources.mockResolvedValue({ resources: {} });
      claudeService.analyzeResources.mockResolvedValue({
        analysis: 'ok',
        processingTime: 1234,
        usage: { input_tokens: 100, output_tokens: 200 }
      });

      const response = await request(app)
        .post('/analyze')
        .send({ resources: ['ec2'] })
        .expect(200);

      expect(response.body.data).toMatchObject({
        requestId: expect.stringMatching(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/),
        timestamp: expect.any(String)
      });
    });
  });

  describe('GET /analyze/health', () => {
    it('should return analyze service health status', async () => {
      awsService.validateCredentials = jest.fn().mockResolvedValue(true);

      const response = await request(app)
        .get('/analyze/health')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'healthy',
        services: {
          aws: 'connected',
          claude: 'configured'
        }
      });
    });

    it('should report unhealthy when AWS credentials invalid', async () => {
      awsService.validateCredentials = jest.fn().mockResolvedValue(false);

      const response = await request(app)
        .get('/analyze/health')
        .expect(200);

      expect(response.body.services.aws).toBe('disconnected');
    });
  });
});