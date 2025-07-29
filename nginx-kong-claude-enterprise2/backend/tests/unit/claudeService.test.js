/**
 * @fileoverview Unit tests for Claude service
 * @module tests/unit/claudeService
 */

const claudeService = require('../../src/services/claude/claudeService');
const axios = require('axios');
const logger = require('../../src/utils/logger');

// Mock dependencies
jest.mock('axios');
jest.mock('../../src/utils/logger');

describe('Claude Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Set test environment
    process.env.ANTHROPIC_API_KEY = 'test-api-key';
    process.env.KONG_PROXY_URL = 'http://kong:8000';
  });

  describe('analyzeResources', () => {
    it('should successfully analyze AWS resources', async () => {
      const mockAWSData = {
        resources: {
          ec2: { instances: [] },
          s3: { buckets: [] }
        }
      };

      const mockResponse = {
        data: {
          content: [{
            text: 'Analysis results: No security issues found.'
          }],
          model: 'claude-3-5-sonnet-20241022',
          usage: {
            input_tokens: 100,
            output_tokens: 200
          }
        },
        headers: {
          'x-masked-resources': '5',
          'x-request-id': 'req-123'
        }
      };

      axios.post.mockResolvedValue(mockResponse);

      const result = await claudeService.analyzeResources(mockAWSData);

      expect(result).toMatchObject({
        analysis: 'Analysis results: No security issues found.',
        model: 'claude-3-5-sonnet-20241022',
        usage: {
          input_tokens: 100,
          output_tokens: 200
        },
        processingTime: expect.any(Number),
        metadata: {
          maskedResources: '5',
          requestId: 'req-123'
        }
      });

      expect(axios.post).toHaveBeenCalledWith(
        'http://kong:8000/analyze',
        expect.objectContaining({
          model: 'claude-3-5-sonnet-20241022',
          max_tokens: 4096,
          messages: expect.arrayContaining([
            expect.objectContaining({
              role: 'user',
              content: expect.any(String)
            })
          ])
        }),
        expect.objectContaining({
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': 'test-api-key'
          },
          timeout: 60000
        })
      );
    });

    it('should throw error when API key is not configured', async () => {
      delete process.env.ANTHROPIC_API_KEY;
      // Recreate the service without API key
      jest.resetModules();
      const serviceWithoutKey = require('../../src/services/claude/claudeService');

      await expect(
        serviceWithoutKey.analyzeResources({})
      ).rejects.toThrow('Claude API key not configured');
    });

    it('should handle API errors with proper status codes', async () => {
      const error = new Error('API Error');
      error.response = {
        status: 429,
        data: {
          error: { message: 'Rate limit exceeded' }
        }
      };

      axios.post.mockRejectedValue(error);

      await expect(
        claudeService.analyzeResources({})
      ).rejects.toThrow('Rate limit exceeded');

      expect(logger.error).toHaveBeenCalledWith(
        'Claude API request failed:',
        error
      );
    });

    it('should handle connection refused errors', async () => {
      const error = new Error('Connection refused');
      error.code = 'ECONNREFUSED';

      axios.post.mockRejectedValue(error);

      await expect(
        claudeService.analyzeResources({})
      ).rejects.toThrow('Kong gateway is not accessible');
    });

    it('should handle timeout errors', async () => {
      const error = new Error('Request timeout');
      error.code = 'ETIMEDOUT';

      axios.post.mockRejectedValue(error);

      await expect(
        claudeService.analyzeResources({})
      ).rejects.toThrow('Claude API request timed out');
    });

    it('should handle generic errors', async () => {
      const error = new Error('Unknown error');

      axios.post.mockRejectedValue(error);

      await expect(
        claudeService.analyzeResources({})
      ).rejects.toThrow('Claude service error: Unknown error');
    });

    it('should support different analysis types', async () => {
      const mockResponse = {
        data: {
          content: [{ text: 'Security analysis results' }],
          model: 'claude-3-5-sonnet-20241022',
          usage: { input_tokens: 50, output_tokens: 100 }
        },
        headers: {}
      };

      axios.post.mockResolvedValue(mockResponse);

      await claudeService.analyzeResources({}, { analysisType: 'security' });

      const callArgs = axios.post.mock.calls[0];
      expect(callArgs[1].messages[0].content).toContain('security');
    });

    it('should include metadata when masked resources header is missing', async () => {
      const mockResponse = {
        data: {
          content: [{ text: 'Analysis results' }],
          model: 'claude-3-5-sonnet-20241022',
          usage: { input_tokens: 50, output_tokens: 100 }
        },
        headers: {}
      };

      axios.post.mockResolvedValue(mockResponse);

      const result = await claudeService.analyzeResources({});

      expect(result.metadata.maskedResources).toBe('unknown');
    });

    it('should log analysis completion with usage data', async () => {
      const mockResponse = {
        data: {
          content: [{ text: 'Analysis results' }],
          model: 'claude-3-5-sonnet-20241022',
          usage: { input_tokens: 100, output_tokens: 200 }
        },
        headers: {}
      };

      axios.post.mockResolvedValue(mockResponse);

      await claudeService.analyzeResources({});

      expect(logger.info).toHaveBeenCalledWith(
        'Claude analysis completed',
        expect.objectContaining({
          processingTime: expect.any(Number),
          usage: { input_tokens: 100, output_tokens: 200 }
        })
      );
    });

    it('should handle API error response without error message', async () => {
      const error = new Error('API Error');
      error.response = {
        status: 500,
        data: {}
      };

      axios.post.mockRejectedValue(error);

      await expect(
        claudeService.analyzeResources({})
      ).rejects.toThrow('Claude API error');
    });
  });

  describe('buildAnalysisPrompt', () => {
    it('should build prompt for all analysis types', () => {
      const awsData = {
        resources: {
          ec2: { instances: [{ InstanceId: 'i-123' }] },
          s3: { buckets: [{ Name: 'bucket-1' }] }
        }
      };

      const prompt = claudeService.buildAnalysisPrompt(awsData, 'all');

      expect(prompt).toContain('AWS resources');
      expect(prompt).toContain('security');
      expect(prompt).toContain('compliance');
      expect(prompt).toContain('cost optimization');
      expect(prompt).toContain(JSON.stringify(awsData, null, 2));
    });

    it('should build prompt for security analysis only', () => {
      const awsData = { resources: {} };

      const prompt = claudeService.buildAnalysisPrompt(awsData, 'security');

      expect(prompt).toContain('security vulnerabilities');
      expect(prompt).not.toContain('cost optimization');
    });

    it('should build prompt for compliance analysis', () => {
      const awsData = { resources: {} };

      const prompt = claudeService.buildAnalysisPrompt(awsData, 'compliance');

      expect(prompt).toContain('compliance requirements');
      expect(prompt).toContain('best practices');
    });

    it('should build prompt for cost analysis', () => {
      const awsData = { resources: {} };

      const prompt = claudeService.buildAnalysisPrompt(awsData, 'cost');

      expect(prompt).toContain('cost optimization');
      expect(prompt).toContain('resource utilization');
    });
  });

  describe('formatAnalysisResponse', () => {
    it('should format text response as JSON when possible', () => {
      const textResponse = `{
        "security_findings": [],
        "compliance_status": "compliant"
      }`;

      const formatted = claudeService.formatAnalysisResponse(textResponse);

      expect(formatted).toEqual({
        security_findings: [],
        compliance_status: 'compliant'
      });
    });

    it('should return text as-is if not valid JSON', () => {
      const textResponse = 'This is plain text analysis';

      const formatted = claudeService.formatAnalysisResponse(textResponse);

      expect(formatted).toBe(textResponse);
    });

    it('should handle empty response', () => {
      const formatted = claudeService.formatAnalysisResponse('');

      expect(formatted).toBe('');
    });

    it('should log warning for invalid JSON', () => {
      const textResponse = '{ invalid json';

      claudeService.formatAnalysisResponse(textResponse);

      expect(logger.debug).toHaveBeenCalledWith(
        'Response is not valid JSON, returning as text'
      );
    });
  });
});