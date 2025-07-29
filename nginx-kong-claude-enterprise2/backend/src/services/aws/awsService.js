/**
 * @fileoverview AWS service for fetching AWS resources using CLI
 * @module services/aws/awsService
 */

const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const logger = require('../../utils/logger');
const { ApiError } = require('../../middlewares/errorHandler');

class AWSService {
  constructor() {
    this.region = process.env.AWS_REGION || 'ap-northeast-2';
    this.timeout = 30000; // 30 seconds timeout for AWS CLI commands
  }

  /**
   * Execute AWS CLI command
   * @param {string} command - AWS CLI command
   * @returns {Promise<Object>} Parsed JSON output
   */
  async executeAwsCommand(command) {
    const fullCommand = `aws ${command} --region ${this.region} --output json`;
    
    logger.debug(`Executing AWS CLI command: ${fullCommand}`);
    
    try {
      const { stdout, stderr } = await execAsync(fullCommand, {
        timeout: this.timeout,
        maxBuffer: 10 * 1024 * 1024 // 10MB buffer
      });
      
      if (stderr) {
        logger.warn(`AWS CLI stderr: ${stderr}`);
      }
      
      return JSON.parse(stdout);
    } catch (error) {
      logger.error('AWS CLI command failed:', error);
      
      if (error.code === 'ENOENT') {
        throw new ApiError(500, 'AWS CLI not found. Please ensure AWS CLI is installed.');
      }
      
      if (error.killed || error.signal === 'SIGTERM') {
        throw new ApiError(504, 'AWS CLI command timed out');
      }
      
      throw new ApiError(500, `AWS CLI error: ${error.message}`);
    }
  }

  /**
   * Fetch AWS resources based on resource types
   * @param {string[]} resourceTypes - Array of resource types
   * @returns {Promise<Object>} AWS resources data
   */
  async fetchResources(resourceTypes) {
    const resources = {};
    const errors = [];
    
    for (const resourceType of resourceTypes) {
      try {
        logger.info(`Fetching ${resourceType} resources`);
        
        switch (resourceType) {
          case 'ec2':
            resources.ec2 = await this.fetchEC2Resources();
            break;
          
          case 's3':
            resources.s3 = await this.fetchS3Resources();
            break;
          
          case 'rds':
            resources.rds = await this.fetchRDSResources();
            break;
          
          case 'lambda':
            resources.lambda = await this.fetchLambdaResources();
            break;
          
          case 'iam':
            resources.iam = await this.fetchIAMResources();
            break;
          
          case 'vpc':
            resources.vpc = await this.fetchVPCResources();
            break;
          
          default:
            errors.push({
              resource: resourceType,
              error: 'Unsupported resource type'
            });
        }
      } catch (error) {
        logger.error(`Failed to fetch ${resourceType} resources:`, error);
        errors.push({
          resource: resourceType,
          error: error.message
        });
      }
    }
    
    if (errors.length > 0 && Object.keys(resources).length === 0) {
      throw new ApiError(500, 'Failed to fetch any resources', errors);
    }
    
    return {
      resources,
      errors: errors.length > 0 ? errors : undefined,
      metadata: {
        region: this.region,
        timestamp: new Date().toISOString(),
        resourceTypes: resourceTypes
      }
    };
  }

  /**
   * Fetch EC2 resources
   * @returns {Promise<Object>} EC2 resources
   */
  async fetchEC2Resources() {
    const [instances, securityGroups, keypairs] = await Promise.all([
      this.executeAwsCommand('ec2 describe-instances'),
      this.executeAwsCommand('ec2 describe-security-groups'),
      this.executeAwsCommand('ec2 describe-key-pairs')
    ]);
    
    return {
      instances: instances.Reservations || [],
      securityGroups: securityGroups.SecurityGroups || [],
      keyPairs: keypairs.KeyPairs || []
    };
  }

