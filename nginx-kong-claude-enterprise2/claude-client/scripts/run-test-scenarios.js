#!/usr/bin/env node

const fs = require('fs').promises;
const path = require('path');
const axios = require('axios');
const winston = require('winston');

// Configure logger
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
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
      filename: '/app/logs/test-automation.log',
      format: winston.format.json()
    })
  ]
});

// Test configuration
const config = {
  baseUrl: process.env.ANTHROPIC_BASE_URL || 'http://nginx:8082',
  apiKey: process.env.ANTHROPIC_API_KEY,
  timeout: parseInt(process.env.TEST_TIMEOUT) || 60000,
  scenarioDir: '/app/test-scenarios',
  resultsDir: '/app/test-results'
};

/**
 * Load test scenarios from JSON files
 * @returns {Promise<Array>} Array of test scenario objects
 */
async function loadTestScenarios() {
  try {
    const files = await fs.readdir(config.scenarioDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));
    
    const scenarios = [];
    for (const file of jsonFiles) {
      const content = await fs.readFile(path.join(config.scenarioDir, file), 'utf8');
      const data = JSON.parse(content);
      scenarios.push({
        file,
        ...data
      });
    }
    
    logger.info(`Loaded ${scenarios.length} test scenario files`);
    return scenarios;
  } catch (error) {
    logger.error('Failed to load test scenarios', { error: error.message });
    throw error;
  }
}

/**
 * Execute a single test scenario
 * @param {Object} scenario - Test scenario object
 * @returns {Promise<Object>} Test result
 */
async function executeScenario(scenario) {
  const startTime = Date.now();
  const result = {
    id: scenario.id,
    name: scenario.name,
    status: 'pending',
    startTime: new Date().toISOString(),
    duration: 0,
    request: null,
    response: null,
    validation: {},
    errors: []
  };

  try {
    // Prepare request
    const payload = {
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 1024,
      ...scenario.input
    };

    result.request = payload;
    logger.debug(`Executing scenario ${scenario.id}`, { payload });

    // Make API request
    const response = await axios.post(
      `${config.baseUrl}/v1/messages`,
      payload,
      {
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01'
        },
        timeout: config.timeout
      }
    );

    result.response = {
      status: response.status,
      headers: response.headers,
      data: response.data
    };

    // Perform validations
    if (scenario.expected_masking) {
      result.validation.masking = validateMasking(
        response.data,
        scenario.expected_masking
      );
    }

    if (scenario.validation) {
      result.validation.checks = performValidationChecks(
        response.data,
        scenario.validation
      );
    }

    // Determine overall status
    const allValidationsPassed = Object.values(result.validation)
      .flat()
      .every(v => v.passed !== false);

    result.status = allValidationsPassed ? 'passed' : 'failed';

  } catch (error) {
    result.status = 'error';
    result.errors.push({
      type: error.name,
      message: error.message,
      stack: error.stack
    });
    logger.error(`Scenario ${scenario.id} failed`, { error: error.message });
  }

  result.duration = Date.now() - startTime;
  result.endTime = new Date().toISOString();

  return result;
}

/**
 * Validate masking patterns in response
 * @param {Object} responseData - API response data
 * @param {Object} expectedMasking - Expected masking configuration
 * @returns {Array} Validation results
 */
function validateMasking(responseData, expectedMasking) {
  const results = [];
  const responseText = JSON.stringify(responseData);

  // Check for original patterns (should NOT be present)
  if (expectedMasking.patterns) {
    for (const pattern of expectedMasking.patterns) {
      results.push({
        check: `Pattern "${pattern}" should be masked`,
        passed: !responseText.includes(pattern),
        actual: responseText.includes(pattern) ? 'Found original pattern' : 'Pattern properly masked'
      });
    }
  }

  // Check for masked formats (should be present)
  if (expectedMasking.masked_format) {
    const formats = Array.isArray(expectedMasking.masked_format) 
      ? expectedMasking.masked_format 
      : [expectedMasking.masked_format];
    
    for (const format of formats) {
      results.push({
        check: `Masked format "${format}" should be present`,
        passed: responseText.includes(format),
        actual: responseText.includes(format) ? 'Found masked format' : 'Masked format not found'
      });
    }
  }

  return results;
}

/**
 * Perform additional validation checks
 * @param {Object} responseData - API response data
 * @param {Object} validationConfig - Validation configuration
 * @returns {Array} Validation results
 */
function performValidationChecks(responseData, validationConfig) {
  const results = [];
  const responseText = JSON.stringify(responseData);

  if (validationConfig.response_should_contain) {
    for (const expected of validationConfig.response_should_contain) {
      results.push({
        check: `Response should contain "${expected}"`,
        passed: responseText.includes(expected),
        actual: responseText.includes(expected) ? 'Found' : 'Not found'
      });
    }
  }

  if (validationConfig.response_should_not_contain) {
    for (const unexpected of validationConfig.response_should_not_contain) {
      results.push({
        check: `Response should NOT contain "${unexpected}"`,
        passed: !responseText.includes(unexpected),
        actual: !responseText.includes(unexpected) ? 'Not found (good)' : 'Found (bad)'
      });
    }
  }

  return results;
}

