/**
 * @fileoverview Analyze Route 추가 테스트 - 미커버 라인 100% 커버리지
 * @description analyze.js의 미커버 라인들을 테스트
 */

const request = require('supertest');
const createApp = require('../../../../src/app');
const awsService = require('../../../../src/services/aws/awsService');
const claudeService = require('../../../../src/services/claude/claudeService');

// Mock services
jest.mock('../../../../src/services/aws/awsService');
jest.mock('../../../../src/services/claude/claudeService');
jest.mock('../../../../utils/logger', () => ({
  info: jest.fn(),
  debug: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  performance: jest.fn()
}));

describe('Analyze Route - Additional Coverage Tests', () => {
  let app;

  beforeAll(() => {
    app = createApp;
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Validation Edge Cases', () => {
    test('should reject empty resources array - Line 66', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: [] // Empty array should trigger line 66
        })
        .expect(400);

      expect(response.body).toMatchObject({
        success: false,
        error: 'At least one resource type is required'
      });
    });

    test('should reject invalid resource types - Line 87', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 'invalid-service', 's3'] // Contains invalid service
        })
        .expect(400);

      expect(response.body).toMatchObject({
        success: false,
        error: expect.stringContaining('Unsupported resource types: invalid-service')
      });
    });

    test('should handle multiple invalid resource types', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['invalid1', 'invalid2', 'ec2']
        })
        .expect(400);

      expect(response.body).toMatchObject({
        success: false,
        error: expect.stringContaining('Unsupported resource types: invalid1, invalid2')
      });
    });
  });

  describe('Service Error Handling - Lines 142, 146', () => {
    test('should handle AWS service timeout errors - Line 142', async () => {
      // Mock AWS service to throw timeout error
      awsService.collectResources.mockImplementationOnce(() => {
        const timeoutError = new Error('Request timeout');
        timeoutError.code = 'TIMEOUT';
        throw timeoutError;
      });

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2']
        })
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Internal Server Error'
      });
    });

    test('should handle Claude service authentication errors - Line 146', async () => {
      // Mock successful AWS collection
      awsService.collectResources.mockResolvedValueOnce({
        ec2: [['i-123', 't2.micro']]
      });

      // Mock Claude service to throw auth error
      claudeService.analyzeAwsData.mockImplementationOnce(() => {
        const authError = new Error('Authentication failed');
        authError.statusCode = 401;
        throw authError;
      });

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2']
        })
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Internal Server Error'
      });
    });

    test('should handle generic AWS service errors', async () => {
      awsService.collectResources.mockImplementationOnce(() => {
        throw new Error('AWS credentials not found');
      });

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2']
        })
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Internal Server Error',
        message: expect.any(String),
        timestamp: expect.any(String)
      });
    });

    test('should handle generic Claude service errors', async () => {
      awsService.collectResources.mockResolvedValueOnce({
        ec2: [['i-123', 't2.micro']]
      });

      claudeService.analyzeAwsData.mockImplementationOnce(() => {
        throw new Error('Claude API server error');
      });

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2']
        })
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Internal Server Error'
      });
    });
  });

  describe('Request Processing Success Scenarios', () => {
    test('should handle successful analysis with all resource types', async () => {
      const mockAwsData = {
        ec2: [['i-123', 't2.micro']],
        s3: [['bucket-1', '2023-01-01']],
        rds: [['db-1', 'mysql']],
        vpc: [['vpc-1', '10.0.0.0/16']],
        iam: [['role-1', 'admin']]
      };

      const mockClaudeResponse = {
        content: [{ type: 'text', text: 'Complete analysis' }],
        usage: { total_tokens: 150 }
      };

      awsService.collectResources.mockResolvedValueOnce(mockAwsData);
      claudeService.analyzeAwsData.mockResolvedValueOnce(mockClaudeResponse);

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 's3', 'rds', 'vpc', 'iam'],
          options: {
            analysisType: 'security_only',
            region: 'us-west-2',
            skipCache: true
          }
        })
        .expect(200);

      expect(response.body).toMatchObject({
        success: true,
        data: {
          awsResources: mockAwsData,
          analysis: mockClaudeResponse
        },
        metadata: {
          totalResources: 5,
          analysisType: 'security_only',
          region: 'us-west-2',
          timestamp: expect.any(String)
        }
      });

      // Verify service calls with correct parameters
      expect(awsService.collectResources).toHaveBeenCalledWith({
        resources: ['ec2', 's3', 'rds', 'vpc', 'iam'],
        region: 'us-west-2',
        skipCache: true
      });

      expect(claudeService.analyzeAwsData).toHaveBeenCalledWith(mockAwsData, {
        analysisType: 'security_only'
      });
    });

    test('should handle partial AWS data with errors', async () => {
      const mockAwsData = {
        ec2: [['i-123', 't2.micro']],
        s3: {
          error: 'Permission denied',
          data: []
        }
      };

      const mockClaudeResponse = {
        content: [{ type: 'text', text: 'Partial analysis due to errors' }]
      };

      awsService.collectResources.mockResolvedValueOnce(mockAwsData);
      claudeService.analyzeAwsData.mockResolvedValueOnce(mockClaudeResponse);

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 's3']
        })
        .expect(200);

      expect(response.body).toMatchObject({
        success: true,
        data: {
          awsResources: mockAwsData,
          analysis: mockClaudeResponse
        }
      });
    });
  });

  describe('Request ID and Metadata Handling', () => {
    test('should generate proper metadata with resource counting', async () => {
      const mockAwsData = {
        ec2: [['i-1'], ['i-2'], ['i-3']], // 3 resources
        s3: [['bucket-1']], // 1 resource
        rds: [] // 0 resources
      };

      awsService.collectResources.mockResolvedValueOnce(mockAwsData);
      claudeService.analyzeAwsData.mockResolvedValueOnce({
        content: [{ type: 'text', text: 'Analysis' }]
      });

      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 's3', 'rds']
        })
        .expect(200);

      expect(response.body.metadata).toMatchObject({
        totalResources: 4, // 3 + 1 + 0
        analysisType: 'security_and_optimization', // default
        timestamp: expect.any(String)
      });
    });

    test('should handle custom analysis options correctly', async () => {
      awsService.collectResources.mockResolvedValueOnce({ ec2: [['i-123']] });
      claudeService.analyzeAwsData.mockResolvedValueOnce({
        content: [{ type: 'text', text: 'Cost analysis' }]
      });

      await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2'],
          options: {
            analysisType: 'cost_only',
            maxTokens: 1000
          }
        })
        .expect(200);

      expect(claudeService.analyzeAwsData).toHaveBeenCalledWith(
        { ec2: [['i-123']] },
        {
          analysisType: 'cost_only',
          maxTokens: 1000
        }
      );
    });
  });

  describe('Performance and Timing', () => {
    test('should complete within performance requirements', async () => {
      awsService.collectResources.mockResolvedValueOnce({
        ec2: [['i-123']]
      });
      claudeService.analyzeAwsData.mockResolvedValueOnce({
        content: [{ type: 'text', text: 'Fast analysis' }]
      });

      const startTime = Date.now();
      
      await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2']
        })
        .expect(200);

      const duration = Date.now() - startTime;
      expect(duration).toBeLessThan(5000); // CLAUDE.md requirement: < 5 seconds
    });
  });
});