/**
 * Kong AWS Masking 이벤트 구독 클라이언트
 * 외부 TypeScript 시스템에서 Kong 마스킹 이벤트를 실시간으로 구독
 */

import Redis from 'ioredis';
import { EventEmitter } from 'events';
import winston from 'winston';
import {
  KongMaskingEvent,
  KongUnmaskingEvent,
  KongSecurityAlert,
  KongMetricsEvent,
  KONG_CHANNELS,
  SubscriptionConfig,
  EventHandlers
} from './kong-events.types';

export class KongEventSubscriber extends EventEmitter {
  private redis: Redis | null = null;
  private subscriber: Redis | null = null;
  private logger: winston.Logger;
  private config: SubscriptionConfig;
  private handlers: EventHandlers;
  private isConnected: boolean = false;
  private eventBuffer: any[] = [];
  private stats = {
    totalEvents: 0,
    maskingEvents: 0,
    unmaskingEvents: 0,
    alerts: 0,
    errors: 0,
    startTime: Date.now()
  };

  constructor(config: SubscriptionConfig, handlers: EventHandlers = {}) {
    super();
    this.config = config;
    this.handlers = handlers;
    this.setupLogger();
  }

  /**
   * 로거 설정
   */
  private setupLogger(): void {
    const transports: winston.transport[] = [
      new winston.transports.Console({
        format: winston.format.combine(
          winston.format.colorize(),
          winston.format.timestamp(),
          winston.format.printf(({ timestamp, level, message, ...meta }) => {
            return `${timestamp} [${level}] Kong-Event-Subscriber: ${message} ${
              Object.keys(meta).length ? JSON.stringify(meta) : ''
            }`;
          })
        )
      })
    ];

    if (this.config.logging.file) {
      transports.push(
        new winston.transports.File({
          filename: this.config.logging.file,
          format: winston.format.combine(
            winston.format.timestamp(),
            winston.format.json()
          )
        })
      );
    }

    this.logger = winston.createLogger({
      level: this.config.logging.level,
      transports
    });
  }

  /**
   * Kong Redis에 연결 및 구독 시작
   */
  async connect(): Promise<void> {
    try {
      this.logger.info('🔌 Connecting to Kong Redis...', {
        host: this.config.redis.host,
        port: this.config.redis.port,
        db: this.config.redis.db
      });

      // Redis 클라이언트 생성
      this.redis = new Redis({
        host: this.config.redis.host,
        port: this.config.redis.port,
        password: this.config.redis.password,
        db: this.config.redis.db || 0,
        connectTimeout: this.config.redis.connectTimeout || 10000,
        commandTimeout: this.config.redis.commandTimeout || 5000,
        maxRetriesPerRequest: this.config.redis.maxRetriesPerRequest || 3,
        retryStrategy: (times) => Math.min(times * 50, 2000)
      });

      // 구독 전용 클라이언트 생성
      this.subscriber = new Redis({
        host: this.config.redis.host,
        port: this.config.redis.port,
        password: this.config.redis.password,
        db: this.config.redis.db || 0,
        connectTimeout: this.config.redis.connectTimeout || 10000,
        commandTimeout: this.config.redis.commandTimeout || 5000
      });

      // 이벤트 핸들러 설정
      this.setupEventHandlers();

      // 채널 구독
      await this.subscribeToChannels();

      // 연결 테스트
      await this.redis.ping();
      this.isConnected = true;

      this.logger.info('✅ Successfully connected to Kong Redis and subscribed to channels');
      
      if (this.handlers.onConnection) {
        await this.handlers.onConnection();
      }

      // 배치 처리 시작
      this.startBatchProcessing();

    } catch (error) {
      this.logger.error('❌ Failed to connect to Kong Redis:', error);
      throw error;
    }
  }

  /**
   * Redis 이벤트 핸들러 설정
   */
  private setupEventHandlers(): void {
    if (!this.subscriber) return;

    this.subscriber.on('error', (error) => {
      this.logger.error('Redis subscriber error:', error);
      this.stats.errors++;
      if (this.handlers.onError) {
        this.handlers.onError(error, 'subscriber');
      }
    });

    this.subscriber.on('close', () => {
      this.logger.warn('Redis subscriber connection closed');
      this.isConnected = false;
      if (this.handlers.onDisconnection) {
        this.handlers.onDisconnection();
      }
    });

    this.subscriber.on('reconnecting', () => {
      this.logger.info('Redis subscriber reconnecting...');
    });

    // 메시지 수신 핸들러
    this.subscriber.on('message', (channel: string, message: string) => {
      this.handleMessage(channel, message);
    });
  }

