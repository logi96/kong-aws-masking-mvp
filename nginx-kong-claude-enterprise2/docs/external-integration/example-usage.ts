/**
 * Kong AWS Masking 이벤트 구독 사용 예제
 * 외부 TypeScript 시스템에서 Kong 이벤트를 구독하는 방법
 */

import dotenv from 'dotenv';
import KongEventSubscriber from './KongEventSubscriber';
import { SubscriptionConfig, EventHandlers, KongMaskingEvent, KongSecurityAlert } from './kong-events.types';

// 환경 변수 로드
dotenv.config();

/**
 * 설정 생성
 */
const createConfig = (): SubscriptionConfig => ({
  redis: {
    host: process.env.KONG_REDIS_HOST || 'localhost',
    port: parseInt(process.env.KONG_REDIS_PORT || '6379'),
    password: process.env.KONG_REDIS_PASSWORD,
    db: parseInt(process.env.KONG_REDIS_DB || '0'),
    connectTimeout: parseInt(process.env.REDIS_CONNECT_TIMEOUT || '10000'),
    commandTimeout: parseInt(process.env.REDIS_COMMAND_TIMEOUT || '5000'),
    maxRetriesPerRequest: parseInt(process.env.REDIS_MAX_RETRIES || '3')
  },
  channels: {
    masking: process.env.ENABLE_MASKING_EVENTS === 'true',
    unmasking: process.env.ENABLE_UNMASKING_EVENTS === 'true',
    alerts: process.env.ENABLE_ALERT_EVENTS === 'true',
    metrics: process.env.ENABLE_METRICS_EVENTS === 'true'
  },
  processing: {
    bufferSize: parseInt(process.env.EVENT_BUFFER_SIZE || '1000'),
    batchSize: parseInt(process.env.BATCH_PROCESS_SIZE || '50'),
    intervalMs: parseInt(process.env.PROCESS_INTERVAL_MS || '1000')
  },
  logging: {
    level: (process.env.LOG_LEVEL as any) || 'info',
    file: process.env.LOG_FILE
  }
});

/**
 * 이벤트 핸들러 정의
 */
const createHandlers = (): EventHandlers => ({
  // 마스킹 이벤트 처리
  onMaskingEvent: async (event: KongMaskingEvent) => {
    console.log('🎯 Custom Masking Handler:', {
      requestId: event.request_id,
      success: event.success,
      patterns: event.total_patterns,
      time: event.processing_time_ms
    });

    // 마스킹 실패 알림
    if (!event.success || event.total_patterns === 0) {
      await sendSlackNotification(`🚨 Masking failure detected for request ${event.request_id}`);
    }

    // 성능 모니터링
    if (event.processing_time_ms > 3000) {
      await sendSlackNotification(`⚡ Slow masking detected: ${event.processing_time_ms}ms for request ${event.request_id}`);
    }

    // 데이터베이스에 저장 (예시)
    await saveMaskingEventToDatabase(event);
  },

  // 보안 알림 처리
  onSecurityAlert: async (alert: KongSecurityAlert) => {
    console.log('🚨 Security Alert Handler:', {
      type: alert.alert_type,
      severity: alert.severity,
      message: alert.message
    });

    // 심각도에 따른 알림
    if (alert.severity === 'critical' || alert.severity === 'high') {
      await sendPagerDutyAlert(alert);
      await sendSlackNotification(`🔥 CRITICAL SECURITY ALERT: ${alert.message}`);
    }

    // 보안 이벤트 로그
    await logSecurityEvent(alert);
  },

  // 연결 성공 시
  onConnection: async () => {
    console.log('✅ Connected to Kong event system');
    await sendSlackNotification('📡 Kong event subscriber connected successfully');
  },

  // 연결 실패 시
  onError: async (error: Error, channel: string) => {
    console.error('❌ Kong event error:', error.message);
    await sendSlackNotification(`🚨 Kong event error on channel ${channel}: ${error.message}`);
  }
});

/**
 * Slack 알림 전송 (예시)
 */
