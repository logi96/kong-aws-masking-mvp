const request = require('supertest');

/**
 * @typedef {Object} HealthResponse
 * @property {string} status - 서비스 상태 ('healthy' | 'unhealthy')
 * @property {string} timestamp - ISO 8601 형식 타임스탬프
 * @property {string} version - 애플리케이션 버전
 * @property {Object} [details] - 상세 헬스 정보
 */

// Test helper functions
function setupHealthApp() {
  let app;
  try {
    // Set environment for test
    process.env.NODE_ENV = 'test';
    process.env.ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY || 'sk-ant-api03-UNIT-TEST-PLACEHOLDER';
    
    // Clear require cache to get fresh instance (security: use fixed path)
    const appPath = require.resolve('../../src/app');
    // eslint-disable-next-line security/detect-object-injection
    delete require.cache[appPath];
    app = require('../../src/app');
  } catch (error) {
    console.error('Failed to load app for health test:', error.message);
  }
  return app;
}

function validateHealthResponse(response) {
  expect(response.status).toBe(200);
  expect(response.body).toEqual({
    status: 'healthy',
    timestamp: expect.any(String),
    version: expect.any(String),
    details: expect.objectContaining({
      uptime: expect.any(Number),
      memory: expect.any(Object),
      pid: expect.any(Number)
    })
  });
  
  // ISO 8601 날짜 형식 검증
  expect(new Date(response.body.timestamp).toISOString()).toBe(response.body.timestamp);
}

function validateTimestampFormat(timestamp) {
  expect(timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/);
}

function validateVersionMatch(response) {
  const packageJson = require('../../package.json');
  expect(response.body.version).toBe(packageJson.version);
}

function validatePerformance(duration) {
  // CLAUDE.md 성능 요구사항: < 5초
  expect(duration).toBeLessThan(5000);
}

function runHealthTests(app) {
  test('should return 200 with healthy status', async () => {
    expect(app).toBeTruthy();
    const response = await request(app).get('/health');
    validateHealthResponse(response);
  });

  test('should return timestamp in ISO 8601 format', async () => {
    expect(app).toBeTruthy();
    const response = await request(app).get('/health');
    validateTimestampFormat(response.body.timestamp);
  });

  test('should include version from package.json', async () => {
    expect(app).toBeTruthy();
    const response = await request(app).get('/health');
    validateVersionMatch(response);
  });

  test('should respond within performance target (<5 seconds)', async () => {
    expect(app).toBeTruthy();
    const startTime = Date.now();
    await request(app).get('/health');
    const duration = Date.now() - startTime;
    validatePerformance(duration);
  }, 6000);
}

describe('Health Check Endpoint', () => {
  let app;

  beforeAll(() => {
    app = setupHealthApp();
  });

  describe('GET /health', () => {
    beforeEach(() => {
      if (!app) {
        throw new Error('App not implemented yet - this is expected in RED phase');
      }
    });
    
    runHealthTests(app);
  });
});

// Health service integration tests only
// No mock services allowed per security guidelines