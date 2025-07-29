/**
 * @fileoverview Unit tests for Redis service
 * @module tests/unit/redisService
 */

const Redis = require('ioredis');
const logger = require('../../src/utils/logger');

// Mock dependencies first
jest.mock('ioredis');
jest.mock('../../src/utils/logger');

// Now require the service after mocks are set up
const redisService = require('../../src/services/redis/redisService');

describe('Redis Service', () => {
  let mockRedisClient;

  beforeEach(() => {
    jest.clearAllMocks();
    
    // Create mock Redis client
    mockRedisClient = {
      on: jest.fn(),
      ping: jest.fn().mockResolvedValue('PONG'),
      get: jest.fn(),
      set: jest.fn().mockResolvedValue('OK'),
      setex: jest.fn().mockResolvedValue('OK'),
      del: jest.fn().mockResolvedValue(1),
      exists: jest.fn(),
      expire: jest.fn().mockResolvedValue(1),
      ttl: jest.fn(),
      mget: jest.fn(),
      mset: jest.fn().mockResolvedValue('OK'),
      scan: jest.fn(),
      quit: jest.fn().mockResolvedValue('OK'),
      multi: jest.fn().mockReturnThis(),
      exec: jest.fn().mockResolvedValue([['OK'], ['OK']]),
      pipeline: jest.fn().mockReturnThis()
    };

    Redis.mockImplementation(() => mockRedisClient);
    
    // Reset the service state
    redisService.client = null;
    redisService.isConnected = false;
  });

  describe('Connection Management', () => {
    it('should connect successfully', async () => {
      await redisService.connect();

      expect(Redis).toHaveBeenCalledWith(
        expect.objectContaining({
          host: 'redis',
          port: 6379,
          maxRetriesPerRequest: 3,
          enableReadyCheck: true,
          enableOfflineQueue: false
        })
      );

      expect(mockRedisClient.on).toHaveBeenCalledWith('connect', expect.any(Function));
      expect(mockRedisClient.on).toHaveBeenCalledWith('error', expect.any(Function));
    });

    it('should not reconnect if already connected', async () => {
      redisService.isConnected = true;
      redisService.client = mockRedisClient;
      
      await redisService.connect();
      
      expect(Redis).not.toHaveBeenCalled();
    });

    it('should handle connection events', async () => {
      await redisService.connect();
      
      // Simulate connect event
      const connectHandler = mockRedisClient.on.mock.calls.find(
        call => call[0] === 'connect'
      )[1];
      connectHandler();

      expect(logger.info).toHaveBeenCalledWith('Redis client connected');
      expect(redisService.isConnected).toBe(true);
    });

    it('should handle error events', async () => {
      await redisService.connect();
      
      const errorHandler = mockRedisClient.on.mock.calls.find(
        call => call[0] === 'error'
      )[1];
      
      const error = new Error('Connection failed');
      errorHandler(error);

      expect(logger.error).toHaveBeenCalledWith('Redis client error:', error);
    });

    it('should disconnect gracefully', async () => {
      await redisService.connect();
      redisService.isConnected = true;
      
      await redisService.disconnect();

      expect(mockRedisClient.quit).toHaveBeenCalled();
      expect(redisService.isConnected).toBe(false);
    });
  });

  describe('Basic Operations', () => {
    beforeEach(async () => {
      await redisService.connect();
      redisService.isConnected = true;
    });

    it('should set value successfully', async () => {
      await redisService.set('key1', 'value1');

      expect(mockRedisClient.set).toHaveBeenCalledWith('key1', 'value1');
    });

    it('should set value with TTL', async () => {
      await redisService.setWithTTL('key1', 'value1', 3600);

      expect(mockRedisClient.setex).toHaveBeenCalledWith('key1', 3600, 'value1');
    });

    it('should get value successfully', async () => {
      mockRedisClient.get.mockResolvedValue('value1');

      const result = await redisService.get('key1');

      expect(result).toBe('value1');
      expect(mockRedisClient.get).toHaveBeenCalledWith('key1');
    });

    it('should handle operations when not connected', async () => {
      redisService.isConnected = false;

      await expect(redisService.get('key1')).rejects.toThrow('Redis not connected');
    });
  });

  describe('Masking Operations', () => {
    beforeEach(async () => {
      await redisService.connect();
      redisService.isConnected = true;
    });

    it('should store masking mapping', async () => {
      const mapping = {
        masked: 'EC2_001',
        original: 'i-1234567890abcdef0',
        type: 'ec2_instance'
      };

      await redisService.storeMaskingMapping('EC2_001', mapping);

      expect(mockRedisClient.setex).toHaveBeenCalledWith(
        'mask:EC2_001',
        604800,
        JSON.stringify(mapping)
      );
    });

    it('should retrieve masking mapping', async () => {
      const mapping = {
        masked: 'EC2_001',
        original: 'i-1234567890abcdef0'
      };
      
      mockRedisClient.get.mockResolvedValue(JSON.stringify(mapping));

      const result = await redisService.getMaskingMapping('EC2_001');

      expect(result).toEqual(mapping);
      expect(mockRedisClient.get).toHaveBeenCalledWith('mask:EC2_001');
    });

    it('should handle JSON parse errors', async () => {
      mockRedisClient.get.mockResolvedValue('invalid json');

      await expect(redisService.getMaskingMapping('EC2_001')).rejects.toThrow();
    });
  });

  describe('Health Check', () => {
    it('should report healthy when connected', async () => {
      await redisService.connect();
      redisService.isConnected = true;

      const health = await redisService.healthCheck();

      expect(health).toMatchObject({
        status: 'healthy',
        connected: true,
        ping: 'PONG'
      });
    });

    it('should report unhealthy when not connected', async () => {
      const health = await redisService.healthCheck();

      expect(health).toMatchObject({
        status: 'unhealthy',
        connected: false,
        error: expect.any(String)
      });
    });

    it('should handle ping errors', async () => {
      await redisService.connect();
      redisService.isConnected = true;
      mockRedisClient.ping.mockRejectedValue(new Error('Ping failed'));

      const health = await redisService.healthCheck();

      expect(health.status).toBe('unhealthy');
      expect(health.error).toContain('Ping failed');
    });
  });
});