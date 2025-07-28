#!/usr/bin/env node

/**
 * AWS Pattern Validation Script
 * Validates AWS resource masking patterns match expected formats
 */

const winston = require('winston');

// Configure logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    }),
    new winston.transports.File({ 
      filename: '/app/logs/pattern-validation.log' 
    })
  ]
});

// AWS Resource Patterns (matching Kong plugin patterns)
const AWS_PATTERNS = {
  // EC2 Resources
  ec2_instance: {
    pattern: /i-[0-9a-f]{17}/g,
    masked: /AWS_EC2_\d{3}/g,
    examples: ['i-1234567890abcdef0', 'i-0a1b2c3d4e5f67890'],
    description: 'EC2 Instance ID'
  },
  
  ami: {
    pattern: /ami-[0-9a-f]{8}/g,
    masked: /AWS_AMI_\d{3}/g,
    examples: ['ami-12345678', 'ami-abcdef12'],
    description: 'Amazon Machine Image ID'
  },
  
  // VPC Resources
  vpc: {
    pattern: /vpc-[0-9a-f]{8}/g,
    masked: /AWS_VPC_\d{3}/g,
    examples: ['vpc-12345678', 'vpc-abcdef12'],
    description: 'VPC ID'
  },
  
  subnet: {
    pattern: /subnet-[0-9a-f]{17}/g,
    masked: /AWS_SUBNET_\d{3}/g,
    examples: ['subnet-12345678901234567', 'subnet-abcdef12345678901'],
    description: 'Subnet ID'
  },
  
  security_group: {
    pattern: /sg-[0-9a-f]{8}/g,
    masked: /AWS_SECURITY_GROUP_\d{3}/g,
    examples: ['sg-12345678', 'sg-abcdef12'],
    description: 'Security Group ID'
  },
  
  // S3 Resources
  s3_bucket: {
    pattern: /[a-z0-9][a-z0-9-]*bucket[a-z0-9-]*/g,
    masked: /AWS_S3_BUCKET_\d{3}/g,
    examples: ['my-bucket', 'data-bucket-prod', 'backup-bucket-2024'],
    description: 'S3 Bucket Name (containing "bucket")'
  },
  
  s3_logs: {
    pattern: /[a-z0-9][a-z0-9-]*logs[a-z0-9-]*/g,
    masked: /AWS_S3_LOGS_BUCKET_\d{3}/g,
    examples: ['app-logs', 'production-logs-2024', 'audit-logs-backup'],
    description: 'S3 Logs Bucket Name'
  },
  
  // RDS Resources
  rds_instance: {
    pattern: /[a-z-]*db[a-z-]*/g,
    masked: /AWS_RDS_\d{3}/g,
    examples: ['production-db', 'mysql-db-prod', 'analytics-db'],
    description: 'RDS Database Instance'
  },
  
  // IAM Resources
  iam_role_arn: {
    pattern: /arn:aws:iam::[0-9]{12}:role\/[a-zA-Z0-9+=,.@\-_]+/g,
    masked: /AWS_ARN_\d{3}/g,
    examples: [
      'arn:aws:iam::123456789012:role/AdminRole',
      'arn:aws:iam::987654321098:role/EC2-Instance-Profile'
    ],
    description: 'IAM Role ARN'
  },
  
  account_id: {
    pattern: /\b\d{12}\b/g,
    masked: /AWS_ACCOUNT_\d{3}/g,
    examples: ['123456789012', '987654321098'],
    description: 'AWS Account ID'
  },
  
  // Credentials
  access_key: {
    pattern: /AKIA[0-9A-Z]{16}/g,
    masked: /AWS_ACCESS_KEY_\d{3}/g,
    examples: ['AKIAIOSFODNN7EXAMPLE', 'AKIAI44QH8DHBEXAMPLE'],
    description: 'AWS Access Key ID'
  },
  
  // Lambda
  lambda_arn: {
    pattern: /arn:aws:lambda:[a-z0-9-]+:[0-9]+:function:[a-zA-Z0-9-_]+/g,
    masked: /AWS_LAMBDA_ARN_\d{3}/g,
    examples: [
      'arn:aws:lambda:us-east-1:123456789012:function:ProcessOrders',
      'arn:aws:lambda:eu-west-1:987654321098:function:data-processor'
    ],
    description: 'Lambda Function ARN'
  },
  
  // ELB/ALB
  elb_arn: {
    pattern: /arn:aws:elasticloadbalancing:[a-z0-9-]+:[0-9]+:loadbalancer\/[a-zA-Z0-9-\/]+/g,
    masked: /AWS_ELB_ARN_\d{3}/g,
    examples: [
      'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/50dc6c495c0c9188'
    ],
    description: 'Elastic Load Balancer ARN'
  }
};

/**
 * Validate a single pattern
 * @param {String} name - Pattern name
 * @param {Object} config - Pattern configuration
 * @returns {Object} Validation result
 */
function validatePattern(name, config) {
  const result = {
    name,
    description: config.description,
    pattern: config.pattern.toString(),
    examples_tested: config.examples.length,
    passed: 0,
    failed: 0,
    errors: []
  };

  for (const example of config.examples) {
    try {
      // Test if pattern matches
      const matches = example.match(config.pattern);
      if (matches && matches[0] === example) {
        result.passed++;
      } else {
        result.failed++;
        result.errors.push(`Pattern failed to match example: ${example}`);
      }
    } catch (error) {
      result.failed++;
      result.errors.push(`Error testing ${example}: ${error.message}`);
    }
  }

  return result;
}

/**
 * Test masking transformation
 * @param {String} input - Input text with AWS resources
 * @param {Object} patterns - Patterns to apply
 * @returns {Object} Masking result
 */
