/**
 * @fileoverview /analyze 엔드포인트 TDD 테스트
 * @description TDD Red-Green-Refactor 전략 적용
 */

const request = require('supertest');
const app = require('../../src/app');

describe('POST /analyze', () => {
  describe('🔴 RED: 실패하는 테스트 (TDD 1단계)', () => {
    test('should respond with 404 for non-existent route initially', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 's3'],
          options: {
            analysisType: 'security_and_optimization'
          }
        });

      expect(response.status).toBe(404);
    });

    test('should handle AWS resource analysis request', async () => {
      const requestPayload = {
        resources: ['ec2', 's3'],
        options: {
          analysisType: 'security_and_optimization',
          region: 'us-east-1'
        }
      };

      const response = await request(app)
        .post('/analyze')
        .send(requestPayload);

      // 최종 목표 응답 (현재는 실패할 것)
      expect(response.status).toBe(200);
      expect(response.body).toMatchObject({
        success: true,
        data: expect.objectContaining({
          awsResources: expect.any(Object),
          analysis: expect.any(Object)
        }),
        timestamp: expect.any(String),
        duration: expect.any(Number)
      });

      // Performance requirement: < 5s
      expect(response.body.duration).toBeLessThan(5000);
    });

    test('should validate request payload', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({});

      expect(response.status).toBe(400);
      expect(response.body).toMatchObject({
        success: false,
        error: expect.any(String)
      });
    });

    test('should handle invalid resource types', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['invalid-resource'],
          options: {}
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });

    test('should handle AWS CLI errors gracefully', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2'],
          options: {
            region: 'invalid-region'
          }
        });

      expect(response.status).toBe(500);
      expect(response.body).toMatchObject({
        success: false,
        error: expect.any(String)
      });
    });

    test('should enforce 5-second timeout', async () => {
      const startTime = Date.now();
      
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2', 's3', 'rds', 'vpc'],
          options: {
            timeout: 6000 // Try to exceed limit
          }
        });

      const duration = Date.now() - startTime;
      
      // Should complete within 5 seconds or return timeout error
      expect(duration).toBeLessThan(6000);
      
      if (response.status === 500) {
        expect(response.body.error).toMatch(/timeout/i);
      } else {
        expect(response.body.duration).toBeLessThan(5000);
      }
    });

    test('should return proper response format with all required fields', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2'],
          options: {}
        });

      if (response.status === 200) {
        expect(response.body).toHaveProperty('success');
        expect(response.body).toHaveProperty('data');
        expect(response.body).toHaveProperty('timestamp');
        expect(response.body).toHaveProperty('duration');
        
        expect(response.body.data).toHaveProperty('awsResources');
        expect(response.body.data).toHaveProperty('analysis');
      }
    });

    test('should handle Claude API integration errors', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          resources: ['ec2'],
          options: {
            analysisType: 'security_only'
          }
        });

      // Should handle Claude API errors gracefully
      if (response.status === 500) {
        expect(response.body).toMatchObject({
          success: false,
          error: expect.stringMatching(/claude|api/i)
        });
      }
    });
  });

  describe('Request Validation', () => {
    test('should require resources array', async () => {
      const response = await request(app)
        .post('/analyze')
        .send({
          options: {}
        });

      expect(response.status).toBe(400);
    });

    test('should validate supported resource types', async () => {
      const supportedResources = ['ec2', 's3', 'rds', 'vpc', 'iam'];
      
      for (const resource of supportedResources) {
        const response = await request(app)
          .post('/analyze')
          .send({
            resources: [resource],
            options: {}
          });

        expect([200, 500]).toContain(response.status); // Either success or server error (not validation error)
      }
    });

    test('should validate analysis type options', async () => {
      const validTypes = ['security_and_optimization', 'security_only', 'cost_only'];
      
      for (const type of validTypes) {
        const response = await request(app)
          .post('/analyze')
          .send({
            resources: ['ec2'],
            options: {
              analysisType: type
            }
          });

        expect([200, 500]).toContain(response.status);
      }
    });
  });
});