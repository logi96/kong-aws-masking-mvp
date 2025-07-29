/**
 * @fileoverview Anthropic SDK proxy test suite
 * @description Tests different connection methods for Claude API access
 * 
 * Test scenarios:
 * 1. Direct connection test (should be blocked)
 * 2. ProxyAgent connection test
 * 3. Environment variable (ANTHROPIC_BASE_URL) test
 * 4. Custom fetch implementation test
 * 
 * @module test-sdk-proxy
 */

import Anthropic from '@anthropic-ai/sdk';
import { ProxyAgent } from 'undici';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Test configuration
 * @typedef {Object} TestConfig
 * @property {string} apiKey - Anthropic API key
 * @property {string} proxyUrl - Proxy server URL
 * @property {string} resultsDir - Directory for test results
 */
const config = {
  apiKey: process.env.ANTHROPIC_API_KEY || 'sk-ant-api03-test-key',
  proxyUrl: process.env.PROXY_URL || 'http://kong:8000',
  resultsDir: path.join(__dirname, '..', 'results')
};

/**
 * Test result structure
 * @typedef {Object} TestResult
 * @property {string} testName - Name of the test
 * @property {boolean} success - Test success status
 * @property {string} method - Connection method used
 * @property {number} responseTime - Response time in milliseconds
 * @property {string} [error] - Error message if test failed
 * @property {Object} [response] - API response if successful
 * @property {Date} timestamp - Test execution timestamp
 */

/**
 * Ensures the results directory exists
 * @returns {Promise<void>}
 */
async function ensureResultsDir() {
  try {
    await fs.mkdir(config.resultsDir, { recursive: true });
  } catch (error) {
    console.error('Failed to create results directory:', error);
  }
}

/**
 * Saves test results to JSON file
 * @param {TestResult[]} results - Array of test results
 * @returns {Promise<void>}
 */
async function saveResults(results) {
  const filePath = path.join(config.resultsDir, 'test-results.json');
  const report = {
    testSuite: 'Anthropic SDK Proxy Tests',
    executionTime: new Date().toISOString(),
    environment: {
      nodeVersion: process.version,
      platform: process.platform,
      proxyUrl: config.proxyUrl
    },
    results,
    summary: {
      total: results.length,
      passed: results.filter(r => r.success).length,
      failed: results.filter(r => !r.success).length
    }
  };

  await fs.writeFile(filePath, JSON.stringify(report, null, 2));
  console.log(`Results saved to: ${filePath}`);
}

/**
 * Test 1: Direct connection (should be blocked)
 * @returns {Promise<TestResult>}
 */
async function testDirectConnection() {
  const startTime = Date.now();
  const testName = 'Direct Connection Test';
  
  console.log('\n=== Test 1: Direct Connection (Should Fail) ===');
  
  try {
    const client = new Anthropic({
      apiKey: config.apiKey,
      // No proxy configuration - direct connection
    });

    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 50,
      messages: [{
        role: 'user',
        content: 'Say "Direct connection successful" if you can read this.'
      }]
    });

    // If we reach here, direct connection worked (unexpected)
    return {
      testName,
      success: false,
      method: 'direct',
      responseTime: Date.now() - startTime,
      error: 'Direct connection succeeded when it should have been blocked',
      response: response.content[0].text,
      timestamp: new Date()
    };

  } catch (error) {
    // Expected behavior - direct connection should fail
    console.log('✓ Direct connection blocked as expected:', error.message);
    return {
      testName,
      success: true,
      method: 'direct',
      responseTime: Date.now() - startTime,
      error: `Blocked: ${error.message}`,
      timestamp: new Date()
    };
  }
}

/**
 * Test 2: ProxyAgent connection
 * @returns {Promise<TestResult>}
 */
async function testProxyAgent() {
  const startTime = Date.now();
  const testName = 'ProxyAgent Connection Test';
  
  console.log('\n=== Test 2: ProxyAgent Connection ===');
  
  try {
    const proxyAgent = new ProxyAgent(config.proxyUrl);
    
    const client = new Anthropic({
      apiKey: config.apiKey,
      httpAgent: proxyAgent
    });

    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 50,
      messages: [{
        role: 'user',
        content: 'Say "ProxyAgent connection successful" if you can read this.'
      }]
    });

    console.log('✓ ProxyAgent connection successful');
    return {
      testName,
      success: true,
      method: 'ProxyAgent',
      responseTime: Date.now() - startTime,
      response: response.content[0].text,
      timestamp: new Date()
    };

  } catch (error) {
    console.error('✗ ProxyAgent connection failed:', error.message);
    return {
      testName,
      success: false,
      method: 'ProxyAgent',
      responseTime: Date.now() - startTime,
      error: error.message,
      timestamp: new Date()
    };
  }
}

/**
 * Test 3: Environment variable (ANTHROPIC_BASE_URL)
 * @returns {Promise<TestResult>}
 */
