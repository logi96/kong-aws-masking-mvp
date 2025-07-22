#!/usr/bin/env node

/**
 * AST-based tool to convert "used in module" exports to private
 * Safely removes export keyword from TypeScript declarations
 */

const fs = require('fs');
const path = require('path');

// Simple regex-based approach for initial implementation
// More sophisticated AST parsing could be added later if needed

/**
 * Parse ts-prune output to get "used in module" items
 */
function parseUsedInModuleItems() {
  const tsPruneOutput = path.join(__dirname, 'report', 'ts-prune-output.txt');
  
  if (!fs.existsSync(tsPruneOutput)) {
    console.error('❌ ts-prune output not found. Run ts-prune first.');
    process.exit(1);
  }
  
  const content = fs.readFileSync(tsPruneOutput, 'utf8');
  const lines = content.split('\n');
  
  const usedInModuleItems = [];
  
  for (const line of lines) {
    if (line.includes('(used in module)')) {
      // Parse format: "file:line - name (used in module)"
      const match = line.match(/^([^:]+):(\d+) - (.+) \(used in module\)$/);
      if (match) {
        const [, filePath, lineNum, name] = match;
        usedInModuleItems.push({
          file: filePath,
          line: parseInt(lineNum),
          name: name.trim(),
          originalLine: line
        });
      }
    }
  }
  
  return usedInModuleItems;
}

/**
 * Read file and find the export declaration at specific line
 */
function findExportAtLine(filePath, lineNum, name) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');
  
  // Check the exact line first
  const targetLine = lines[lineNum - 1];
  if (targetLine && targetLine.includes(name) && targetLine.includes('export')) {
    return {
      lineIndex: lineNum - 1,
      content: targetLine,
      fullContent: content,
      lines: lines
    };
  }
  
  // Search nearby lines (±5) for the export
  for (let i = Math.max(0, lineNum - 6); i < Math.min(lines.length, lineNum + 5); i++) {
    const line = lines[i];
    if (line && line.includes(name) && line.includes('export')) {
      return {
        lineIndex: i,
        content: line,
        fullContent: content,
        lines: lines
      };
    }
  }
  
  return null;
}

/**
 * Remove export keyword from a line
 */
function removeExportKeyword(line) {
  // Handle various export patterns
  const patterns = [
    /^(\s*)export\s+(interface|type|const|let|var|function|class)\s+/,
    /^(\s*)export\s+\{/,
    /^(\s*)export\s+default\s+/,
    /^(\s*)export\s+/
  ];
  
  for (const pattern of patterns) {
    if (pattern.test(line)) {
      if (pattern === patterns[0]) {
        // For "export interface/type/const/etc", just remove "export "
        return line.replace(/^(\s*)export\s+/, '$1');
      } else if (pattern === patterns[1]) {
        // For "export {", this needs special handling - skip for now
        return null;
      } else if (pattern === patterns[2]) {
        // For "export default", remove "export default"
        return line.replace(/^(\s*)export\s+default\s+/, '$1');
      } else {
        // Generic export removal
        return line.replace(/^(\s*)export\s+/, '$1');
      }
    }
  }
  
  return null;
}

/**
 * Process a single file to remove exports
 */
function processFile(items) {
  const fileGroups = {};
  
  // Group items by file
  for (const item of items) {
    if (!fileGroups[item.file]) {
      fileGroups[item.file] = [];
    }
    fileGroups[item.file].push(item);
  }
  
  const results = {
    processed: 0,
    skipped: 0,
    errors: 0,
    changes: []
  };
  
  for (const [filePath, fileItems] of Object.entries(fileGroups)) {
    console.log(`\n📁 Processing: ${filePath}`);
    
    if (!fs.existsSync(filePath)) {
      console.log(`   ⚠️  File not found: ${filePath}`);
      results.errors += fileItems.length;
      continue;
    }
    
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');
    let modified = false;
    const changes = [];
    
    // Sort items by line number (descending) to avoid line number shifts
    fileItems.sort((a, b) => b.line - a.line);
    
    for (const item of fileItems) {
      const exportInfo = findExportAtLine(filePath, item.line, item.name);
      
      if (!exportInfo) {
        console.log(`   ❌ Export not found: ${item.name} at line ${item.line}`);
        results.errors++;
        continue;
      }
      
      const newLine = removeExportKeyword(exportInfo.content);
      
      if (!newLine) {
        console.log(`   ⚠️  Skipping complex export: ${item.name}`);
        results.skipped++;
        continue;
      }
      
      // Apply change
      lines[exportInfo.lineIndex] = newLine;
      modified = true;
      results.processed++;
      
      changes.push({
        line: exportInfo.lineIndex + 1,
        name: item.name,
        before: exportInfo.content,
        after: newLine
      });
      
      console.log(`   ✅ Converted: ${item.name} (line ${exportInfo.lineIndex + 1})`);
    }
    
    if (modified) {
      // Write back to file
      const newContent = lines.join('\n');
      fs.writeFileSync(filePath, newContent, 'utf8');
      results.changes.push({
        file: filePath,
        changes: changes
      });
      console.log(`   💾 Updated: ${filePath} (${changes.length} changes)`);
    }
  }
  
  return results;
}

/**
 * Create backup before processing
 */
function createBackup() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupBranch = `export-to-private-backup-${timestamp}`;
  
  try {
    const { execSync } = require('child_process');
    execSync(`git checkout -b ${backupBranch}`, { stdio: 'inherit' });
    console.log(`✅ Created backup branch: ${backupBranch}`);
    return backupBranch;
  } catch (error) {
    console.error('❌ Failed to create backup branch:', error.message);
    process.exit(1);
  }
}

