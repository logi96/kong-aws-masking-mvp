#!/usr/bin/env node
/**
 * Redis 연결 테스트 스크립트
 * RedisEventSubscriber 구현 전 전제 조건 검증
 */

const Redis = require('ioredis');

async function testRedisConnection() {
  console.log('=== Redis 연결 테스트 시작 ===');
  
  // 환경변수 확인
  const config = {
    host: process.env.REDIS_HOST || 'redis',
    port: parseInt(process.env.REDIS_PORT) || 6379,
    password: process.env.REDIS_PASSWORD || 'CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL',
    db: parseInt(process.env.REDIS_DB) || 0,
    retryDelayOnFailover: 100,
    maxRetriesPerRequest: 3,
    lazyConnect: true
  };
  
  console.log('Redis 설정:', {
    host: config.host,
    port: config.port,
    db: config.db,
    password: config.password ? '***' : 'none'
  });
  
  const redis = new Redis(config);
  
  try {
    // 연결 테스트
    console.log('\n1. 기본 연결 테스트...');
    await redis.connect();
    console.log('✅ Redis 연결 성공');
    
    // Ping 테스트
    console.log('\n2. Ping 테스트...');
    const pong = await redis.ping();
    console.log('✅ Ping 응답:', pong);
    
    // Set/Get 테스트
    console.log('\n3. Set/Get 테스트...');
    const testKey = 'test:redis:connection';
    await redis.set(testKey, 'backend-connection-test');
    const value = await redis.get(testKey);
    console.log('✅ Set/Get 성공:', value);
    
    // Pub/Sub 테스트 (가장 중요)
    console.log('\n4. Pub/Sub 기능 테스트...');
    const subscriber = new Redis(config);
    const publisher = new Redis(config);
    
    let messageReceived = false;
    
    // 구독자 설정
    subscriber.psubscribe('test:*');
    subscriber.on('pmessage', (pattern, channel, message) => {
      console.log('✅ Pub/Sub 메시지 수신:', { pattern, channel, message });
      messageReceived = true;
    });
    
    // 1초 후 메시지 발행
    setTimeout(async () => {
      await publisher.publish('test:pubsub', 'Hello from Backend!');
      console.log('📤 테스트 메시지 발행됨');
    }, 1000);
    
    // 결과 확인
    setTimeout(async () => {
      if (messageReceived) {
        console.log('✅ Pub/Sub 테스트 성공');
      } else {
        console.log('❌ Pub/Sub 테스트 실패 - 메시지 수신되지 않음');
      }
      
      // 정리
      await subscriber.disconnect();
      await publisher.disconnect();
      await redis.disconnect();
      
      console.log('\n=== Redis 연결 테스트 완료 ===');
      console.log(messageReceived ? '🎉 모든 테스트 통과 - RedisEventSubscriber 구현 가능' : '❌ Pub/Sub 문제 - 수정 필요');
    }, 3000);
    
  } catch (error) {
    console.error('❌ Redis 연결 실패:', error.message);
    process.exit(1);
  }
}

// 메인 실행
if (require.main === module) {
  testRedisConnection().catch(console.error);
}

module.exports = { testRedisConnection };