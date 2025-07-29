/**
 * Simple AWS Resource Masker
 * 
 * Kong 플러그인의 핵심 마스킹 패턴을 JavaScript로 구현한 독립 모듈
 * 프록시 레벨에서 사용 가능한 경량화된 버전
 * 
 * @module simple-masker
 */

const patterns = {
  // EC2 Instance ID Pattern (i-xxxxxxxxxxxxxxxxx)
  ec2_instance: {
    pattern: /i-[0-9a-f]{17}/g,
    replacement: 'AWS_EC2_',
    type: 'ec2',
    description: 'EC2 instance identifier'
  },
  
  // S3 Bucket Names (common patterns)
  s3_bucket: {
    pattern: /[a-z0-9][a-z0-9-]*bucket[a-z0-9-]*/g,
    replacement: 'AWS_S3_BUCKET_',
    type: 's3',
    description: 'S3 bucket names containing "bucket"'
  },
  
  // S3 Logs/Data Pattern
  s3_logs_bucket: {
    pattern: /[a-z0-9][a-z0-9-]*logs[a-z0-9-]*/g,
    replacement: 'AWS_S3_LOGS_BUCKET_',
    type: 's3',
    description: 'S3 bucket names containing "logs"'
  },
  
  // RDS Database Pattern
  rds_instance: {
    pattern: /[a-z-]*db[a-z-]*/g,
    replacement: 'AWS_RDS_',
    type: 'rds',
    description: 'RDS database names containing "db"'
  },
  
  // Public IP Pattern (with validation)
  public_ip: {
    pattern: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
    replacement: 'AWS_PUBLIC_IP_',
    type: 'ip',
    description: 'Public IP Address',
    validator: isPublicIP
  }
};

/**
 * IP 주소가 Public IP인지 검증
 * Private IP 범위와 특수 용도 IP를 제외한 나머지를 Public으로 분류
 * 
 * @param {string} ip - 검증할 IP 주소
 * @returns {boolean} Public IP 여부
 */
function isPublicIP(ip) {
  const parts = ip.split('.');
  if (parts.length !== 4) return false;
  
  const [a, b, c, d] = parts.map(Number);
  
  // 유효성 검증
  if ([a, b, c, d].some(n => isNaN(n) || n < 0 || n > 255)) {
    return false;
  }
  
  // Private IP 범위 체크 (RFC 1918)
  if (a === 10) return false; // 10.0.0.0/8
  if (a === 172 && b >= 16 && b <= 31) return false; // 172.16.0.0/12
  if (a === 192 && b === 168) return false; // 192.168.0.0/16
  
  // 특수 용도 IP 체크
  if (a === 169 && b === 254) return false; // AWS metadata service
  if (a === 127) return false; // Loopback
  if (a >= 224) return false; // Multicast and reserved
  if (a === 0) return false; // Network address
  
  return true; // 나머지는 Public IP
}

/**
 * Masker 클래스
 * AWS 리소스 식별자를 마스킹하고 복원하는 기능 제공
 */
class SimpleMasker {
  constructor() {
    this.mappings = new Map(); // 원본값과 마스킹값의 매핑 저장
    this.reverseMap = new Map(); // 마스킹값으로 원본값 찾기용
    this.counters = {}; // 각 리소스 타입별 카운터
  }

  /**
   * 텍스트에서 AWS 리소스를 찾아 마스킹
   * 
   * @param {string} text - 마스킹할 텍스트
   * @returns {string} 마스킹된 텍스트
   */
  mask(text) {
    if (!text || typeof text !== 'string') {
      return text;
    }

    let maskedText = text;

    // 각 패턴에 대해 마스킹 수행
    Object.entries(patterns).forEach(([key, config]) => {
      maskedText = maskedText.replace(config.pattern, (match) => {
        // validator가 있으면 검증
        if (config.validator && !config.validator(match)) {
          return match; // 검증 실패시 원본 유지
        }

        // 이미 마스킹된 값이 있는지 확인
        if (this.mappings.has(match)) {
          return this.mappings.get(match);
        }

        // 새로운 마스킹 값 생성
        const counter = this.getNextCounter(key);
        const masked = `${config.replacement}${String(counter).padStart(3, '0')}`;

        // 매핑 저장
        this.mappings.set(match, masked);
        this.reverseMap.set(masked, match);

        return masked;
      });
    });

    return maskedText;
  }