  /**
   * Fetch S3 resources
   * @returns {Promise<Object>} S3 resources
   */
  async fetchS3Resources() {
    const buckets = await this.executeAwsCommand('s3api list-buckets');
    
    // Get bucket details for each bucket (limited to first 10 for performance)
    const bucketDetails = [];
    const bucketsToCheck = (buckets.Buckets || []).slice(0, 10);
    
    for (const bucket of bucketsToCheck) {
      try {
        const [location, versioning, encryption] = await Promise.all([
          this.executeAwsCommand(`s3api get-bucket-location --bucket ${bucket.Name}`),
          this.executeAwsCommand(`s3api get-bucket-versioning --bucket ${bucket.Name}`),
          this.executeAwsCommand(`s3api get-bucket-encryption --bucket ${bucket.Name}`).catch(() => null)
        ]);
        
        bucketDetails.push({
          ...bucket,
          Location: location.LocationConstraint || 'us-east-1',
          Versioning: versioning,
          Encryption: encryption
        });
      } catch (error) {
        logger.warn(`Failed to get details for bucket ${bucket.Name}:`, error.message);
        bucketDetails.push(bucket);
      }
    }
    
    return {
      buckets: bucketDetails,
      totalBuckets: buckets.Buckets?.length || 0
    };
  }

  /**
   * Fetch RDS resources
   * @returns {Promise<Object>} RDS resources
   */
  async fetchRDSResources() {
    const [instances, clusters, snapshots] = await Promise.all([
      this.executeAwsCommand('rds describe-db-instances'),
      this.executeAwsCommand('rds describe-db-clusters'),
      this.executeAwsCommand('rds describe-db-snapshots --max-records 20')
    ]);
    
    return {
      instances: instances.DBInstances || [],
      clusters: clusters.DBClusters || [],
      snapshots: snapshots.DBSnapshots || []
    };
  }

  /**
   * Fetch Lambda resources
   * @returns {Promise<Object>} Lambda resources
   */
  async fetchLambdaResources() {
    const functions = await this.executeAwsCommand('lambda list-functions');
    
    // Get configuration for each function (limited to first 10)
    const functionDetails = [];
    const functionsToCheck = (functions.Functions || []).slice(0, 10);
    
    for (const func of functionsToCheck) {
      try {
        const config = await this.executeAwsCommand(
          `lambda get-function-configuration --function-name ${func.FunctionName}`
        );
        functionDetails.push({
          ...func,
          Configuration: config
        });
      } catch (error) {
        logger.warn(`Failed to get config for function ${func.FunctionName}:`, error.message);
        functionDetails.push(func);
      }
    }
    
    return {
      functions: functionDetails,
      totalFunctions: functions.Functions?.length || 0
    };
  }

  /**
   * Fetch IAM resources
   * @returns {Promise<Object>} IAM resources
   */
  async fetchIAMResources() {
    const [users, roles, policies] = await Promise.all([
      this.executeAwsCommand('iam list-users --max-items 50'),
      this.executeAwsCommand('iam list-roles --max-items 50'),
      this.executeAwsCommand('iam list-policies --scope Local --max-items 50')
    ]);
    
    return {
      users: users.Users || [],
      roles: roles.Roles || [],
      policies: policies.Policies || []
    };
  }

  /**
   * Fetch VPC resources
   * @returns {Promise<Object>} VPC resources
   */
  async fetchVPCResources() {
    const [vpcs, subnets, routeTables, natGateways] = await Promise.all([
      this.executeAwsCommand('ec2 describe-vpcs'),
      this.executeAwsCommand('ec2 describe-subnets'),
      this.executeAwsCommand('ec2 describe-route-tables'),
      this.executeAwsCommand('ec2 describe-nat-gateways')
    ]);
    
    return {
      vpcs: vpcs.Vpcs || [],
      subnets: subnets.Subnets || [],
      routeTables: routeTables.RouteTables || [],
      natGateways: natGateways.NatGateways || []
    };
  }

  /**
   * Validate AWS credentials
   * @returns {Promise<boolean>} True if credentials are valid
   */
  async validateCredentials() {
    try {
      await this.executeAwsCommand('sts get-caller-identity');
      return true;
    } catch (error) {
      logger.error('AWS credentials validation failed:', error);
      return false;
    }
  }
}

// Create singleton instance
const awsService = new AWSService();

module.exports = awsService;