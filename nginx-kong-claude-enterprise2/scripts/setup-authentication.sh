#!/bin/bash

# Setup Authentication for Kong AWS Masking MVP
# This script configures Kong with authentication plugins and creates test consumers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
KONG_CONFIG_FILE="../kong/kong-auth.yml"

echo -e "${BLUE}=== Kong Authentication Setup ===${NC}"
echo "Kong Admin URL: $KONG_ADMIN_URL"
echo ""

# Function to check if Kong is ready
check_kong_health() {
    echo -e "${YELLOW}Checking Kong health...${NC}"
    if curl -s "${KONG_ADMIN_URL}/status" > /dev/null; then
        echo -e "${GREEN}✓ Kong is healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Kong is not responding${NC}"
        return 1
    fi
}

# Function to apply Kong configuration
apply_kong_config() {
    echo -e "${YELLOW}Applying Kong authentication configuration...${NC}"
    
    # Check if config file exists
    if [ ! -f "$KONG_CONFIG_FILE" ]; then
        echo -e "${RED}✗ Kong config file not found: $KONG_CONFIG_FILE${NC}"
        exit 1
    fi
    
    # Apply configuration using deck (Kong's declarative config tool)
    # If deck is not available, we'll use the Admin API
    if command -v deck &> /dev/null; then
        echo "Using deck to apply configuration..."
        deck sync -s "$KONG_CONFIG_FILE" --kong-addr "$KONG_ADMIN_URL"
    else
        echo -e "${YELLOW}deck not found, using Admin API...${NC}"
        # Note: This is a simplified version. In production, use deck or kong-config
        echo -e "${YELLOW}Please apply kong-auth.yml manually or install deck${NC}"
    fi
}

# Function to create test API keys
create_test_keys() {
    echo -e "${YELLOW}Creating test API keys...${NC}"
    
    # Create standard tier consumer
    echo "Creating standard tier consumer..."
    curl -s -X POST "${KONG_ADMIN_URL}/consumers" \
        -H "Content-Type: application/json" \
        -d '{
            "username": "test-standard-user",
            "custom_id": "standard-001",
            "tags": ["test", "standard"]
        }' > /dev/null
    
    # Create API key for standard user
    STANDARD_KEY=$(curl -s -X POST "${KONG_ADMIN_URL}/consumers/test-standard-user/key-auth" \
        -H "Content-Type: application/json" \
        -d '{"tags": ["standard"]}' | jq -r '.key')
    
    echo -e "${GREEN}✓ Standard API Key: $STANDARD_KEY${NC}"
    
    # Create premium tier consumer
    echo "Creating premium tier consumer..."
    curl -s -X POST "${KONG_ADMIN_URL}/consumers" \
        -H "Content-Type: application/json" \
        -d '{
            "username": "test-premium-user",
            "custom_id": "premium-001",
            "tags": ["test", "premium"]
        }' > /dev/null
    
    # Create API key for premium user
    PREMIUM_KEY=$(curl -s -X POST "${KONG_ADMIN_URL}/consumers/test-premium-user/key-auth" \
        -H "Content-Type: application/json" \
        -d '{"tags": ["premium"]}' | jq -r '.key')
    
    echo -e "${GREEN}✓ Premium API Key: $PREMIUM_KEY${NC}"
    
    # Save keys to file
    cat > test-api-keys.txt << EOF
# Test API Keys (DELETE THIS FILE AFTER TESTING)
# Generated: $(date)

Standard Tier API Key: $STANDARD_KEY
Premium Tier API Key: $PREMIUM_KEY

# Usage example:
curl -X POST http://localhost:8000/v1/messages \\
  -H "X-API-Key: $STANDARD_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{"model": "claude-3-5-sonnet-20241022", "messages": [{"role": "user", "content": "Test"}]}'
EOF
    
    echo -e "${GREEN}✓ Test keys saved to test-api-keys.txt${NC}"
}

# Function to verify authentication setup
verify_setup() {
    echo -e "${YELLOW}Verifying authentication setup...${NC}"
    
    # Check plugins
    PLUGINS=$(curl -s "${KONG_ADMIN_URL}/plugins" | jq -r '.data[] | select(.name == "key-auth" or .name == "rate-limiting" or .name == "jwt") | .name' | sort | uniq)
    
    if echo "$PLUGINS" | grep -q "key-auth"; then
        echo -e "${GREEN}✓ Key-Auth plugin configured${NC}"
    else
        echo -e "${RED}✗ Key-Auth plugin not found${NC}"
    fi
    
    if echo "$PLUGINS" | grep -q "rate-limiting"; then
        echo -e "${GREEN}✓ Rate-Limiting plugin configured${NC}"
    else
        echo -e "${RED}✗ Rate-Limiting plugin not found${NC}"
    fi
    
    # Check consumers
    CONSUMERS=$(curl -s "${KONG_ADMIN_URL}/consumers" | jq -r '.data[].username')
    echo -e "${BLUE}Configured consumers:${NC}"
    echo "$CONSUMERS" | while read -r consumer; do
        echo "  - $consumer"
    done
}

# Main execution
echo -e "${BLUE}Starting authentication setup...${NC}"
echo ""

# Step 1: Check Kong health
if ! check_kong_health; then
    echo -e "${RED}Please ensure Kong is running and accessible${NC}"
    exit 1
fi

# Step 2: Apply Kong configuration
echo ""
apply_kong_config

# Step 3: Create test keys
echo ""
create_test_keys

# Step 4: Verify setup
echo ""
verify_setup

# Summary
echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Check test-api-keys.txt for test API keys"
echo "2. Run ./test-authentication.sh to verify the setup"
echo "3. Update backend/.env with any required settings"
echo "4. Restart services: docker-compose restart"
echo ""
echo -e "${YELLOW}⚠️  Remember to delete test-api-keys.txt after testing!${NC}"