#!/bin/bash

# AIDA Backup Files Cleanup Script
# This script finds and removes all backup files in the src/ directory

echo "🧹 AIDA Backup Files Cleanup"
echo "============================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counter
TOTAL_COUNT=0

# Function to find and remove backup files
clean_backup_files() {
    local pattern=$1
    local count=0
    
    echo -e "${YELLOW}Searching for *${pattern} files...${NC}"
    
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            echo -e "${RED}Removing:${NC} $file"
            rm -f "$file"
            ((count++))
            ((TOTAL_COUNT++))
        fi
    done < <(find src/ -name "*${pattern}" -type f -print0 2>/dev/null)
    
    if [[ $count -eq 0 ]]; then
        echo -e "${GREEN}✓ No *${pattern} files found${NC}"
    else
        echo -e "${GREEN}✓ Removed $count *${pattern} files${NC}"
    fi
    echo ""
}

# Main execution
echo "Starting cleanup process..."
echo ""

# Clean different types of backup files
clean_backup_files ".bak"
clean_backup_files ".bak2"
clean_backup_files ".backup"
clean_backup_files ".old"
clean_backup_files ".orig"
clean_backup_files "~"  # Vim/Emacs backup files

# Summary
echo "============================"
if [[ $TOTAL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✨ No backup files found! Your src/ directory is clean.${NC}"
else
    echo -e "${GREEN}✅ Cleanup complete! Removed $TOTAL_COUNT backup files total.${NC}"
fi
echo ""

# Optional: Show remaining TypeScript files count
TS_COUNT=$(find src/ -name "*.ts" -not -name "*.d.ts" -type f | wc -l)
echo "📊 Remaining TypeScript files in src/: $TS_COUNT"