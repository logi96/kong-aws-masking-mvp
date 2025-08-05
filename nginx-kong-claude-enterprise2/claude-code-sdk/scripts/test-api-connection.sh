#!/bin/sh
# Test Claude Code SDK API connection

echo "=== Claude Code SDK API Connection Test ==="
echo "Test Time: $(date)"
echo ""

# 1. Check environment variable
echo "1. Checking API Key environment variable..."
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "✅ API Key is set (first 10 chars): ${ANTHROPIC_API_KEY:0:10}..."
else
    echo "❌ API Key is not set"
    exit 1
fi
echo ""

# 2. Test version command
echo "2. Testing Claude version..."
claude --version
echo ""

# 3. Test simple headless query
echo "3. Testing headless mode with simple query..."
claude -p "Hello Claude, please respond with: 'API connection successful'" 2>&1 | tee /home/claude/logs/api-test.log
echo ""

# 4. Test JSON output
echo "4. Testing JSON output format..."
claude -p "What is 2+2?" --output-format json 2>&1 | tee /home/claude/logs/json-test.log
echo ""

# 5. Check proxy settings
echo "5. Checking proxy configuration..."
echo "HTTP_PROXY: $HTTP_PROXY"
echo "HTTPS_PROXY: $HTTPS_PROXY"
echo "NO_PROXY: $NO_PROXY"
echo ""

echo "=== Test Complete ==="