async function testEnvironmentVariable() {
  const startTime = Date.now();
  const testName = 'Environment Variable Test';
  
  console.log('\n=== Test 3: Environment Variable (ANTHROPIC_BASE_URL) ===');
  
  // Save original env var
  const originalBaseUrl = process.env.ANTHROPIC_BASE_URL;
  
  try {
    // Set the base URL to use our proxy
    // Note: SDK will append /v1 automatically, so we only provide the base URL
    process.env.ANTHROPIC_BASE_URL = config.proxyUrl;
    
    const client = new Anthropic({
      apiKey: config.apiKey
      // SDK should use ANTHROPIC_BASE_URL from environment
    });

    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 50,
      messages: [{
        role: 'user',
        content: 'Say "Environment variable connection successful" if you can read this.'
      }]
    });

    console.log('✓ Environment variable connection successful');
    return {
      testName,
      success: true,
      method: 'ANTHROPIC_BASE_URL',
      responseTime: Date.now() - startTime,
      response: response.content[0].text,
      timestamp: new Date()
    };

  } catch (error) {
    console.error('✗ Environment variable connection failed:', error.message);
    return {
      testName,
      success: false,
      method: 'ANTHROPIC_BASE_URL',
      responseTime: Date.now() - startTime,
      error: error.message,
      timestamp: new Date()
    };
  } finally {
    // Restore original env var
    if (originalBaseUrl) {
      process.env.ANTHROPIC_BASE_URL = originalBaseUrl;
    } else {
      delete process.env.ANTHROPIC_BASE_URL;
    }
  }
}

/**
 * Test 4: Custom fetch implementation
 * @returns {Promise<TestResult>}
 */
async function testCustomFetch() {
  const startTime = Date.now();
  const testName = 'Custom Fetch Test';
  
  console.log('\n=== Test 4: Custom Fetch Implementation ===');
  
  try {
    // Custom fetch that routes through our proxy
    const customFetch = async (url, options) => {
      const proxyUrl = new URL(url);
      proxyUrl.protocol = config.proxyUrl.split(':')[0] + ':';
      proxyUrl.host = config.proxyUrl.split('//')[1];
      
      console.log(`Routing request through proxy: ${proxyUrl.toString()}`);
      
      return fetch(proxyUrl.toString(), {
        ...options,
        headers: {
          ...options.headers,
          'X-Original-Host': new URL(url).host
        }
      });
    };

    const client = new Anthropic({
      apiKey: config.apiKey,
      fetch: customFetch
    });

    const response = await client.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 50,
      messages: [{
        role: 'user',
        content: 'Say "Custom fetch connection successful" if you can read this.'
      }]
    });

    console.log('✓ Custom fetch connection successful');
    return {
      testName,
      success: true,
      method: 'customFetch',
      responseTime: Date.now() - startTime,
      response: response.content[0].text,
      timestamp: new Date()
    };

  } catch (error) {
    console.error('✗ Custom fetch connection failed:', error.message);
    return {
      testName,
      success: false,
      method: 'customFetch',
      responseTime: Date.now() - startTime,
      error: error.message,
      timestamp: new Date()
    };
  }
}

/**
 * Main test runner
 * @returns {Promise<void>}
 */
async function runTests() {
  console.log('🚀 Starting Anthropic SDK Proxy Tests');
  console.log(`Proxy URL: ${config.proxyUrl}`);
  console.log(`API Key: ${config.apiKey.substring(0, 10)}...`);
  
  await ensureResultsDir();
  
  const results = [];
  
  try {
    // Run all tests
    results.push(await testDirectConnection());
    results.push(await testProxyAgent());
    results.push(await testEnvironmentVariable());
    results.push(await testCustomFetch());
    
  } catch (error) {
    console.error('Test suite error:', error);
  }
  
  // Save results
  await saveResults(results);
  
  // Print summary
  console.log('\n=== Test Summary ===');
  console.log(`Total tests: ${results.length}`);
  console.log(`Passed: ${results.filter(r => r.success).length}`);
  console.log(`Failed: ${results.filter(r => !r.success).length}`);
  
  results.forEach(result => {
    const status = result.success ? '✓' : '✗';
    const time = `${result.responseTime}ms`;
    console.log(`${status} ${result.testName} (${result.method}) - ${time}`);
    if (!result.success && result.error) {
      console.log(`  Error: ${result.error}`);
    }
  });
  
  // Exit with appropriate code
  const hasFailures = results.some(r => !r.success && r.testName !== 'Direct Connection Test');
  process.exit(hasFailures ? 1 : 0);
}

// Handle unhandled rejections
process.on('unhandledRejection', (error) => {
  console.error('Unhandled rejection:', error);
  process.exit(1);
});

// Run tests if this is the main module
if (import.meta.url === `file://${process.argv[1]}`) {
  runTests().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

export { runTests, testDirectConnection, testProxyAgent, testEnvironmentVariable, testCustomFetch };