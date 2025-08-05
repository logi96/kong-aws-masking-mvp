#!/bin/bash

# Claude Code Logging Wrapper
# This script wraps the Claude SDK to log all requests and responses

# Configuration
LOG_DIR="/home/claude/logs"
REQUEST_LOG="$LOG_DIR/requests.log"
RESPONSE_LOG="$LOG_DIR/responses.log"
TIMESTAMP=$(date -Iseconds)
REQUEST_ID="${REQUEST_ID:-$(date +%s%N)-$$}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to log JSON data
log_json() {
    local log_file=$1
    local stage=$2
    local data=$3
    
    echo "{\"timestamp\":\"$TIMESTAMP\",\"request_id\":\"$REQUEST_ID\",\"stage\":\"$stage\",\"data\":$data}" >> "$log_file"
}

# Function to intercept Claude Code commands
claude_code_command() {
    local cmd="$@"
    local start_time=$(date +%s.%N)
    
    # Log the request
    log_json "$REQUEST_LOG" "claude_code_request" "{\"command\":\"$cmd\",\"start_time\":\"$start_time\"}"
    
    # Set request ID header for downstream tracking
    export ANTHROPIC_EXTRA_HEADERS="X-Request-ID: $REQUEST_ID"
    
    # Execute the actual command and capture output
    local temp_output=$(mktemp)
    local temp_error=$(mktemp)
    
    # Run the command with output capture
    if claude-code $cmd > "$temp_output" 2> "$temp_error"; then
        local exit_code=0
    else
        local exit_code=$?
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    # Read captured output
    local output=$(cat "$temp_output")
    local error=$(cat "$temp_error")
    
    # Log the response
    log_json "$RESPONSE_LOG" "claude_code_response" "{\"command\":\"$cmd\",\"exit_code\":$exit_code,\"duration\":$duration,\"output_size\":${#output},\"error_size\":${#error}}"
    
    # Display output to user
    if [ -s "$temp_output" ]; then
        cat "$temp_output"
    fi
    if [ -s "$temp_error" ]; then
        cat "$temp_error" >&2
    fi
    
    # Cleanup
    rm -f "$temp_output" "$temp_error"
    
    return $exit_code
}

# Main execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <claude-code-command>"
    echo "Example: $0 'analyze AWS infrastructure'"
    exit 1
fi

# Export request ID for correlation
export REQUEST_ID

# Log wrapper start
log_json "$REQUEST_LOG" "wrapper_start" "{\"args\":\"$*\"}"

# Execute wrapped command
claude_code_command "$@"

# Log wrapper end
log_json "$RESPONSE_LOG" "wrapper_end" "{\"request_id\":\"$REQUEST_ID\"}"