#!/bin/bash

# Fix test scripts to use correct API Gateway pattern
# Changes localhost:8000 (Kong direct) to localhost:3000 (Backend API)
# SECURITY: 100% quality requirement - API Gateway transparency

set -euo pipefail

echo "========================================="
echo "🔒 FIXING TEST SCRIPTS - API GATEWAY PATTERN"
echo "========================================="
echo "Date: $(date)"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base directory
TEST_DIR="/Users/tw.kim/Documents/AGA/test/Kong/tests"

# Patterns to fix
OLD_PATTERNS=(
    "http://localhost:8000/analyze"
    "localhost:8000/analyze"
    "http://localhost:8000/test-masking"
    "localhost:8000/test-masking"
    "http://localhost:8000/quick-mask-test"
    "localhost:8000/quick-mask-test"
)

NEW_PATTERNS=(
    "http://localhost:3000/analyze"
    "localhost:3000/analyze"
    "http://localhost:3000/test-masking"
    "localhost:3000/test-masking"
    "http://localhost:3000/quick-mask-test"
    "localhost:3000/quick-mask-test"
)

# Also remove analyze-claude references completely
REMOVE_PATTERNS=(
    "http://localhost:8000/analyze-claude"
    "localhost:8000/analyze-claude"
)

# Count changes
TOTAL_FILES=0
MODIFIED_FILES=0
TOTAL_CHANGES=0

echo -e "${BLUE}Scanning test files...${NC}"
echo ""

# Function to fix a file
fix_file() {
    local file="$1"
    local changes=0
    local temp_file="${file}.tmp"
    
    # Create a copy
    cp "$file" "$temp_file"
    
    # Fix patterns
    for i in "${!OLD_PATTERNS[@]}"; do
        if grep -q "${OLD_PATTERNS[$i]}" "$temp_file"; then
            sed -i '' "s|${OLD_PATTERNS[$i]}|${NEW_PATTERNS[$i]}|g" "$temp_file"
            changes=$((changes + $(grep -c "${NEW_PATTERNS[$i]}" "$temp_file" || true)))
        fi
    done
    
    # Remove analyze-claude patterns (these should not exist in correct pattern)
    for pattern in "${REMOVE_PATTERNS[@]}"; do
        if grep -q "$pattern" "$temp_file"; then
            echo -e "${YELLOW}WARNING: Found direct Kong API call '$pattern' in $(basename "$file")${NC}"
            echo -e "${YELLOW}This pattern should be completely removed or redesigned${NC}"
            # Comment out these lines for now
            sed -i '' "s|.*${pattern}.*|# REMOVED: Direct Kong call - needs redesign: &|g" "$temp_file"
            changes=$((changes + 1))
        fi
    done
    
    # Check if file was modified
    if [ $changes -gt 0 ]; then
        mv "$temp_file" "$file"
        echo -e "${GREEN}✓ Fixed $(basename "$file") - $changes changes${NC}"
        ((MODIFIED_FILES++))
        TOTAL_CHANGES=$((TOTAL_CHANGES + changes))
    else
        rm "$temp_file"
    fi
    
    ((TOTAL_FILES++))
}

# Find and fix all test files
echo "Processing shell scripts (.sh):"
while IFS= read -r file; do
    fix_file "$file"
done < <(find "$TEST_DIR" -name "*.sh" -type f)

echo ""
echo "========================================="
echo "🔒 SECURITY VALIDATION"
echo "========================================="

# Verify no direct Kong calls remain
echo -e "${BLUE}Checking for remaining direct Kong calls...${NC}"
REMAINING=$(grep -r "localhost:8000" "$TEST_DIR" --include="*.sh" | grep -v "^#" | grep -v "Kong Admin" || true)

if [ -n "$REMAINING" ]; then
    echo -e "${RED}❌ SECURITY ISSUE: Found remaining direct Kong calls:${NC}"
    echo "$REMAINING"
    echo ""
    echo -e "${RED}These must be manually reviewed and fixed!${NC}"
else
    echo -e "${GREEN}✅ No direct Kong proxy calls found${NC}"
fi

echo ""
echo "========================================="
echo "📊 SUMMARY"
echo "========================================="
echo "Total files scanned: $TOTAL_FILES"
echo "Files modified: $MODIFIED_FILES"
echo "Total changes made: $TOTAL_CHANGES"
echo ""

if [ $MODIFIED_FILES -gt 0 ]; then
    echo -e "${GREEN}✅ Successfully updated $MODIFIED_FILES test files${NC}"
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Review the changes manually"
    echo "2. Run a sample test to verify functionality"
    echo "3. Update any test documentation"
else
    echo -e "${YELLOW}No files needed modification${NC}"
fi

echo ""
echo "========================================="
echo -e "${BLUE}IMPORTANT NOTES:${NC}"
echo "========================================="
echo "1. Tests should ONLY call Backend API (localhost:3000)"
echo "2. Kong transparently intercepts external API calls"
echo "3. Direct Kong calls violate API Gateway pattern"
echo "4. Any 'analyze-claude' endpoints have been commented out"
echo "   - These need complete redesign for correct pattern"
echo ""
echo "Completed: $(date)"