# Kong AWS Masker - System Metrics Definition

## Overview

This document defines the key metrics for monitoring the Kong AWS Masker system's reliability, performance, and health.

## Metric Categories

### 1. Availability Metrics

#### System Uptime
- **Metric**: `system.uptime.percentage`
- **Target**: 99.9% (Three nines)
- **Calculation**: (Total time - Downtime) / Total time * 100
- **Collection**: Every 60 seconds
- **Alert Threshold**: < 99.5%

#### Service Availability
- **Metrics**:
  - `kong.availability`
  - `redis.availability`
  - `backend.availability`
  - `nginx.availability`
- **Target**: 99.95% per service
- **Collection**: Every 30 seconds
- **Alert Threshold**: Any service < 99%

### 2. Performance Metrics

#### Request Latency
- **Metrics**:
  - `request.latency.p50` - 50th percentile
  - `request.latency.p95` - 95th percentile
  - `request.latency.p99` - 99th percentile
- **Targets**:
  - P50: < 50ms
  - P95: < 200ms
  - P99: < 500ms
- **Collection**: Real-time
- **Alert Thresholds**:
  - P95 > 300ms
  - P99 > 1000ms

#### Throughput
- **Metric**: `request.rate`
- **Target**: > 10,000 requests/second
- **Collection**: Every 10 seconds
- **Alert Threshold**: < 1,000 req/s under normal load

#### Masking Performance
- **Metrics**:
  - `masking.latency.avg` - Average masking time
  - `masking.success.rate` - Successful masking percentage
  - `masking.patterns.matched` - Patterns matched per request
- **Targets**:
  - Latency: < 1ms
  - Success Rate: > 99.9%
- **Collection**: Per request
- **Alert Threshold**: Success rate < 99%

### 3. Resource Utilization

#### CPU Usage
- **Metrics**:
  - `cpu.usage.kong`
  - `cpu.usage.redis`
  - `cpu.usage.backend`
- **Target**: < 70% average, < 90% peak
- **Collection**: Every 30 seconds
- **Alert Thresholds**:
  - Average > 80%
  - Peak > 95%

#### Memory Usage
- **Metrics**:
  - `memory.usage.kong`
  - `memory.usage.redis`
  - `memory.usage.backend`
- **Targets**:
  - Kong: < 1GB
  - Redis: < 512MB
  - Backend: < 512MB
- **Collection**: Every 30 seconds
- **Alert Threshold**: > 90% of allocated memory

#### Network I/O
- **Metrics**:
  - `network.in.bytes`
  - `network.out.bytes`
  - `network.connections.active`
- **Collection**: Every 10 seconds
- **Alert Threshold**: Active connections > 10,000

### 4. Error Metrics

#### Error Rates
- **Metrics**:
  - `error.rate.4xx` - Client errors
  - `error.rate.5xx` - Server errors
  - `error.rate.timeout` - Request timeouts
- **Targets**:
  - 4xx: < 5%
  - 5xx: < 0.1%
  - Timeouts: < 0.01%
- **Collection**: Real-time
- **Alert Thresholds**:
  - 5xx > 1%
  - Timeouts > 0.1%

#### Kong Plugin Errors
- **Metrics**:
  - `kong.plugin.aws_masker.errors`
  - `kong.plugin.aws_masker.failures`
- **Target**: < 0.01%
- **Collection**: Per request
- **Alert Threshold**: > 0.1%

### 5. Business Metrics

#### Masking Efficiency
- **Metrics**:
  - `masking.coverage` - Percentage of AWS resources masked
  - `masking.false_positives` - Incorrectly masked non-AWS data
  - `masking.false_negatives` - Missed AWS resources
- **Targets**:
  - Coverage: > 99.9%
  - False Positives: < 0.1%
  - False Negatives: < 0.1%
- **Collection**: Daily analysis
- **Alert Threshold**: Coverage < 99%

#### API Usage
- **Metrics**:
  - `api.requests.total`
  - `api.requests.by_endpoint`
  - `api.unique_clients`
- **Collection**: Hourly aggregation

### 6. Security Metrics

#### Authentication
- **Metrics**:
  - `auth.attempts.total`
  - `auth.failures.rate`
  - `auth.suspicious.activity`
- **Target**: Failure rate < 1%
- **Collection**: Real-time
- **Alert Threshold**: Failure rate > 5%

#### Data Protection
- **Metrics**:
  - `data.masked.volume` - Amount of data masked
  - `data.leaked.incidents` - Data leak incidents
- **Target**: Zero data leaks
- **Collection**: Continuous
- **Alert Threshold**: Any data leak incident

## Metric Collection Architecture

### Collection Methods

1. **Kong Metrics**
   - Prometheus plugin for Kong
   - Custom Lua metrics in aws-masker plugin
   - Admin API polling

2. **Redis Metrics**
   - Redis INFO command
   - Custom Lua scripts for business metrics
   - Keyspace notifications

3. **Backend Metrics**
   - Application-level instrumentation
   - Health endpoint polling
   - Custom metrics API

4. **System Metrics**
   - Docker stats API
   - Host system monitoring
   - Network interface statistics

### Storage and Retention

- **Real-time Metrics**: 24 hours in memory
- **Aggregated Metrics**: 30 days in Redis
- **Historical Data**: 90 days in compressed logs
- **Compliance Data**: 7 years in cold storage

## Alert Configuration

### Severity Levels

1. **Critical** - Immediate action required
   - System down
   - Data leak detected
   - Security breach

2. **Warning** - Investigation needed
   - Performance degradation
   - High error rates
   - Resource constraints

3. **Info** - Monitoring only
   - Normal fluctuations
   - Scheduled maintenance
   - Configuration changes

### Alert Channels

- **Critical**: PagerDuty, SMS, Phone call
- **Warning**: Email, Slack, Dashboard
- **Info**: Dashboard, Logs

## SLI/SLO Definitions

### Service Level Indicators (SLIs)

1. **Availability SLI**: Percentage of successful health checks
2. **Latency SLI**: 95th percentile request latency
3. **Error SLI**: Percentage of non-5xx responses
4. **Masking SLI**: Percentage of correctly masked resources

### Service Level Objectives (SLOs)

- **Availability SLO**: 99.9% uptime per month
- **Latency SLO**: 95% of requests < 200ms
- **Error SLO**: 99.9% success rate
- **Masking SLO**: 99.95% accuracy

### Error Budget

- **Monthly Error Budget**: 43.2 minutes downtime
- **Latency Budget**: 5% of requests can exceed 200ms
- **Error Rate Budget**: 0.1% error rate allowed

## Monitoring Dashboard Requirements

### Real-time Views
- Service health status
- Current request rate
- Active connections
- Error rate trends

### Historical Analysis
- Daily/weekly/monthly trends
- Peak usage patterns
- Incident correlation
- Capacity planning

### Alerting Dashboard
- Active alerts
- Alert history
- Escalation status
- MTTR tracking

## Compliance and Reporting

### Regulatory Requirements
- GDPR compliance metrics
- Data residency tracking
- Audit trail completeness
- Security incident reporting

### Business Reports
- Monthly uptime report
- Performance summary
- Capacity utilization
- Cost per transaction

## Implementation Checklist

- [ ] Configure Prometheus for Kong
- [ ] Set up Redis metrics collection
- [ ] Implement custom business metrics
- [ ] Create Grafana dashboards
- [ ] Configure alert rules
- [ ] Set up alert channels
- [ ] Implement metric aggregation
- [ ] Create compliance reports
- [ ] Test metric accuracy
- [ ] Document metric formulas