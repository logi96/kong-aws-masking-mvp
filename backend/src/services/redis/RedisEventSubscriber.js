/**
 * Redis Event Subscriber for Kong AWS Masker Real-time Monitoring
 * 실시간 모니터링을 위한 Redis Pub/Sub 이벤트 구독자
 * 
 * Features:
 * - Winston 로거 통합
 * - 레이트 리미팅 (로그 폭증 방지)
 * - 배치 이벤트 처리
 * - 환경별 로깅 차별화
 * - 자동 재연결 전략
 * - 통계 수집
 */

const Redis = require('ioredis');
const logger = require('../../../utils/logger');

class RedisEventSubscriber {
  constructor(options = {}) {
    // 환경 설정
    this.enabled = process.env.ENABLE_REDIS_EVENTS === 'true';
    this.nodeEnv = process.env.NODE_ENV || 'development';
    
    // Redis 설정
    this.redisConfig = {
      host: process.env.REDIS_HOST || 'redis',
      port: parseInt(process.env.REDIS_PORT) || 6379,
      password: process.env.REDIS_PASSWORD || '',
      db: parseInt(process.env.REDIS_DB) || 0,
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 3,
      lazyConnect: true,
      enableOfflineQueue: false,
      ...options.redis
    };
    
    // 레이트 리미팅 설정
    this.logRateLimit = parseInt(process.env.EVENT_LOG_RATE_LIMIT) || 100;
    this.eventCount = 0;
    this.lastLogTime = Date.now();
    this.resetInterval = 60000; // 1분마다 리셋
    
    // 배치 처리 설정
    this.batchSize = parseInt(process.env.EVENT_BATCH_SIZE) || 10;
    this.batchTimeout = parseInt(process.env.EVENT_BATCH_TIMEOUT) || 5000;
    this.eventBatch = [];
    this.batchTimer = null;
    
    // 통계 수집
    this.stats = {
      totalEvents: 0,
      maskingEvents: 0,
      unmaskingEvents: 0,
      securityAlerts: 0,
      performanceMetrics: 0,
      connectionErrors: 0,
      lastEventTime: null,
      startTime: Date.now()
    };
    
    // 최근 마스킹 로그 저장 (API 제공용)
    this.recentMaskingLogs = [];
    this.maxLogHistory = 100; // 최근 100개 로그만 유지
    
    // 구독 채널 패턴
    this.channels = {
      MASKING: 'aws-masker:events:masking',
      UNMASKING: 'aws-masker:events:unmasking', 
      ALERTS: 'aws-masker:alerts:security',
      METRICS: 'aws-masker:metrics:performance'
    };
    
    // Redis 클라이언트
    this.subscriber = null;
    this.connectionState = 'disconnected'; // 'disconnected', 'connecting', 'connected', 'error'
    this.reconnectTimer = null;
    this.rateLimitTimer = null;
    
    // 재연결 관리
    this.maxReconnectAttempts = parseInt(process.env.REDIS_MAX_RECONNECT_ATTEMPTS) || 10;
    this.currentReconnectAttempts = 0;
    this.reconnectDelay = 5000; // 5초
    this.maxReconnectDelay = 60000; // 최대 1분
    
    // 기존 Logger 사용 (service context 추가)
    this.logger = logger.child({ service: 'redis-event-subscriber' });
    
    // 레이트 리미터 타이머 시작
    this.startRateLimitReset();
  }
  
  /**
   * 기존 Redis 연결 정리 (중복 연결 방지)
   */
  async cleanupExistingConnection() {
    if (this.subscriber) {
      try {
        this.logger.debug('Cleaning up existing Redis connection...');
        
        // 이벤트 리스너 제거 (메모리 리크 방지)
        this.subscriber.removeAllListeners();
        
        // 연결 해제
        await this.subscriber.disconnect();
        
        this.logger.debug('Existing Redis connection cleaned up');
      } catch (error) {
        this.logger.warn('Error cleaning up existing Redis connection:', error);
      } finally {
        this.subscriber = null;
        this.connectionState = 'disconnected';
      }
    }
  }
  
