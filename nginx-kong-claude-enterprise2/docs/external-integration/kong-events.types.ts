/**
 * Kong AWS Masking 이벤트 타입 정의
 * Kong event_publisher.lua에서 발행하는 이벤트 구조
 */

export interface KongMaskingEvent {
  /** 고유 이벤트 ID (예: mask_1738123456_12345) */
  event_id: string;
  
  /** 이벤트 타입 (항상 "masking_applied") */
  event_type: "masking_applied";
  
  /** 타임스탬프 (밀리초) */
  timestamp: number;
  
  /** Kong 요청 ID */
  request_id: string;
  
  /** 마스킹 성공 여부 */
  success: boolean;
  
  /** 적용된 패턴 정보 */
  patterns_applied: Record<string, number>;
  
  /** 총 마스킹된 패턴 수 */
  total_patterns: number;
  
  /** 처리 시간 (밀리초) */
  processing_time_ms: number;
  
  /** 요청 크기 (바이트) */
  request_size_bytes: number;
  
  /** 데모용 데이터 (내부 테스트용) */
  demo_data?: {
    /** 원본 텍스트 (최대 500자) */
    original_text?: string;
    
    /** 마스킹된 텍스트 (최대 500자) */
    masked_text?: string;
    
    /** 데모 모드 여부 */
    is_demo_mode: boolean;
    
    /** 텍스트 잘림 여부 */
    truncated: boolean;
  };
  
  /** 이벤트 소스 (항상 "kong-aws-masker") */
  source: "kong-aws-masker";
  
  /** 플러그인 버전 */
  version: string;
}

export interface KongUnmaskingEvent {
  /** 고유 이벤트 ID (예: unmask_1738123456_67890) */
  event_id: string;
  
  /** 이벤트 타입 (항상 "unmasking_applied") */
  event_type: "unmasking_applied";
  
  /** 타임스탬프 (밀리초) */
  timestamp: number;
  
  /** Kong 요청 ID */
  request_id: string;
  
  /** 언마스킹 성공 여부 */
  success: boolean;
  
  /** 복원된 패턴 수 */
  patterns_restored: number;
  
  /** 처리 시간 (밀리초) */
  processing_time_ms: number;
  
  /** 응답 크기 (바이트) */
  response_size_bytes: number;
  
  /** 이벤트 소스 */
  source: "kong-aws-masker";
  
  /** 플러그인 버전 */
  version: string;
}

export interface KongSecurityAlert {
  /** 알림 ID */
  alert_id: string;
  
  /** 알림 타입 */
  alert_type: "security_breach" | "masking_failure" | "performance_issue";
  
  /** 심각도 레벨 */
  severity: "low" | "medium" | "high" | "critical";
  
  /** 타임스탬프 */
  timestamp: number;
  
  /** 관련 요청 ID */
  request_id?: string;
  
  /** 알림 메시지 */
  message: string;
  
  /** 세부 정보 */
  details: Record<string, any>;
  
  /** 권장 조치 */
  recommended_action?: string;
}

export interface KongMetricsEvent {
  /** 메트릭 타입 */
  metric_type: "performance" | "throughput" | "error_rate";
  
  /** 타임스탬프 */
  timestamp: number;
  
  /** 메트릭 값 */
  value: number;
  
  /** 메트릭 단위 */
  unit: string;
  
  /** 메트릭 라벨 */
  labels: Record<string, string>;
}

/** Redis 채널 이름 상수 */
export const KONG_CHANNELS = {
  MASKING: 'aws-masker:events:masking',
  UNMASKING: 'aws-masker:events:unmasking',
  ALERTS: 'aws-masker:alerts:security',
  METRICS: 'aws-masker:metrics:performance'
} as const;

/** 구독 설정 인터페이스 */
export interface SubscriptionConfig {
  /** Redis 연결 설정 */
  redis: {
    host: string;
    port: number;
    password?: string;
    db?: number;
    connectTimeout?: number;
    commandTimeout?: number;
    maxRetriesPerRequest?: number;
  };
  
  /** 구독할 채널 설정 */
  channels: {
    masking: boolean;
    unmasking: boolean;
    alerts: boolean;
    metrics: boolean;
  };
  
  /** 이벤트 처리 설정 */
  processing: {
    bufferSize: number;
    batchSize: number;
    intervalMs: number;
  };
  
  /** 로깅 설정 */
  logging: {
    level: 'debug' | 'info' | 'warn' | 'error';
    file?: string;
  };
}

/** 이벤트 핸들러 인터페이스 */
export interface EventHandlers {
  onMaskingEvent?: (event: KongMaskingEvent) => Promise<void> | void;
  onUnmaskingEvent?: (event: KongUnmaskingEvent) => Promise<void> | void;
  onSecurityAlert?: (alert: KongSecurityAlert) => Promise<void> | void;
  onMetricsEvent?: (metrics: KongMetricsEvent) => Promise<void> | void;
  onError?: (error: Error, channel: string) => Promise<void> | void;
  onConnection?: () => Promise<void> | void;
  onDisconnection?: () => Promise<void> | void;
}