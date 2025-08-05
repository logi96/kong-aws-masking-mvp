#!/bin/bash

# Real-time Request Flow Monitor
# Visualizes requests flowing through the proxy chain

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
LOG_DIR="/Users/tw.kim/Documents/AGA/test/Kong/nginx-kong-claude-enterprise2/logs"
REFRESH_RATE=1

# Clear screen and set up display
clear
echo -e "${WHITE}Kong AWS Masking - Real-time Flow Monitor${NC}"
echo -e "${WHITE}===========================================${NC}"
echo

# Function to format timestamp
format_time() {
    echo "$1" | cut -d'T' -f2 | cut -d'+' -f1
}

# Function to extract request ID
get_request_id() {
    echo "$1" | grep -oE '"request_id":"[^"]+' | cut -d'"' -f4
}

# Function to monitor logs
monitor_logs() {
    # Create named pipes for each log source
    mkfifo /tmp/nginx_pipe /tmp/kong_pipe 2>/dev/null || true
    
    # Start tailing logs in background
    tail -f "$LOG_DIR/nginx/claude-proxy-access.log" 2>/dev/null > /tmp/nginx_pipe &
    NGINX_PID=$!
    
    tail -f "$LOG_DIR/kong/access.log" 2>/dev/null > /tmp/kong_pipe &
    KONG_PID=$!
    
    # Cleanup function
    cleanup() {
        kill $NGINX_PID $KONG_PID 2>/dev/null
        rm -f /tmp/nginx_pipe /tmp/kong_pipe
        echo -e "\n${WHITE}Monitor stopped.${NC}"
        exit 0
    }
    trap cleanup EXIT INT TERM
    
    echo -e "${CYAN}Monitoring request flow... Press Ctrl+C to stop${NC}\n"
    
    # Main monitoring loop
    while true; do
        # Check Nginx logs
        if read -t 0.1 line <> /tmp/nginx_pipe; then
            if [[ "$line" =~ "request_id" ]]; then
                request_id=$(get_request_id "$line")
                timestamp=$(echo "$line" | jq -r '.timestamp' 2>/dev/null | xargs -I {} date -d {} '+%H:%M:%S' 2>/dev/null || echo "??:??:??")
                method=$(echo "$line" | jq -r '.request_method' 2>/dev/null || echo "???")
                uri=$(echo "$line" | jq -r '.request_uri' 2>/dev/null || echo "???")
                status=$(echo "$line" | jq -r '.status' 2>/dev/null || echo "???")
                
                echo -e "${GREEN}[NGINX]${NC} ${WHITE}$timestamp${NC} | ${YELLOW}$method${NC} $uri | Status: ${CYAN}$status${NC} | ID: ${BLUE}$request_id${NC}"
            fi
        fi
        
        # Check Kong logs
        if read -t 0.1 line <> /tmp/kong_pipe; then
            if [[ "$line" =~ "MASKING-EVENT" ]]; then
                request_id=$(echo "$line" | grep -oE 'request_id=[^ ]+' | cut -d'=' -f2)
                masking_data=$(echo "$line" | sed 's/.*\[MASKING-EVENT\] //')
                mask_count=$(echo "$masking_data" | jq -r '.mask_count' 2>/dev/null || echo "?")
                process_time=$(echo "$masking_data" | jq -r '.processing_time_ms' 2>/dev/null || echo "?")
                
                echo -e "  ${PURPLE}↓ [KONG-MASK]${NC} Masked ${WHITE}$mask_count${NC} items in ${YELLOW}${process_time}ms${NC}"
                
                # Show patterns used
                patterns=$(echo "$masking_data" | jq -r '.patterns_used | to_entries[] | "\(.key): \(.value)"' 2>/dev/null)
                if [ -n "$patterns" ]; then
                    echo "$patterns" | while read pattern; do
                        echo -e "    ${CYAN}→${NC} $pattern"
                    done
                fi
            elif [[ "$line" =~ "UNMASK-EVENT" ]]; then
                request_id=$(echo "$line" | grep -oE 'request_id=[^ ]+' | cut -d'=' -f2)
                unmask_data=$(echo "$line" | sed 's/.*\[UNMASK-EVENT\] //')
                unmask_count=$(echo "$unmask_data" | jq -r '.unmask_count' 2>/dev/null || echo "?")
                process_time=$(echo "$unmask_data" | jq -r '.processing_time_ms' 2>/dev/null || echo "?")
                
                echo -e "  ${PURPLE}↑ [KONG-UNMASK]${NC} Restored ${WHITE}$unmask_count${NC} items in ${YELLOW}${process_time}ms${NC}"
            elif [[ "$line" =~ "REQUEST-START" ]]; then
                request_id=$(echo "$line" | grep -oE 'request_id=[^ ]+' | cut -d'=' -f2)
                body_size=$(echo "$line" | grep -oE 'body_size=[0-9]+' | cut -d'=' -f2)
                
                echo -e "  ${BLUE}→ [KONG-START]${NC} Processing request (${WHITE}$body_size${NC} bytes)"
            fi
        fi
        
        sleep 0.1
    done
}

# Function to show statistics
show_stats() {
    echo -e "\n${WHITE}=== Current Statistics ===${NC}"
    
    # Count recent requests
    if [ -f "$LOG_DIR/nginx/claude-proxy-access.log" ]; then
        total_requests=$(tail -1000 "$LOG_DIR/nginx/claude-proxy-access.log" | grep -c "request_id" || echo 0)
        success_requests=$(tail -1000 "$LOG_DIR/nginx/claude-proxy-access.log" | grep -c '"status":200' || echo 0)
        
        echo -e "Recent Requests: ${WHITE}$total_requests${NC}"
        echo -e "Success Rate: ${GREEN}$((success_requests * 100 / (total_requests + 1)))%${NC}"
    fi
    
    # Average response time
    if [ -f "$LOG_DIR/nginx/claude-proxy-access.log" ]; then
        avg_time=$(tail -100 "$LOG_DIR/nginx/claude-proxy-access.log" | \
            jq -r '.request_time' 2>/dev/null | \
            awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "N/A"}')
        
        echo -e "Avg Response Time: ${YELLOW}${avg_time}s${NC}"
    fi
    
    # Masking statistics
    if [ -f "$LOG_DIR/kong/access.log" ]; then
        mask_events=$(tail -1000 "$LOG_DIR/kong/access.log" | grep -c "MASKING-EVENT" || echo 0)
        avg_mask_time=$(tail -100 "$LOG_DIR/kong/access.log" | \
            grep "MASKING-EVENT" | \
            sed 's/.*\[MASKING-EVENT\] //' | \
            jq -r '.processing_time_ms' 2>/dev/null | \
            awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "N/A"}')
        
        echo -e "Masking Events: ${WHITE}$mask_events${NC}"
        echo -e "Avg Masking Time: ${YELLOW}${avg_mask_time}ms${NC}"
    fi
    
    echo -e "${WHITE}=========================${NC}\n"
}

# Main execution
case "${1:-monitor}" in
    monitor)
        monitor_logs
        ;;
    stats)
        while true; do
            clear
            echo -e "${WHITE}Kong AWS Masking - Statistics Dashboard${NC}"
            echo -e "${WHITE}=======================================${NC}"
            show_stats
            sleep 5
        done
        ;;
    *)
        echo "Usage: $0 [monitor|stats]"
        echo "  monitor - Show real-time request flow"
        echo "  stats   - Show statistics dashboard"
        exit 1
        ;;
esac