  /**
   * Redis 이벤트 구독 시작
   * 재연결 전략 포함
   */
  async start() {
    if (!this.enabled) {
      this.logger.info('Redis event subscription is disabled');
      return;
    }
    
    try {
      this.logger.info('Starting Redis event subscriber...', {
        host: this.redisConfig.host,
        port: this.redisConfig.port,
        db: this.redisConfig.db
      });
      
      // 연결 상태 업데이트
      this.connectionState = 'connecting';
      
      // 기존 연결 정리 (중복 연결 방지)
      await this.cleanupExistingConnection();
      
      // Redis 구독자 생성
      this.subscriber = new Redis(this.redisConfig);
      
      // 연결 이벤트 핸들러
      this.subscriber.on('connect', () => {
        this.connectionState = 'connected';
        this.logger.info('Redis subscriber connected');
      });
      
      this.subscriber.on('ready', () => {
        this.connectionState = 'connected';
        this.logger.info('Redis subscriber ready');
        this.subscribeToChannels();
      });
      
      this.subscriber.on('error', (error) => {
        this.connectionState = 'error';
        this.stats.connectionErrors++;
        this.logger.error('Redis subscriber error:', error);
        this.scheduleReconnect();
      });
      
      this.subscriber.on('close', () => {
        this.connectionState = 'disconnected';
        this.logger.warn('Redis subscriber connection closed');
        this.scheduleReconnect();
      });
      
      // 패턴 메시지 핸들러 (연결 상태 체크 추가)
      this.subscriber.on('pmessage', (pattern, channel, message) => {
        if (this.connectionState === 'connected') {
          this.handleMessage(pattern, channel, message);
        } else {
          this.logger.debug('Ignoring message due to connection state:', { 
            connectionState: this.connectionState,
            channel 
          });
        }
      });
      
      // 연결 시작
      await this.subscriber.connect();
      
    } catch (error) {
      this.connectionState = 'error';
      this.logger.error('Failed to start Redis subscriber:', error);
      this.scheduleReconnect();
    }
  }
  
  /**
   * 채널 구독
   */
  subscribeToChannels() {
    // 패턴 기반 구독 (모든 aws-masker 이벤트)
    this.subscriber.psubscribe('aws-masker:*')
      .then(() => {
        this.logger.info('Subscribed to aws-masker:* pattern');
      })
      .catch((error) => {
        this.logger.error('Failed to subscribe to channels:', error);
      });
  }
  
  /**
   * 메시지 핸들러
   */
  handleMessage(pattern, channel, message) {
    try {
      // 통계 업데이트
      this.stats.totalEvents++;
      this.stats.lastEventTime = Date.now();
      
      // JSON 파싱
      let eventData;
      try {
        eventData = JSON.parse(message);
      } catch (parseError) {
        this.logger.warn('Failed to parse event message:', { channel, message });
        return;
      }
      
      // 채널별 통계
      this.updateChannelStats(channel);
      
      // 배치 처리 또는 즉시 처리
      if (this.batchSize > 1) {
        this.addToBatch({ pattern, channel, eventData });
      } else {
        this.processEvent({ pattern, channel, eventData });
      }
      
    } catch (error) {
      this.logger.error('Error handling message:', error, { channel, pattern });
    }
  }
  
  /**
   * 채널별 통계 업데이트
   */
  updateChannelStats(channel) {
    if (channel.includes(':masking')) {
      this.stats.maskingEvents++;
    } else if (channel.includes(':unmasking')) {
      this.stats.unmaskingEvents++;
    } else if (channel.includes(':security')) {
      this.stats.securityAlerts++;
    } else if (channel.includes(':performance')) {
      this.stats.performanceMetrics++;
    }
  }
  
  /**
   * 배치에 이벤트 추가
   */
  addToBatch(event) {
    this.eventBatch.push(event);
    
    // 배치 크기 도달 시 즉시 처리
    if (this.eventBatch.length >= this.batchSize) {
      // 타이머가 설정되어 있으면 먼저 클리어 (효율성 개선)
      if (this.batchTimer) {
        clearTimeout(this.batchTimer);
        this.batchTimer = null;
      }
      // 비동기 배치 처리 (백그라운드 실행)
      this.processBatch().catch(error => {
        this.logger.error('Error in batch processing from addToBatch:', error);
      });
    } else {
      // 타이머 설정 (첫 번째 이벤트인 경우)
      if (this.eventBatch.length === 1) {
        this.batchTimer = setTimeout(async () => {
          try {
            await this.processBatch();
          } catch (error) {
            this.logger.error('Error in batch processing from timer:', error);
          }
        }, this.batchTimeout);
      }
    }
  }
  
  /**
   * 배치 처리 (비동기 처리 지원)
   */
  async processBatch() {
    if (this.eventBatch.length === 0) return Promise.resolve();
    
    const batch = [...this.eventBatch];
    this.eventBatch = [];
    
    // 타이머 클리어
    if (this.batchTimer) {
      clearTimeout(this.batchTimer);
      this.batchTimer = null;
    }
    
    // 배치 로깅
    this.logger.info(`Processing event batch: ${batch.length} events`);
    
    try {
      // 각 이벤트 처리 (순차적 처리로 안정성 보장)
      for (const event of batch) {
        await this.processEvent(event);
      }
      
      this.logger.debug(`Batch processing completed: ${batch.length} events`);
    } catch (error) {
      this.logger.error('Error processing event batch:', error);
      throw error;
    }
  }
  
