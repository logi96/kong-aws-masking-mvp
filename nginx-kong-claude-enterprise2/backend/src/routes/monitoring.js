/**
 * @fileoverview Monitoring routes for metrics and observability
 * @module routes/monitoring
 */

const express = require('express');
const router = express.Router();
const monitoringService = require('../services/monitoring/monitoringService');
const logger = require('../utils/logger');
const { asyncHandler } = require('../middlewares/errorHandler');

/**
 * @api {get} /monitoring/metrics Get system metrics
 * @apiName GetMetrics
 * @apiGroup Monitoring
 * @apiDescription Get comprehensive system and application metrics
 * 
 * @apiSuccess {Object} system System-level metrics
 * @apiSuccess {Object} application Application-level metrics
 * @apiSuccess {Object} dependencies Dependency health metrics
 * @apiSuccess {String} timestamp Metrics collection timestamp
 */
router.get('/metrics', asyncHandler(async (req, res) => {
  const metrics = await monitoringService.collectMetrics();
  res.json(metrics);
}));

/**
 * @api {get} /monitoring/prometheus Prometheus metrics endpoint
 * @apiName GetPrometheusMetrics
 * @apiGroup Monitoring
 * @apiDescription Export metrics in Prometheus format
 * 
 * @apiSuccess {String} metrics Prometheus-formatted metrics
 */
router.get('/prometheus', asyncHandler(async (req, res) => {
  const prometheusMetrics = await monitoringService.getPrometheusMetrics();
  res.set('Content-Type', 'text/plain; version=0.0.4');
  res.send(prometheusMetrics);
}));

/**
 * @api {get} /monitoring/events Get recent system events
 * @apiName GetSystemEvents
 * @apiGroup Monitoring
 * @apiDescription Get recent system events and alerts
 * 
 * @apiQuery {Number} [limit=100] Maximum number of events to return
 * @apiQuery {String} [level] Filter by event level (info, warn, error)
 * @apiQuery {String} [since] ISO timestamp to get events after
 * 
 * @apiSuccess {Object[]} events Array of system events
 * @apiSuccess {Number} total Total number of events matching criteria
 */
router.get('/events', asyncHandler(async (req, res) => {
  const { limit = 100, level, since } = req.query;
  
  const events = await monitoringService.getEvents({
    limit: parseInt(limit),
    level,
    since: since ? new Date(since) : undefined
  });
  
  res.json(events);
}));

/**
 * @api {post} /monitoring/events Record a custom event
 * @apiName RecordEvent
 * @apiGroup Monitoring
 * @apiDescription Record a custom monitoring event
 * 
 * @apiBody {String} type Event type
 * @apiBody {String} level Event level (info, warn, error)
 * @apiBody {String} message Event message
 * @apiBody {Object} [metadata] Additional event metadata
 * 
 * @apiSuccess {String} eventId Unique event identifier
 * @apiSuccess {String} timestamp Event timestamp
 */
router.post('/events', asyncHandler(async (req, res) => {
  const { type, level, message, metadata } = req.body;
  
  const eventId = await monitoringService.recordEvent({
    type,
    level: level || 'info',
    message,
    metadata,
    source: 'api'
  });
  
  res.status(201).json({
    eventId,
    timestamp: new Date().toISOString()
  });
}));

/**
 * @api {get} /monitoring/alerts Get active alerts
 * @apiName GetAlerts
 * @apiGroup Monitoring
 * @apiDescription Get currently active system alerts
 * 
 * @apiSuccess {Object[]} alerts Array of active alerts
 * @apiSuccess {Object} summary Alert summary statistics
 */
router.get('/alerts', asyncHandler(async (req, res) => {
  const alerts = await monitoringService.getActiveAlerts();
  res.json(alerts);
}));

/**
 * @api {get} /monitoring/dashboard Dashboard data
 * @apiName GetDashboardData
 * @apiGroup Monitoring
 * @apiDescription Get aggregated data for monitoring dashboard
 * 
 * @apiSuccess {Object} overview System overview metrics
 * @apiSuccess {Object} trends Historical trend data
 * @apiSuccess {Object} alerts Active alerts summary
 */
router.get('/dashboard', asyncHandler(async (req, res) => {
  const dashboardData = await monitoringService.getDashboardData();
  res.json(dashboardData);
}));

/**
 * @api {get} /monitoring/traces Get request traces
 * @apiName GetTraces
 * @apiGroup Monitoring
 * @apiDescription Get request trace information
 * 
 * @apiQuery {Number} [limit=50] Maximum number of traces
 * @apiQuery {String} [requestId] Filter by specific request ID
 * @apiQuery {Number} [minDuration] Minimum duration in ms
 * 
 * @apiSuccess {Object[]} traces Array of request traces
 */
router.get('/traces', asyncHandler(async (req, res) => {
  const { limit = 50, requestId, minDuration } = req.query;
  
  const traces = await monitoringService.getTraces({
    limit: parseInt(limit),
    requestId,
    minDuration: minDuration ? parseInt(minDuration) : undefined
  });
  
  res.json(traces);
}));

/**
 * @api {get} /monitoring/logs Stream logs
 * @apiName StreamLogs
 * @apiGroup Monitoring
 * @apiDescription Stream application logs (SSE endpoint)
 * 
 * @apiQuery {String} [level] Minimum log level to stream
 * @apiQuery {String} [service] Filter by service name
 */
router.get('/logs', (req, res) => {
  const { level = 'info', service } = req.query;
  
  // Set up SSE
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive'
  });
  
  // Send initial connection message
  res.write(`data: ${JSON.stringify({ type: 'connected', timestamp: new Date().toISOString() })}\n\n`);
  
  // Set up log streaming
  const streamId = monitoringService.streamLogs((log) => {
    res.write(`data: ${JSON.stringify(log)}\n\n`);
  }, { level, service });
  
  // Clean up on client disconnect
  req.on('close', () => {
    monitoringService.stopLogStream(streamId);
    res.end();
  });
});

module.exports = router;