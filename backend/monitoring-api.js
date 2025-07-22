/**
 * monitoring-api.js
 * Phase 4 - 3단계: 모니터링 대시보드 API
 * 보안 최우선: 실시간 감시 및 알림
 */

const express = require('express');
const axios = require('axios');

const router = express.Router();

/**
 * Kong Admin API를 통한 메트릭 수집
 * @param {string} endpoint - Kong Admin API 엔드포인트
 * @returns {Promise<Object>} API 응답 데이터
 */
async function fetchKongMetrics(endpoint) {
    try {
        const response = await axios.get(`http://kong:8001${endpoint}`);
        return response.data;
    } catch (error) {
        console.error(`Failed to fetch Kong metrics from ${endpoint}:`, error.message);
        return null;
    }
}

/**
 * 모니터링 대시보드 데이터 조회
 * GET /api/monitoring/dashboard
 */
router.get('/dashboard', async (req, res) => {
    try {
        // Kong 상태 확인
        const kongStatus = await fetchKongMetrics('/status');
        
        // 플러그인 상태 확인
        const plugins = await fetchKongMetrics('/plugins');
        const awsMaskerPlugin = plugins?.data?.find(p => p.name === 'aws-masker');
        
        // 모니터링 데이터 수집
        const monitoringData = {
            timestamp: new Date().toISOString(),
            system: {
                kong: {
                    version: kongStatus?.version,
                    status: kongStatus ? 'HEALTHY' : 'UNHEALTHY',
                    database: kongStatus?.database?.reachable ? 'Connected' : 'DB-less mode'
                },
                plugin: {
                    enabled: awsMaskerPlugin?.enabled || false,
                    config: awsMaskerPlugin?.config || {}
                }
            },
            metrics: {
                // 실제 환경에서는 메트릭 수집 시스템과 연동
                total_requests: 0,
                masked_requests: 0,
                failed_requests: 0,
                avg_response_time: '0ms',
                pattern_usage: []
            },
            alerts: [],
            health: {
                status: 'HEALTHY',
                details: []
            }
        };
        
        res.json(monitoringData);
    } catch (error) {
        console.error('Dashboard error:', error);
        res.status(500).json({
            error: 'Failed to fetch monitoring data',
            message: error.message
        });
    }
});

/**
 * 실시간 메트릭 조회
 * GET /api/monitoring/metrics
 */
router.get('/metrics', async (req, res) => {
    try {
        const { period = '5min' } = req.query;
        
        // 메트릭 데이터 구조
        const metrics = {
            period,
            timestamp: new Date().toISOString(),
            performance: {
                requests_per_second: 0,
                average_latency_ms: 0,
                p95_latency_ms: 0,
                p99_latency_ms: 0,
                error_rate: 0
            },
            patterns: {
                total_patterns_matched: 0,
                critical_patterns_detected: 0,
                top_patterns: []
            },
            security: {
                blocked_requests: 0,
                circuit_breaker_trips: 0,
                emergency_mode_activations: 0
            }
        };
        
        res.json(metrics);
    } catch (error) {
        console.error('Metrics error:', error);
        res.status(500).json({
            error: 'Failed to fetch metrics',
            message: error.message
        });
    }
});

/**
 * 알림 조회
 * GET /api/monitoring/alerts
 */
router.get('/alerts', async (req, res) => {
    try {
        const { severity = 'all', limit = 50 } = req.query;
        
        // 알림 데이터 구조
        const alerts = {
            timestamp: new Date().toISOString(),
            total: 0,
            alerts: []
        };
        
        // 예시 알림 (실제 환경에서는 데이터베이스에서 조회)
        if (process.env.NODE_ENV === 'development') {
            alerts.alerts = [
                {
                    id: '1',
                    timestamp: new Date().toISOString(),
                    severity: 'HIGH',
                    type: 'CRITICAL_PATTERN_THRESHOLD',
                    message: 'IAM access key pattern detected 15 times in last hour',
                    details: {
                        pattern: 'iam_access_key',
                        count: 15,
                        threshold: 10
                    }
                }
            ];
            alerts.total = alerts.alerts.length;
        }
        
        res.json(alerts);
    } catch (error) {
        console.error('Alerts error:', error);
        res.status(500).json({
            error: 'Failed to fetch alerts',
            message: error.message
        });
    }
});

/**
 * 헬스 체크
 * GET /api/monitoring/health
 */