  /**
   * 개별 이벤트 처리 (비동기 지원)
   */
  async processEvent({ pattern, channel, eventData }) {
    // 레이트 리미팅 체크
    if (!this.shouldLog()) {
      return Promise.resolve();
    }
    
    try {
      // 마스킹 로그 저장 (API 제공용)
      this.storeMaskingLog({ pattern, channel, eventData, timestamp: new Date().toISOString() });
      
      // 환경별 로깅 차별화
      if (this.nodeEnv === 'production') {
        this.logProductionEvent(eventData);
      } else {
        this.logDetailedEvent(eventData, channel);
      }
      
      return Promise.resolve();
    } catch (error) {
      this.logger.error('Error processing individual event:', error, { channel, pattern });
      return Promise.reject(error);
    }
  }
  
  /**
   * 마스킹 로그 저장 (API 제공용)
   */
  storeMaskingLog(logEntry) {
    try {
      // 최근 로그에 추가
      this.recentMaskingLogs.unshift(logEntry);
      
      // 최대 개수 유지 (오래된 것 제거)
      if (this.recentMaskingLogs.length > this.maxLogHistory) {
        this.recentMaskingLogs = this.recentMaskingLogs.slice(0, this.maxLogHistory);
      }
      
      this.logger.debug(`Stored masking log: ${this.recentMaskingLogs.length}/${this.maxLogHistory}`);
    } catch (error) {
      this.logger.error('Error storing masking log:', error);
    }
  }
  