  /**
   * 마스킹된 텍스트를 원본으로 복원
   * 
   * @param {string} text - 복원할 텍스트
   * @returns {string} 복원된 텍스트
   */
  unmask(text) {
    if (!text || typeof text !== 'string') {
      return text;
    }

    let unmaskedText = text;

    // reverseMap을 사용하여 복원
    this.reverseMap.forEach((original, masked) => {
      // 정확한 매칭을 위해 word boundary 사용
      const regex = new RegExp(`\\b${this.escapeRegex(masked)}\\b`, 'g');
      unmaskedText = unmaskedText.replace(regex, original);
    });

    return unmaskedText;
  }

  /**
   * JSON 객체 내의 AWS 리소스를 재귀적으로 마스킹
   * 
   * @param {any} obj - 마스킹할 객체
   * @returns {any} 마스킹된 객체
   */
  maskJSON(obj) {
    if (!obj) return obj;

    if (typeof obj === 'string') {
      return this.mask(obj);
    }

    if (Array.isArray(obj)) {
      return obj.map(item => this.maskJSON(item));
    }

    if (typeof obj === 'object') {
      const masked = {};
      for (const [key, value] of Object.entries(obj)) {
        masked[key] = this.maskJSON(value);
      }
      return masked;
    }

    return obj;
  }

  /**
   * JSON 객체 내의 마스킹된 값을 재귀적으로 복원
   * 
   * @param {any} obj - 복원할 객체
   * @returns {any} 복원된 객체
   */
  unmaskJSON(obj) {
    if (!obj) return obj;

    if (typeof obj === 'string') {
      return this.unmask(obj);
    }

    if (Array.isArray(obj)) {
      return obj.map(item => this.unmaskJSON(item));
    }

    if (typeof obj === 'object') {
      const unmasked = {};
      for (const [key, value] of Object.entries(obj)) {
        unmasked[key] = this.unmaskJSON(value);
      }
      return unmasked;
    }

    return obj;
  }

  /**
   * 리소스 타입별 카운터 관리
   * 
   * @private
   * @param {string} type - 리소스 타입
   * @returns {number} 다음 카운터 값
   */
  getNextCounter(type) {
    if (!this.counters[type]) {
      this.counters[type] = 0;
    }
    return ++this.counters[type];
  }

  /**
   * 정규식 특수문자 이스케이프
   * 
   * @private
   * @param {string} str - 이스케이프할 문자열
   * @returns {string} 이스케이프된 문자열
   */
  escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  /**
   * 현재 매핑 정보 조회
   * 
   * @returns {Object} 매핑 통계 정보
   */
  getStats() {
    return {
      totalMappings: this.mappings.size,
      counters: { ...this.counters },
      patterns: Object.keys(patterns)
    };
  }

  /**
   * 매핑 초기화
   */
  clear() {
    this.mappings.clear();
    this.reverseMap.clear();
    this.counters = {};
  }

  /**
   * 특정 마스킹 값의 원본 값 조회
   * 
   * @param {string} masked - 마스킹된 값
   * @returns {string|undefined} 원본 값
   */
  getOriginal(masked) {
    return this.reverseMap.get(masked);
  }

  /**
   * 특정 원본 값의 마스킹 값 조회
   * 
   * @param {string} original - 원본 값
   * @returns {string|undefined} 마스킹된 값
   */
  getMasked(original) {
    return this.mappings.get(original);
  }
}

// 싱글톤 인스턴스 생성
const maskerInstance = new SimpleMasker();

// 모듈 exports
module.exports = {
  // 메인 클래스
  SimpleMasker,
  
  // 싱글톤 인스턴스의 메서드들
  mask: (text) => maskerInstance.mask(text),
  unmask: (text) => maskerInstance.unmask(text),
  maskJSON: (obj) => maskerInstance.maskJSON(obj),
  unmaskJSON: (obj) => maskerInstance.unmaskJSON(obj),
  getStats: () => maskerInstance.getStats(),
  clear: () => maskerInstance.clear(),
  getOriginal: (masked) => maskerInstance.getOriginal(masked),
  getMasked: (original) => maskerInstance.getMasked(original),
  
  // 새 인스턴스 생성용
  createMasker: () => new SimpleMasker(),
  
  // 유틸리티 함수
  isPublicIP,
  
  // 패턴 정보 (읽기 전용)
  patterns: Object.freeze(patterns)
};