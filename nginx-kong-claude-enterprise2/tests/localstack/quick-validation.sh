#!/bin/bash

# Quick LocalStack Validation Script
set -e

echo "🚀 Starting Quick LocalStack Validation"

# Check LocalStack container
if docker ps | grep -q "claude-localstack"; then
    echo "✅ LocalStack container running"
else
    echo "❌ LocalStack container not running"
    exit 1
fi

# Check health endpoint
if curl -sf "http://localhost:4566/_localstack/health" > /dev/null; then
    echo "✅ LocalStack health endpoint accessible"
    
    # Check edition
    if curl -s "http://localhost:4566/_localstack/health" | grep -q '"edition": "pro"'; then
        echo "✅ LocalStack Pro edition confirmed"
    else
        echo "❌ LocalStack Pro edition not confirmed"
    fi
else
    echo "❌ LocalStack health endpoint not accessible"
    exit 1
fi

# Test AWS services
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566

echo "Testing AWS services..."

# Test EC2
if aws ec2 describe-regions --endpoint-url=http://localhost:4566 &>/dev/null; then
    echo "✅ EC2 service operational"
else
    echo "❌ EC2 service not operational"
fi

# Test ECS
if aws ecs list-clusters --endpoint-url=http://localhost:4566 &>/dev/null; then
    echo "✅ ECS service operational"
else
    echo "❌ ECS service not operational"
fi

# Test ElastiCache
if aws elasticache describe-cache-clusters --endpoint-url=http://localhost:4566 &>/dev/null; then
    echo "✅ ElastiCache service operational"
else
    echo "❌ ElastiCache service not operational"
fi

# Test S3
if aws s3 ls --endpoint-url=http://localhost:4566 &>/dev/null; then
    echo "✅ S3 service operational"
else
    echo "❌ S3 service not operational"
fi

# Check configurations
echo "Checking configurations..."

if [ -f "kong/kong-traditional.yml" ]; then
    echo "✅ kong-traditional.yml found"
    if grep -q 'redis_type: "traditional"' "kong/kong-traditional.yml"; then
        echo "✅ Traditional Redis mode configured"
    fi
else
    echo "❌ kong-traditional.yml missing"
fi

if [ -f "kong/kong-managed.yml" ]; then
    echo "✅ kong-managed.yml found"
    if grep -q 'redis_type: "managed"' "kong/kong-managed.yml"; then
        echo "✅ Managed Redis mode configured"
    fi
else
    echo "❌ kong-managed.yml missing"
fi

# Check plugin files
if [ -f "kong/plugins/aws-masker/schema.lua" ]; then
    echo "✅ Kong plugin schema found"
    if grep -q "redis_type" "kong/plugins/aws-masker/schema.lua"; then
        echo "✅ ElastiCache schema extensions found"
    fi
else
    echo "❌ Kong plugin schema missing"
fi

echo "🎉 Quick validation completed successfully!"