  /**
   * 채널 구독
   */
  private async subscribeToChannels(): Promise<void> {
    if (!this.subscriber) throw new Error('Subscriber not initialized');

    const channelsToSubscribe: string[] = [];

    if (this.config.channels.masking) {
      channelsToSubscribe.push(KONG_CHANNELS.MASKING);
    }
    if (this.config.channels.unmasking) {
      channelsToSubscribe.push(KONG_CHANNELS.UNMASKING);
    }
    if (this.config.channels.alerts) {
      channelsToSubscribe.push(KONG_CHANNELS.ALERTS);
    }
    if (this.config.channels.metrics) {
      channelsToSubscribe.push(KONG_CHANNELS.METRICS);
    }

    if (channelsToSubscribe.length === 0) {
      throw new Error('No channels configured for subscription');
    }

    await this.subscriber.subscribe(...channelsToSubscribe);
    
    this.logger.info('📡 Subscribed to Kong channels:', {
      channels: channelsToSubscribe,
      count: channelsToSubscribe.length
    });
  }

  /**
   * 메시지 처리
   */
  private handleMessage(channel: string, message: string): void {
    try {
      this.stats.totalEvents++;
      
      // 버퍼에 추가
      this.eventBuffer.push({
        channel,
        message,
        timestamp: Date.now()
      });

      // 버퍼 크기 제한
      if (this.eventBuffer.length > this.config.processing.bufferSize) {
        this.eventBuffer = this.eventBuffer.slice(-this.config.processing.bufferSize);
        this.logger.warn('Event buffer overflow, dropping old events');
      }

      this.logger.debug('📥 Received message from channel:', {
        channel,
        messageLength: message.length,
        bufferSize: this.eventBuffer.length
      });

    } catch (error) {
      this.logger.error('Error handling message:', error);
      this.stats.errors++;
    }
  }

  /**
   * 배치 이벤트 처리
   */
  private startBatchProcessing(): void {
    setInterval(() => {
      this.processBatchEvents();
    }, this.config.processing.intervalMs);
  }

  /**
   * 배치로 이벤트 처리
   */
  private async processBatchEvents(): Promise<void> {
    if (this.eventBuffer.length === 0) return;

    const batch = this.eventBuffer.splice(0, this.config.processing.batchSize);
    
    for (const item of batch) {
      try {
        await this.processEvent(item.channel, item.message);
      } catch (error) {
        this.logger.error('Error processing event:', error);
        this.stats.errors++;
      }
    }
  }

  /**
   * 개별 이벤트 처리
   */
  private async processEvent(channel: string, message: string): Promise<void> {
    try {
      const event = JSON.parse(message);

      switch (channel) {
        case KONG_CHANNELS.MASKING:
          await this.handleMaskingEvent(event as KongMaskingEvent);
          this.stats.maskingEvents++;
          break;

        case KONG_CHANNELS.UNMASKING:
          await this.handleUnmaskingEvent(event as KongUnmaskingEvent);
          this.stats.unmaskingEvents++;
          break;

        case KONG_CHANNELS.ALERTS:
          await this.handleSecurityAlert(event as KongSecurityAlert);
          this.stats.alerts++;
          break;

        case KONG_CHANNELS.METRICS:
          await this.handleMetricsEvent(event as KongMetricsEvent);
          break;

        default:
          this.logger.warn('Unknown channel:', channel);
      }

    } catch (error) {
      this.logger.error('Error parsing event JSON:', error);
      this.stats.errors++;
    }
  }

