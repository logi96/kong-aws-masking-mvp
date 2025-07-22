#!/bin/bash

# Safe Dead Code Cleanup Script
# Only processes LOW RISK items

echo "🧹 AIDA Safe Dead Code Cleanup"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Safety checks
if [[ ! -f "package.json" ]] || [[ ! -d "src" ]]; then
    echo -e "${RED}❌ Error: Please run from AIDA project root${NC}"
    exit 1
fi

# Create backup branch
BRANCH_NAME="dead-code-cleanup-$(date +%Y%m%d-%H%M%S)"
echo -e "${YELLOW}Creating backup branch: $BRANCH_NAME${NC}"
git checkout -b "$BRANCH_NAME"

# Function to check if an item can be safely deleted
is_safe_to_delete() {
    local file=$1
    local line=$2
    local name=$3
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        echo "File not found: $file"
        return 1
    fi
    
    # Check for direct imports
    local import_count=$(grep -r "import.*$name" src/ test/ 2>/dev/null | grep -v "$file" | wc -l)
    if [[ $import_count -gt 0 ]]; then
        echo "Found $import_count imports of $name"
        return 1
    fi
    
    # Check for dynamic imports
    local dynamic_count=$(grep -r "require.*$name" src/ test/ 2>/dev/null | wc -l)
    if [[ $dynamic_count -gt 0 ]]; then
        echo "Found $dynamic_count dynamic imports of $name"
        return 1
    fi
    
    return 0
}

# Process a single LOW RISK item
process_low_risk_item() {
    local file=$1
    local line=$2
    local name=$3
    local note=$4
    
    echo ""
    echo "Processing: $name in $file:$line"
    
    # Skip if "used in module" - these need to be made private, not deleted
    if [[ "$note" == "used in module" ]]; then
        echo -e "${YELLOW}⚠️  Skipping 'used in module' item - should be made private instead${NC}"
        return
    fi
    
    # Safety check
    if ! is_safe_to_delete "$file" "$line" "$name"; then
        echo -e "${RED}❌ Not safe to delete - found usage${NC}"
        return
    fi
    
    # Run tests before deletion
    echo "Running tests before deletion..."
    npm test -- --testPathPattern="$(dirname "$file")" > /dev/null 2>&1
    local before_test=$?
    
    # Create temporary file for editing
    local temp_file="${file}.tmp"
    
    # Remove the specific export (this is simplified - real implementation would be more complex)
    # For now, just log what would be deleted
    echo -e "${YELLOW}Would delete: export $name at line $line${NC}"
    
    # TODO: Implement actual deletion logic
    # This would require parsing the TypeScript AST to safely remove exports
    
    echo -e "${GREEN}✓ Marked for deletion${NC}"
}

# Extract LOW RISK items from risk assessment
echo -e "${BLUE}Extracting LOW RISK items...${NC}"

# Parse the risk assessment report
RISK_REPORT="Docs/scripts/dead-code/report/dead-code-risk-assessment.md"
if [[ ! -f "$RISK_REPORT" ]]; then
    echo -e "${RED}❌ Risk assessment report not found. Run categorize-dead-code.cjs first.${NC}"
    exit 1
fi

# Extract LOW RISK section
awk '/## 🟢 LOW RISK Items/,/^---$/' "$RISK_REPORT" | grep '^- `' | while read -r line; do
    # Parse line format: - `file:line` - **name** (note)
    if [[ $line =~ \`([^:]+):([0-9]+)\`[[:space:]]-[[:space:]]\*\*([^*]+)\*\*[[:space:]]*(.*) ]]; then
        file="${BASH_REMATCH[1]}"
        line_num="${BASH_REMATCH[2]}"
        name="${BASH_REMATCH[3]}"
        note="${BASH_REMATCH[4]}"
        
        # Remove parentheses from note
        note=$(echo "$note" | sed 's/[()]//g')
        
        # Only process test utilities for now
        if [[ "$file" =~ test-doubles|mocks ]] && [[ "$name" =~ ^create|^Mock ]]; then
            process_low_risk_item "$file" "$line_num" "$name" "$note"
        fi
    fi
done

echo ""
echo "=============================="
echo -e "${GREEN}✅ Safe cleanup analysis complete${NC}"
echo ""
echo "Next steps:"
echo "1. Review the items marked for deletion"
echo "2. Implement actual AST-based deletion"
echo "3. Run full test suite"
echo "4. Commit changes"
echo ""
echo -e "${YELLOW}Note: This is a dry run. No files were actually modified.${NC}"