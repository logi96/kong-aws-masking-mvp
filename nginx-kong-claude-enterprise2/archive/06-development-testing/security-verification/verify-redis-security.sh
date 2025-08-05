#!/bin/bash
# Redis Security Verification Script

echo "🔍 Redis Password Security Verification"
echo "======================================="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for hardcoded password in source files
echo -e "\n📝 Checking for hardcoded passwords in source code..."
HARDCODED_FOUND=$(grep -r "CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL" . \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=logs \
  --exclude="*.log" \
  --exclude="verify-redis-security.sh" \
  --exclude="REDIS_PASSWORD_SECURITY_GUIDE.md" \
  --exclude="SECURITY_COMPLIANCE_REPORT.md" \
  2>/dev/null)

if [ -z "$HARDCODED_FOUND" ]; then
    echo -e "${GREEN}✅ No hardcoded passwords found in source code${NC}"
else
    echo -e "${RED}❌ Hardcoded password found in:${NC}"
    echo "$HARDCODED_FOUND" | head -5
    echo -e "${YELLOW}   ... and possibly more files${NC}"
fi

# Check if .env file exists
echo -e "\n📁 Checking .env file..."
if [ -f ".env" ]; then
    echo -e "${GREEN}✅ .env file exists${NC}"
    
    # Check if REDIS_PASSWORD is set
    if grep -q "^REDIS_PASSWORD=" .env; then
        # Check if it's not the default/example password
        if grep -q "REDIS_PASSWORD=your-secure-redis-password-here" .env; then
            echo -e "${YELLOW}⚠️  REDIS_PASSWORD is still using the example placeholder${NC}"
            echo -e "${YELLOW}   Please set a secure password in .env file${NC}"
        elif grep -q "REDIS_PASSWORD=CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL" .env; then
            echo -e "${RED}❌ REDIS_PASSWORD is still using the old hardcoded password${NC}"
            echo -e "${RED}   Please generate a new secure password${NC}"
        else
            echo -e "${GREEN}✅ REDIS_PASSWORD is set (and not using default)${NC}"
        fi
    else
        echo -e "${RED}❌ REDIS_PASSWORD not found in .env file${NC}"
    fi
else
    echo -e "${RED}❌ .env file not found${NC}"
    echo -e "${YELLOW}   Please copy .env.example to .env and set REDIS_PASSWORD${NC}"
fi

# Check Redis entrypoint script
echo -e "\n🐳 Checking Docker configuration..."
if [ -f "redis/docker-entrypoint.sh" ]; then
    echo -e "${GREEN}✅ Redis entrypoint script exists${NC}"
    
    # Check if it's executable
    if [ -x "redis/docker-entrypoint.sh" ]; then
        echo -e "${GREEN}✅ Entrypoint script is executable${NC}"
    else
        echo -e "${RED}❌ Entrypoint script is not executable${NC}"
        echo -e "${YELLOW}   Run: chmod +x redis/docker-entrypoint.sh${NC}"
    fi
else
    echo -e "${RED}❌ Redis entrypoint script not found${NC}"
fi

# Check if old redis.conf exists
if [ -f "redis/redis.conf" ]; then
    echo -e "${YELLOW}⚠️  Old redis.conf file still exists${NC}"
    echo -e "${YELLOW}   This file should have been renamed to redis.conf.template${NC}"
fi

# Check backend service implementation
echo -e "\n💻 Checking backend implementation..."
if grep -q "throw new Error('REDIS_PASSWORD must be provided" backend/src/services/redis/redisService.js 2>/dev/null; then
    echo -e "${GREEN}✅ Backend validates REDIS_PASSWORD requirement${NC}"
else
    echo -e "${RED}❌ Backend missing REDIS_PASSWORD validation${NC}"
fi

# Summary
echo -e "\n📊 Summary"
echo "=========="

ISSUES=0

# Count issues
if [ ! -z "$HARDCODED_FOUND" ]; then ((ISSUES++)); fi
if [ ! -f ".env" ]; then ((ISSUES++)); fi
if [ -f ".env" ] && grep -q "REDIS_PASSWORD=your-secure-redis-password-here" .env 2>/dev/null; then ((ISSUES++)); fi
if [ -f ".env" ] && grep -q "REDIS_PASSWORD=CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL" .env 2>/dev/null; then ((ISSUES++)); fi
if [ ! -f "redis/docker-entrypoint.sh" ]; then ((ISSUES++)); fi
if [ -f "redis/redis.conf" ]; then ((ISSUES++)); fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ All security checks passed!${NC}"
    echo -e "${GREEN}   Redis password security is properly implemented.${NC}"
else
    echo -e "${YELLOW}⚠️  Found $ISSUES issue(s) that need attention${NC}"
    echo -e "\n📋 Next steps:"
    echo "1. Create .env file from .env.example"
    echo "2. Generate a secure password: openssl rand -base64 48"
    echo "3. Set REDIS_PASSWORD in .env file"
    echo "4. Remove any remaining hardcoded passwords"
    echo "5. Clean git history if needed"
fi

echo -e "\n🔐 Security Tips:"
echo "- Use a strong password (32+ characters)"
echo "- Different passwords for each environment"
echo "- Never commit .env files to git"
echo "- Rotate passwords regularly (every 90 days)"