function testMasking(input, patterns) {
  let masked = input;
  const replacements = [];
  let counter = {};

  for (const [name, config] of Object.entries(patterns)) {
    const matches = input.match(config.pattern) || [];
    
    for (const match of matches) {
      const type = name.toUpperCase();
      counter[type] = (counter[type] || 0) + 1;
      const replacement = config.masked.source.replace('\\d{3}', String(counter[type]).padStart(3, '0'));
      
      masked = masked.replace(match, replacement);
      replacements.push({
        original: match,
        masked: replacement,
        type: name
      });
    }
  }

  return {
    original: input,
    masked,
    replacements,
    stats: {
      total_replacements: replacements.length,
      by_type: counter
    }
  };
}

/**
 * Run comprehensive pattern tests
 */
function runPatternTests() {
  logger.info('Starting AWS pattern validation tests');
  
  const results = {
    timestamp: new Date().toISOString(),
    pattern_tests: [],
    masking_tests: [],
    summary: {
      total_patterns: 0,
      patterns_passed: 0,
      patterns_failed: 0,
      total_examples: 0,
      examples_passed: 0,
      examples_failed: 0
    }
  };

  // Test individual patterns
  logger.info('Testing individual patterns...');
  for (const [name, config] of Object.entries(AWS_PATTERNS)) {
    const result = validatePattern(name, config);
    results.pattern_tests.push(result);
    
    results.summary.total_patterns++;
    results.summary.total_examples += result.examples_tested;
    results.summary.examples_passed += result.passed;
    results.summary.examples_failed += result.failed;
    
    if (result.failed === 0) {
      results.summary.patterns_passed++;
      logger.info(`✓ ${name}: All examples passed`);
    } else {
      results.summary.patterns_failed++;
      logger.error(`✗ ${name}: ${result.failed} failures`, { errors: result.errors });
    }
  }

  // Test masking scenarios
  logger.info('Testing masking scenarios...');
  
  const testScenarios = [
    {
      name: 'Simple EC2 and VPC',
      input: 'Instance i-1234567890abcdef0 in vpc-12345678 with security group sg-abcdef12'
    },
    {
      name: 'Complex AWS Infrastructure',
      input: 'Deploy Lambda arn:aws:lambda:us-east-1:123456789012:function:ProcessOrders to read from s3://production-bucket and write to RDS instance mysql-prod-db'
    },
    {
      name: 'IAM Configuration',
      input: 'Grant role arn:aws:iam::987654321098:role/AdminRole access to account 987654321098 resources'
    },
    {
      name: 'Multi-Region Setup',
      input: 'Replicate data from production-db in us-east-1 to dr-backup-db in us-west-2, storing backups in disaster-recovery-logs bucket'
    }
  ];

  for (const scenario of testScenarios) {
    const result = testMasking(scenario.input, AWS_PATTERNS);
    results.masking_tests.push({
      name: scenario.name,
      ...result
    });
    
    logger.info(`Masking test: ${scenario.name}`, {
      replacements: result.stats.total_replacements
    });
  }

  return results;
}

/**
 * Generate validation report
 * @param {Object} results - Test results
 */
function generateReport(results) {
  const reportPath = `/app/test-results/pattern-validation-${Date.now()}.json`;
  const fs = require('fs');
  
  fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
  logger.info(`Pattern validation report saved to ${reportPath}`);

  // Generate summary report
  const summaryPath = `/app/test-results/pattern-validation-summary-${Date.now()}.md`;
  let summary = '# AWS Pattern Validation Report\n\n';
  summary += `Generated: ${results.timestamp}\n\n`;
  
  summary += '## Pattern Test Summary\n\n';
  summary += `- Total Patterns: ${results.summary.total_patterns}\n`;
  summary += `- Patterns Passed: ${results.summary.patterns_passed}\n`;
  summary += `- Patterns Failed: ${results.summary.patterns_failed}\n`;
  summary += `- Total Examples: ${results.summary.total_examples}\n`;
  summary += `- Examples Passed: ${results.summary.examples_passed}\n`;
  summary += `- Examples Failed: ${results.summary.examples_failed}\n\n`;
  
  summary += '## Pattern Details\n\n';
  for (const test of results.pattern_tests) {
    const status = test.failed === 0 ? '✅' : '❌';
    summary += `### ${status} ${test.name}\n`;
    summary += `- Description: ${test.description}\n`;
    summary += `- Pattern: \`${test.pattern}\`\n`;
    summary += `- Examples tested: ${test.examples_tested}\n`;
    summary += `- Passed: ${test.passed}, Failed: ${test.failed}\n`;
    if (test.errors.length > 0) {
      summary += `- Errors:\n${test.errors.map(e => `  - ${e}`).join('\n')}\n`;
    }
    summary += '\n';
  }
  
  summary += '## Masking Test Results\n\n';
  for (const test of results.masking_tests) {
    summary += `### ${test.name}\n`;
    summary += `- Original: \`${test.original}\`\n`;
    summary += `- Masked: \`${test.masked}\`\n`;
    summary += `- Total replacements: ${test.stats.total_replacements}\n`;
    summary += `- By type: ${JSON.stringify(test.stats.by_type)}\n\n`;
  }
  
  fs.writeFileSync(summaryPath, summary);
  logger.info(`Summary report saved to ${summaryPath}`);
}

// Main execution
function main() {
  try {
    const results = runPatternTests();
    generateReport(results);
    
    // Exit with appropriate code
    if (results.summary.patterns_failed > 0) {
      logger.error(`Pattern validation completed with ${results.summary.patterns_failed} failures`);
      process.exit(1);
    } else {
      logger.info('All pattern validations passed successfully');
      process.exit(0);
    }
  } catch (error) {
    logger.error('Pattern validation failed', { error: error.message });
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { validatePattern, testMasking, AWS_PATTERNS };