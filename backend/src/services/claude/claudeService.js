/**
 * @fileoverview Claude API service for AWS resource analysis
 * @description Handles communication with Claude API through Kong Gateway
 * @author Infrastructure Team 
 * @version 1.0.0
 */

'use strict';

// 환경 변수 로딩 (독립 실행 및 테스트 환경 지원)
require('dotenv').config();

const axios = require('axios');
const logger = require('../../../utils/logger');
const { sanitizeString } = require('../../../utils/validation');

/**
 * @typedef {Object} ClaudeRequest
 * @property {string} model - Claude model identifier
 * @property {number} max_tokens - Maximum tokens for response
 * @property {Array<Object>} messages - Conversation messages
 * @property {Object} [metadata] - Request metadata
 */

/**
 * @typedef {Object} ClaudeResponse
 * @property {string} id - Response identifier
 * @property {string} type - Response type
 * @property {string} role - Response role
 * @property {Array<Object>} content - Response content
 * @property {string} model - Model used
 * @property {Object} usage - Token usage statistics
 */

/**
 * @typedef {Object} AnalysisOptions
 * @property {number} [maxTokens] - Maximum tokens for Claude response
 * @property {string} [temperature] - Response creativity (0.0-1.0)
 * @property {string} [analysisType] - Type of analysis to perform
 */

/**
 * Claude API service class
 * @class
 */
class ClaudeService {
  constructor() {
    /** @type {string} */
    this.apiKey = process.env.ANTHROPIC_API_KEY;
    
    /** @type {string} */
    this.model = process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-20241022';
    
    /** @type {string} */
    this.kongUrl = process.env.KONG_PROXY_URL || 'http://localhost:8000';
    
    /** @type {number} */
    this.timeout = parseInt(process.env.REQUEST_TIMEOUT, 10) || 5000; // CLAUDE.md: < 5 seconds
    
    /** @type {number} */
    this.maxRetries = parseInt(process.env.MAX_RETRIES, 10) || 3;
    
    /** @type {number} */
    this.retryDelay = parseInt(process.env.RETRY_DELAY, 10) || 1000;
    
    this.validateConfiguration();
  }
  
  /**
   * Validate Claude service configuration
   * @throws {Error} When configuration is invalid
   * @description Validates API key format and required environment variables
   * @private
   * @example
   * // Throws error if ANTHROPIC_API_KEY is missing or invalid format
   * this.validateConfiguration();
   */
  validateConfiguration() {
    if (!this.apiKey) {
      throw new Error('ANTHROPIC_API_KEY environment variable is required');
    }
    
    // Skip validation for test environment
    if (process.env.NODE_ENV === 'test' && this.apiKey.includes('test')) {
      return;
    }
    
    if (!this.apiKey.startsWith('sk-ant-api03-')) {
      throw new Error('Invalid Anthropic API key format');
    }
  }
  
  /**
   * Analyze AWS resource data using Claude API
   * @param {Object} awsData - AWS resource data to analyze
   * @param {AnalysisOptions} [options={}] - Analysis options
   * @returns {Promise<ClaudeResponse>} Claude API analysis response
   * @throws {Error} When analysis fails
   */
  async analyzeAwsData(awsData, options = {}) {
    const startTime = Date.now();
    
    logger.info('Starting Claude API analysis', {
      resourceTypes: Object.keys(awsData),
      maxTokens: options.maxTokens || 2048
    });
    
    try {
      // Prepare analysis prompt
      const prompt = this.buildAnalysisPrompt(awsData, options);
      
      // Build Claude API request
      /** @type {ClaudeRequest} */
      const claudeRequest = {
        model: this.model,
        max_tokens: options.maxTokens || 2048,
        messages: [{
          role: 'user',
          content: prompt
        }],
        metadata: {
          analysis_type: options.analysisType || 'security_and_optimization',
          resource_count: this.countResources(awsData),
          timestamp: new Date().toISOString()
        }
      };
      
      // Send request through Kong Gateway (masking will be handled by Kong plugin)
      const response = await this.sendClaudeRequest(claudeRequest);
      
      const duration = Date.now() - startTime;
      
      logger.performance('claude_api_request', duration, {
        model: this.model,
        tokensUsed: response.usage?.total_tokens || 0,
        inputTokens: response.usage?.input_tokens || 0,
        outputTokens: response.usage?.output_tokens || 0
      });
      
      logger.info('Claude API analysis completed', {
        duration,
        tokensUsed: response.usage?.total_tokens || 0
      });
      
      return response;
      
    } catch (error) {
      const duration = Date.now() - startTime;
      
      logger.error('Claude API analysis failed', {
        error: error.message,
        duration,
        stack: error.stack
      });
      
      throw this.enhanceError(error);
    }
  }
  
  /**
   * Build analysis prompt for Claude API
   * @param {Object} awsData - AWS resource data
   * @param {AnalysisOptions} options - Analysis options
   * @returns {string} Formatted prompt for Claude API
   * @private
   */
  buildAnalysisPrompt(awsData, options) {
    const analysisType = options.analysisType || 'security_and_optimization';
    
    let prompt = `Please analyze the following AWS infrastructure data for ${analysisType}:\n\n`;
    
    // Add resource summaries
    for (const [resourceType, resources] of Object.entries(awsData)) {
      if (resources && resources.error) {
        prompt += `${resourceType.toUpperCase()}: Error collecting data - ${resources.error}\n\n`;
        continue;
      }
      
      const resourceArray = Array.isArray(resources) ? resources : resources.data || [];
      prompt += `${resourceType.toUpperCase()} Resources (${resourceArray.length} items):\n`;
      prompt += JSON.stringify(resourceArray, null, 2) + '\n\n';
    }
    
    // Add specific analysis instructions
    prompt += this.getAnalysisInstructions(analysisType);
    
    return prompt;
  }
  
