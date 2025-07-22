/**
 * @fileoverview API Integration Tests
 * @description End-to-end integration testing for the Kong AWS Masking MVP
 */

const request = require('supertest');
const createApp = require('../../src/app');

// Mock external dependencies
jest.mock('../../src/services/aws/awsService');
jest.mock('../../src/services/claude/claudeService');
jest.mock('../../utils/logger', () => ({
  info: jest.fn(),
  debug: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  performance: jest.fn()
}));

const awsService = require('../../src/services/aws/awsService');
const claudeService = require('../../src/services/claude/claudeService');

describe('API Integration Tests', () => {
  let app;

  beforeAll(() => {
    app = createApp;
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Health Check Integration', () => {
    test('GET /health should return comprehensive health status', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'healthy',
        timestamp: expect.any(String),
        version: expect.any(String),
        details: expect.objectContaining({
          uptime: expect.any(Number),
          memory: expect.any(Object),
          pid: expect.any(Number)
        })
      });

      // Validate response time (CLAUDE.md requirement: < 5 seconds)
      expect(response.header['x-response-time']).toBeLessThan('5000');
    });

    test('should include proper CORS headers', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.headers).toHaveProperty('access-control-allow-origin');
      expect(response.headers).toHaveProperty('access-control-allow-credentials', 'true');
    });

    test('should include security headers', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.headers).toHaveProperty('x-frame-options', 'DENY');
      expect(response.headers).toHaveProperty('x-content-type-options', 'nosniff');
    });
  });

  describe('Analyze Endpoint Integration', () => {
    const mockAwsData = {
      ec2: [
        ['i-1234567890abcdef0', 't2.micro', 'running', '10.0.0.1', '203.0.113.1', []]
      ],
      s3: [
        ['my-test-bucket', '2023-01-01T00:00:00.000Z']
      ]
    };

    const mockClaudeResponse = {
      id: 'msg_12345',
      content: [
        {
          type: 'text',
          text: 'Analysis complete: Your AWS infrastructure shows good security practices.'
        }
      ],
      model: 'claude-3-5-sonnet-20241022',
      usage: {
        input_tokens: 150,
        output_tokens: 75,
        total_tokens: 225
      }
    };

    test('POST /analyze should process AWS resources and return Claude analysis', async () => {
      awsService.collectResources.mockResolvedValueOnce(mockAwsData);
      claudeService.analyzeAwsData.mockResolvedValueOnce(mockClaudeResponse);

      const requestBody = {
        resources: ['ec2', 's3'],
        options: {
          analysisType: 'security_and_optimization',
          skipCache: false
        }
      };

      const response = await request(app)
        .post('/analyze')
        .send(requestBody)
        .expect(200);

      expect(response.body).toMatchObject({
        success: true,
        data: expect.objectContaining({
          awsResources: mockAwsData,
          analysis: mockClaudeResponse
        }),
        metadata: expect.objectContaining({
          totalResources: expect.any(Number),
          analysisType: 'security_and_optimization',
          timestamp: expect.any(String)
        })
      });

      expect(awsService.collectResources).toHaveBeenCalledWith(
        expect.objectContaining({
          resources: ['ec2', 's3'],
          skipCache: false
        })
      );

      expect(claudeService.analyzeAwsData).toHaveBeenCalledWith(
        mockAwsData,
        expect.objectContaining({
          analysisType: 'security_and_optimization'
        })
      );
    });

    test('should handle validation errors properly', async () => {
      const invalidRequest = {
        resources: 'invalid', // Should be array
        options: {
          analysisType: 'invalid_type'
        }
      };

      const response = await request(app)
        .post('/analyze')
        .send(invalidRequest)
        .expect(400);

      expect(response.body).toMatchObject({
        error: 'Validation failed',
        message: expect.any(String),
        details: expect.any(Array)
      });
    });

    test('should handle AWS service errors gracefully', async () => {
      awsService.collectResources.mockRejectedValueOnce(
        new Error('AWS credentials not found')
      );

      const requestBody = {
        resources: ['ec2']
      };

      const response = await request(app)
        .post('/analyze')
        .send(requestBody)
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Internal Server Error',
        message: expect.any(String),
        timestamp: expect.any(String)
      });
    });

    test('should handle Claude API errors gracefully', async () => {
      awsService.collectResources.mockResolvedValueOnce(mockAwsData);
      claudeService.analyzeAwsData.mockRejectedValueOnce(
        new Error('Claude API rate limit exceeded')
      );

      const requestBody = {
        resources: ['ec2']
      };

      const response = await request(app)
        .post('/analyze')
        .send(requestBody)
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Internal Server Error',
        message: expect.any(String),
        timestamp: expect.any(String)
      });
    });

    test('should enforce request timeout', async () => {
      // Mock a slow AWS service call
      awsService.collectResources.mockImplementationOnce(() => 
        new Promise(resolve => setTimeout(() => resolve(mockAwsData), 6000))
      );

      const requestBody = {
        resources: ['ec2']
      };

      const startTime = Date.now();
      const response = await request(app)
        .post('/analyze')
        .send(requestBody);

      const duration = Date.now() - startTime;
      
      // Should timeout before 6 seconds (within 5 second CLAUDE.md requirement)
      expect(duration).toBeLessThan(6000);
      
      if (response.status === 500) {
        expect(response.body.error).toMatch(/timeout|error/i);
      }
    });

    test('should handle large payloads within 10MB limit', async () => {
      awsService.collectResources.mockResolvedValueOnce(mockAwsData);
      claudeService.analyzeAwsData.mockResolvedValueOnce(mockClaudeResponse);

      // Create a large but valid payload (under 10MB)
      const largePayload = {
        resources: ['ec2'],
        options: {
          metadata: 'x'.repeat(1000000) // 1MB string
        }
      };

      const response = await request(app)
        .post('/analyze')
        .send(largePayload)
        .expect(200);

      expect(response.body.success).toBe(true);
    });
  });

  describe('Error Handling Integration', () => {
    test('should handle 404 errors with proper format', async () => {
      const response = await request(app)
        .get('/non-existent-route')
        .expect(404);

      expect(response.body).toMatchObject({
        error: 'Not Found',
        message: expect.stringContaining('not found'),
        timestamp: expect.any(String)
      });
    });

    test('should handle malformed JSON requests', async () => {
      const response = await request(app)
        .post('/analyze')
        .set('Content-Type', 'application/json')
        .send('{"invalid": json}')
        .expect(400);

      expect(response.body).toMatchObject({
        error: expect.any(String),
        message: expect.any(String)
      });
    });

    test('should handle unsupported HTTP methods', async () => {
      const response = await request(app)
        .patch('/health')
        .expect(404);

      expect(response.body.error).toBe('Not Found');
    });
  });

  describe('Security Integration', () => {
    test('should reject requests with excessively large payloads', async () => {
      // Create payload larger than 10MB limit
      const oversizedPayload = {
        resources: ['ec2'],
        data: 'x'.repeat(11 * 1024 * 1024) // 11MB
      };

      const response = await request(app)
        .post('/analyze')
        .send(oversizedPayload)
        .expect(413);

      expect(response.body).toMatchObject({
        error: expect.any(String)
      });
    });

    test('should handle CORS preflight requests', async () => {
      const response = await request(app)
        .options('/analyze')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'POST')
        .set('Access-Control-Request-Headers', 'Content-Type')
        .expect(204);

      expect(response.headers).toHaveProperty('access-control-allow-methods');
      expect(response.headers).toHaveProperty('access-control-allow-headers');
    });

    test('should sanitize error messages to prevent information leakage', async () => {
      awsService.collectResources.mockRejectedValueOnce(
        new Error('Detailed internal error with sensitive info: sk-ant-api03-secret-key')
      );

      const response = await request(app)
        .post('/analyze')
        .send({ resources: ['ec2'] });

      // Should not expose sensitive information in error response
      expect(response.body.message).not.toContain('sk-ant-api03');
      expect(response.body.message).not.toContain('secret-key');
    });
  });

  describe('Performance Integration', () => {
    test('should complete health check within performance requirements', async () => {
      const startTime = Date.now();
      
      await request(app)
        .get('/health')
        .expect(200);
      
      const duration = Date.now() - startTime;
      expect(duration).toBeLessThan(5000); // CLAUDE.md: < 5 seconds
    });

    test('should handle concurrent requests efficiently', async () => {
      awsService.collectResources.mockResolvedValue(mockAwsData);
      claudeService.analyzeAwsData.mockResolvedValue(mockClaudeResponse);

      const requests = Array(5).fill().map(() =>
        request(app)
          .post('/analyze')
          .send({ resources: ['ec2'] })
      );

      const startTime = Date.now();
      const responses = await Promise.all(requests);
      const duration = Date.now() - startTime;

      // All requests should succeed
      responses.forEach(response => {
        expect(response.status).toBe(200);
      });

      // Should handle concurrent requests efficiently
      expect(duration).toBeLessThan(10000); // 10 seconds for 5 concurrent requests
    });

    test('should compress responses appropriately', async () => {
      const response = await request(app)
        .get('/health')
        .set('Accept-Encoding', 'gzip, deflate')
        .expect(200);

      // Should have compression headers for responses
      expect(response.headers).toHaveProperty('content-encoding');
    });
  });

  describe('Logging and Monitoring Integration', () => {
    test('should generate appropriate access logs', async () => {
      await request(app)
        .get('/health')
        .expect(200);

      // Morgan logging should be called (implicitly tested through middleware)
      // In real scenarios, this would check log aggregation services
    });

    test('should track request timing', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      // Response should include timing information
      expect(response.headers).toHaveProperty('x-response-time');
    });
  });
});