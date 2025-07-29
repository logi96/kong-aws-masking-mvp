/**
 * @fileoverview Monitoring service for system metrics and observability
 * @module services/monitoring/monitoringService
 */

const os = require('os');
const { EventEmitter } = require('events');
const logger = require('../../utils/logger');
const healthCheckService = require('../health/healthCheckService');

class MonitoringService extends EventEmitter {
  constructor() {
    super();
    this.metrics = new Map();
    this.events = [];
    this.alerts = new Map();
    this.traces = [];
    this.logStreams = new Map();
    this.startTime = Date.now();
    
    // Initialize metric collectors
    this.initializeCollectors();
  }

  /**
   * Initialize metric collectors
   */
  initializeCollectors() {
    // Collect metrics every 10 seconds
    setInterval(() => {
      this.collectSystemMetrics();
    }, 10000);
  }

  /**
   * Collect system metrics
   */
  collectSystemMetrics() {
    const timestamp = Date.now();
    
    // CPU metrics
    const cpus = os.cpus();
    const cpuUsage = cpus.map((cpu, index) => {
      const total = Object.values(cpu.times).reduce((acc, time) => acc + time, 0);
      const idle = cpu.times.idle;
      return {
        core: index,
        usage: ((total - idle) / total * 100).toFixed(2)
      };
    });
    
    // Memory metrics
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMem = totalMem - freeMem;
    
    // Store metrics
    this.metrics.set('system', {
      timestamp,
      cpu: {
        cores: cpus.length,
        usage: cpuUsage,
        loadAverage: os.loadavg()
      },
      memory: {
        total: totalMem,
        free: freeMem,
        used: usedMem,
        usagePercent: (usedMem / totalMem * 100).toFixed(2)
      },
      uptime: os.uptime()
    });
  }

  /**
   * Collect all metrics
   * @returns {Promise<Object>} Comprehensive metrics
   */
  async collectMetrics() {
    const timestamp = new Date().toISOString();
    
    // Get system metrics
    const systemMetrics = this.metrics.get('system') || {};
    
    // Get process metrics
    const processMetrics = {
      memory: process.memoryUsage(),
      cpu: process.cpuUsage(),
      uptime: process.uptime(),
      pid: process.pid,
      version: process.version
    };
    
    // Get health metrics
    const healthMetrics = await healthCheckService.getDetailedHealth();
    
    // Get request metrics (would be populated by middleware)
    const requestMetrics = this.getRequestMetrics();
    
    return {
      timestamp,
      system: systemMetrics,
      process: processMetrics,
      application: {
        uptime: (Date.now() - this.startTime) / 1000,
        requests: requestMetrics,
        errors: this.getErrorMetrics()
      },
      dependencies: healthMetrics.dependencies,
      custom: Object.fromEntries(this.metrics)
    };
  }

  /**
   * Get Prometheus formatted metrics
   * @returns {Promise<string>} Prometheus metrics
   */
  async getPrometheusMetrics() {
    const metrics = await this.collectMetrics();
    const lines = [];
    
    // System metrics
    lines.push('# HELP system_cpu_usage_percent CPU usage percentage');
    lines.push('# TYPE system_cpu_usage_percent gauge');
    if (metrics.system.cpu) {
      metrics.system.cpu.usage.forEach(cpu => {
        lines.push(`system_cpu_usage_percent{core="${cpu.core}"} ${cpu.usage}`);
      });
    }
    
    lines.push('# HELP system_memory_usage_bytes Memory usage in bytes');
    lines.push('# TYPE system_memory_usage_bytes gauge');
    if (metrics.system.memory) {
      lines.push(`system_memory_usage_bytes{type="total"} ${metrics.system.memory.total}`);
      lines.push(`system_memory_usage_bytes{type="used"} ${metrics.system.memory.used}`);
      lines.push(`system_memory_usage_bytes{type="free"} ${metrics.system.memory.free}`);
    }
    
    // Process metrics
    lines.push('# HELP process_memory_usage_bytes Process memory usage');
    lines.push('# TYPE process_memory_usage_bytes gauge');
    lines.push(`process_memory_usage_bytes{type="rss"} ${metrics.process.memory.rss}`);
    lines.push(`process_memory_usage_bytes{type="heapTotal"} ${metrics.process.memory.heapTotal}`);
    lines.push(`process_memory_usage_bytes{type="heapUsed"} ${metrics.process.memory.heapUsed}`);
    
    // Dependency health
    lines.push('# HELP dependency_health_status Dependency health status (1=healthy, 0=unhealthy)');
    lines.push('# TYPE dependency_health_status gauge');
    metrics.dependencies.forEach(dep => {
      const value = dep.status === 'healthy' ? 1 : 0;
      lines.push(`dependency_health_status{name="${dep.name}"} ${value}`);
    });
    
    // Request metrics
    lines.push('# HELP http_requests_total Total HTTP requests');
    lines.push('# TYPE http_requests_total counter');
    lines.push(`http_requests_total ${metrics.application.requests.total}`);
    
    return lines.join('\n');
  }

