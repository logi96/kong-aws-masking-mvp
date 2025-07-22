/**
 * @fileoverview AWS service for resource collection and management
 * @description Handles AWS CLI execution and resource data collection
 * @author Infrastructure Team
 * @version 1.0.0
 */

'use strict';

// 환경 변수 로딩 (독립 실행 및 테스트 환경 지원)
require('dotenv').config();

const { exec } = require('child_process');
const { promisify } = require('util');
const logger = require('../../../utils/logger');
const { sanitizeString } = require('../../../utils/validation');

const execAsync = promisify(exec);

/**
 * @typedef {Object} AwsResourceData
 * @property {Array} ec2 - EC2 instances data
 * @property {Array} s3 - S3 buckets data  
 * @property {Array} rds - RDS instances data
 * @property {Array} vpc - VPC networks data
 * @property {Array} iam - IAM resources data
 */

/**
 * @typedef {Object} CollectionOptions
 * @property {string[]} resources - Resource types to collect
 * @property {string} [region] - AWS region override
 * @property {boolean} [skipCache] - Skip cached results
 * @property {number} [timeout] - Command timeout in milliseconds
 */

/**
 * AWS service class for resource management
 * @class
 */
class AwsService {
  constructor() {
    /** @type {number} */
    this.defaultTimeout = parseInt(process.env.REQUEST_TIMEOUT, 10) || 5000;
    
    /** @type {string} */
    this.region = process.env.AWS_REGION || 'ap-northeast-2'; // 한국 리전 (서울) 기본값
    
    /** @type {Map<string, Object>} */
    this.cache = new Map();
    
    /** @type {number} */
    this.cacheMaxAge = 5 * 60 * 1000; // 5 minutes
  }
  
  /**
   * Collect AWS resources based on request parameters
   * @param {CollectionOptions} options - Collection options
   * @returns {Promise<AwsResourceData>} Collected AWS resource data
   * @throws {Error} When AWS CLI commands fail
   */
  async collectResources(options) {
    logger.info('Collecting AWS resources', { 
      resources: options.resources,
      region: options.region || this.region
    });
    
    const resourceTypes = options.resources || ['ec2', 's3', 'rds'];
    const results = {};
    
    // Collect each resource type
    for (const resourceType of resourceTypes) {
      try {
        logger.debug(`Collecting ${resourceType} resources`);
        
        const cacheKey = `${resourceType}:${options.region || this.region}`;
        
        // Check cache first (unless skipCache is true)
        if (!options.skipCache && this.cache.has(cacheKey)) {
          const cached = this.cache.get(cacheKey);
          if (Date.now() - cached.timestamp < this.cacheMaxAge) {
            logger.debug(`Using cached ${resourceType} data`);
            results[resourceType] = cached.data;
            continue;
          }
        }
        
        // Collect fresh data
        const data = await this.collectResourceType(resourceType, options);
        results[resourceType] = data;
        
        // Cache the results
        this.cache.set(cacheKey, {
          data,
          timestamp: Date.now()
        });
        
      } catch (error) {
        logger.error(`Failed to collect ${resourceType} resources`, {
          resourceType,
          error: error.message
        });
        
        // Continue with empty data rather than failing completely
        results[resourceType] = {
          error: error.message,
          data: []
        };
      }
    }
    
    logger.info('AWS resource collection completed', {
      resourceTypes: Object.keys(results),
      totalItems: Object.values(results).reduce((sum, r) => {
        return sum + (Array.isArray(r) ? r.length : (r.data?.length || 0));
      }, 0)
    });
    
    return results;
  }
  
  /**
   * Collect specific resource type data
   * @param {string} resourceType - Type of resource to collect
   * @param {CollectionOptions} options - Collection options
   * @returns {Promise<Array>} Resource data array
   * @private
   */
  async collectResourceType(resourceType, options) {
    const command = this.buildCommand(resourceType, options);
    const timeout = options.timeout || this.defaultTimeout;
    
    logger.debug('Executing AWS command', { command, timeout });
    
    try {
      const { stdout, stderr } = await execAsync(command, { 
        timeout,
        env: {
          ...process.env,
          AWS_REGION: options.region || this.region
        }
      });
      
      if (stderr) {
        logger.warn('AWS command stderr output', { stderr });
      }
      
      // Parse JSON output
      if (!stdout.trim()) {
        return [];
      }
      
      const parsed = JSON.parse(stdout);
      return Array.isArray(parsed) ? parsed : [parsed];
      
    } catch (error) {
      if (error.code === 'TIMEOUT') {
        throw new Error(`AWS command timeout after ${timeout}ms`);
      }
      
      if (error.code === 'ENOENT') {
        throw new Error('AWS CLI not found - ensure aws-cli is installed');
      }
      
      // Parse AWS CLI error messages
      if (error.stderr) {
        const errorMsg = this.parseAwsError(error.stderr);
        throw new Error(`AWS CLI error: ${errorMsg}`);
      }
      
      throw error;
    }
  }
  