  /**
   * 최근 마스킹 로그 조회 (API용)
   */
  getMaskingLogs(limit = 50) {
    try {
      const logs = limit > 0 ? this.recentMaskingLogs.slice(0, limit) : this.recentMaskingLogs;
      
      return {
        logs,
        total: this.recentMaskingLogs.length,
        limit,
        stats: this.getStats(),
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      this.logger.error('Error retrieving masking logs:', error);
      return {
        logs: [],
        total: 0,
        limit,
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }
  
  /**
   * 프로덕션 환경 로깅 (최소 정보) - 기존 로거 활용
   */
  logProductionEvent(event) {
    // 성능 메트릭 로깅 (기존 로거 기능 활용)
    if (event.processing_time_ms) {
      this.logger.performance(event.event_type, event.processing_time_ms, {
        request_id: event.request_id
      });
    }
    
    // 보안 이벤트 로깅 (필요시)
    if (event.event_type.includes('security') || event.event_type.includes('alert')) {
      this.logger.security(event.event_type, {
        request_id: event.request_id,
        success: event.success
      });
    }
  }
  
  /**
   * 개발 환경 상세 로깅 - 기존 로거 메트릭 기능 활용
   */
  logDetailedEvent(event, channel) {
    // 비즈니스 메트릭 로깅
    this.logger.metric('kong_masking_event', event.total_patterns, {
      channel,
      event_type: event.event_type,
      request_id: event.request_id,
      success: event.success,
      patterns_applied: event.patterns_applied,
      request_size_bytes: event.request_size_bytes,
      timestamp: new Date(event.timestamp).toISOString()
    });
    
    // 성능 메트릭 (처리 시간이 있는 경우)
    if (event.processing_time_ms) {
      this.logger.performance(event.event_type, event.processing_time_ms, {
        request_id: event.request_id,
        patterns: event.total_patterns
      });
    }
    
    // 개발 환경에서만 상세 정보 포함
    if (this.nodeEnv === 'development') {
      this.logger.info('Kong Masking Event Received:', {
        channel,
        event_type: event.event_type,
        request_id: event.request_id,
        success: event.success,
        patterns_applied: event.patterns_applied,
        total_patterns: event.total_patterns,
        processing_time_ms: event.processing_time_ms,
        request_size_bytes: event.request_size_bytes,
        timestamp: new Date(event.timestamp).toISOString(),
        // 데모 데이터 (개발 환경에서만)
        demo_data: event.demo_data
      });
    }
  }
  
  /**
   * 레이트 리미팅 체크
   */
  shouldLog() {
    const now = Date.now();
    
    // 1분마다 카운터 리셋
    if (now - this.lastLogTime > this.resetInterval) {
      this.eventCount = 0;
      this.lastLogTime = now;
    }
    
    // 제한 체크
    if (this.eventCount >= this.logRateLimit) {
      return false;
    }
    
    this.eventCount++;
    return true;
  }
  
  /**
   * 레이트 리미터 리셋 타이머
   */
  startRateLimitReset() {
    // 기존 타이머가 있으면 정리
    if (this.rateLimitTimer) {
      clearInterval(this.rateLimitTimer);
    }
    
    // 새 타이머 설정 및 ID 저장
    this.rateLimitTimer = setInterval(() => {
      this.eventCount = 0;
      this.lastLogTime = Date.now();
    }, this.resetInterval);
  }
  
  /**
   * 재연결 스케줄링 (최대 시도 횟수 제한 및 지수 백오프)
   */
  scheduleReconnect() {
    if (this.reconnectTimer) return;
    
    // 최대 재연결 시도 횟수 체크
    if (this.currentReconnectAttempts >= this.maxReconnectAttempts) {
      this.logger.error('Maximum reconnection attempts reached. Stopping reconnection attempts.', {
        maxAttempts: this.maxReconnectAttempts,
        currentAttempts: this.currentReconnectAttempts
      });
      return;
    }
    
    this.currentReconnectAttempts++;
    
    // 지수 백오프: 시도 횟수에 따라 지연 시간 증가
    const backoffDelay = Math.min(
      this.reconnectDelay * Math.pow(2, this.currentReconnectAttempts - 1),
      this.maxReconnectDelay
    );
    
    this.logger.info('Scheduling Redis reconnection attempt', {
      attempt: this.currentReconnectAttempts,
      maxAttempts: this.maxReconnectAttempts,
      delayMs: backoffDelay
    });
    
    this.reconnectTimer = setTimeout(async () => {
      this.reconnectTimer = null;
      this.logger.info('Attempting to reconnect Redis subscriber...', {
        attempt: this.currentReconnectAttempts
      });
      
      try {
        await this.start();
        // 성공 시 재연결 시도 횟수 리셋
        this.currentReconnectAttempts = 0;
        this.logger.info('Redis reconnection successful');
      } catch (error) {
        this.logger.error('Redis reconnection failed:', error);
        // 실패 시 다시 재연결 시도 (최대 횟수 체크는 scheduleReconnect에서 수행)
        this.scheduleReconnect();
      }
    }, backoffDelay);
  }
  
  /**
   * 통계 정보 반환
   */
  getStats() {
    const uptime = Date.now() - this.stats.startTime;
    return {
      ...this.stats,
      uptime_ms: uptime,
      uptime_formatted: this.formatUptime(uptime),
      events_per_minute: this.stats.totalEvents / (uptime / 60000) || 0,
      connection_status: this.connectionState,
      current_batch_size: this.eventBatch.length,
      rate_limit_remaining: Math.max(0, this.logRateLimit - this.eventCount),
      // 재연결 관련 통계 추가
      reconnect_attempts: this.currentReconnectAttempts,
      max_reconnect_attempts: this.maxReconnectAttempts,
      is_reconnect_scheduled: this.reconnectTimer !== null
    };
  }
  
  /**
   * 업타임 포매팅
   */
  formatUptime(ms) {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    
    if (days > 0) return `${days}d ${hours % 24}h ${minutes % 60}m`;
    if (hours > 0) return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
    return `${seconds}s`;
  }
  
  /**
   * 정리 및 연결 해제 (배치 처리 완료 대기)
   */
  async stop() {
    this.logger.info('Stopping Redis event subscriber...');
    
    // 배치 처리 완료 및 대기 (타임아웃 5초)
    if (this.eventBatch.length > 0) {
      try {
        this.logger.info(`Processing final batch: ${this.eventBatch.length} events`);
        
        // 타임아웃과 함께 배치 처리 완료 대기
        await Promise.race([
          this.processBatch(),
          new Promise((_, reject) => 
            setTimeout(() => reject(new Error('Batch processing timeout')), 5000)
          )
        ]);
        
        this.logger.info('Final batch processing completed');
      } catch (error) {
        this.logger.warn('Error or timeout during final batch processing:', error);
      }
    }
    
    // 타이머 정리
    if (this.batchTimer) {
      clearTimeout(this.batchTimer);
    }
    
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    
    if (this.rateLimitTimer) {
      clearInterval(this.rateLimitTimer);
    }
    
    // Redis 연결 해제
    if (this.subscriber) {
      await this.subscriber.disconnect();
    }
    
    this.connectionState = 'disconnected';
    this.logger.info('Redis event subscriber stopped');
  }
}

module.exports = RedisEventSubscriber;