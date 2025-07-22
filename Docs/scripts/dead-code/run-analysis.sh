#!/bin/bash

# AIDA Dead Code Analysis Runner
# This script orchestrates the complete dead code analysis process

echo "🔍 AIDA Dead Code Analysis"
echo "=========================="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running from project root
if [[ ! -f "package.json" ]] || [[ ! -d "src" ]]; then
    echo "❌ Error: Please run this script from the AIDA project root directory"
    exit 1
fi

# Step 1: Clean backup files
echo -e "${BLUE}Step 1: Cleaning backup files...${NC}"
chmod +x Docs/scripts/dead-code/clean-backup-files.sh
./Docs/scripts/dead-code/clean-backup-files.sh
echo ""

# Step 2: Install required dependencies
echo -e "${BLUE}Step 2: Checking dependencies...${NC}"
if ! command -v ts-node &> /dev/null; then
    echo "Installing ts-node..."
    npm install -g ts-node
fi

if ! npm list ts-prune &> /dev/null; then
    echo "Installing ts-prune..."
    npm install --save-dev ts-prune
fi

if ! npm list typescript &> /dev/null; then
    echo "Installing typescript..."
    npm install --save-dev typescript
fi
echo -e "${GREEN}✓ Dependencies ready${NC}"
echo ""

# Step 3: Run dead code analysis
echo -e "${BLUE}Step 3: Running dead code analysis...${NC}"
echo "This may take a few minutes depending on project size..."
echo ""

# Run the TypeScript dead code detector
ts-node Docs/scripts/dead-code/detect-dead-code.ts

# Check if the analysis was successful
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Dead code analysis completed successfully!${NC}"
    
    # Find the latest report
    LATEST_REPORT=$(ls -t Docs/scripts/dead-code/report/dead-code-analysis-*.md 2>/dev/null | head -1)
    
    if [[ -n "$LATEST_REPORT" ]]; then
        echo ""
        echo -e "${YELLOW}📄 Report generated: $LATEST_REPORT${NC}"
        echo ""
        echo "View the report with:"
        echo "  cat $LATEST_REPORT"
        echo ""
        echo "Or open in your editor:"
        echo "  code $LATEST_REPORT"
    fi
else
    echo ""
    echo "❌ Dead code analysis failed. Check the error messages above."
    exit 1
fi

# Optional: Quick summary
echo ""
echo -e "${BLUE}Quick Actions:${NC}"
echo "1. Review the generated report for detailed findings"
echo "2. Use the cleanup script in the report to remove dead code"
echo "3. Commit changes after careful review"
echo ""
echo "🎯 Recommended: Run this analysis monthly to maintain code quality"