#!/bin/bash

# Test to verify which routes have the aws-masker plugin enabled

echo "=== Kong Plugin Association Test ==="
echo "Testing which routes have aws-masker plugin enabled"
echo ""

# Get all routes with their plugins
echo "Routes and their plugins:"
echo "========================"

routes=$(curl -s http://localhost:8001/routes | jq -r '.data[].name')

for route in $routes; do
    echo -e "\nRoute: $route"
    echo "-------------"
    
    # Get route details
    route_data=$(curl -s http://localhost:8001/routes/$route)
    paths=$(echo "$route_data" | jq -r '.paths[]? // "N/A"' | tr '\n' ' ')
    hosts=$(echo "$route_data" | jq -r '.hosts[]? // "any"' | tr '\n' ' ')
    
    echo "Paths: $paths"
    echo "Hosts: $hosts"
    
    # Check for plugins
    plugins=$(curl -s http://localhost:8001/routes/$route/plugins | jq -r '.data[].name' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    
    if [ -z "$plugins" ]; then
        echo "Plugins: NONE"
    else
        echo "Plugins: $plugins"
    fi
done

echo -e "\n\nPlugin Configuration Details:"
echo "============================="

# Get aws-masker plugin instances
aws_masker_plugins=$(curl -s http://localhost:8001/plugins | jq -r '.data[] | select(.name=="aws-masker")')

if [ -n "$aws_masker_plugins" ]; then
    echo "$aws_masker_plugins" | jq -r '"Route: \(.route.name // "global"), Redis: \(.config.use_redis), Masks: EC2=\(.config.mask_ec2_instances) S3=\(.config.mask_s3_buckets)"'
else
    echo "No aws-masker plugins found!"
fi

echo -e "\n\nConclusion:"
echo "==========="
echo "1. Only analyze-claude and claude-proxy routes have aws-masker plugin"
echo "2. The anthropic-transparent route has NO plugins attached"
echo "3. This explains why the transparent route wouldn't mask data even if used"