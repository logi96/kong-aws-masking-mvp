/**
 * Redis Masking Data Structure Optimizer
 * Optimizes data structures for efficient storage and retrieval of AWS masking data
 * @module maskingDataOptimizer
 */

const crypto = require('crypto');

/**
 * @typedef {Object} MaskingEntry
 * @property {string} original - Original AWS resource identifier
 * @property {string} masked - Masked identifier
 * @property {string} resourceType - Type of AWS resource
 * @property {number} ttl - Time to live in seconds
 * @property {Object} metadata - Additional metadata
 */

/**
 * @typedef {Object} OptimizedMaskingData
 * @property {string} key - Redis key
 * @property {string|Object} value - Optimized value
 * @property {number} ttl - TTL in seconds
 * @property {number} db - Target Redis database
 */

class MaskingDataOptimizer {
  constructor() {
    /**
     * Compression thresholds
     */
    this.COMPRESSION_THRESHOLD = 1024; // Compress values larger than 1KB
    this.BATCH_SIZE = 100; // Optimal batch size for pipeline operations
    
    /**
     * TTL configurations by data type
     */
    this.TTL_CONFIG = {
      active: 3600,        // 1 hour for active mappings
      session: 1800,       // 30 minutes for session data
      history: 604800,     // 7 days for historical data
      metrics: 86400,      // 24 hours for detailed metrics
      permanent: 0         // No expiration for unmask mappings
    };
    
    /**
     * Database assignments
     */
    this.DB_MAPPING = {
      active: 0,
      history: 1,
      unmask: 2,
      metrics: 3
    };
  }

  /**
   * Optimize masking data for storage
   * @param {MaskingEntry} entry - Raw masking entry
   * @param {string} requestId - Request identifier
   * @returns {OptimizedMaskingData} Optimized data structure
   */
  optimizeMaskingData(entry, requestId) {
    const { original, masked, resourceType, metadata = {} } = entry;
    
    // Generate compact key
    const key = this.generateOptimizedKey('active', requestId, resourceType, masked);
    
    // Optimize value structure
    const optimizedValue = this.compressValue({
      o: original,  // Short keys for common fields
      t: resourceType,
      m: new Date().toISOString(),
      r: requestId,
      ...this.filterMetadata(metadata)
    });
    
    return {
      key,
      value: optimizedValue,
      ttl: this.TTL_CONFIG.active,
      db: this.DB_MAPPING.active
    };
  }

  /**
   * Optimize unmask mapping for permanent storage
   * @param {string} maskedId - Masked identifier
   * @param {string} original - Original value
   * @param {string} resourceType - Resource type
   * @returns {OptimizedMaskingData} Optimized unmask data
   */
  optimizeUnmaskMapping(maskedId, original, resourceType) {
    const key = `u:${maskedId}`; // Ultra-compact unmask key
    
    // Store minimal data for unmask operations
    const value = {
      o: original,
      t: resourceType,
      c: new Date().toISOString(),
      a: 0  // Access count
    };
    
    return {
      key,
      value: JSON.stringify(value),
      ttl: this.TTL_CONFIG.permanent,
      db: this.DB_MAPPING.unmask
    };
  }

  /**
   * Optimize historical data for long-term storage
   * @param {Array<MaskingEntry>} entries - Array of masking entries
   * @param {string} date - Date string (YYYYMMDD)
   * @returns {OptimizedMaskingData} Optimized historical data
   */
  optimizeHistoricalData(entries, date) {
    // Group by resource type for better compression
    const grouped = this.groupByResourceType(entries);
    
    const optimizedEntries = Object.entries(grouped).map(([type, items]) => {
      const hash = this.generateHash(`${date}:${type}`);
      const key = `h:${date}:${type}:${hash.substring(0, 8)}`;
      
      // Compress grouped data
      const compressedValue = this.compressHistoricalData({
        t: type,
        c: items.length,
        f: items[0]?.timestamp || date,
        l: items[items.length - 1]?.timestamp || date,
        d: this.extractUniquePatterns(items)
      });
      
      return {
        key,
        value: compressedValue,
        ttl: this.TTL_CONFIG.history,
        db: this.DB_MAPPING.history
      };
    });
    
    return optimizedEntries;
  }

