# Comprehensive Logging System Guide

## Overview

The Kong AWS Masking system implements end-to-end request/response logging with correlation across all components in the proxy chain:

```
Claude Code SDK → Nginx (8082) → Kong (8010) → Claude API
                ↓                 ↓               ↓
            SDK Logs         Proxy Logs    Masking/Unmasking Logs
```

## Architecture

### 1. Request Flow Logging

#### Claude Code SDK
- **Location**: `/logs/claude-code-sdk/requests.log`
- **Format**: JSON with timestamp, request_id, command, and metadata
- **Wrapper Script**: `claude-code-wrapper.sh` for automatic logging

#### Nginx Proxy (Port 8082)
- **Access Log**: `/logs/nginx/claude-proxy-access.log`
- **Proxy Log**: `/logs/nginx/claude-proxy-proxy.log`
- **Format**: Structured JSON with request details and timing

#### Kong Gateway (Port 8010)
- **Access Log**: `/logs/kong/access.log`
- **Masking Events**: `[MASKING-EVENT]` tagged logs
- **Unmasking Events**: `[UNMASK-EVENT]` tagged logs

### 2. Response Flow Logging

The response flow is logged in reverse order with the same request ID for correlation.

## Log Formats

### Nginx JSON Log Format
```json
{
  "timestamp": "2024-01-29T10:30:45+09:00",
  "request_id": "1706490645-1234-5678",
  "flow_direction": "request",
  "remote_addr": "172.29.0.5",
  "request_method": "POST",
  "request_uri": "/v1/messages",
  "status": 200,
  "request_time": 0.523,
  "upstream_response_time": "0.521"
}
```

### Kong Masking Event Format
```json
{
  "request_id": "1706490645-1234-5678",
  "stage": "masking",
  "original_size": 1024,
  "masked_size": 1050,
  "mask_count": 4,
  "patterns_used": {
    "ec2_instance": 1,
    "s3_bucket": 1,
    "private_ip": 2
  },
  "processing_time_ms": 2.3
}
```

### Kong Unmasking Event Format
```json
{
  "request_id": "1706490645-1234-5678",
  "stage": "unmasking",
  "unmask_count": 4,
  "chunks_processed": 3,
  "processing_time_ms": 1.2
}
```

## Request ID Correlation

### Request ID Generation
1. Client provides via `X-Request-ID` header
2. Nginx generates if missing: `$request_time-$connection-$connection_requests`
3. Kong preserves and forwards the request ID

### Request ID Propagation
- SDK → Nginx: Via `X-Request-ID` header
- Nginx → Kong: Header preserved
- Kong → Claude API: Header forwarded
- All logs: Request ID included in log entries

## Log Aggregation

### Using the Aggregation Script

```bash
# Show recent request IDs
./scripts/aggregate-logs.sh recent

# Trace a specific request
./scripts/aggregate-logs.sh trace <request-id>

# Monitor in real-time
./scripts/aggregate-logs.sh monitor

# Generate HTML report
./scripts/aggregate-logs.sh report <request-id>
```

### Example Flow Trace Output
```
=== Flow Trace for Request ID: 1706490645-1234-5678 ===

[1] Claude Code SDK Request:
{
  "timestamp": "2024-01-29T10:30:45+09:00",
  "request_id": "1706490645-1234-5678",
  "stage": "claude_code_request",
  "command": "analyze AWS infrastructure"
}

[2] Nginx Proxy (Port 8082):
{
  "timestamp": "2024-01-29T10:30:45+09:00",
  "request_id": "1706490645-1234-5678",
  "method": "POST",
  "uri": "/v1/messages",
  "upstream": "kong:8010"
}

[3] Kong Masking Events:
{
  "request_id": "1706490645-1234-5678",
  "stage": "masking",
  "mask_count": 4,
  "processing_time_ms": 2.3
}

[4] Kong → Claude API:
Forwarding masked request to api.anthropic.com

[5] Kong Unmasking Events:
{
  "request_id": "1706490645-1234-5678",
  "stage": "unmasking",
  "unmask_count": 4,
  "processing_time_ms": 1.2
}

[6] Nginx Response:
Status 200, response time 523ms

[7] Claude Code SDK Response:
Response received and displayed to user
```

## Performance Monitoring

### Key Metrics Logged
1. **Request Processing Time**: Total end-to-end time
2. **Masking Latency**: Time to mask AWS resources
3. **Unmasking Latency**: Time to restore original values
4. **Upstream Response Time**: Claude API response time

### Performance Analysis
```bash
# Extract masking performance
grep "MASKING-EVENT" /logs/kong/access.log | \
  jq -r '.processing_time_ms' | \
  awk '{sum+=$1; count++} END {print "Avg masking time:", sum/count, "ms"}'

# Analyze response times
grep "request_id" /logs/nginx/claude-proxy-access.log | \
  jq -r '.request_time' | \
  awk '{sum+=$1; count++} END {print "Avg request time:", sum/count, "s"}'
```

## Debugging Common Issues

### Missing Request Logs
1. Check if request ID is being generated
2. Verify log file permissions
3. Ensure containers have log volume mounts

### Log Correlation Failed
1. Confirm request ID header is preserved
2. Check time synchronization between containers
3. Verify log format consistency

### Performance Issues
1. Monitor masking event processing times
2. Check for pattern matching bottlenecks
3. Analyze chunk processing in unmasking

## Testing the Logging System

Run the comprehensive logging test:
```bash
./tests/test-comprehensive-logging.sh
```

This will:
1. Generate a test request with known request ID
2. Send it through the entire proxy chain
3. Verify logs are generated at each stage
4. Test log correlation and aggregation
5. Generate a test report

## Log Rotation

Configure log rotation in Docker:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

Or use logrotate configuration:
```
/path/to/logs/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        docker exec nginx nginx -s reopen
        docker exec kong kong reload
    endscript
}
```

## Security Considerations

1. **Sensitive Data**: API keys are partially masked in logs
2. **Log Access**: Restrict log directory permissions
3. **Log Retention**: Follow compliance requirements
4. **PII Protection**: Ensure no personal data in logs

## Integration with Monitoring Tools

### Elasticsearch/Logstash
```json
{
  "input": {
    "file": {
      "path": "/logs/*/claude-proxy-access.log",
      "codec": "json"
    }
  },
  "filter": {
    "date": {
      "match": ["timestamp", "ISO8601"]
    }
  },
  "output": {
    "elasticsearch": {
      "hosts": ["localhost:9200"],
      "index": "kong-aws-masking-%{+YYYY.MM.dd}"
    }
  }
}
```

### Prometheus Metrics
Extract metrics from logs for Prometheus:
```bash
# Count requests by status
grep "request_id" /logs/nginx/claude-proxy-access.log | \
  jq -r '.status' | sort | uniq -c
```

## Troubleshooting Commands

```bash
# Find all logs for a request
find /logs -name "*.log" -exec grep -l "request-id-here" {} \;

# Show last 10 masking events
grep "MASKING-EVENT" /logs/kong/access.log | tail -10 | jq '.'

# Monitor real-time errors
tail -f /logs/*/error.log | grep -E "ERROR|WARN"

# Calculate success rate
total=$(grep -c "request_id" /logs/nginx/claude-proxy-access.log)
success=$(grep -c '"status":200' /logs/nginx/claude-proxy-access.log)
echo "Success rate: $((success * 100 / total))%"
```