  /**
   * Build AWS CLI command for resource type
   * @param {string} resourceType - Resource type
   * @param {CollectionOptions} options - Collection options
   * @returns {string} AWS CLI command
   * @private
   */
  buildCommand(resourceType, options) {
    const region = options.region || this.region;
    
    switch (resourceType) {
      case 'ec2':
        return `aws ec2 describe-instances --region ${region} ` +
               `--query "Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,Tags]" ` +
               `--output json`;
               
      case 's3':
        return `aws s3api list-buckets --query "Buckets[*].[Name,CreationDate]" --output json`;
        
      case 'rds':
        return `aws rds describe-db-instances --region ${region} ` +
               `--query "DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus,Endpoint.Address]" ` +
               `--output json`;
               
      case 'vpc':
        return `aws ec2 describe-vpcs --region ${region} ` +
               `--query "Vpcs[*].[VpcId,CidrBlock,State,IsDefault,Tags]" ` +
               `--output json`;
               
      case 'iam':
        return `aws iam list-roles --query "Roles[*].[RoleName,CreateDate,AssumeRolePolicyDocument]" --output json`;
        
      default:
        throw new Error(`Unsupported resource type: ${resourceType}`);
    }
  }
  
  /**
   * Parse AWS CLI error messages
   * @param {string} stderr - Error output from AWS CLI
   * @returns {string} Parsed error message
   * @private
   */
  parseAwsError(stderr) {
    // Common AWS error patterns
    if (stderr.includes('InvalidUserID.NotFound')) {
      return 'AWS credentials not found or invalid';
    }
    
    if (stderr.includes('UnauthorizedOperation')) {
      return 'Insufficient AWS permissions';
    }
    
    if (stderr.includes('Throttling')) {
      return 'AWS API rate limit exceeded';
    }
    
    if (stderr.includes('ServiceUnavailable')) {
      return 'AWS service temporarily unavailable';
    }
    
    // Return sanitized error message
    return sanitizeString(stderr.split('\n')[0]);
  }
  
  /**
   * Execute custom AWS CLI command
   * @param {string} command - Custom AWS CLI command
   * @param {Object} [options={}] - Execution options
   * @returns {Promise<Object>} Command execution results
   */
  async executeCustomCommand(command, options = {}) {
    logger.info('Executing custom AWS command', { command });
    
    // Validate command format
    if (!command.startsWith('aws ')) {
      throw new Error('Command must start with "aws "');
    }
    
    // Security validation
    const forbiddenPatterns = [
      /\b(delete|remove|terminate|destroy)\b/i,
      /\b(put|create|run)\b/i,
      /[;&|`$()]/,
      /--force/i,
      /--yes/i
    ];
    
    const hasForbiddenPattern = forbiddenPatterns.some(pattern => pattern.test(command));
    if (hasForbiddenPattern) {
      throw new Error('Command contains forbidden operations');
    }
    
    try {
      const timeout = options.timeout || this.defaultTimeout;
      const { stdout, stderr } = await execAsync(command, { timeout });
      
      return {
        success: true,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        timestamp: new Date().toISOString()
      };
      
    } catch (error) {
      logger.error('Custom AWS command failed', {
        command,
        error: error.message
      });
      
      return {
        success: false,
        error: error.message,
        stderr: error.stderr || '',
        timestamp: new Date().toISOString()
      };
    }
  }
  
  /**
   * Clear resource cache
   * @param {string} [resourceType] - Specific resource type to clear, or all if not specified
   */
  clearCache(resourceType) {
    if (resourceType) {
      // Clear specific resource type cache
      const keysToDelete = Array.from(this.cache.keys())
        .filter(key => key.startsWith(`${resourceType}:`));
      
      keysToDelete.forEach(key => this.cache.delete(key));
      logger.debug(`Cleared cache for ${resourceType}`, { keysCleared: keysToDelete.length });
    } else {
      // Clear all cache
      const totalKeys = this.cache.size;
      this.cache.clear();
      logger.debug('Cleared all resource cache', { keysCleared: totalKeys });
    }
  }
  
  /**
   * Get cache statistics
   * @returns {Object} Cache usage statistics
   */
  getCacheStats() {
    const stats = {
      totalEntries: this.cache.size,
      maxAge: this.cacheMaxAge,
      entries: {}
    };
    
    for (const [key, value] of this.cache.entries()) {
      const age = Date.now() - value.timestamp;
      stats.entries[key] = {
        age,
        expired: age > this.cacheMaxAge,
        dataSize: JSON.stringify(value.data).length
      };
    }
    
    return stats;
  }
}

// Export singleton instance
module.exports = new AwsService();