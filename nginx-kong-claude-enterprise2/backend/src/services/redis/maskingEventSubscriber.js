/**
 * @fileoverview Kong AWS Masking Event Subscriber
 * @module services/redis/maskingEventSubscriber
 * 
 * Kong의 마스킹 이벤트를 실시간으로 구독하고 처리하는 모듈
 * Redis Pub/Sub를 사용하여 지속적인 연결을 유지
 */

const redisService = require('./redisService');
const logger = require('../../utils/logger');

class MaskingEventSubscriber {
  constructor() {
    this.isSubscribed = false;
    this.subscriber = null;
    this.maskingStats = {
      totalEvents: 0,
      successfulMasking: 0,
      failedMasking: 0,
      averageProcessingTime: 0
    };
  }

  /**
   * Kong 마스킹 이벤트 구독 시작
   * 서버 시작시 한번만 호출하면 됨
   * @returns {Promise<void>}
   */
  async startSubscription() {
    if (this.isSubscribed) {
      logger.warn('Masking event subscription already active');
      return;
    }

    try {
      logger.info('Starting Kong masking event subscription...');
      
      // Kong이 정의한 채널 구독
      this.subscriber = await redisService.subscribe(
        'aws-masker:events:masking', 
        this.handleMaskingEvent.bind(this)
      );
      
      this.isSubscribed = true;
      logger.info('✅ Successfully subscribed to Kong masking events');
      
      // 언마스킹 이벤트도 구독
      await redisService.subscribe(
        'aws-masker:events:unmasking',
        this.handleUnmaskingEvent.bind(this)
      );
      
      logger.info('✅ Successfully subscribed to Kong unmasking events');
      
    } catch (error) {
      logger.error('Failed to start masking event subscription:', error);
      throw error;
    }
  }

  /**
   * Kong에서 발행한 마스킹 이벤트 처리
   * Kong이 메시지 발행할 때마다 자동 실행됨
   * @param {string} message - Redis 메시지 (JSON 문자열)
   */
  handleMaskingEvent(message) {
    try {
      const event = JSON.parse(message);
      
      // 통계 업데이트
      this.maskingStats.totalEvents++;
      
      if (event.success) {
        this.maskingStats.successfulMasking++;
      } else {
        this.maskingStats.failedMasking++;
      }
      
      // 평균 처리시간 계산
      const currentAvg = this.maskingStats.averageProcessingTime;
      const newAvg = (currentAvg * (this.maskingStats.totalEvents - 1) + event.processing_time_ms) / this.maskingStats.totalEvents;
      this.maskingStats.averageProcessingTime = Math.round(newAvg * 100) / 100;
      
      logger.info('🎯 Masking Event Received:', {
        eventId: event.event_id,
        requestId: event.request_id,
        patternsApplied: event.total_patterns,
        processingTime: event.processing_time_ms + 'ms',
        success: event.success
      });
      
      // 실시간 마스킹 검증 로직
      this.validateMasking(event);
      
      // 성능 모니터링
      this.monitorPerformance(event);
      
      // 보안 검증
      this.securityValidation(event);
      
    } catch (error) {
      logger.error('Error processing masking event:', error);
    }
  }

  /**
   * 언마스킹 이벤트 처리
   * @param {string} message - Redis 메시지
   */
  handleUnmaskingEvent(message) {
    try {
      const event = JSON.parse(message);
      
      logger.info('🔓 Unmasking Event Received:', {
        eventId: event.event_id,
        requestId: event.request_id,
        patternsRestored: event.patterns_restored,
        processingTime: event.processing_time_ms + 'ms'
      });
      
    } catch (error) {
      logger.error('Error processing unmasking event:', error);
    }
  }