  /**
   * Optimize metrics data for efficient storage
   * @param {Object} metrics - Raw metrics data
   * @param {string} metricType - Type of metric
   * @param {number} timestamp - Unix timestamp
   * @returns {OptimizedMaskingData} Optimized metrics
   */
  optimizeMetricsData(metrics, metricType, timestamp) {
    const hourlyBucket = Math.floor(timestamp / 3600) * 3600;
    const key = `m:${metricType}:${hourlyBucket}`;
    
    // Use sorted set for time-series data
    const score = timestamp;
    const member = this.compressMetrics(metrics);
    
    return {
      key,
      value: { score, member },
      ttl: this.TTL_CONFIG.metrics,
      db: this.DB_MAPPING.metrics,
      type: 'zadd'  // Special type for sorted set operation
    };
  }

  /**
   * Generate optimized Redis key
   * @private
   */
  generateOptimizedKey(namespace, ...parts) {
    // Use short namespace prefixes
    const prefixes = {
      active: 'a',
      history: 'h',
      unmask: 'u',
      metrics: 'm',
      session: 's'
    };
    
    const prefix = prefixes[namespace] || namespace.substring(0, 1);
    const compactParts = parts.map(p => this.compactIdentifier(p));
    
    return `${prefix}:${compactParts.join(':')}`;
  }

  /**
   * Compact long identifiers
   * @private
   */
  compactIdentifier(id) {
    if (!id || id.length <= 10) return id;
    
    // For request IDs and similar, use first 8 chars + hash
    if (id.startsWith('req') || id.length > 20) {
      const hash = this.generateHash(id);
      return `${id.substring(0, 8)}${hash.substring(0, 4)}`;
    }
    
    return id;
  }

  /**
   * Compress value if it exceeds threshold
   * @private
   */
  compressValue(value) {
    const jsonStr = JSON.stringify(value);
    
    if (jsonStr.length < this.COMPRESSION_THRESHOLD) {
      return jsonStr;
    }
    
    // For large values, remove null/undefined and empty strings
    const cleaned = this.cleanObject(value);
    return JSON.stringify(cleaned);
  }

  /**
   * Filter metadata to keep only essential fields
   * @private
   */
  filterMetadata(metadata) {
    const essentialFields = ['region', 'accountId', 'tags', 'arn'];
    const filtered = {};
    
    essentialFields.forEach(field => {
      if (metadata[field] !== undefined && metadata[field] !== null) {
        // Use short keys
        const shortKey = field.substring(0, 1);
        filtered[shortKey] = metadata[field];
      }
    });
    
    return filtered;
  }

  /**
   * Group entries by resource type
   * @private
   */
  groupByResourceType(entries) {
    return entries.reduce((grouped, entry) => {
      const type = entry.resourceType;
      if (!grouped[type]) grouped[type] = [];
      grouped[type].push(entry);
      return grouped;
    }, {});
  }

  /**
   * Extract unique patterns from historical data
   * @private
   */
  extractUniquePatterns(items) {
    const patterns = new Set();
    
    items.forEach(item => {
      if (item.original) {
        // Extract pattern signature (e.g., i-xxx for EC2)
        const pattern = item.original.substring(0, 5);
        patterns.add(pattern);
      }
    });
    
    return Array.from(patterns);
  }

  /**
   * Compress metrics data
   * @private
   */
  compressMetrics(metrics) {
    // Convert to compact format
    const compressed = {
      r: metrics.requests || 0,
      m: metrics.masked_resources || 0,
      l: Math.round(metrics.avg_latency_ms * 10) / 10,  // 1 decimal place
      e: metrics.errors || 0
    };
    
    // Add optional fields only if present
    if (metrics.cache_hits) compressed.h = metrics.cache_hits;
    if (metrics.cache_misses) compressed.i = metrics.cache_misses;
    
    return JSON.stringify(compressed);
  }

