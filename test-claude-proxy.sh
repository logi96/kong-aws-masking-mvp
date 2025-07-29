#!/bin/bash

echo "=== Claude Code Proxy Support Validation ==="
echo "Testing various proxy configurations..."
echo

# Test 1: Check if ANTHROPIC_BASE_URL is recognized
echo "Test 1: ANTHROPIC_BASE_URL Environment Variable"
echo "-----------------------------------------------"
export ANTHROPIC_BASE_URL="http://localhost:8000"
echo "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
# Note: We can't actually run 'claude' command here as it's the current process
echo

# Test 2: Check HTTP_PROXY support
echo "Test 2: HTTP_PROXY Environment Variable"
echo "---------------------------------------"
export HTTP_PROXY="http://localhost:8000"
export HTTPS_PROXY="http://localhost:8000"
echo "HTTP_PROXY=$HTTP_PROXY"
echo "HTTPS_PROXY=$HTTPS_PROXY"
echo

# Test 3: Create a test settings.json
echo "Test 3: Settings.json Configuration"
echo "-----------------------------------"
cat > ~/.claude/settings.json.test << EOF
{
  "model": "opus",
  "env": {
    "ANTHROPIC_BASE_URL": "http://kong:8000",
    "HTTP_PROXY": "http://kong:8000"
  }
}
EOF
echo "Created test settings.json with proxy config"
cat ~/.claude/settings.json.test
echo

# Test 4: Network connectivity test
echo "Test 4: Network Connectivity Test"
echo "---------------------------------"
echo "Testing if Kong is reachable on port 8000..."
nc -zv localhost 8000 2>&1 || echo "Kong not running on localhost:8000"
echo

# Test 5: Check if we can see Claude's actual network requests
echo "Test 5: Checking for Network Debugging Options"
echo "----------------------------------------------"
echo "Looking for debug/verbose options in Claude..."
which claude 2>/dev/null && claude --help 2>&1 | grep -i "debug\|verbose\|proxy" || echo "Claude CLI not found in PATH"