/**
 * Main execution
 */
function main() {
  console.log('🔄 Converting "used in module" exports to private...\n');
  
  // Parse used in module items
  const items = parseUsedInModuleItems();
  console.log(`📊 Found ${items.length} "used in module" items`);
  
  if (items.length === 0) {
    console.log('✅ No items to process');
    return;
  }
  
  // Create backup
  const backupBranch = createBackup();
  
  // Process files
  const results = processFile(items);
  
  // Report results
  console.log('\n📊 Summary:');
  console.log(`   ✅ Processed: ${results.processed}`);
  console.log(`   ⚠️  Skipped: ${results.skipped}`);
  console.log(`   ❌ Errors: ${results.errors}`);
  console.log(`   📁 Files modified: ${results.changes.length}`);
  
  if (results.changes.length > 0) {
    console.log('\n📝 Changed files:');
    for (const change of results.changes) {
      console.log(`   - ${change.file} (${change.changes.length} changes)`);
    }
    
    // Generate change log
    const logPath = path.join(__dirname, 'report', `export-conversion-log-${new Date().toISOString().slice(0, 10)}.md`);
    generateChangeLog(results, logPath);
    console.log(`\n📋 Change log: ${logPath}`);
  }
  
  console.log(`\n🔙 Backup branch: ${backupBranch}`);
  console.log('\n✅ Conversion complete!');
}

/**
 * Generate detailed change log
 */
function generateChangeLog(results, logPath) {
  const timestamp = new Date().toISOString();
  
  let log = `# Export to Private Conversion Log\n\n`;
  log += `**Date**: ${timestamp}\n`;
  log += `**Processed**: ${results.processed} items\n`;
  log += `**Skipped**: ${results.skipped} items\n`;
  log += `**Errors**: ${results.errors} items\n\n`;
  log += `---\n\n`;
  
  for (const fileChange of results.changes) {
    log += `## ${fileChange.file}\n\n`;
    
    for (const change of fileChange.changes) {
      log += `### ${change.name} (Line ${change.line})\n\n`;
      log += `**Before**:\n\`\`\`typescript\n${change.before}\n\`\`\`\n\n`;
      log += `**After**:\n\`\`\`typescript\n${change.after}\n\`\`\`\n\n`;
    }
    
    log += `---\n\n`;
  }
  
  fs.writeFileSync(logPath, log, 'utf8');
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = {
  parseUsedInModuleItems,
  removeExportKeyword,
  processFile
};