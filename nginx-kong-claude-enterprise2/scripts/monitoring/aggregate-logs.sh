#!/bin/bash

# Log Aggregation Script
# Correlates logs by request ID across all components

# Configuration
BASE_DIR="/Users/tw.kim/Documents/AGA/test/Kong/nginx-kong-claude-enterprise2"
LOG_DIR="$BASE_DIR/logs"
INTEGRATION_LOG="$LOG_DIR/integration/flow-trace.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to extract logs by request ID
extract_logs_by_request_id() {
    local request_id=$1
    local output_file="${2:-/dev/stdout}"
    
    echo -e "${BLUE}=== Flow Trace for Request ID: $request_id ===${NC}" > "$output_file"
    echo >> "$output_file"
    
    # 1. Claude Code SDK Request
    echo -e "${CYAN}[1] Claude Code SDK Request:${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/claude-code-sdk/requests.log" ]; then
        grep "\"request_id\":\"$request_id\"" "$LOG_DIR/claude-code-sdk/requests.log" | jq '.' >> "$output_file" 2>/dev/null || \
        grep "$request_id" "$LOG_DIR/claude-code-sdk/requests.log" >> "$output_file"
    fi
    echo >> "$output_file"
    
    # 2. Nginx Access Logs
    echo -e "${GREEN}[2] Nginx Proxy (Port 8082):${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/nginx/claude-proxy-access.log" ]; then
        grep "\"request_id\":\"$request_id\"" "$LOG_DIR/nginx/claude-proxy-access.log" | jq '.' >> "$output_file" 2>/dev/null || \
        grep "$request_id" "$LOG_DIR/nginx/claude-proxy-access.log" >> "$output_file"
    fi
    echo >> "$output_file"
    
    # 3. Kong Masking Events
    echo -e "${YELLOW}[3] Kong Masking Events:${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/kong/access.log" ]; then
        grep "$request_id.*MASKING-EVENT" "$LOG_DIR/kong/access.log" | while read line; do
            echo "$line" | sed 's/.*\[MASKING-EVENT\] //' | jq '.' >> "$output_file" 2>/dev/null || echo "$line" >> "$output_file"
        done
    fi
    echo >> "$output_file"
    
    # 4. Kong to Claude API
    echo -e "${PURPLE}[4] Kong → Claude API:${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/kong/access.log" ]; then
        grep "$request_id.*api.anthropic.com" "$LOG_DIR/kong/access.log" >> "$output_file"
    fi
    echo >> "$output_file"
    
    # 5. Kong Unmasking Events
    echo -e "${YELLOW}[5] Kong Unmasking Events:${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/kong/access.log" ]; then
        grep "$request_id.*UNMASK-EVENT" "$LOG_DIR/kong/access.log" | while read line; do
            echo "$line" | sed 's/.*\[UNMASK-EVENT\] //' | jq '.' >> "$output_file" 2>/dev/null || echo "$line" >> "$output_file"
        done
    fi
    echo >> "$output_file"
    
    # 6. Response back through Nginx
    echo -e "${GREEN}[6] Nginx Response:${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/nginx/claude-proxy-proxy.log" ]; then
        grep "\"request_id\":\"$request_id\"" "$LOG_DIR/nginx/claude-proxy-proxy.log" | jq '.' >> "$output_file" 2>/dev/null || \
        grep "$request_id" "$LOG_DIR/nginx/claude-proxy-proxy.log" >> "$output_file"
    fi
    echo >> "$output_file"
    
    # 7. Claude Code SDK Response
    echo -e "${CYAN}[7] Claude Code SDK Response:${NC}" >> "$output_file"
    if [ -f "$LOG_DIR/claude-code-sdk/responses.log" ]; then
        grep "\"request_id\":\"$request_id\"" "$LOG_DIR/claude-code-sdk/responses.log" | jq '.' >> "$output_file" 2>/dev/null || \
        grep "$request_id" "$LOG_DIR/claude-code-sdk/responses.log" >> "$output_file"
    fi
    echo >> "$output_file"
    
    # Summary
    echo -e "${BLUE}=== Flow Summary ===${NC}" >> "$output_file"
    echo "Request Flow: SDK → Nginx(8082) → Kong(8010) → Claude API" >> "$output_file"
    echo "Response Flow: Claude API → Kong(unmask) → Nginx → SDK" >> "$output_file"
}

# Function to show recent request IDs
show_recent_requests() {
    echo -e "${BLUE}Recent Request IDs:${NC}"
    
    # Collect unique request IDs from all logs
    local request_ids=""
    
    # From Nginx logs
    if [ -f "$LOG_DIR/nginx/claude-proxy-access.log" ]; then
        request_ids+=$(grep -oE '"request_id":"[^"]+' "$LOG_DIR/nginx/claude-proxy-access.log" | cut -d'"' -f4 | tail -20)
        request_ids+="\n"
    fi
    
    # From Kong logs
    if [ -f "$LOG_DIR/kong/access.log" ]; then
        request_ids+=$(grep -oE 'request_id=[^ ]+' "$LOG_DIR/kong/access.log" | cut -d'=' -f2 | tail -20)
        request_ids+="\n"
    fi
    
    # Show unique IDs with timestamps
    echo -e "$request_ids" | sort -u | tail -10
}

