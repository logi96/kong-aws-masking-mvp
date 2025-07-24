/**
 * @fileoverview Service Integration Tests
 * @description Integration testing for AWS and Claude services working together
 */

const awsService = require('../../src/services/aws/awsService');
const claudeService = require('../../src/services/claude/claudeService');

// Mock child_process and axios for integration testing
jest.mock('child_process');
jest.mock('axios');
jest.mock('../../utils/logger', () => ({
  info: jest.fn(),
  debug: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  performance: jest.fn()
}));

const { exec } = require('child_process');
const axios = require('axios');

describe('Service Integration Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    awsService.clearCache();
    
    // Setup environment for integration tests
    process.env.NODE_ENV = 'test';
    process.env.ANTHROPIC_API_KEY = 'sk-ant-api03-test-key-integration';
    process.env.AWS_REGION = 'us-east-1';
    process.env.CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages';
  });

  describe('AWS Service Integration', () => {
    test('should collect and cache resources across multiple calls', async () => {
      const mockEc2Data = [
        ['i-1234567890abcdef0', 't2.micro', 'running', '10.0.0.1', '203.0.113.1', []]
      ];

      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: JSON.stringify(mockEc2Data), stderr: '' });
      });

      // First call should execute AWS CLI
      const result1 = await awsService.collectResources({ 
        resources: ['ec2'],
        region: 'us-east-1' 
      });

      expect(result1).toMatchObject({
        ec2: mockEc2Data
      });
      expect(exec).toHaveBeenCalledTimes(1);

      exec.mockClear();

      // Second call should use cache
      const result2 = await awsService.collectResources({ 
        resources: ['ec2'],
        region: 'us-east-1'
      });

      expect(result2).toMatchObject({
        ec2: mockEc2Data
      });
      expect(exec).not.toHaveBeenCalled(); // Should use cache

      // Cache stats should reflect usage
      const cacheStats = awsService.getCacheStats();
      expect(cacheStats.totalEntries).toBe(1);
      expect(cacheStats.entries).toHaveProperty('ec2:us-east-1');
    });

    test('should handle mixed success/failure scenarios', async () => {
      exec.mockImplementation((command, options, callback) => {
        if (command.includes('ec2')) {
          callback(null, { stdout: JSON.stringify([['i-123', 't2.micro']]), stderr: '' });
        } else if (command.includes('s3')) {
          callback(new Error('Access denied'), { stdout: '', stderr: 'UnauthorizedOperation' });
        } else {
          callback(null, { stdout: JSON.stringify([]), stderr: '' });
        }
      });

      const result = await awsService.collectResources({ 
        resources: ['ec2', 's3', 'rds'] 
      });

      expect(result).toMatchObject({
        ec2: [['i-123', 't2.micro']],
        s3: {
          error: expect.any(String),
          data: []
        },
        rds: []
      });
    });

    test('should execute custom commands with security validation', async () => {
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: 'Command executed successfully', stderr: '' });
      });

      // Valid command should work
      const result1 = await awsService.executeCustomCommand('aws ec2 describe-instances');
      expect(result1).toMatchObject({
        success: true,
        stdout: 'Command executed successfully'
      });

      // Invalid command should be rejected
      await expect(awsService.executeCustomCommand('aws ec2 delete-instance i-123'))
        .rejects.toThrow('Command contains forbidden operations');
    });
  });

  describe('Claude Service Integration', () => {
    const mockAwsData = {
      ec2: [['i-123', 't2.micro', 'running']],
      s3: [['bucket-1', '2023-01-01']]
    };

    test('should analyze AWS data with retry mechanism', async () => {
      const mockClaudeResponse = {
        id: 'msg_123',
        content: [{ type: 'text', text: 'Analysis complete' }],
        usage: { total_tokens: 100 }
      };

      // First call fails, second succeeds (testing retry)
      axios.post
        .mockRejectedValueOnce(new Error('Network error'))
        .mockResolvedValueOnce({ data: mockClaudeResponse });

      const result = await claudeService.analyzeAwsData(mockAwsData);

      expect(result).toEqual(mockClaudeResponse);
      expect(axios.post).toHaveBeenCalledTimes(2); // One retry
    });

    test('should handle different analysis types', async () => {
      const mockResponse = {
        content: [{ type: 'text', text: 'Security analysis' }]
      };

      axios.post.mockResolvedValue({ data: mockResponse });

      // Test security-only analysis
      await claudeService.analyzeAwsData(mockAwsData, { 
        analysisType: 'security_only' 
      });

      const requestCall = axios.post.mock.calls[0][1];
      expect(requestCall.messages[0].content).toContain('security_only');
      expect(requestCall.messages[0].content).toContain('Critical Security Issues');

      axios.post.mockClear();

      // Test cost-only analysis
      await claudeService.analyzeAwsData(mockAwsData, { 
        analysisType: 'cost_only' 
      });

      const costRequestCall = axios.post.mock.calls[0][1];
      expect(costRequestCall.messages[0].content).toContain('cost_only');
      expect(costRequestCall.messages[0].content).toContain('High-Impact Cost Savings');
    });

    test('should enhance errors appropriately', async () => {
      const authError = new Error('Unauthorized');
      authError.response = { 
        status: 401, 
        data: { error: { message: 'Invalid API key' } }
      };

      axios.post.mockRejectedValue(authError);

      await expect(claudeService.analyzeAwsData(mockAwsData))
        .rejects.toThrow('Authentication failed: Invalid API key');
    });

    test('should test connectivity successfully', async () => {
      const mockResponse = {
        model: 'claude-3-5-sonnet-20241022',
        usage: { total_tokens: 25 },
        content: [{ type: 'text', text: 'Connection test successful' }]
      };

      axios.post.mockResolvedValue({ data: mockResponse });

      const result = await claudeService.testConnection();

      expect(result).toMatchObject({
        success: true,
        duration: expect.any(Number),
        model: mockResponse.model,
        usage: mockResponse.usage
      });
    });
  });

  describe('AWS + Claude Integration Workflow', () => {
    test('should complete full analysis workflow', async () => {
      // Setup AWS service mock
      const mockAwsData = {
        ec2: [
          ['i-1234567890abcdef0', 't2.micro', 'running', '10.0.0.1', '203.0.113.1', 
           [{ Key: 'Name', Value: 'Web Server' }]]
        ],
        s3: [
          ['production-data-bucket', '2023-01-01T00:00:00.000Z']
        ],
        rds: [
          ['prod-database', 'db.t3.micro', 'mysql', 'available', 'prod-db.amazonaws.com']
        ]
      };

      exec.mockImplementation((command, options, callback) => {
        if (command.includes('ec2')) {
          callback(null, { stdout: JSON.stringify(mockAwsData.ec2), stderr: '' });
        } else if (command.includes('s3')) {
          callback(null, { stdout: JSON.stringify(mockAwsData.s3), stderr: '' });
        } else if (command.includes('rds')) {
          callback(null, { stdout: JSON.stringify(mockAwsData.rds), stderr: '' });
        }
      });

      // Setup Claude service mock
      const mockClaudeResponse = {
        id: 'msg_workflow_123',
        content: [{
          type: 'text',
          text: `# AWS Infrastructure Analysis

## Security Issues
1. **Critical**: S3 bucket 'production-data-bucket' may have public access
2. **Warning**: EC2 instance lacks detailed security group analysis

## Cost Optimization
1. RDS instance 'db.t3.micro' may be oversized for current usage
2. Consider implementing S3 lifecycle policies

## Recommendations
1. Enable S3 bucket encryption
2. Review and optimize RDS instance sizing
3. Implement comprehensive security group rules`
        }],
        model: 'claude-3-5-sonnet-20241022',
        usage: {
          input_tokens: 256,
          output_tokens: 128,
          total_tokens: 384
        }
      };

      axios.post.mockResolvedValue({ data: mockClaudeResponse });

      // Execute full workflow
      const startTime = Date.now();

      // Step 1: Collect AWS resources
      const awsResources = await awsService.collectResources({
        resources: ['ec2', 's3', 'rds'],
        region: 'us-east-1'
      });

      // Step 2: Analyze with Claude
      const claudeAnalysis = await claudeService.analyzeAwsData(awsResources, {
        analysisType: 'security_and_optimization',
        maxTokens: 2048
      });

      const duration = Date.now() - startTime;

      // Verify results
      expect(awsResources).toEqual(mockAwsData);
      expect(claudeAnalysis).toEqual(mockClaudeResponse);

      // Verify performance (CLAUDE.md: < 5 seconds)
      expect(duration).toBeLessThan(5000);

      // Verify service interactions
      expect(exec).toHaveBeenCalledTimes(3); // One call per resource type
      expect(axios.post).toHaveBeenCalledTimes(1);

      // Verify request structure
      const claudeRequest = axios.post.mock.calls[0][1];
      expect(claudeRequest).toMatchObject({
        model: 'claude-3-5-sonnet-20241022',
        max_tokens: 2048,
        messages: expect.arrayContaining([
          expect.objectContaining({
            role: 'user',
            content: expect.stringContaining('security_and_optimization')
          })
        ]),
        metadata: expect.objectContaining({
          analysis_type: 'security_and_optimization',
          resource_count: 3,
          timestamp: expect.any(String)
        })
      });
    });

    test('should handle partial failures gracefully', async () => {
      // AWS service partially fails
      exec.mockImplementation((command, options, callback) => {
        if (command.includes('ec2')) {
          callback(null, { stdout: JSON.stringify([['i-123', 't2.micro']]), stderr: '' });
        } else {
          callback(new Error('Access denied'), { stdout: '', stderr: 'UnauthorizedOperation' });
        }
      });

      // Claude service succeeds with partial data
      const mockResponse = {
        content: [{ type: 'text', text: 'Limited analysis due to partial data' }]
      };
      axios.post.mockResolvedValue({ data: mockResponse });

      const awsResources = await awsService.collectResources({
        resources: ['ec2', 's3']
      });

      const analysis = await claudeService.analyzeAwsData(awsResources);

      // Should complete successfully with partial data
      expect(awsResources.ec2).toEqual([['i-123', 't2.micro']]);
      expect(awsResources.s3).toMatchObject({
        error: expect.any(String),
        data: []
      });
      expect(analysis).toEqual(mockResponse);
    });

    test('should handle Claude API unavailability', async () => {
      // AWS service succeeds
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: JSON.stringify([['i-123']]), stderr: '' });
      });

      // Claude service fails with service unavailable
      const serviceError = new Error('Service Unavailable');
      serviceError.response = { status: 503 };
      axios.post.mockRejectedValue(serviceError);

      const awsResources = await awsService.collectResources({ resources: ['ec2'] });

      await expect(claudeService.analyzeAwsData(awsResources))
        .rejects.toThrow('Claude API temporarily unavailable');

      // AWS data should still be available
      expect(awsResources.ec2).toEqual([['i-123']]);
    });

    test('should handle resource counting edge cases', async () => {
      // Mixed data formats
      const mixedAwsData = {
        ec2: [['i-1'], ['i-2']], // Array format
        s3: { data: [['bucket-1']] }, // Object with data property
        rds: { error: 'Access denied', data: [] }, // Error format
        vpc: null // Null value
      };

      const mockResponse = { content: [{ type: 'text', text: 'Mixed data analysis' }] };
      axios.post.mockResolvedValue({ data: mockResponse });

      const resourceCount = claudeService.countResources(mixedAwsData);
      expect(resourceCount).toBe(3); // 2 + 1 + 0 + 0

      await claudeService.analyzeAwsData(mixedAwsData);

      const request = axios.post.mock.calls[0][1];
      expect(request.metadata.resource_count).toBe(3);
    });
  });

  describe('Performance Integration', () => {
    test('should handle concurrent service calls efficiently', async () => {
      const mockData = [['resource-1'], ['resource-2']];
      
      exec.mockImplementation((command, options, callback) => {
        // Simulate slight delay for realism
        setTimeout(() => {
          callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
        }, 100);
      });

      const promises = Array(3).fill().map((_, index) => 
        awsService.collectResources({ 
          resources: ['ec2'],
          region: `us-east-${index + 1}`
        })
      );

      const startTime = Date.now();
      const results = await Promise.all(promises);
      const duration = Date.now() - startTime;

      results.forEach(result => {
        expect(result.ec2).toEqual(mockData);
      });

      // Should handle concurrent calls efficiently
      expect(duration).toBeLessThan(1000); // Under 1 second for 3 concurrent calls
    });

    test('should respect cache TTL across multiple regions', async () => {
      const mockData = [['cached-resource']];
      
      exec.mockImplementation((command, options, callback) => {
        callback(null, { stdout: JSON.stringify(mockData), stderr: '' });
      });

      // First call - populates cache
      await awsService.collectResources({ resources: ['ec2'], region: 'us-east-1' });
      expect(exec).toHaveBeenCalledTimes(1);

      exec.mockClear();

      // Second call same region - uses cache
      await awsService.collectResources({ resources: ['ec2'], region: 'us-east-1' });
      expect(exec).not.toHaveBeenCalled();

      // Different region - new call
      await awsService.collectResources({ resources: ['ec2'], region: 'us-west-2' });
      expect(exec).toHaveBeenCalledTimes(1);

      // Verify cache contains both regions
      const stats = awsService.getCacheStats();
      expect(stats.totalEntries).toBe(2);
      expect(stats.entries).toHaveProperty('ec2:us-east-1');
      expect(stats.entries).toHaveProperty('ec2:us-west-2');
    });
  });
});