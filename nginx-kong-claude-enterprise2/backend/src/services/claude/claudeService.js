/**
 * @fileoverview Claude API service for AI analysis
 * @module services/claude/claudeService
 */

const axios = require('axios');
const logger = require('../../utils/logger');
const { ApiError } = require('../../middlewares/errorHandler');

class ClaudeService {
  constructor() {
    this.kongProxyUrl = process.env.KONG_PROXY_URL || 'http://kong:8000';
    this.anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    this.model = 'claude-3-5-sonnet-20241022';
    this.maxTokens = 4096;
  }

  /**
   * Analyze AWS resources using Claude API through Kong proxy
   * @param {Object} awsData - AWS resources data
   * @param {Object} options - Analysis options
   * @returns {Promise<Object>} Analysis results
   */
  async analyzeResources(awsData, options = {}) {
    const startTime = Date.now();
    
    if (!this.anthropicApiKey) {
      throw new ApiError(500, 'Claude API key not configured');
    }
    
    const { analysisType = 'all' } = options;
    
    // Prepare the prompt
    const prompt = this.buildAnalysisPrompt(awsData, analysisType);
    
    try {
      // Send request through Kong proxy
      const response = await axios.post(
        `${this.kongProxyUrl}/analyze`,
        {
          model: this.model,
          max_tokens: this.maxTokens,
          messages: [
            {
              role: 'user',
              content: prompt
            }
          ]
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': this.anthropicApiKey
          },
          timeout: 60000 // 60 seconds timeout
        }
      );
      
      const processingTime = Date.now() - startTime;
      
      logger.info('Claude analysis completed', { 
        processingTime,
        usage: response.data.usage 
      });
      
      return {
        analysis: response.data.content[0].text,
        model: response.data.model,
        usage: response.data.usage,
        processingTime,
        metadata: {
          maskedResources: response.headers['x-masked-resources'] || 'unknown',
          requestId: response.headers['x-request-id']
        }
      };
    } catch (error) {
      logger.error('Claude API request failed:', error);
      
      if (error.response) {
        throw new ApiError(
          error.response.status,
          error.response.data?.error?.message || 'Claude API error',
          error.response.data
        );
      }
      
      if (error.code === 'ECONNREFUSED') {
        throw new ApiError(503, 'Kong gateway is not accessible');
      }
      
      if (error.code === 'ETIMEDOUT') {
        throw new ApiError(504, 'Claude API request timed out');
      }
      
      throw new ApiError(500, `Claude service error: ${error.message}`);
    }
  }

  /**
   * Build analysis prompt based on AWS data and analysis type
   * @param {Object} awsData - AWS resources data
   * @param {string} analysisType - Type of analysis
   * @returns {string} Formatted prompt
   */
  buildAnalysisPrompt(awsData, analysisType) {
    const resourceSummary = this.summarizeResources(awsData.resources);
    
    let analysisInstructions = '';
    
    switch (analysisType) {
      case 'security':
        analysisInstructions = `
Focus on security aspects:
- Identify security vulnerabilities and misconfigurations
- Check for exposed resources and overly permissive policies
- Recommend security best practices
- Highlight critical security issues that need immediate attention`;
        break;
      
      case 'cost':
        analysisInstructions = `
Focus on cost optimization:
- Identify underutilized or idle resources
- Suggest cost-saving opportunities
- Recommend right-sizing for resources
- Highlight resources with high cost impact`;
        break;
      
      case 'performance':
        analysisInstructions = `
Focus on performance optimization:
- Identify performance bottlenecks
- Suggest scaling improvements
- Recommend configuration optimizations
- Highlight resources affecting application performance`;
        break;
      
      default:
        analysisInstructions = `
Provide comprehensive analysis covering:
- Security vulnerabilities and recommendations
- Cost optimization opportunities
- Performance improvements
- General best practices
- Prioritized action items`;
    }
    
    return `Analyze the following AWS resources from region ${awsData.metadata.region}:

${resourceSummary}

${analysisInstructions}

Please provide a structured analysis with clear sections and actionable recommendations. 
Format the response in markdown for better readability.`;
  }

  /**
   * Summarize AWS resources for the prompt
   * @param {Object} resources - AWS resources
   * @returns {string} Resource summary
   */
  summarizeResources(resources) {
    const summaries = [];
    
    for (const [type, data] of Object.entries(resources)) {
      switch (type) {
        case 'ec2':
          summaries.push(this.summarizeEC2(data));
          break;
        case 's3':
          summaries.push(this.summarizeS3(data));
          break;
        case 'rds':
          summaries.push(this.summarizeRDS(data));
          break;
        case 'lambda':
          summaries.push(this.summarizeLambda(data));
          break;
        case 'iam':
          summaries.push(this.summarizeIAM(data));
          break;
        case 'vpc':
          summaries.push(this.summarizeVPC(data));
          break;
      }
    }
    
    return summaries.join('\n\n');
  }

  /**
   * Summarize EC2 resources
   * @param {Object} ec2Data - EC2 resources
   * @returns {string} EC2 summary
   */
  summarizeEC2(ec2Data) {
    const instanceCount = ec2Data.instances.reduce((count, reservation) => 
      count + (reservation.Instances?.length || 0), 0
    );
    
    return `EC2 Resources:
- Total Instances: ${instanceCount}
- Security Groups: ${ec2Data.securityGroups?.length || 0}
- Key Pairs: ${ec2Data.keyPairs?.length || 0}
Raw Data: ${JSON.stringify(ec2Data, null, 2)}`;
  }

  /**
   * Summarize S3 resources
   * @param {Object} s3Data - S3 resources
   * @returns {string} S3 summary
   */
  summarizeS3(s3Data) {
    return `S3 Resources:
- Total Buckets: ${s3Data.totalBuckets}
- Analyzed Buckets: ${s3Data.buckets?.length || 0}
Raw Data: ${JSON.stringify(s3Data, null, 2)}`;
  }

  /**
   * Summarize RDS resources
   * @param {Object} rdsData - RDS resources
   * @returns {string} RDS summary
   */
  summarizeRDS(rdsData) {
    return `RDS Resources:
- DB Instances: ${rdsData.instances?.length || 0}
- DB Clusters: ${rdsData.clusters?.length || 0}
- Snapshots: ${rdsData.snapshots?.length || 0}
Raw Data: ${JSON.stringify(rdsData, null, 2)}`;
  }

  /**
   * Summarize Lambda resources
   * @param {Object} lambdaData - Lambda resources
   * @returns {string} Lambda summary
   */
  summarizeLambda(lambdaData) {
    return `Lambda Resources:
- Total Functions: ${lambdaData.totalFunctions}
- Analyzed Functions: ${lambdaData.functions?.length || 0}
Raw Data: ${JSON.stringify(lambdaData, null, 2)}`;
  }

  /**
   * Summarize IAM resources
   * @param {Object} iamData - IAM resources
   * @returns {string} IAM summary
   */
  summarizeIAM(iamData) {
    return `IAM Resources:
- Users: ${iamData.users?.length || 0}
- Roles: ${iamData.roles?.length || 0}
- Policies: ${iamData.policies?.length || 0}
Raw Data: ${JSON.stringify(iamData, null, 2)}`;
  }

  /**
   * Summarize VPC resources
   * @param {Object} vpcData - VPC resources
   * @returns {string} VPC summary
   */
  summarizeVPC(vpcData) {
    return `VPC Resources:
- VPCs: ${vpcData.vpcs?.length || 0}
- Subnets: ${vpcData.subnets?.length || 0}
- Route Tables: ${vpcData.routeTables?.length || 0}
- NAT Gateways: ${vpcData.natGateways?.length || 0}
Raw Data: ${JSON.stringify(vpcData, null, 2)}`;
  }
}

// Create singleton instance
const claudeService = new ClaudeService();

module.exports = claudeService;