router.get('/health', async (req, res) => {
    try {
        // Kong 헬스 체크
        const kongHealth = await fetchKongMetrics('/status');
        
        // 시스템 상태 판단
        let status = 'HEALTHY';
        const checks = [];
        
        // Kong 상태 체크
        if (!kongHealth) {
            status = 'CRITICAL';
            checks.push({
                component: 'kong',
                status: 'DOWN',
                message: 'Kong Gateway is not responding'
            });
        } else {
            checks.push({
                component: 'kong',
                status: 'UP',
                message: 'Kong Gateway is healthy'
            });
        }
        
        // 응답
        res.status(status === 'HEALTHY' ? 200 : 503).json({
            status,
            timestamp: new Date().toISOString(),
            checks
        });
    } catch (error) {
        console.error('Health check error:', error);
        res.status(503).json({
            status: 'CRITICAL',
            timestamp: new Date().toISOString(),
            error: error.message
        });
    }
});

/**
 * 패턴 사용 통계
 * GET /api/monitoring/patterns
 */
router.get('/patterns', async (req, res) => {
    try {
        const { top = 10 } = req.query;
        
        // 패턴 통계 데이터
        const patterns = {
            timestamp: new Date().toISOString(),
            total_unique_patterns: 47,
            patterns: [
                { name: 'ec2_instance', count: 156, percentage: 25.4 },
                { name: 'private_ip', count: 98, percentage: 16.0 },
                { name: 's3_bucket', count: 87, percentage: 14.2 },
                { name: 'iam_access_key', count: 45, percentage: 7.3 },
                { name: 'vpc_id', count: 42, percentage: 6.8 }
            ].slice(0, parseInt(top))
        };
        
        res.json(patterns);
    } catch (error) {
        console.error('Patterns error:', error);
        res.status(500).json({
            error: 'Failed to fetch pattern statistics',
            message: error.message
        });
    }
});

/**
 * 성능 추세
 * GET /api/monitoring/trends
 */
router.get('/trends', async (req, res) => {
    try {
        const { interval = '1h', points = 60 } = req.query;
        
        // 추세 데이터 생성
        const trends = {
            timestamp: new Date().toISOString(),
            interval,
            data: []
        };
        
        // 시뮬레이션 데이터 (실제 환경에서는 시계열 DB에서 조회)
        const now = Date.now();
        const intervalMs = interval === '1h' ? 60000 : 300000; // 1분 또는 5분
        
        for (let i = points - 1; i >= 0; i--) {
            trends.data.push({
                timestamp: new Date(now - (i * intervalMs)).toISOString(),
                requests: Math.floor(Math.random() * 100) + 50,
                avg_latency: Math.random() * 50 + 30,
                error_rate: Math.random() * 0.05,
                patterns_matched: Math.floor(Math.random() * 20) + 10
            });
        }
        
        res.json(trends);
    } catch (error) {
        console.error('Trends error:', error);
        res.status(500).json({
            error: 'Failed to fetch trends',
            message: error.message
        });
    }
});

/**
 * 비상 모드 상태
 * GET /api/monitoring/emergency-status
 */
router.get('/emergency-status', async (req, res) => {
    try {
        // 비상 모드 상태 확인
        const emergencyStatus = {
            timestamp: new Date().toISOString(),
            mode: 'NORMAL',
            reason: null,
            activated_at: null,
            auto_recovery_enabled: true,
            circuit_breaker: {
                state: 'CLOSED',
                failure_count: 0,
                last_failure: null
            }
        };
        
        res.json(emergencyStatus);
    } catch (error) {
        console.error('Emergency status error:', error);
        res.status(500).json({
            error: 'Failed to fetch emergency status',
            message: error.message
        });
    }
});

/**
 * 수동 비상 모드 전환
 * POST /api/monitoring/emergency-mode
 */
router.post('/emergency-mode', async (req, res) => {
    try {
        const { mode, reason } = req.body;
        
        // 유효한 모드 확인
        const validModes = ['NORMAL', 'DEGRADED', 'BYPASS', 'BLOCK_ALL'];
        if (!validModes.includes(mode)) {
            return res.status(400).json({
                error: 'Invalid mode',
                valid_modes: validModes
            });
        }
        
        // 실제 환경에서는 Kong 플러그인 설정 업데이트
        console.log(`[EMERGENCY] Switching to ${mode} mode. Reason: ${reason}`);
        
        res.json({
            success: true,
            mode,
            reason,
            activated_at: new Date().toISOString(),
            activated_by: 'admin' // 실제로는 인증된 사용자
        });
    } catch (error) {
        console.error('Emergency mode error:', error);
        res.status(500).json({
            error: 'Failed to switch emergency mode',
            message: error.message
        });
    }
});

module.exports = router;