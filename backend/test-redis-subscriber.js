#!/usr/bin/env node
/**
 * RedisEventSubscriber 테스트 스크립트
 * Kong 이벤트 수신 기능 검증
 */

const path = require('path');
const RedisEventSubscriber = require('./src/services/redis/RedisEventSubscriber');

async function testRedisSubscriber() {
  console.log('=== RedisEventSubscriber 테스트 시작 ===');
  
  // 환경변수 설정 (테스트용)
  process.env.ENABLE_REDIS_EVENTS = 'true';
  process.env.NODE_ENV = 'development';
  process.env.LOG_LEVEL = 'info';
  
  const subscriber = new RedisEventSubscriber({
    redis: {
      // 테스트용 설정
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 2
    }
  });
  
  try {
    console.log('1. RedisEventSubscriber 시작...');
    await subscriber.start();
    
    console.log('2. 30초 동안 Kong 이벤트 수신 대기...');
    console.log('   Kong에서 AWS 리소스 요청을 보내면 이벤트가 출력됩니다.');
    console.log('   예: curl -X POST http://localhost:8000/analyze-claude ...');
    
    // 30초 후 통계 출력
    setTimeout(() => {
      console.log('\\n3. 수신 통계:');
      const stats = subscriber.getStats();
      console.log(JSON.stringify(stats, null, 2));
      
      console.log('\\n4. RedisEventSubscriber 종료...');
      subscriber.stop().then(() => {
        console.log('✅ 테스트 완료');
        process.exit(0);
      });
    }, 30000);
    
    // Graceful shutdown
    process.on('SIGINT', async () => {
      console.log('\\n신호 수신 - RedisEventSubscriber 종료 중...');
      await subscriber.stop();
      process.exit(0);
    });
    
  } catch (error) {
    console.error('❌ RedisEventSubscriber 테스트 실패:', error);
    process.exit(1);
  }
}

// 메인 실행
if (require.main === module) {
  testRedisSubscriber().catch(console.error);
}

module.exports = { testRedisSubscriber };