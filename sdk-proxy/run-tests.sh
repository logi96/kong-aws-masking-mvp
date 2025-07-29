#!/bin/bash

# SDK Proxy Test Runner Script
# Executes the test suite inside Docker container

set -e

echo "🚀 Starting SDK Proxy Tests in Docker"

# Build the Docker image if needed
echo "📦 Building Docker image..."
docker build -t sdk-proxy-test .

# Create results directory on host
mkdir -p ./results

# Run the tests
echo "🧪 Running tests..."
docker run \
  --rm \
  --network kong-network \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  -e PROXY_URL="http://kong:8000" \
  -v "$(pwd)/results:/app/results" \
  sdk-proxy-test \
  npm test

# Check if results were generated
if [ -f "./results/test-results.json" ]; then
  echo "✅ Test results saved to ./results/test-results.json"
  echo ""
  echo "📊 Test Summary:"
  cat ./results/test-results.json | jq '.summary'
else
  echo "❌ No test results found"
  exit 1
fi