/**
 * Execute all scenarios in a test suite
 * @param {Object} suite - Test suite object
 * @returns {Promise<Object>} Suite results
 */
async function executeSuite(suite) {
  logger.info(`Starting test suite: ${suite.name}`);
  
  const suiteResult = {
    file: suite.file,
    name: suite.name,
    description: suite.description,
    startTime: new Date().toISOString(),
    scenarios: [],
    summary: {
      total: 0,
      passed: 0,
      failed: 0,
      error: 0
    }
  };

  for (const scenario of suite.scenarios) {
    logger.info(`Running scenario ${scenario.id}: ${scenario.name}`);
    const result = await executeScenario(scenario);
    
    suiteResult.scenarios.push(result);
    suiteResult.summary.total++;
    suiteResult.summary[result.status]++;
    
    // Add delay between tests to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  suiteResult.endTime = new Date().toISOString();
  suiteResult.duration = Date.now() - new Date(suiteResult.startTime).getTime();

  return suiteResult;
}

/**
 * Save test results to file
 * @param {Array} results - Test results
 * @returns {Promise<void>}
 */
async function saveResults(results) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `test-results-${timestamp}.json`;
  const filepath = path.join(config.resultsDir, filename);

  await fs.mkdir(config.resultsDir, { recursive: true });
  await fs.writeFile(filepath, JSON.stringify(results, null, 2));
  
  logger.info(`Test results saved to ${filepath}`);

  // Also create a summary report
  const summary = createSummaryReport(results);
  const summaryFile = path.join(config.resultsDir, `summary-${timestamp}.md`);
  await fs.writeFile(summaryFile, summary);
  
  logger.info(`Summary report saved to ${summaryFile}`);
}

/**
 * Create a markdown summary report
 * @param {Array} results - Test results
 * @returns {String} Markdown report
 */
function createSummaryReport(results) {
  let report = '# AWS Masking Test Results\n\n';
  report += `Generated: ${new Date().toISOString()}\n\n`;

  let totalScenarios = 0;
  let totalPassed = 0;
  let totalFailed = 0;
  let totalError = 0;

  for (const suite of results) {
    report += `## ${suite.name}\n\n`;
    report += `${suite.description}\n\n`;
    
    report += '| Scenario | Status | Duration | Details |\n';
    report += '|----------|--------|----------|---------|\n';
    
    for (const scenario of suite.scenarios) {
      const status = scenario.status === 'passed' ? '✅' : 
                     scenario.status === 'failed' ? '❌' : '⚠️';
      const details = scenario.errors.length > 0 
        ? scenario.errors[0].message 
        : `${Object.values(scenario.validation).flat().filter(v => v.passed).length} checks passed`;
      
      report += `| ${scenario.name} | ${status} | ${scenario.duration}ms | ${details} |\n`;
      
      totalScenarios++;
      if (scenario.status === 'passed') totalPassed++;
      if (scenario.status === 'failed') totalFailed++;
      if (scenario.status === 'error') totalError++;
    }
    
    report += '\n';
  }

  report += '## Summary\n\n';
  report += `- Total Scenarios: ${totalScenarios}\n`;
  report += `- Passed: ${totalPassed} (${((totalPassed/totalScenarios)*100).toFixed(1)}%)\n`;
  report += `- Failed: ${totalFailed}\n`;
  report += `- Errors: ${totalError}\n`;

  return report;
}

/**
 * Main execution function
 */
async function main() {
  logger.info('Starting AWS masking test automation');
  
  try {
    // Check API key
    if (!config.apiKey) {
      throw new Error('ANTHROPIC_API_KEY environment variable is required');
    }

    // Load test scenarios
    const suites = await loadTestScenarios();
    
    if (suites.length === 0) {
      logger.warn('No test scenarios found');
      return;
    }

    // Execute all test suites
    const results = [];
    for (const suite of suites) {
      const result = await executeSuite(suite);
      results.push(result);
    }

    // Save results
    await saveResults(results);

    // Log summary
    const totalScenarios = results.reduce((sum, r) => sum + r.summary.total, 0);
    const totalPassed = results.reduce((sum, r) => sum + r.summary.passed, 0);
    
    logger.info('Test automation completed', {
      suites: results.length,
      scenarios: totalScenarios,
      passed: totalPassed,
      success_rate: `${((totalPassed/totalScenarios)*100).toFixed(1)}%`
    });

  } catch (error) {
    logger.error('Test automation failed', { error: error.message });
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { executeScenario, executeSuite };