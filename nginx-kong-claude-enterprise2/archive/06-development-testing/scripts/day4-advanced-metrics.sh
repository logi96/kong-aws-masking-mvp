#!/bin/bash

# Day 4 Advanced Metrics Collection System
# Purpose: Collect AWS masking performance metrics, response times, and Kong plugin metrics
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create required directories
mkdir -p "${PROJECT_ROOT}/logs/monitoring/day4"
mkdir -p "${PROJECT_ROOT}/monitoring/metrics"
mkdir -p "${PROJECT_ROOT}/monitoring/alerts"

# Metrics file locations
METRICS_LOG="${PROJECT_ROOT}/logs/monitoring/day4/advanced-metrics.log"
AWS_MASKING_METRICS="${PROJECT_ROOT}/monitoring/metrics/aws-masking-metrics.json"
RESPONSE_TIME_METRICS="${PROJECT_ROOT}/monitoring/metrics/response-time-metrics.json"
KONG_PLUGIN_METRICS="${PROJECT_ROOT}/monitoring/metrics/kong-plugin-metrics.json"
REDIS_METRICS="${PROJECT_ROOT}/monitoring/metrics/redis-metrics.json"

# Configuration
KONG_ADMIN_URL="http://localhost:8001"
BACKEND_URL="http://localhost:8085"
REDIS_CLI_CMD="docker exec claude-redis redis-cli"

# Functions
log_message() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a "$METRICS_LOG"
}

# AWS Masking Success Rate Metrics
collect_aws_masking_metrics() {
    log_message "Collecting AWS masking metrics..."
    
    # Test different AWS resource patterns
    local patterns=(
        "i-1234567890abcdef0"           # EC2 Instance
        "vol-049df61146c4d7901"         # EBS Volume  
        "ami-12345678"                  # AMI
        "sg-903004f8"                   # Security Group
        "subnet-12345678"               # Subnet
        "arn:aws:s3:::my-bucket-name"   # S3 ARN
        "10.0.1.100"                    # Private IP
        "172.16.0.50"                   # Private IP
    )
    
    local total_tests=0
    local successful_masks=0
    local failed_masks=0
    local response_times=()
    
    for pattern in "${patterns[@]}"; do
        local start_time=$(date +%s)
        local start_ms=$(date +%3N)
        
        # Test masking via Kong proxy
        local test_data="{\"model\": \"claude-3-haiku-20240307\", \"max_tokens\": 10, \"messages\": [{\"role\": \"user\", \"content\": \"Test AWS resource: $pattern\"}]}"
        
        local response=$(curl -s -w "%{http_code}|%{time_total}" \
            -X POST "$BACKEND_URL/v1/messages" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer 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" \
            -d "$test_data" 2>/dev/null || echo "000|99.999")
        
        local end_time=$(date +%s)
        local end_ms=$(date +%3N)
        local response_time=$(( (end_time - start_time) * 1000 + (end_ms - start_ms) ))
        
        # Parse response
        local http_code=$(echo "$response" | tail -c 10 | cut -d'|' -f1)
        local curl_time=$(echo "$response" | tail -c 10 | cut -d'|' -f2)
        
        total_tests=$((total_tests + 1))
        response_times+=("$response_time")
        
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            successful_masks=$((successful_masks + 1))
            log_message "✅ Pattern '$pattern' masked successfully (${response_time}ms)"
        else
            failed_masks=$((failed_masks + 1))
            log_message "❌ Pattern '$pattern' masking failed (HTTP: $http_code, ${response_time}ms)"
        fi
        
        sleep 1  # Rate limiting
    done
    
    # Calculate statistics
    local success_rate=$((successful_masks * 100 / total_tests))
    local failure_rate=$((failed_masks * 100 / total_tests))
    
    # Calculate response time percentiles
    IFS=$'\n' sorted_times=($(sort -n <<<"${response_times[*]}"))
    local count=${#sorted_times[@]}
    local p50_index=$((count * 50 / 100))
    local p95_index=$((count * 95 / 100))
    local p99_index=$((count * 99 / 100))
    
    local p50=${sorted_times[$p50_index]:-0}
    local p95=${sorted_times[$p95_index]:-0}
    local p99=${sorted_times[$p99_index]:-0}
    
    # Generate metrics JSON
    cat > "$AWS_MASKING_METRICS" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_masking_metrics": {
        "total_tests": $total_tests,
        "successful_masks": $successful_masks,
        "failed_masks": $failed_masks,
        "success_rate_percent": $success_rate,
        "failure_rate_percent": $failure_rate,
        "response_times": {
            "p50_ms": $p50,
            "p95_ms": $p95,
            "p99_ms": $p99,
            "samples": $count
        },
        "test_patterns": [
            $(printf '"%s",' "${patterns[@]}" | sed 's/,$//')
        ]
    }
}
EOF
    
    log_message "AWS masking metrics collected: ${success_rate}% success rate"
}

