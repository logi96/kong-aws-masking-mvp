/**
 * @fileoverview Unit tests for health check endpoints
 * @module tests/unit/health
 */

const request = require('supertest');
const app = require('../../src/app');
const healthCheckService = require('../../src/services/health/healthCheckService');

// Mock the health check service
jest.mock('../../src/services/health/healthCheckService');

describe('Health Check Routes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('should return basic health status', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'healthy',
        service: {
          name: 'nginx-kong-claude-enterprise2-backend',
          version: '1.0.0'
        }
      });
      expect(response.body.timestamp).toBeDefined();
      expect(response.body.uptime).toBeGreaterThan(0);
    });
  });

  describe('GET /health/detailed', () => {
    it('should return detailed health status when all services are healthy', async () => {
      const mockDetailedHealth = {
        dependencies: [
          { name: 'kong', status: 'healthy', responseTime: 50 },
          { name: 'redis', status: 'healthy', responseTime: 10 },
          { name: 'claude', status: 'healthy', responseTime: 200 }
        ],
        system: {
          hostname: 'test-host',
          memory: { usagePercent: '45.00' }
        },
        process: {
          pid: 12345,
          uptime: 3600
        }
      };

      healthCheckService.getDetailedHealth.mockResolvedValue(mockDetailedHealth);

      const response = await request(app)
        .get('/health/detailed')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'healthy',
        dependencies: mockDetailedHealth.dependencies
      });
    });

    it('should return degraded status when some services are unhealthy', async () => {
      const mockDetailedHealth = {
        dependencies: [
          { name: 'kong', status: 'healthy', responseTime: 50 },
          { name: 'redis', status: 'unhealthy', error: 'Connection failed' },
          { name: 'claude', status: 'healthy', responseTime: 200 }
        ]
      };

      healthCheckService.getDetailedHealth.mockResolvedValue(mockDetailedHealth);

      const response = await request(app)
        .get('/health/detailed')
        .expect(503);

      expect(response.body.status).toBe('degraded');
    });

    it('should handle errors gracefully', async () => {
      healthCheckService.getDetailedHealth.mockRejectedValue(new Error('Service error'));

      const response = await request(app)
        .get('/health/detailed')
        .expect(503);

      expect(response.body).toMatchObject({
        status: 'unhealthy',
        error: 'Service error'
      });
    });
  });

  describe('GET /health/live', () => {
    it('should return ok for liveness probe', async () => {
      const response = await request(app)
        .get('/health/live')
        .expect(200);

      expect(response.body).toEqual({ status: 'ok' });
    });
  });

  describe('GET /health/ready', () => {
    it('should return ready when all critical services are available', async () => {
      healthCheckService.checkReadiness.mockResolvedValue(true);

      const response = await request(app)
        .get('/health/ready')
        .expect(200);

      expect(response.body).toEqual({ status: 'ready' });
    });

    it('should return not ready when critical services are unavailable', async () => {
      healthCheckService.checkReadiness.mockResolvedValue(false);

      const response = await request(app)
        .get('/health/ready')
        .expect(503);

      expect(response.body).toEqual({ status: 'not ready' });
    });
  });

  describe('GET /health/dependencies/:name', () => {
    it('should return health status for Kong', async () => {
      const mockKongHealth = {
        name: 'kong',
        status: 'healthy',
        responseTime: 45,
        details: {
          admin: { status: 'healthy' },
          proxy: { status: 'healthy' }
        }
      };

      healthCheckService.checkDependency.mockResolvedValue(mockKongHealth);

      const response = await request(app)
        .get('/health/dependencies/kong')
        .expect(200);

      expect(response.body).toEqual(mockKongHealth);
      expect(healthCheckService.checkDependency).toHaveBeenCalledWith('kong');
    });

    it('should return health status for Redis', async () => {
      const mockRedisHealth = {
        name: 'redis',
        status: 'healthy',
        responseTime: 12,
        details: {
          ping: 'PONG',
          version: '7.0.5'
        }
      };

      healthCheckService.checkDependency.mockResolvedValue(mockRedisHealth);

      const response = await request(app)
        .get('/health/dependencies/redis')
        .expect(200);

      expect(response.body).toEqual(mockRedisHealth);
    });

    it('should return error for invalid dependency name', async () => {
      const response = await request(app)
        .get('/health/dependencies/invalid')
        .expect(400);

      expect(response.body).toMatchObject({
        error: 'Invalid dependency name',
        validDependencies: ['kong', 'redis', 'claude']
      });
    });

    it('should handle dependency check errors', async () => {
      healthCheckService.checkDependency.mockRejectedValue(new Error('Check failed'));

      const response = await request(app)
        .get('/health/dependencies/kong')
        .expect(503);

      expect(response.body).toMatchObject({
        name: 'kong',
        status: 'unhealthy',
        error: 'Check failed'
      });
    });
  });

  describe('GET /health/metrics', () => {
    it('should return service metrics', async () => {
      const mockMetrics = {
        memory: {
          rss: 123456789,
          heapTotal: 98765432,
          heapUsed: 87654321
        },
        cpu: {
          user: 1234567,
          system: 765432
        },
        process: {
          uptime: 3600,
          pid: 12345
        }
      };

      healthCheckService.getMetrics.mockResolvedValue(mockMetrics);

      const response = await request(app)
        .get('/health/metrics')
        .expect(200);

      expect(response.body).toEqual(mockMetrics);
    });

    it('should handle metrics collection errors', async () => {
      healthCheckService.getMetrics.mockRejectedValue(new Error('Metrics error'));

      const response = await request(app)
        .get('/health/metrics')
        .expect(500);

      expect(response.body).toMatchObject({
        error: 'Failed to collect metrics',
        message: 'Metrics error'
      });
    });
  });
});