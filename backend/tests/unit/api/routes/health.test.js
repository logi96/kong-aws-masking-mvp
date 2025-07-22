/**
 * @fileoverview Health route comprehensive tests
 * @description 100% 테스트 커버리지를 위한 완전한 health.js 테스트
 */

const request = require('supertest');
const express = require('express');
const { router, createHealthResponse, checkSystemHealth } = require('../../../../src/api/routes/health');

// Express 앱 설정
const app = express();
app.use('/health', router);

describe('Health Route Tests', () => {
  beforeEach(() => {
    // Mock process.uptime to ensure health checks pass
    jest.spyOn(process, 'uptime').mockReturnValue(60); // 60 seconds uptime
  });
  
  afterEach(() => {
    // Restore all mocks after each test
    jest.restoreAllMocks();
  });

  describe('GET /health', () => {
    test('should return healthy status with 200', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'healthy',
        timestamp: expect.any(String),
        version: expect.any(String),
        details: expect.objectContaining({
          uptime: expect.any(Number),
          memory: expect.objectContaining({
            rss: expect.any(Number),
            heapTotal: expect.any(Number),
            heapUsed: expect.any(Number),
            external: expect.any(Number)
          }),
          pid: expect.any(Number)
        })
      });
    });

    test('should return valid ISO timestamp', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      const timestamp = new Date(response.body.timestamp);
      expect(timestamp.toISOString()).toBe(response.body.timestamp);
      expect(Date.now() - timestamp.getTime()).toBeLessThan(1000); // 1초 이내
    });

    test('should include process information', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body.details.pid).toBe(process.pid);
      expect(response.body.details.uptime).toBeGreaterThan(0);
    });
  });

  describe('createHealthResponse function', () => {
    test('should create valid health response object', () => {
      const response = createHealthResponse();

      expect(response).toMatchObject({
        status: 'healthy',
        timestamp: expect.any(String),
        version: expect.any(String),
        details: expect.objectContaining({
          uptime: expect.any(Number),
          memory: expect.any(Object),
          pid: expect.any(Number)
        })
      });
    });

    test('should have valid timestamp format', () => {
      const response = createHealthResponse();
      const timestamp = new Date(response.timestamp);
      
      expect(timestamp.toISOString()).toBe(response.timestamp);
      expect(response.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    });

    test('should include package version', () => {
      const packageJson = require('../../../../package.json');
      const response = createHealthResponse();
      
      expect(response.version).toBe(packageJson.version);
    });

    test('should include memory usage details', () => {
      const response = createHealthResponse();
      const memoryKeys = ['rss', 'heapTotal', 'heapUsed', 'external'];
      
      memoryKeys.forEach(key => {
        expect(response.details.memory[key]).toBeGreaterThan(0);
        expect(typeof response.details.memory[key]).toBe('number');
      });
    });

    test('should include process uptime', () => {
      const response = createHealthResponse();
      
      expect(response.details.uptime).toBeGreaterThanOrEqual(0);
      expect(Number.isInteger(response.details.uptime)).toBe(true);
    });
  });

  describe('checkSystemHealth function', () => {
    test('should return true for normal conditions', () => {
      const isHealthy = checkSystemHealth();
      expect(typeof isHealthy).toBe('boolean');
      expect(isHealthy).toBe(true);
    });

    test('should handle memory usage checks', () => {
      // Mock process.memoryUsage to simulate high memory
      const originalMemoryUsage = process.memoryUsage;
      process.memoryUsage = jest.fn(() => ({
        rss: 2000000000, // 2GB
        heapTotal: 1500000000, // 1.5GB  
        heapUsed: 1200000000 * 1024 * 1024, // 1.2TB (over limit)
        external: 50000000,
        arrayBuffers: 10000000
      }));

      const isHealthy = checkSystemHealth();
      expect(isHealthy).toBe(false);

      // Restore original function
      process.memoryUsage = originalMemoryUsage;
    });

    test('should handle uptime checks', () => {
      // Mock process.uptime to simulate just started process
      const originalUptime = process.uptime;
      process.uptime = jest.fn(() => 0.5); // 0.5 seconds

      const isHealthy = checkSystemHealth();
      expect(isHealthy).toBe(false);

      // Restore original function
      process.uptime = originalUptime;
    });

    test('should handle exceptions gracefully', () => {
      // Mock process.memoryUsage to throw error
      const originalMemoryUsage = process.memoryUsage;
      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
      
      process.memoryUsage = jest.fn(() => {
        throw new Error('Memory access error');
      });

      const isHealthy = checkSystemHealth();
      expect(isHealthy).toBe(false);
      expect(consoleSpy).toHaveBeenCalledWith('Health check failed:', expect.any(Error));

      // Restore original functions
      process.memoryUsage = originalMemoryUsage;
      consoleSpy.mockRestore();
    });
  });

  describe('Unhealthy status scenarios', () => {
    test('should return 503 when system is unhealthy', () => {
      // Mock checkSystemHealth to return false
      const originalMemoryUsage = process.memoryUsage;
      process.memoryUsage = jest.fn(() => ({
        rss: 2000000000,
        heapTotal: 1500000000,  
        heapUsed: 1200000000 * 1024 * 1024, // Over limit
        external: 50000000,
        arrayBuffers: 10000000
      }));

      return request(app)
        .get('/health')
        .expect(503)
        .then(response => {
          expect(response.body.status).toBe('unhealthy');
          expect(response.body).toHaveProperty('timestamp');
          expect(response.body).toHaveProperty('version');
          expect(response.body).toHaveProperty('details');
          
          // Restore original function
          process.memoryUsage = originalMemoryUsage;
        });
    });

    test('should maintain response structure even when unhealthy', async () => {
      // Mock for unhealthy state
      const originalUptime = process.uptime;
      process.uptime = jest.fn(() => 0.5);

      const response = await request(app)
        .get('/health')
        .expect(503);

      expect(response.body).toMatchObject({
        status: 'unhealthy',
        timestamp: expect.any(String),
        version: expect.any(String),
        details: expect.objectContaining({
          uptime: expect.any(Number),
          memory: expect.any(Object),
          pid: expect.any(Number)
        })
      });

      // Restore original function
      process.uptime = originalUptime;
    });
  });

  describe('Response timing', () => {
    test('should respond within CLAUDE.md requirements (<5 seconds)', async () => {
      const startTime = Date.now();
      
      await request(app)
        .get('/health')
        .expect(200);
      
      const duration = Date.now() - startTime;
      expect(duration).toBeLessThan(5000); // < 5 seconds
    });

    test('should be fast response (< 100ms for health check)', async () => {
      const startTime = Date.now();
      
      await request(app)
        .get('/health')
        .expect(200);
      
      const duration = Date.now() - startTime;
      expect(duration).toBeLessThan(100); // < 100ms for health check
    });
  });
});