# Function to monitor logs in real-time
monitor_flow() {
    echo -e "${BLUE}Monitoring request flow in real-time...${NC}"
    echo "Press Ctrl+C to stop"
    echo
    
    # Use multitail if available, otherwise use tail
    if command -v multitail &> /dev/null; then
        multitail \
            -l "tail -f $LOG_DIR/nginx/claude-proxy-access.log | grep --line-buffered 'request_id'" \
            -l "tail -f $LOG_DIR/kong/access.log | grep --line-buffered -E 'MASKING-EVENT|UNMASK-EVENT|request_id'" \
            -l "tail -f $LOG_DIR/claude-code-sdk/requests.log 2>/dev/null || echo 'SDK logs not available'"
    else
        tail -f "$LOG_DIR/nginx/claude-proxy-access.log" "$LOG_DIR/kong/access.log" | \
            grep --line-buffered -E "request_id|MASKING-EVENT|UNMASK-EVENT"
    fi
}

# Function to generate flow report
generate_flow_report() {
    local request_id=$1
    local report_file="$LOG_DIR/integration/flow-report-${request_id}.html"
    
    mkdir -p "$LOG_DIR/integration"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Request Flow Report: $request_id</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .stage { margin: 20px 0; padding: 15px; background: #f9f9f9; border-left: 4px solid #007bff; border-radius: 4px; }
        .stage h3 { margin-top: 0; color: #007bff; }
        .log-entry { font-family: monospace; font-size: 12px; background: #272822; color: #f8f8f2; padding: 10px; border-radius: 4px; overflow-x: auto; }
        .metric { display: inline-block; margin: 5px 10px; padding: 5px 10px; background: #e9ecef; border-radius: 3px; }
        .flow-diagram { text-align: center; margin: 20px 0; }
        .arrow { font-size: 24px; color: #28a745; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Request Flow Report</h1>
        <p><strong>Request ID:</strong> $request_id</p>
        <p><strong>Generated:</strong> $(date)</p>
        
        <div class="flow-diagram">
            <span>Claude SDK</span> <span class="arrow">→</span>
            <span>Nginx (8082)</span> <span class="arrow">→</span>
            <span>Kong (8010)</span> <span class="arrow">→</span>
            <span>Claude API</span>
        </div>
        
        <div class="stage">
            <h3>1. Claude Code SDK Request</h3>
            <div class="log-entry">
$(grep "$request_id" "$LOG_DIR/claude-code-sdk/requests.log" 2>/dev/null | head -1 | jq '.' 2>/dev/null || echo "No SDK logs found")
            </div>
        </div>
        
        <div class="stage">
            <h3>2. Nginx Proxy Processing</h3>
            <div class="log-entry">
$(grep "$request_id" "$LOG_DIR/nginx/claude-proxy-access.log" 2>/dev/null | head -1 | jq '.' 2>/dev/null || echo "No Nginx logs found")
            </div>
        </div>
        
        <div class="stage">
            <h3>3. Kong AWS Masking</h3>
            <div class="log-entry">
$(grep "$request_id.*MASKING-EVENT" "$LOG_DIR/kong/access.log" 2>/dev/null | head -1 | sed 's/.*\[MASKING-EVENT\] //' | jq '.' 2>/dev/null || echo "No masking logs found")
            </div>
        </div>
        
        <div class="stage">
            <h3>4. Kong AWS Unmasking</h3>
            <div class="log-entry">
$(grep "$request_id.*UNMASK-EVENT" "$LOG_DIR/kong/access.log" 2>/dev/null | head -1 | sed 's/.*\[UNMASK-EVENT\] //' | jq '.' 2>/dev/null || echo "No unmasking logs found")
            </div>
        </div>
    </div>
</body>
</html>
EOF
    
    echo -e "${GREEN}Flow report generated: $report_file${NC}"
}

# Main script logic
case "${1:-help}" in
    trace)
        if [ -z "$2" ]; then
            echo "Usage: $0 trace <request-id>"
            exit 1
        fi
        extract_logs_by_request_id "$2"
        ;;
    recent)
        show_recent_requests
        ;;
    monitor)
        monitor_flow
        ;;
    report)
        if [ -z "$2" ]; then
            echo "Usage: $0 report <request-id>"
            exit 1
        fi
        generate_flow_report "$2"
        ;;
    *)
        echo -e "${BLUE}Kong AWS Masking - Log Aggregation Tool${NC}"
        echo
        echo "Usage: $0 [command] [options]"
        echo
        echo "Commands:"
        echo "  trace <request-id>    Extract and display flow trace for a specific request"
        echo "  recent               Show recent request IDs"
        echo "  monitor              Monitor request flow in real-time"
        echo "  report <request-id>  Generate HTML report for a request"
        echo
        echo "Examples:"
        echo "  $0 recent"
        echo "  $0 trace 1234567890-1-1"
        echo "  $0 monitor"
        echo "  $0 report 1234567890-1-1"
        ;;
esac