# Kong Plugin Performance Metrics
collect_kong_plugin_metrics() {
    log_message "Collecting Kong plugin performance metrics..."
    
    # Get Kong status
    local kong_status=$(curl -s "$KONG_ADMIN_URL/status" 2>/dev/null || echo '{"error": "unavailable"}')
    
    # Get plugin information
    local plugins_info=$(curl -s "$KONG_ADMIN_URL/plugins" 2>/dev/null || echo '{"data": []}')
    
    # Get service information
    local services_info=$(curl -s "$KONG_ADMIN_URL/services" 2>/dev/null || echo '{"data": []}')
    
    # Extract key metrics
    local memory_lua=$(echo "$kong_status" | jq -r '.memory.lua_shared_dicts // "N/A"' 2>/dev/null || echo "N/A")
    local connections=$(echo "$kong_status" | jq -r '.server.connections_handled // 0' 2>/dev/null || echo "0")
    
    # Generate Kong plugin metrics JSON
    cat > "$KONG_PLUGIN_METRICS" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "kong_plugin_metrics": {
        "status": {
            "memory_lua": "$memory_lua",
            "connections_handled": $connections,
            "server_status": "$(echo "$kong_status" | jq -r '.server.health // "unknown"' 2>/dev/null || echo "unknown")"
        },
        "plugins": {
            "total_enabled": $(echo "$plugins_info" | jq '.data | length' 2>/dev/null || echo "0"),
            "aws_masker_status": "$(echo "$plugins_info" | jq -r '.data[] | select(.name=="aws-masker") | .enabled // false' 2>/dev/null || echo "false")"
        },
        "services": {
            "total_services": $(echo "$services_info" | jq '.data | length' 2>/dev/null || echo "0"),
            "claude_service_active": "$(echo "$services_info" | jq -r '.data[] | select(.name=="claude-service") | .enabled // false' 2>/dev/null || echo "false")"
        }
    }
}
EOF
    
    log_message "Kong plugin metrics collected successfully"
}

# Redis Metrics Collection
collect_redis_metrics() {
    log_message "Collecting Redis metrics..."
    
    # Get Redis info
    local redis_info=$($REDIS_CLI_CMD INFO 2>/dev/null || echo "# Error: Redis unavailable")
    local redis_memory=$($REDIS_CLI_CMD INFO memory 2>/dev/null || echo "# Error: Redis unavailable")
    local redis_stats=$($REDIS_CLI_CMD INFO stats 2>/dev/null || echo "# Error: Redis unavailable")
    
    # Get key count
    local total_keys=$($REDIS_CLI_CMD DBSIZE 2>/dev/null || echo "0")
    
    # Extract metrics
    local used_memory=$(echo "$redis_memory" | grep "used_memory:" | cut -d: -f2 | tr -d '\r' || echo "0")
    local used_memory_human=$(echo "$redis_memory" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r' || echo "N/A")
    local connected_clients=$(echo "$redis_info" | grep "connected_clients:" | cut -d: -f2 | tr -d '\r' || echo "0")
    local total_commands=$(echo "$redis_stats" | grep "total_commands_processed:" | cut -d: -f2 | tr -d '\r' || echo "0")
    
    # Get masking-specific keys
    local masking_keys=$($REDIS_CLI_CMD KEYS "mask:*" 2>/dev/null | wc -l || echo "0")
    local unmask_keys=$($REDIS_CLI_CMD KEYS "unmask:*" 2>/dev/null | wc -l || echo "0")
    
    # Generate Redis metrics JSON
    cat > "$REDIS_METRICS" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "redis_metrics": {
        "memory": {
            "used_memory_bytes": $used_memory,
            "used_memory_human": "$used_memory_human",
            "total_keys": $total_keys
        },
        "connections": {
            "connected_clients": $connected_clients,
            "total_commands_processed": $total_commands
        },
        "masking_data": {
            "mask_keys": $masking_keys,
            "unmask_keys": $unmask_keys,
            "total_mapping_keys": $((masking_keys + unmask_keys))
        }
    }
}
EOF
    
    log_message "Redis metrics collected: $total_keys total keys, $masking_keys masking mappings"
}

