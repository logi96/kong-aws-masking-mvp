#!/usr/bin/env node

const axios = require('axios');
const winston = require('winston');

// Configure logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: '/app/logs/test-client.log' })
  ]
});

// Test configuration
const config = {
  baseUrl: process.env.ANTHROPIC_BASE_URL || 'http://nginx:8082',
  apiKey: process.env.ANTHROPIC_API_KEY,
  timeout: 60000
};

/**
 * Test Claude API through Kong gateway
 */
async function testClaudeAPI() {
  const testPayload = {
    model: "claude-3-5-sonnet-20241022",
    max_tokens: 1024,
    messages: [
      {
        role: "user",
        content: "List these AWS resources: i-1234567890abcdef0, arn:aws:iam::123456789012:role/MyRole, 10.0.1.100"
      }
    ]
  };

  try {
    logger.info('Starting Claude API test', { 
      baseUrl: config.baseUrl,
      payload: testPayload 
    });

    const response = await axios.post(
      `${config.baseUrl}/v1/messages`,
      testPayload,
      {
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01'
        },
        timeout: config.timeout
      }
    );

    logger.info('Claude API response received', {
      status: response.status,
      headers: response.headers,
      data: response.data
    });

    // Check if AWS resources were masked
    const responseContent = JSON.stringify(response.data);
    const maskedPatterns = ['EC2_', 'IAM_ROLE_', 'PRIVATE_IP_'];
    const foundMasking = maskedPatterns.some(pattern => responseContent.includes(pattern));

    logger.info('Masking verification', {
      maskedPatternsFound: foundMasking,
      responseSnippet: responseContent.substring(0, 200)
    });

    return response.data;
  } catch (error) {
    logger.error('Claude API test failed', {
      error: error.message,
      response: error.response?.data,
      status: error.response?.status
    });
    throw error;
  }
}

// Run test if executed directly
if (require.main === module) {
  testClaudeAPI()
    .then(result => {
      logger.info('Test completed successfully');
      process.exit(0);
    })
    .catch(error => {
      logger.error('Test failed', { error: error.message });
      process.exit(1);
    });
}

module.exports = { testClaudeAPI };