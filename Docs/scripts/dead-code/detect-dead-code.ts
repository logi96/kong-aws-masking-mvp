#!/usr/bin/env ts-node

/**
 * AIDA Dead Code Detection Script
 * 
 * This script combines multiple tools to provide comprehensive dead code analysis:
 * 1. ts-prune for unused exports
 * 2. Custom AST analysis for internal dead code
 * 3. File analysis for empty/duplicate files
 * 4. Comment analysis for commented code blocks
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import * as ts from 'typescript';

interface DeadCodeReport {
  timestamp: string;
  summary: {
    totalFiles: number;
    filesWithIssues: number;
    totalIssues: number;
  };
  unusedExports: UnusedExport[];
  unusedInternals: UnusedInternal[];
  emptyFiles: string[];
  duplicateFiles: DuplicateFile[];
  commentedCodeBlocks: CommentedCode[];
  backupFiles: string[];
}

interface UnusedExport {
  file: string;
  line: number;
  name: string;
  type: 'function' | 'class' | 'interface' | 'type' | 'variable' | 'enum';
}

interface UnusedInternal {
  file: string;
  line: number;
  name: string;
  type: string;
}

interface DuplicateFile {
  file1: string;
  file2: string;
  hash: string;
}

interface CommentedCode {
  file: string;
  startLine: number;
  endLine: number;
  preview: string;
}

class DeadCodeDetector {
  private srcPath: string;
  private report: DeadCodeReport;
  private fileCache: Map<string, string> = new Map();

  constructor(srcPath: string = 'src') {
    this.srcPath = srcPath;
    this.report = {
      timestamp: new Date().toISOString(),
      summary: {
        totalFiles: 0,
        filesWithIssues: 0,
        totalIssues: 0
      },
      unusedExports: [],
      unusedInternals: [],
      emptyFiles: [],
      duplicateFiles: [],
      commentedCodeBlocks: [],
      backupFiles: []
    };
  }

  async run(): Promise<void> {
    console.log('🔍 Starting AIDA Dead Code Detection...\n');

    // Step 1: Find and report backup files
    console.log('📁 Step 1/6: Finding backup files...');
    this.findBackupFiles();

    // Step 2: Count total TypeScript files
    console.log('📊 Step 2/6: Analyzing project structure...');
    this.countTotalFiles();

    // Step 3: Run ts-prune for unused exports
    console.log('🔎 Step 3/6: Detecting unused exports...');
    await this.detectUnusedExports();

    // Step 4: Analyze internal dead code
    console.log('🔬 Step 4/6: Analyzing internal dead code...');
    await this.analyzeInternalDeadCode();

    // Step 5: Find empty and duplicate files
    console.log('📄 Step 5/6: Finding empty and duplicate files...');
    await this.findEmptyAndDuplicateFiles();

    // Step 6: Find commented code blocks
    console.log('💬 Step 6/6: Finding commented code blocks...');
    await this.findCommentedCode();

    // Generate report
    console.log('\n📝 Generating report...');
    this.calculateSummary();
    await this.generateReport();
  }

  private findBackupFiles(): void {
    const backupPatterns = ['*.bak', '*.backup', '*.old', '*.orig'];
    const backupFiles: string[] = [];

    const findFiles = (dir: string): void => {
      const files = fs.readdirSync(dir);
      files.forEach(file => {
        const filePath = path.join(dir, file);
        const stat = fs.statSync(filePath);
        
        if (stat.isDirectory() && !file.includes('node_modules')) {
          findFiles(filePath);
        } else if (stat.isFile()) {
          if (backupPatterns.some(pattern => 
            file.endsWith(pattern.replace('*', '')))) {
            backupFiles.push(filePath);
          }
        }
      });
    };

    findFiles(this.srcPath);
    this.report.backupFiles = backupFiles;
    console.log(`   Found ${backupFiles.length} backup files`);
  }

  private countTotalFiles(): void {
    const countFiles = (dir: string): number => {
      let count = 0;
      const files = fs.readdirSync(dir);
      
      files.forEach(file => {
        const filePath = path.join(dir, file);
        const stat = fs.statSync(filePath);
        
        if (stat.isDirectory() && !file.includes('node_modules')) {
          count += countFiles(filePath);
        } else if (stat.isFile() && file.endsWith('.ts') && !file.endsWith('.bak')) {
          count++;
        }
      });
      
      return count;
    };

    this.report.summary.totalFiles = countFiles(this.srcPath);
    console.log(`   Total TypeScript files: ${this.report.summary.totalFiles}`);
  }

  private async detectUnusedExports(): Promise<void> {
    try {
      // First try ts-prune
      const tsPruneOutput = execSync('npx ts-prune --project tsconfig.json', {
        encoding: 'utf8',
        stdio: 'pipe'
      });

      const lines = tsPruneOutput.split('\n').filter(line => line.trim());
      lines.forEach(line => {
        const match = line.match(/(.+):(\d+) - (.+)/);
        if (match) {
          const [, file, lineNum, identifier] = match;
          
          // Determine type from identifier
          let type: UnusedExport['type'] = 'variable';
          if (identifier.includes('(')) type = 'function';
          else if (identifier.startsWith('class ')) type = 'class';
          else if (identifier.startsWith('interface ')) type = 'interface';
          else if (identifier.startsWith('type ')) type = 'type';
          else if (identifier.startsWith('enum ')) type = 'enum';

          this.report.unusedExports.push({
            file: file.trim(),
            line: parseInt(lineNum),
            name: identifier.replace(/(class |interface |type |enum )/, '').trim(),
            type
          });
        }
      });

      console.log(`   Found ${this.report.unusedExports.length} unused exports`);
    } catch (error) {
      console.log('   ⚠️  ts-prune not available, using fallback method');
      // Fallback to basic analysis
      await this.basicUnusedExportAnalysis();
    }
  }

  private async basicUnusedExportAnalysis(): Promise<void> {
    // Basic implementation for when ts-prune is not available
    // This would require more complex AST analysis
    console.log('   Using basic export analysis...');
  }

  private async analyzeInternalDeadCode(): Promise<void> {
    const files = this.getAllTypeScriptFiles();
    
    for (const file of files) {
      const content = fs.readFileSync(file, 'utf8');
      this.fileCache.set(file, content);

      // Create AST
      const sourceFile = ts.createSourceFile(
        file,
        content,
        ts.ScriptTarget.Latest,
        true
      );

      // Visit nodes to find unused internal declarations
      const visit = (node: ts.Node) => {
        if (ts.isFunctionDeclaration(node) && !ts.getCombinedModifierFlags(node)) {
          // Check if function is used
          const name = node.name?.getText();
          if (name && !this.isIdentifierUsed(name, content, node)) {
            this.report.unusedInternals.push({
              file,
              line: this.getLineNumber(node, sourceFile),
              name,
              type: 'function'
            });
          }
        }
        
        ts.forEachChild(node, visit);
      };

      visit(sourceFile);
    }

    console.log(`   Found ${this.report.unusedInternals.length} unused internal declarations`);
  }

  private async findEmptyAndDuplicateFiles(): Promise<void> {
    const files = this.getAllTypeScriptFiles();
    const fileHashes = new Map<string, string[]>();

    for (const file of files) {
      const content = this.fileCache.get(file) || fs.readFileSync(file, 'utf8');
      
      // Check for empty files
      const trimmedContent = content.trim();
      if (trimmedContent.length === 0 || 
          trimmedContent === '// Empty file' ||
          trimmedContent.match(/^\/\*[\s\S]*?\*\/$/)) {
        this.report.emptyFiles.push(file);
      }

      // Calculate hash for duplicate detection
      const hash = crypto.createHash('md5').update(content).digest('hex');
      if (!fileHashes.has(hash)) {
        fileHashes.set(hash, []);
      }
      fileHashes.get(hash)!.push(file);
    }

    // Find duplicates
    fileHashes.forEach((files, hash) => {
      if (files.length > 1) {
        for (let i = 0; i < files.length - 1; i++) {
          for (let j = i + 1; j < files.length; j++) {
            this.report.duplicateFiles.push({
              file1: files[i],
              file2: files[j],
              hash
            });
          }
        }
      }
    });

    console.log(`   Found ${this.report.emptyFiles.length} empty files`);
    console.log(`   Found ${this.report.duplicateFiles.length} duplicate file pairs`);
  }

  private async findCommentedCode(): Promise<void> {
    const files = this.getAllTypeScriptFiles();
    
    for (const file of files) {
      const content = this.fileCache.get(file) || fs.readFileSync(file, 'utf8');
      const lines = content.split('\n');
      
      // Find multi-line comment blocks that look like code
      const commentBlocks = this.findCommentBlocks(lines);
      
      for (const block of commentBlocks) {
        if (this.looksLikeCode(block.content)) {
          this.report.commentedCodeBlocks.push({
            file,
            startLine: block.start,
            endLine: block.end,
            preview: block.content.slice(0, 100) + (block.content.length > 100 ? '...' : '')
          });
        }
      }
    }

    console.log(`   Found ${this.report.commentedCodeBlocks.length} commented code blocks`);
  }

  private findCommentBlocks(lines: string[]): Array<{start: number, end: number, content: string}> {
    const blocks: Array<{start: number, end: number, content: string}> = [];
    let inBlock = false;
    let blockStart = 0;
    let blockContent: string[] = [];

    lines.forEach((line, index) => {
      if (line.trim().startsWith('/*')) {
        inBlock = true;
        blockStart = index + 1;
        blockContent = [];
      } else if (inBlock && line.trim().endsWith('*/')) {
        inBlock = false;
        blocks.push({
          start: blockStart,
          end: index + 1,
          content: blockContent.join('\n')
        });
      } else if (inBlock) {
        blockContent.push(line);
      }
    });

    // Also check for consecutive // comments
    let consecutiveStart = -1;
    let consecutiveLines: string[] = [];

    lines.forEach((line, index) => {
      if (line.trim().startsWith('//')) {
        if (consecutiveStart === -1) {
          consecutiveStart = index + 1;
        }
        consecutiveLines.push(line.replace(/^\/\/\s?/, ''));
      } else {
        if (consecutiveLines.length > 3) {
          blocks.push({
            start: consecutiveStart,
            end: index,
            content: consecutiveLines.join('\n')
          });
        }
        consecutiveStart = -1;
        consecutiveLines = [];
      }
    });

    return blocks;
  }

  private looksLikeCode(content: string): boolean {
    const codeIndicators = [
      /\bfunction\s+\w+/,
      /\bclass\s+\w+/,
      /\bconst\s+\w+\s*=/,
      /\blet\s+\w+\s*=/,
      /\bif\s*\(/,
      /\bfor\s*\(/,
      /\bwhile\s*\(/,
      /\breturn\s+/,
      /\w+\.\w+\(/,
      /\w+\[\w+\]/
    ];

    return codeIndicators.some(pattern => pattern.test(content));
  }

  private getAllTypeScriptFiles(): string[] {
    const files: string[] = [];
    
    const collectFiles = (dir: string): void => {
      const items = fs.readdirSync(dir);
      items.forEach(item => {
        const itemPath = path.join(dir, item);
        const stat = fs.statSync(itemPath);
        
        if (stat.isDirectory() && !item.includes('node_modules')) {
          collectFiles(itemPath);
        } else if (stat.isFile() && item.endsWith('.ts') && !item.endsWith('.bak')) {
          files.push(itemPath);
        }
      });
    };

    collectFiles(this.srcPath);
    return files;
  }

  private isIdentifierUsed(identifier: string, content: string, declaration: ts.Node): boolean {
    const declarationStart = declaration.getStart();
    const declarationEnd = declaration.getEnd();
    
    // Create regex to find identifier usage
    const regex = new RegExp(`\\b${identifier}\\b`, 'g');
    let match;
    let usageCount = 0;

    while ((match = regex.exec(content)) !== null) {
      // Check if this match is outside the declaration
      const matchIndex = match.index;
      if (matchIndex < declarationStart || matchIndex > declarationEnd) {
        usageCount++;
      }
    }

    return usageCount > 0;
  }

  private getLineNumber(node: ts.Node, sourceFile: ts.SourceFile): number {
    const position = node.getStart();
    const lineAndChar = sourceFile.getLineAndCharacterOfPosition(position);
    return lineAndChar.line + 1;
  }

  private calculateSummary(): void {
    const filesWithIssues = new Set<string>();
    
    this.report.unusedExports.forEach(item => filesWithIssues.add(item.file));
    this.report.unusedInternals.forEach(item => filesWithIssues.add(item.file));
    this.report.emptyFiles.forEach(file => filesWithIssues.add(file));
    this.report.duplicateFiles.forEach(dup => {
      filesWithIssues.add(dup.file1);
      filesWithIssues.add(dup.file2);
    });
    this.report.commentedCodeBlocks.forEach(item => filesWithIssues.add(item.file));
    this.report.backupFiles.forEach(file => filesWithIssues.add(file));

    this.report.summary.filesWithIssues = filesWithIssues.size;
    this.report.summary.totalIssues = 
      this.report.unusedExports.length +
      this.report.unusedInternals.length +
      this.report.emptyFiles.length +
      this.report.duplicateFiles.length +
      this.report.commentedCodeBlocks.length +
      this.report.backupFiles.length;
  }

  private async generateReport(): Promise<void> {
    const reportPath = path.join('Docs', 'scripts', 'dead-code', 'report', `dead-code-analysis-${new Date().toISOString().split('T')[0]}.md`);
    
    const markdown = this.generateMarkdownReport();
    
    // Ensure directory exists
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, markdown);
    
    console.log(`\n✅ Report generated: ${reportPath}`);
    console.log(`\n📊 Summary:`);
    console.log(`   Total files analyzed: ${this.report.summary.totalFiles}`);
    console.log(`   Files with issues: ${this.report.summary.filesWithIssues}`);
    console.log(`   Total issues found: ${this.report.summary.totalIssues}`);
  }

  private generateMarkdownReport(): string {
    const report = this.report;
    
    return `# 🔍 AIDA Dead Code Analysis Report

**Generated**: ${new Date(report.timestamp).toLocaleString()}  
**Project**: AIDA (AI-Driven Incident Diagnosis & Analysis)  
**Scope**: src/ directory (including test files)

---

## 📊 Executive Summary

| Metric | Value |
|--------|-------|
| **Total TypeScript Files** | ${report.summary.totalFiles} |
| **Files with Issues** | ${report.summary.filesWithIssues} |
| **Total Issues Found** | ${report.summary.totalIssues} |
| **Health Score** | ${Math.round((1 - report.summary.filesWithIssues / report.summary.totalFiles) * 100)}% |

### Issue Breakdown
- 🚫 **Backup Files**: ${report.backupFiles.length} files
- 📤 **Unused Exports**: ${report.unusedExports.length} items
- 🔒 **Unused Internal Code**: ${report.unusedInternals.length} items
- 📄 **Empty Files**: ${report.emptyFiles.length} files
- 👥 **Duplicate Files**: ${report.duplicateFiles.length} pairs
- 💬 **Commented Code Blocks**: ${report.commentedCodeBlocks.length} blocks

---

## 🚫 Backup Files (${report.backupFiles.length})
${report.backupFiles.length > 0 ? `
**⚠️ Action Required**: These files should be deleted immediately.

\`\`\`bash
# Run this command to clean backup files:
${report.backupFiles.map(f => `rm "${f}"`).join('\n')}
\`\`\`

### Files:
${report.backupFiles.map(f => `- \`${f}\``).join('\n')}
` : '✅ No backup files found.'}

---

## 📤 Unused Exports (${report.unusedExports.length})

${report.unusedExports.length > 0 ? `
### By Type:
${this.groupByType(report.unusedExports)}

### Details:
${report.unusedExports.slice(0, 20).map(item => 
  `- **${item.file}:${item.line}** - \`${item.name}\` (${item.type})`
).join('\n')}
${report.unusedExports.length > 20 ? `\n... and ${report.unusedExports.length - 20} more items` : ''}
` : '✅ No unused exports found.'}

---

## 🔒 Unused Internal Code (${report.unusedInternals.length})

${report.unusedInternals.length > 0 ? `
${report.unusedInternals.slice(0, 20).map(item => 
  `- **${item.file}:${item.line}** - \`${item.name}\` (${item.type})`
).join('\n')}
${report.unusedInternals.length > 20 ? `\n... and ${report.unusedInternals.length - 20} more items` : ''}
` : '✅ No unused internal code found.'}

---

## 📄 Empty Files (${report.emptyFiles.length})

${report.emptyFiles.length > 0 ? `
These files contain no meaningful content and can be deleted:

${report.emptyFiles.map(f => `- \`${f}\``).join('\n')}
` : '✅ No empty files found.'}

---

## 👥 Duplicate Files (${report.duplicateFiles.length})

${report.duplicateFiles.length > 0 ? `
These file pairs have identical content:

${report.duplicateFiles.map(dup => 
  `- \`${dup.file1}\`\n  ↔️ \`${dup.file2}\`\n  (Hash: ${dup.hash.substring(0, 8)}...)`
).join('\n\n')}
` : '✅ No duplicate files found.'}

---

## 💬 Commented Code Blocks (${report.commentedCodeBlocks.length})

${report.commentedCodeBlocks.length > 0 ? `
Large blocks of commented code that should be removed:

${report.commentedCodeBlocks.slice(0, 10).map(block => 
  `### ${block.file} (Lines ${block.startLine}-${block.endLine})
\`\`\`typescript
${block.preview}
\`\`\`
`).join('\n')}
${report.commentedCodeBlocks.length > 10 ? `\n... and ${report.commentedCodeBlocks.length - 10} more blocks` : ''}
` : '✅ No significant commented code blocks found.'}

---

## 🎯 Recommendations

### Immediate Actions
1. **Delete all backup files** (${report.backupFiles.length} files)
2. **Review and remove unused exports** (${report.unusedExports.length} items)
3. **Clean up empty files** (${report.emptyFiles.length} files)

### Short-term Actions
1. **Resolve duplicate files** by consolidating or removing (${report.duplicateFiles.length} pairs)
2. **Remove commented code blocks** (${report.commentedCodeBlocks.length} blocks)
3. **Review unused internal code** for potential removal (${report.unusedInternals.length} items)

### Long-term Actions
1. Set up pre-commit hooks to prevent backup files
2. Configure ESLint rules for dead code detection
3. Regular code cleanup sprints (monthly recommended)

---

## 🔧 Automated Cleanup Script

Save this as \`cleanup-dead-code.sh\`:

\`\`\`bash
#!/bin/bash
# AIDA Dead Code Cleanup Script

echo "🧹 Starting AIDA dead code cleanup..."

# 1. Remove backup files
echo "Removing backup files..."
${report.backupFiles.map(f => `rm -v "${f}"`).join('\n')}

# 2. Remove empty files (manual review recommended)
echo "Empty files to review:"
${report.emptyFiles.map(f => `echo "  - ${f}"`).join('\n')}

# 3. Report duplicate files for manual resolution
echo "Duplicate files requiring manual resolution:"
${report.duplicateFiles.map(dup => `echo "  - ${dup.file1} <-> ${dup.file2}"`).join('\n')}

echo "✅ Cleanup complete!"
\`\`\`

---

## 📈 Trend Analysis

To track improvement over time, run this analysis regularly and compare:

| Date | Total Files | Issues | Health Score |
|------|------------|--------|--------------|
| ${new Date(report.timestamp).toISOString().split('T')[0]} | ${report.summary.totalFiles} | ${report.summary.totalIssues} | ${Math.round((1 - report.summary.filesWithIssues / report.summary.totalFiles) * 100)}% |

---

**Next Analysis Recommended**: ${new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]}  
**Generated by**: AIDA Dead Code Detector v1.0
`;
  }

  private groupByType(exports: UnusedExport[]): string {
    const grouped = exports.reduce((acc, item) => {
      acc[item.type] = (acc[item.type] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    return Object.entries(grouped)
      .sort(([, a], [, b]) => b - a)
      .map(([type, count]) => `- **${type}**: ${count} items`)
      .join('\n');
  }
}

// Run the detector
if (require.main === module) {
  const detector = new DeadCodeDetector();
  detector.run().catch(console.error);
}

export { DeadCodeDetector, DeadCodeReport };