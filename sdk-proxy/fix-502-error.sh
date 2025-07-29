#!/bin/bash
# Fix 502 Bad Gateway Error Script
# Purpose: Apply fixes for SSL handshake and upstream connection issues

set -e

echo "🔧 Fixing 502 Bad Gateway Error..."
echo "================================="

# 1. Stop existing containers
echo "📦 Stopping existing containers..."
docker-compose down

# 2. Backup original nginx config
echo "💾 Backing up original nginx config..."
cp nginx-proxy/nginx.conf nginx-proxy/nginx.conf.backup

# 3. Apply fixed nginx config
echo "🔄 Applying fixed nginx configuration..."
cp nginx-proxy/nginx-fixed.conf nginx-proxy/nginx.conf

# 4. Clean up logs
echo "🧹 Cleaning up old logs..."
rm -f results/logs/*.log

# 5. Rebuild and start containers
echo "🚀 Starting containers with fixed configuration..."
docker-compose up -d --build

# 6. Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# 7. Check nginx proxy health
echo "🏥 Checking nginx proxy health..."
curl -s http://localhost:8888/health || echo "⚠️  Nginx health check failed"

# 8. Run SDK proxy tests
echo "🧪 Running SDK proxy tests..."
docker-compose run --rm sdk-tester

# 9. Check results
echo "📊 Test Results:"
if [ -f "results/test-results.json" ]; then
    cat results/test-results.json | jq '.summary'
else
    echo "⚠️  No test results found"
fi

# 10. Check for 502 errors in logs
echo "🔍 Checking for 502 errors..."
if grep -q "502" results/logs/claude_errors.log 2>/dev/null; then
    echo "❌ 502 errors still present in logs"
    echo "Recent errors:"
    tail -n 10 results/logs/claude_errors.log
else
    echo "✅ No 502 errors found!"
fi

echo ""
echo "📝 Fix Summary:"
echo "1. Added DNS resolver for proper hostname resolution"
echo "2. Enabled SNI (Server Name Indication) with proxy_ssl_server_name"
echo "3. Set proxy_ssl_name to api.anthropic.com"
echo "4. Updated SSL cipher suite for Claude API compatibility"
echo "5. Added HTTP/1.1 with keep-alive support"
echo "6. Forced IPv4 resolution to avoid IPv6 connectivity issues"

echo ""
echo "🔧 If issues persist, check:"
echo "- Docker network connectivity: docker network inspect sdk-test-net"
echo "- API key validity: echo \$ANTHROPIC_API_KEY"
echo "- Nginx error logs: docker logs sdk-test-proxy"