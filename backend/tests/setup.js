/**
 * Jest test setup file
 * @description Sets up environment variables and mocks for testing
 */

// Load test environment variables
require('dotenv').config({ path: '.env.test' });

// Set up environment variables for all tests
process.env.NODE_ENV = 'test';
process.env.ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY || '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';
process.env.AWS_REGION = 'ap-northeast-2';
process.env.PORT = '3001';

// Increase test timeout for slow tests
jest.setTimeout(10000);

// Mock console methods to reduce noise during tests
const originalConsoleError = console.error;
const originalConsoleLog = console.log;

console.error = jest.fn((...args) => {
  // Only show errors that aren't expected test failures
  if (!args.some(arg => 
    typeof arg === 'string' && 
    (arg.includes('RED phase') || arg.includes('not implemented'))
  )) {
    originalConsoleError(...args);
  }
});

console.log = jest.fn((...args) => {
  // Only show logs in verbose mode
  if (process.env.JEST_VERBOSE) {
    originalConsoleLog(...args);
  }
});

// Clean up after each test
afterEach(() => {
  // Clear all mocks
  jest.clearAllMocks();
});