  /**
   * Get request metrics
   * @returns {Object} Request metrics
   */
  getRequestMetrics() {
    // This would be populated by request tracking middleware
    return {
      total: 0,
      success: 0,
      error: 0,
      active: 0,
      latency: {
        p50: 0,
        p95: 0,
        p99: 0,
        avg: 0
      }
    };
  }

  /**
   * Get error metrics
   * @returns {Object} Error metrics
   */
  getErrorMetrics() {
    return {
      total: 0,
      rate: 0,
      types: {}
    };
  }

  /**
   * Record an event
   * @param {Object} event - Event details
   * @returns {string} Event ID
   */
  recordEvent(event) {
    const eventId = require('uuid').v4();
    const timestamp = new Date().toISOString();
    
    const fullEvent = {
      id: eventId,
      timestamp,
      ...event
    };
    
    this.events.push(fullEvent);
    
    // Keep only last 1000 events
    if (this.events.length > 1000) {
      this.events = this.events.slice(-1000);
    }
    
    // Emit event for real-time subscribers
    this.emit('event', fullEvent);
    
    // Log the event
    logger[event.level || 'info'](`Monitoring event: ${event.type}`, event);
    
    return eventId;
  }

  /**
   * Get events
   * @param {Object} options - Query options
   * @returns {Promise<Object>} Events and metadata
   */
  async getEvents(options = {}) {
    const { limit = 100, level, since } = options;
    
    let filteredEvents = [...this.events];
    
    // Filter by level
    if (level) {
      filteredEvents = filteredEvents.filter(e => e.level === level);
    }
    
    // Filter by timestamp
    if (since) {
      const sinceTime = new Date(since).getTime();
      filteredEvents = filteredEvents.filter(e => 
        new Date(e.timestamp).getTime() > sinceTime
      );
    }
    
    // Sort by timestamp descending
    filteredEvents.sort((a, b) => 
      new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
    );
    
    // Apply limit
    const limitedEvents = filteredEvents.slice(0, limit);
    
    return {
      events: limitedEvents,
      total: filteredEvents.length,
      returned: limitedEvents.length
    };
  }

  /**
   * Get active alerts
   * @returns {Promise<Object>} Active alerts
   */
  async getActiveAlerts() {
    const alerts = Array.from(this.alerts.values());
    
    return {
      alerts: alerts.filter(a => a.status === 'active'),
      summary: {
        total: alerts.length,
        active: alerts.filter(a => a.status === 'active').length,
        critical: alerts.filter(a => a.severity === 'critical').length,
        warning: alerts.filter(a => a.severity === 'warning').length
      }
    };
  }

  /**
   * Get dashboard data
   * @returns {Promise<Object>} Dashboard data
   */
  async getDashboardData() {
    const metrics = await this.collectMetrics();
    const alerts = await this.getActiveAlerts();
    const recentEvents = await this.getEvents({ limit: 10 });
    
    return {
      overview: {
        status: alerts.summary.critical > 0 ? 'critical' : 
                alerts.summary.warning > 0 ? 'warning' : 'healthy',
        uptime: metrics.application.uptime,
        systemLoad: metrics.system.cpu?.loadAverage[0] || 0,
        memoryUsage: metrics.system.memory?.usagePercent || 0,
        activeRequests: metrics.application.requests.active,
        errorRate: metrics.application.errors.rate
      },
      trends: {
        requests: [], // Would be populated from time-series data
        errors: [],
        latency: [],
        cpu: [],
        memory: []
      },
      alerts: alerts.summary,
      recentEvents: recentEvents.events.slice(0, 5),
      dependencies: metrics.dependencies
    };
  }

  /**
   * Get request traces
   * @param {Object} options - Query options
   * @returns {Promise<Object>} Request traces
   */
  async getTraces(options = {}) {
    const { limit = 50, requestId, minDuration } = options;
    
    let filteredTraces = [...this.traces];
    
    // Filter by request ID
    if (requestId) {
      filteredTraces = filteredTraces.filter(t => t.requestId === requestId);
    }
    
    // Filter by duration
    if (minDuration) {
      filteredTraces = filteredTraces.filter(t => t.duration >= minDuration);
    }
    
    // Sort by timestamp descending
    filteredTraces.sort((a, b) => b.timestamp - a.timestamp);
    
    // Apply limit
    return {
      traces: filteredTraces.slice(0, limit),
      total: filteredTraces.length
    };
  }

  /**
   * Stream logs
   * @param {Function} callback - Callback for log events
   * @param {Object} options - Stream options
   * @returns {string} Stream ID
   */
  streamLogs(callback, options = {}) {
    const streamId = require('uuid').v4();
    
    this.logStreams.set(streamId, {
      callback,
      options,
      startTime: Date.now()
    });
    
    // Send initial test log
    callback({
      type: 'log',
      level: 'info',
      message: 'Log stream connected',
      timestamp: new Date().toISOString()
    });
    
    return streamId;
  }

  /**
   * Stop log stream
   * @param {string} streamId - Stream ID
   */
  stopLogStream(streamId) {
    this.logStreams.delete(streamId);
  }
}

// Create singleton instance
const monitoringService = new MonitoringService();

module.exports = monitoringService;