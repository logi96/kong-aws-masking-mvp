#!/bin/bash

# Fix test scripts to use correct API Gateway pattern
# SECURITY CRITICAL: Ensure all tests use Backend API, not Kong directly

echo "🔒 Fixing test scripts for correct API Gateway pattern..."
echo ""

# Change directory to tests
cd /Users/tw.kim/Documents/AGA/test/Kong/tests

# Count files
TOTAL=$(find . -name "*.sh" -type f | wc -l)
echo "Found $TOTAL test scripts to check"
echo ""

# Fix patterns in all shell scripts
echo "Updating localhost:8000 → localhost:3000..."
find . -name "*.sh" -type f -exec sed -i '' 's|localhost:8000/analyze|localhost:3000/analyze|g' {} \;
find . -name "*.sh" -type f -exec sed -i '' 's|localhost:8000/test-masking|localhost:3000/test-masking|g' {} \;
find . -name "*.sh" -type f -exec sed -i '' 's|localhost:8000/quick-mask-test|localhost:3000/quick-mask-test|g' {} \;

# Handle analyze-claude endpoints (these need to be removed)
echo ""
echo "Checking for analyze-claude endpoints..."
CLAUDE_FILES=$(grep -l "analyze-claude" *.sh 2>/dev/null || true)
if [ -n "$CLAUDE_FILES" ]; then
    echo "⚠️  Found analyze-claude in:"
    echo "$CLAUDE_FILES"
    echo ""
    echo "These files need manual review - analyze-claude endpoint doesn't exist in correct pattern"
    # Comment out these lines
    find . -name "*.sh" -type f -exec sed -i '' 's|^\(.*analyze-claude.*\)$|# REMOVED - Wrong pattern: \1|g' {} \;
fi

# Verify changes
echo ""
echo "🔍 Verification:"
echo "==============="

# Check for remaining localhost:8000 (excluding comments and Kong admin)
REMAINING=$(grep -h "localhost:8000" *.sh 2>/dev/null | grep -v "^#" | grep -v "8001" || true)
if [ -n "$REMAINING" ]; then
    echo "❌ Still found localhost:8000 references:"
    echo "$REMAINING"
else
    echo "✅ No direct Kong proxy calls found"
fi

# Show summary of changes
echo ""
echo "📊 Summary:"
echo "=========="
CHANGED=$(grep -l "localhost:3000/analyze" *.sh | wc -l)
echo "Files using correct pattern (localhost:3000): $CHANGED"

echo ""
echo "✅ Done! Please review the changes and test a few scripts manually."