  /**
   * 마스킹 이벤트 처리
   */
  private async handleMaskingEvent(event: KongMaskingEvent): Promise<void> {
    this.logger.info('🎯 Masking Event:', {
      eventId: event.event_id,
      requestId: event.request_id,
      success: event.success,
      patternsApplied: event.total_patterns,
      processingTime: `${event.processing_time_ms}ms`,
      requestSize: event.request_size_bytes
    });

    // 마스킹 실패 검증
    if (event.total_patterns === 0 && event.demo_data?.original_text) {
      const hasAwsPatterns = this.detectAwsPatterns(event.demo_data.original_text);
      if (hasAwsPatterns) {
        this.logger.warn('🚨 MASKING FAILURE DETECTED:', {
          requestId: event.request_id,
          reason: 'AWS resources found but no masking applied'
        });
      }
    }

    // 성능 체크
    if (event.processing_time_ms > 5000) {
      this.logger.warn('⚡ SLOW MASKING:', {
        requestId: event.request_id,
        processingTime: `${event.processing_time_ms}ms`
      });
    }

    // 사용자 정의 핸들러 호출
    if (this.handlers.onMaskingEvent) {
      await this.handlers.onMaskingEvent(event);
    }

    this.emit('masking', event);
  }

  /**
   * 언마스킹 이벤트 처리
   */
  private async handleUnmaskingEvent(event: KongUnmaskingEvent): Promise<void> {
    this.logger.info('🔓 Unmasking Event:', {
      eventId: event.event_id,
      requestId: event.request_id,
      patternsRestored: event.patterns_restored,
      processingTime: `${event.processing_time_ms}ms`
    });

    if (this.handlers.onUnmaskingEvent) {
      await this.handlers.onUnmaskingEvent(event);
    }

    this.emit('unmasking', event);
  }

  /**
   * 보안 알림 처리
   */
  private async handleSecurityAlert(alert: KongSecurityAlert): Promise<void> {
    this.logger.error('🚨 SECURITY ALERT:', {
      alertId: alert.alert_id,
      type: alert.alert_type,
      severity: alert.severity,
      message: alert.message
    });

    if (this.handlers.onSecurityAlert) {
      await this.handlers.onSecurityAlert(alert);
    }

    this.emit('alert', alert);
  }

  /**
   * 메트릭 이벤트 처리
   */
  private async handleMetricsEvent(metrics: KongMetricsEvent): Promise<void> {
    this.logger.debug('📊 Metrics Event:', {
      type: metrics.metric_type,
      value: metrics.value,
      unit: metrics.unit
    });

    if (this.handlers.onMetricsEvent) {
      await this.handlers.onMetricsEvent(metrics);
    }

    this.emit('metrics', metrics);
  }

  /**
   * AWS 패턴 감지
   */
  private detectAwsPatterns(text: string): boolean {
    const patterns = [
      /i-[0-9a-f]{17}/,  // EC2 instance
      /vpc-[0-9a-f]{8}/, // VPC
      /sg-[0-9a-f]{8}/,  // Security group
      /10\.\d+\.\d+\.\d+/, // Private IP
      /arn:aws:/,        // ARN
    ];

    return patterns.some(pattern => pattern.test(text));
  }

  /**
   * 통계 정보 조회
   */
  getStats(): object {
    const uptime = Date.now() - this.stats.startTime;
    return {
      ...this.stats,
      uptime: `${Math.floor(uptime / 1000)}s`,
      eventsPerSecond: Math.round(this.stats.totalEvents / (uptime / 1000)),
      bufferSize: this.eventBuffer.length,
      isConnected: this.isConnected
    };
  }

  /**
   * 헬스체크
   */
  async healthCheck(): Promise<{ status: string; details: object }> {
    try {
      if (!this.redis) throw new Error('Redis not connected');
      
      await this.redis.ping();
      
      return {
        status: 'healthy',
        details: {
          connected: this.isConnected,
          stats: this.getStats()
        }
      };
    } catch (error) {
      return {
        status: 'unhealthy',
        details: {
          error: error instanceof Error ? error.message : 'Unknown error',
          stats: this.getStats()
        }
      };
    }
  }

  /**
   * 연결 종료
   */
  async disconnect(): Promise<void> {
    this.logger.info('🔌 Disconnecting from Kong Redis...');

    if (this.subscriber) {
      await this.subscriber.quit();
      this.subscriber = null;
    }

    if (this.redis) {
      await this.redis.quit();
      this.redis = null;
    }

    this.isConnected = false;
    this.logger.info('✅ Disconnected from Kong Redis');
  }
}

export default KongEventSubscriber;