  /**
   * 실시간 마스킹 검증
   * @param {Object} event - 마스킹 이벤트
   */
  validateMasking(event) {
    // 마스킹 실패 감지
    if (event.total_patterns === 0 && event.demo_data?.original_text) {
      const originalText = event.demo_data.original_text;
      
      // AWS 패턴이 있는데 마스킹이 안된 경우
      const awsPatterns = [
        /i-[0-9a-f]{17}/,  // EC2 instance
        /vpc-[0-9a-f]{8}/, // VPC
        /sg-[0-9a-f]{8}/,  // Security group
        /10\.\d+\.\d+\.\d+/, // Private IP
        /bucket-\w+/       // S3 bucket pattern
      ];
      
      const hasAwsResources = awsPatterns.some(pattern => pattern.test(originalText));
      
      if (hasAwsResources) {
        logger.warn('🚨 MASKING FAILURE DETECTED:', {
          requestId: event.request_id,
          reason: 'AWS resources detected but no masking applied',
          originalTextLength: originalText.length,
          patterns: event.patterns_applied
        });
        
        // 알림 발송 (실제 환경에서는 Slack, Email 등)
        this.sendMaskingFailureAlert(event);
      }
    }
  }

  /**
   * 성능 모니터링
   * @param {Object} event - 마스킹 이벤트
   */
  monitorPerformance(event) {
    const processingTime = event.processing_time_ms;
    
    // 성능 임계값 체크 (5초)
    if (processingTime > 5000) {
      logger.warn('⚡ SLOW MASKING DETECTED:', {
        requestId: event.request_id,
        processingTime: processingTime + 'ms',
        threshold: '5000ms',
        requestSize: event.request_size_bytes + ' bytes'
      });
    }
    
    // 성능 통계 로깅 (매 100건마다)
    if (this.maskingStats.totalEvents % 100 === 0) {
      logger.info('📊 Masking Performance Stats:', {
        totalEvents: this.maskingStats.totalEvents,
        successRate: (this.maskingStats.successfulMasking / this.maskingStats.totalEvents * 100).toFixed(2) + '%',
        averageProcessingTime: this.maskingStats.averageProcessingTime + 'ms'
      });
    }
  }

  /**
   * 보안 검증
   * @param {Object} event - 마스킹 이벤트
   */
  securityValidation(event) {
    // 마스킹된 텍스트에 원본 데이터가 남아있는지 검증
    if (event.demo_data?.original_text && event.demo_data?.masked_text) {
      const originalText = event.demo_data.original_text;
      const maskedText = event.demo_data.masked_text;
      
      // 간단한 검증: EC2 인스턴스 ID가 마스킹된 텍스트에 남아있는지
      const ec2Pattern = /i-[0-9a-f]{17}/g;
      const originalMatches = originalText.match(ec2Pattern) || [];
      const maskedMatches = maskedText.match(ec2Pattern) || [];
      
      if (maskedMatches.length > 0) {
        logger.error('🔥 SECURITY BREACH DETECTED:', {
          requestId: event.request_id,
          issue: 'Original AWS resource IDs found in masked text',
          originalEc2Count: originalMatches.length,
          leakedEc2Count: maskedMatches.length,
          leakedIds: maskedMatches
        });
      }
    }
  }

  /**
   * 마스킹 실패 알림 발송
   * @param {Object} event - 마스킹 이벤트
   */
  sendMaskingFailureAlert(event) {
    // 실제 환경에서는 Slack, Email, PagerDuty 등으로 알림
    logger.error('🚨 ALERT: Masking failure requires immediate attention', {
      eventId: event.event_id,
      requestId: event.request_id,
      timestamp: new Date(event.timestamp).toISOString(),
      severity: 'HIGH',
      action_required: 'Check Kong masking configuration'
    });
  }

  /**
   * 구독 상태 확인
   * @returns {Object} 구독 상태 정보
   */
  getSubscriptionStatus() {
    return {
      isSubscribed: this.isSubscribed,
      stats: { ...this.maskingStats },
      uptime: this.isSubscribed ? Date.now() - this.startTime : 0
    };
  }

  /**
   * 구독 중지
   * @returns {Promise<void>}
   */
  async stopSubscription() {
    if (this.subscriber) {
      await this.subscriber.quit();
      this.isSubscribed = false;
      logger.info('Masking event subscription stopped');
    }
  }
}

// 싱글톤 인스턴스 생성
const maskingEventSubscriber = new MaskingEventSubscriber();

module.exports = maskingEventSubscriber;