async function sendSlackNotification(message: string): Promise<void> {
  const webhookUrl = process.env.SLACK_WEBHOOK_URL;
  if (!webhookUrl) return;

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: message,
        username: 'Kong Event Monitor',
        icon_emoji: ':shield:'
      })
    });

    if (!response.ok) {
      console.error('Failed to send Slack notification:', response.status);
    }
  } catch (error) {
    console.error('Error sending Slack notification:', error);
  }
}

/**
 * PagerDuty 알림 전송 (예시)
 */
async function sendPagerDutyAlert(alert: KongSecurityAlert): Promise<void> {
  // PagerDuty API 연동 로직
  console.log('📟 PagerDuty alert would be sent:', alert.alert_id);
}

/**
 * 마스킹 이벤트 데이터베이스 저장 (예시)
 */
async function saveMaskingEventToDatabase(event: KongMaskingEvent): Promise<void> {
  // 데이터베이스 저장 로직
  console.log('💾 Saving masking event to database:', event.event_id);
}

/**
 * 보안 이벤트 로깅 (예시)
 */
async function logSecurityEvent(alert: KongSecurityAlert): Promise<void> {
  // 보안 로그 시스템에 기록
  console.log('📝 Logging security event:', alert.alert_id);
}

/**
 * 메인 함수
 */
async function main(): Promise<void> {
  const config = createConfig();
  const handlers = createHandlers();
  
  console.log('🚀 Starting Kong Event Subscriber...');
  console.log('📋 Configuration:', {
    redis: {
      host: config.redis.host,
      port: config.redis.port,
      db: config.redis.db
    },
    channels: config.channels
  });

  const subscriber = new KongEventSubscriber(config, handlers);

  // 이벤트 리스너 추가 (EventEmitter 방식)
  subscriber.on('masking', (event) => {
    console.log('📨 Received masking event via EventEmitter:', event.event_id);
  });

  subscriber.on('alert', (alert) => {
    console.log('🚨 Received alert via EventEmitter:', alert.alert_id);
  });

  try {
    // Kong Redis에 연결 및 구독 시작
    await subscriber.connect();

    console.log('✅ Kong Event Subscriber started successfully');
    console.log('📊 Statistics endpoint: http://localhost:3001/stats');
    console.log('🏥 Health check endpoint: http://localhost:3001/health');

    // 통계 정보 주기적 출력
    setInterval(() => {
      const stats = subscriber.getStats();
      console.log('📈 Stats:', stats);
    }, 30000); // 30초마다

    // 헬스체크 주기적 실행
    setInterval(async () => {
      const health = await subscriber.healthCheck();
      if (health.status !== 'healthy') {
        console.warn('⚠️ Health check failed:', health);
      }
    }, 60000); // 1분마다

  } catch (error) {
    console.error('❌ Failed to start Kong Event Subscriber:', error);
    process.exit(1);
  }

  // Graceful shutdown
  process.on('SIGTERM', async () => {
    console.log('🔄 Graceful shutdown initiated...');
    await subscriber.disconnect();
    process.exit(0);
  });

  process.on('SIGINT', async () => {
    console.log('🔄 Graceful shutdown initiated...');
    await subscriber.disconnect();
    process.exit(0);
  });
}

/**
 * Express 서버 추가 (선택사항)
 * 모니터링 및 헬스체크용 HTTP 엔드포인트 제공
 */
async function startHttpServer(subscriber: KongEventSubscriber): Promise<void> {
  const express = require('express');
  const app = express();
  const port = process.env.HEALTH_CHECK_PORT || 3001;

  app.get('/health', async (req: any, res: any) => {
    const health = await subscriber.healthCheck();
    res.status(health.status === 'healthy' ? 200 : 503).json(health);
  });

  app.get('/stats', (req: any, res: any) => {
    const stats = subscriber.getStats();
    res.json(stats);
  });

  app.listen(port, () => {
    console.log(`📡 Monitoring server running on port ${port}`);
  });
}

// 애플리케이션 시작
if (require.main === module) {
  main().catch(console.error);
}

export { main, createConfig, createHandlers };