#!/bin/bash

# Service Validation Script

echo "=== Service Health Check ==="

# Check Backend API
echo -n "Backend API (3000): "
if curl -s http://localhost:3000/health | grep -q "healthy"; then
    echo "✅ Running"
else
    echo "❌ Not responding"
fi

# Check Kong Gateway
echo -n "Kong Gateway (8001): "
if curl -s http://localhost:8001/status | grep -q "database"; then
    echo "✅ Running"
else
    echo "❌ Not responding"
fi

# Check Kong Proxy
echo -n "Kong Proxy (8000): "
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "404"; then
    echo "✅ Running (404 expected)"
else
    echo "❌ Not responding"
fi

# Check Docker containers
echo -e "\n=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(kong|backend|redis)"

# Check environment
echo -e "\n=== Environment Check ==="
echo "ANTHROPIC_API_KEY: $(if [ -n "$ANTHROPIC_API_KEY" ]; then echo "✅ Set"; else echo "❌ Not set"; fi)"
echo "Working directory: $(pwd)"