# Response Time Statistics
collect_response_time_metrics() {
    log_message "Collecting detailed response time metrics..."
    
    local test_endpoints=(
        "$BACKEND_URL/health"
        "$BACKEND_URL/v1/messages"
    )
    
    local endpoint_metrics=()
    
    for endpoint in "${test_endpoints[@]}"; do
        local response_times=()
        local successful_requests=0
        local failed_requests=0
        
        # Perform 10 test requests per endpoint
        for i in {1..10}; do
            local start_time=$(date +%s)
            local start_ms=$(date +%3N)
            
            if [[ "$endpoint" == *"/health" ]]; then
                local response=$(curl -s -w "%{http_code}" "$endpoint" 2>/dev/null || echo "000")
            else
                local test_data='{"model": "claude-3-haiku-20240307", "max_tokens": 10, "messages": [{"role": "user", "content": "test"}]}'
                local response=$(curl -s -w "%{http_code}" \
                    -X POST "$endpoint" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer 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" \
                    -d "$test_data" 2>/dev/null || echo "000")
            fi
            
            local end_time=$(date +%s)
            local end_ms=$(date +%3N)
            local response_time=$(( (end_time - start_time) * 1000 + (end_ms - start_ms) ))
            
            local http_code=$(echo "$response" | tail -c 3)
            
            if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
                successful_requests=$((successful_requests + 1))
                response_times+=("$response_time")
            else
                failed_requests=$((failed_requests + 1))
            fi
            
            sleep 0.5  # Rate limiting between requests
        done
        
        # Calculate statistics for this endpoint
        if [[ ${#response_times[@]} -gt 0 ]]; then
            IFS=$'\n' sorted_times=($(sort -n <<<"${response_times[*]}"))
            local count=${#sorted_times[@]}
            local p50_index=$((count * 50 / 100))
            local p95_index=$((count * 95 / 100))
            local p99_index=$((count * 99 / 100))
            
            local p50=${sorted_times[$p50_index]:-0}
            local p95=${sorted_times[$p95_index]:-0}
            local p99=${sorted_times[$p99_index]:-0}
            
            # Calculate average
            local sum=0
            for time in "${response_times[@]}"; do
                sum=$((sum + time))
            done
            local avg=$((sum / count))
            
            endpoint_metrics+=("{
                \"endpoint\": \"$endpoint\",
                \"successful_requests\": $successful_requests,
                \"failed_requests\": $failed_requests,
                \"response_times\": {
                    \"avg_ms\": $avg,
                    \"p50_ms\": $p50,
                    \"p95_ms\": $p95,
                    \"p99_ms\": $p99,
                    \"min_ms\": ${sorted_times[0]},
                    \"max_ms\": ${sorted_times[-1]},
                    \"samples\": $count
                }
            }")
        fi
    done
    
    # Generate response time metrics JSON
    cat > "$RESPONSE_TIME_METRICS" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "response_time_metrics": {
        "endpoints": [
            $(printf '%s,' "${endpoint_metrics[@]}" | sed 's/,$//')
        ]
    }
}
EOF
    
    log_message "Response time metrics collected for ${#endpoint_metrics[@]} endpoints"
}

# Main collection function
collect_all_metrics() {
    log_message "Starting Day 4 advanced metrics collection..."
    
    collect_aws_masking_metrics
    collect_kong_plugin_metrics
    collect_redis_metrics
    collect_response_time_metrics
    
    # Generate consolidated metrics report
    local consolidated_report="${PROJECT_ROOT}/monitoring/metrics/consolidated-metrics-$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$consolidated_report" << EOF
{
    "collection_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "collection_type": "day4_advanced_metrics",
    "metrics": {
        "aws_masking": $(cat "$AWS_MASKING_METRICS" | jq '.aws_masking_metrics'),
        "kong_plugin": $(cat "$KONG_PLUGIN_METRICS" | jq '.kong_plugin_metrics'),
        "redis": $(cat "$REDIS_METRICS" | jq '.redis_metrics'),
        "response_times": $(cat "$RESPONSE_TIME_METRICS" | jq '.response_time_metrics')
    }
}
EOF
    
    log_message "✅ Day 4 advanced metrics collection completed"
    log_message "📊 Consolidated report: $consolidated_report"
    
    # Display summary
    echo
    echo "=== Day 4 Advanced Metrics Summary ==="
    echo "AWS Masking Success Rate: $(cat "$AWS_MASKING_METRICS" | jq -r '.aws_masking_metrics.success_rate_percent')%"
    echo "Redis Total Keys: $(cat "$REDIS_METRICS" | jq -r '.redis_metrics.memory.total_keys')"
    echo "Kong Plugins Enabled: $(cat "$KONG_PLUGIN_METRICS" | jq -r '.kong_plugin_metrics.plugins.total_enabled')"
    echo "Metrics Files Generated: 4"
    echo "======================================="
}

# Main execution
case "${1:-collect}" in
    collect)
        collect_all_metrics
        ;;
    aws-masking)
        collect_aws_masking_metrics
        ;;
    kong-plugin)
        collect_kong_plugin_metrics
        ;;
    redis)
        collect_redis_metrics
        ;;
    response-time)
        collect_response_time_metrics
        ;;
    help)
        echo "Day 4 Advanced Metrics Collection System"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  collect        Collect all advanced metrics (default)"
        echo "  aws-masking    Collect AWS masking performance metrics only"
        echo "  kong-plugin    Collect Kong plugin metrics only"
        echo "  redis          Collect Redis metrics only"
        echo "  response-time  Collect response time metrics only"
        echo "  help           Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac