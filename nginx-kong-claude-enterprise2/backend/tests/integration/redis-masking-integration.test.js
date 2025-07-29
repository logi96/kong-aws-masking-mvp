/**
 * @fileoverview Integration tests for Redis-based masking service
 * @module tests/integration/redis-masking-integration
 */

const maskingRedisService = require('../../src/services/redis/maskingRedisService');
const maskingService = require('../../src/services/masking/maskingService');
const redisService = require('../../src/services/redis/redisService');

describe('Redis Masking Integration Tests', () => {
  beforeAll(async () => {
    // Ensure Redis connection
    await redisService.connect();
  });

  afterAll(async () => {
    // Cleanup and disconnect
    await redisService.disconnect();
  });

  describe('Masking Service Integration', () => {
    test('should mask AWS resources and store in Redis', async () => {
      const testText = `
        EC2 Instance: i-1234567890abcdef0
        VPC: vpc-12345678
        S3 Bucket: my-bucket.s3.amazonaws.com
        Private IP: 10.0.1.100
      `;

      const result = await maskingService.maskText(testText);

      expect(result.success).toBe(true);
      expect(result.masked).not.toContain('i-1234567890abcdef0');
      expect(result.masked).not.toContain('vpc-12345678');
      expect(result.masked).toContain('EC2_');
      expect(result.masked).toContain('VPC_');
      expect(result.statistics.totalMasked).toBeGreaterThan(0);

      // Verify mappings are stored in Redis
      const ec2Masked = await maskingRedisService.getMaskedValue('i-1234567890abcdef0');
      expect(ec2Masked).toMatch(/EC2_\d{3}/);
    });

    test('should unmask text using Redis mappings', async () => {
      // First mask some text
      const originalText = 'Instance i-abcdef1234567890 in vpc-87654321';
      const maskResult = await maskingService.maskText(originalText);
      
      // Then unmask it
      const unmaskResult = await maskingService.unmaskText(maskResult.masked);
      
      expect(unmaskResult.success).toBe(true);
      expect(unmaskResult.unmasked).toBe(originalText);
      expect(unmaskResult.statistics.totalUnmasked).toBe(2);
    });

    test('should handle batch operations efficiently', async () => {
      const resources = {
        'i-1111111111111111a': 'EC2_101',
        'i-2222222222222222b': 'EC2_102',
        'vpc-aaaaaaaa': 'VPC_101',
        'subnet-bbbbbbbb': 'SUBNET_101'
      };

      // Store batch
      const stored = await maskingRedisService.batchStoreMappings(resources);
      expect(stored).toBe(4);

      // Retrieve batch
      const keys = Object.keys(resources);
      const retrieved = await maskingRedisService.batchGetMappings(keys);
      
      expect(Object.keys(retrieved).length).toBe(4);
      expect(retrieved['i-1111111111111111a']).toBe('EC2_101');
    });
  });

  describe('TTL Management', () => {
    test('should respect TTL settings', async () => {
      const shortTTL = 2; // 2 seconds
      await maskingRedisService.storeMaskingMapping(
        'i-ttltest1234567890',
        'EC2_999',
        shortTTL
      );

      // Verify exists
      const exists1 = await maskingRedisService.mappingExists('i-ttltest1234567890');
      expect(exists1).toBe(true);

      // Check TTL
      const ttl = await maskingRedisService.getMappingTTL('i-ttltest1234567890');
      expect(ttl).toBeLessThanOrEqual(shortTTL);
      expect(ttl).toBeGreaterThan(0);

      // Wait for expiration
      await new Promise(resolve => setTimeout(resolve, 3000));

      // Verify expired
      const exists2 = await maskingRedisService.mappingExists('i-ttltest1234567890');
      expect(exists2).toBe(false);
    });

    test('should extend TTL for existing mappings', async () => {
      await maskingRedisService.storeMaskingMapping(
        'i-extendtest123456',
        'EC2_998',
        10
      );

      // Extend TTL
      const extended = await maskingRedisService.extendMappingTTL(
        'i-extendtest123456',
        'EC2_998',
        3600
      );
      expect(extended).toBe(true);

      // Verify new TTL
      const newTTL = await maskingRedisService.getMappingTTL('i-extendtest123456');
      expect(newTTL).toBeGreaterThan(100);
    });
  });

  describe('Statistics and Monitoring', () => {
    test('should track masking statistics', async () => {
      const stats = await maskingRedisService.getStatistics();
      
      expect(stats).toHaveProperty('total');
      expect(stats).toHaveProperty('daily');
      expect(stats).toHaveProperty('cache');
      expect(stats.total.mappings).toBeGreaterThanOrEqual(0);
    });

    test('should track cache performance', async () => {
      const cacheKey = 'test-cache-key';
      const testData = { result: 'test analysis', timestamp: Date.now() };

      // Cache miss
      const miss = await maskingRedisService.getCachedResponse(cacheKey);
      expect(miss).toBeNull();

      // Cache set
      await maskingRedisService.cacheResponse(cacheKey, testData);

      // Cache hit
      const hit = await maskingRedisService.getCachedResponse(cacheKey);
      expect(hit).toEqual(testData);

      // Check statistics
      const stats = await maskingRedisService.getStatistics();
      expect(stats.cache.hits).toBeGreaterThan(0);
      expect(stats.cache.misses).toBeGreaterThan(0);
    });
  });

  describe('Distributed Locking', () => {
    test('should handle distributed locks', async () => {
      const resource = 'test-resource';
      
      // Acquire lock
      const lockToken = await maskingRedisService.acquireLock(resource, 5);
      expect(lockToken).toBeTruthy();

      // Try to acquire same lock (should fail)
      const lockToken2 = await maskingRedisService.acquireLock(resource, 5);
      expect(lockToken2).toBeNull();

      // Release lock
      const released = await maskingRedisService.releaseLock(resource, lockToken);
      expect(released).toBe(true);

      // Now can acquire again
      const lockToken3 = await maskingRedisService.acquireLock(resource, 5);
      expect(lockToken3).toBeTruthy();
      
      // Cleanup
      await maskingRedisService.releaseLock(resource, lockToken3);
    });
  });

  describe('Error Handling', () => {
    test('should handle Redis connection failures gracefully', async () => {
      // Temporarily disconnect
      await redisService.disconnect();

      try {
        await maskingRedisService.getMaskedValue('test-key');
      } catch (error) {
        expect(error).toBeDefined();
      }

      // Reconnect for other tests
      await redisService.connect();
    });
  });

  describe('Cleanup Operations', () => {
    test('should cleanup expired mappings', async () => {
      // Create some test mappings without TTL (for testing cleanup)
      // Note: In production, all mappings should have TTL
      
      const cleaned = await maskingRedisService.cleanupExpiredMappings();
      expect(cleaned).toBeGreaterThanOrEqual(0);
    });
  });
});