  /**
   * Get analysis instructions based on type
   * @param {string} analysisType - Type of analysis
   * @returns {string} Analysis instructions
   * @private
   */
  getAnalysisInstructions(analysisType) {
    const instructions = {
      security_and_optimization: `
Please provide a comprehensive analysis focusing on:

1. **Security Issues**:
   - Identify potential security vulnerabilities
   - Check for overly permissive access controls
   - Look for unencrypted resources
   - Identify public-facing resources that should be private

2. **Cost Optimization**:
   - Identify oversized or underutilized resources
   - Suggest cost-saving opportunities
   - Recommend resource consolidation where appropriate

3. **Performance Optimization**:
   - Identify performance bottlenecks
   - Suggest architectural improvements
   - Recommend best practices implementation

4. **Compliance & Best Practices**:
   - Check adherence to AWS Well-Architected Framework
   - Identify compliance issues
   - Suggest infrastructure improvements

Please structure your response with clear sections and actionable recommendations.`,

      security_only: `
Please focus exclusively on security analysis:

1. **Critical Security Issues** (immediate attention required)
2. **Security Warnings** (should be addressed soon)
3. **Security Recommendations** (best practices)

For each issue, provide:
- Description of the security concern
- Potential impact if not addressed
- Specific remediation steps`,

      cost_only: `
Please focus exclusively on cost optimization:

1. **High-Impact Cost Savings** (significant cost reduction potential)
2. **Medium-Impact Optimizations** (moderate cost savings)
3. **Best Practices** (long-term cost management)

For each opportunity, provide:
- Current cost implications
- Estimated savings potential
- Implementation difficulty and steps`
    };
    
    return instructions[analysisType] || instructions.security_and_optimization;
  }
  
  /**
   * Send request to Claude API through Kong Gateway
   * @param {ClaudeRequest} request - Claude API request
   * @returns {Promise<ClaudeResponse>} Claude API response
   * @private
   */
  async sendClaudeRequest(request) {
    let lastError;
    
    for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
      try {
        logger.debug(`Claude API request attempt ${attempt}/${this.maxRetries}`, {
          model: request.model,
          messageLength: JSON.stringify(request.messages).length
        });
        
        // 모든 환경에서 Kong Gateway를 통해 Claude API 호출
        const response = await axios.post(
          `${this.kongUrl}/analyze-claude`,
          request,
          {
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': this.apiKey,
              'anthropic-version': '2023-06-01'
            },
            timeout: this.timeout
          }
        );
        
        return response.data;
        
      } catch (error) {
        lastError = error;
        
        logger.warn(`Claude API request attempt ${attempt} failed`, {
          error: error.message,
          status: error.response?.status,
          statusText: error.response?.statusText
        });
        
        // Don't retry for certain error types
        if (error.response?.status === 401 || error.response?.status === 403) {
          throw error; // Authentication/authorization errors
        }
        
        if (error.response?.status === 400) {
          throw error; // Bad request errors
        }
        
        // Wait before retrying
        if (attempt < this.maxRetries) {
          const delay = this.retryDelay * Math.pow(2, attempt - 1); // Exponential backoff
          logger.debug(`Waiting ${delay}ms before retry`);
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    }
    
    throw lastError;
  }
  
  /**
   * Count total resources in AWS data
   * @param {Object} awsData - AWS resource data
   * @returns {number} Total resource count
   * @private
   */
  countResources(awsData) {
    let total = 0;
    
    for (const resources of Object.values(awsData)) {
      if (Array.isArray(resources)) {
        total += resources.length;
      } else if (resources && resources.data && Array.isArray(resources.data)) {
        total += resources.data.length;
      }
    }
    
    return total;
  }
  
  /**
   * Enhance error with additional context
   * @param {Error} error - Original error
   * @returns {Error} Enhanced error
   * @private
   */
  enhanceError(error) {
    if (error.response) {
      const status = error.response.status;
      const data = error.response.data;
      
      switch (status) {
        case 401:
          return new Error('Authentication failed: Invalid API key');
        case 403:
          return new Error('Authorization failed: Insufficient permissions');
        case 429:
          return new Error('Rate limit exceeded: Too many requests');
        case 400:
          return new Error(`Bad request: ${data?.error?.message || 'Invalid request format'}`);
        case 500:
          return new Error('Claude API server error: Please try again later');
        case 503:
          return new Error('Claude API temporarily unavailable');
        default:
          return new Error(`Claude API error (${status}): ${data?.error?.message || error.message}`);
      }
    }
    
    if (error.code === 'ECONNREFUSED') {
      return new Error('Connection refused: Unable to reach Kong Gateway');
    }
    
    if (error.code === 'TIMEOUT' || error.code === 'ECONNABORTED') {
      return new Error(`Request timeout after ${this.timeout}ms`);
    }
    
    return error;
  }
  
  /**
   * Test Claude API connectivity
   * @returns {Promise<Object>} Connection test results
   */
  async testConnection() {
    logger.debug('Testing Claude API connectivity');
    
    try {
      const testRequest = {
        model: this.model,
        max_tokens: 50,
        messages: [{
          role: 'user',
          content: 'Please respond with "Connection test successful" to confirm API connectivity.'
        }]
      };
      
      const startTime = Date.now();
      const response = await this.sendClaudeRequest(testRequest);
      const duration = Date.now() - startTime;
      
      return {
        success: true,
        duration,
        model: response.model,
        usage: response.usage,
        timestamp: new Date().toISOString()
      };
      
    } catch (error) {
      logger.error('Claude API connectivity test failed', { error: error.message });
      
      return {
        success: false,
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }
}

// Export singleton instance
module.exports = new ClaudeService();