  /**
   * Generate hash for data
   * @private
   */
  generateHash(data) {
    return crypto.createHash('sha256')
      .update(data)
      .digest('hex');
  }

  /**
   * Clean object by removing null/undefined values
   * @private
   */
  cleanObject(obj) {
    const cleaned = {};
    
    Object.entries(obj).forEach(([key, value]) => {
      if (value !== null && value !== undefined && value !== '') {
        if (typeof value === 'object' && !Array.isArray(value)) {
          const cleanedNested = this.cleanObject(value);
          if (Object.keys(cleanedNested).length > 0) {
            cleaned[key] = cleanedNested;
          }
        } else {
          cleaned[key] = value;
        }
      }
    });
    
    return cleaned;
  }

  /**
   * Prepare batch operations for Redis pipeline
   * @param {Array<MaskingEntry>} entries - Array of masking entries
   * @param {string} requestId - Request identifier
   * @returns {Array<Array<OptimizedMaskingData>>} Batched operations
   */
  prepareBatchOperations(entries, requestId) {
    const batches = [];
    
    for (let i = 0; i < entries.length; i += this.BATCH_SIZE) {
      const batch = entries.slice(i, i + this.BATCH_SIZE);
      const optimizedBatch = batch.map(entry => {
        // Optimize for active storage
        const active = this.optimizeMaskingData(entry, requestId);
        
        // Optimize for unmask mapping
        const unmask = this.optimizeUnmaskMapping(
          entry.masked,
          entry.original,
          entry.resourceType
        );
        
        return [active, unmask];
      }).flat();
      
      batches.push(optimizedBatch);
    }
    
    return batches;
  }

  /**
   * Calculate memory usage estimate
   * @param {OptimizedMaskingData} data - Optimized data
   * @returns {number} Estimated memory usage in bytes
   */
  estimateMemoryUsage(data) {
    const keySize = Buffer.byteLength(data.key);
    let valueSize = 0;
    
    if (typeof data.value === 'string') {
      valueSize = Buffer.byteLength(data.value);
    } else if (data.value.score && data.value.member) {
      // Sorted set member
      valueSize = Buffer.byteLength(data.value.member) + 8; // 8 bytes for score
    } else {
      valueSize = Buffer.byteLength(JSON.stringify(data.value));
    }
    
    // Redis overhead estimate (approximately 50 bytes per key)
    const overhead = 50;
    
    return keySize + valueSize + overhead;
  }

  /**
   * Optimize data structure based on access patterns
   * @param {string} accessPattern - Expected access pattern
   * @param {Object} data - Data to optimize
   * @returns {Object} Optimization recommendations
   */
  recommendDataStructure(accessPattern, data) {
    const recommendations = {
      structure: 'string',
      indexing: [],
      ttlStrategy: 'default'
    };
    
    switch (accessPattern) {
      case 'frequent-read':
        if (Object.keys(data).length > 5) {
          recommendations.structure = 'hash';
          recommendations.indexing.push('create-secondary-index');
        }
        recommendations.ttlStrategy = 'extended';
        break;
        
      case 'write-heavy':
        recommendations.structure = 'string';
        recommendations.ttlStrategy = 'aggressive';
        break;
        
      case 'time-series':
        recommendations.structure = 'sorted-set';
        recommendations.indexing.push('timestamp-score');
        recommendations.ttlStrategy = 'sliding-window';
        break;
        
      case 'search-heavy':
        recommendations.structure = 'set';
        recommendations.indexing.push('pattern-index', 'prefix-tree');
        break;
        
      default:
        // Keep defaults
    }
    
    return recommendations;
  }
}

module.exports = MaskingDataOptimizer;