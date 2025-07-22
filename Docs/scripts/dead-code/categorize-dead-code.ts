#!/usr/bin/env ts-node

/**
 * Dead Code Categorizer - Classifies dead code by risk level
 */

import * as fs from 'fs';
import * as path from 'path';

interface DeadCodeItem {
  file: string;
  line: number;
  name: string;
  type?: string;
  note?: string;
}

interface CategorizedDeadCode {
  lowRisk: DeadCodeItem[];
  mediumRisk: DeadCodeItem[];
  highRisk: DeadCodeItem[];
  statistics: {
    total: number;
    byCategory: Record<string, number>;
    byType: Record<string, number>;
  };
}

export class DeadCodeCategorizer {
  private deadCodeItems: DeadCodeItem[] = [];

  async categorize(tsPruneOutputPath: string): Promise<CategorizedDeadCode> {
    // Parse ts-prune output
    this.parseTPruneOutput(tsPruneOutputPath);

    // Categorize by risk
    const categorized: CategorizedDeadCode = {
      lowRisk: [],
      mediumRisk: [],
      highRisk: [],
      statistics: {
        total: this.deadCodeItems.length,
        byCategory: { low: 0, medium: 0, high: 0 },
        byType: {}
      }
    };

    for (const item of this.deadCodeItems) {
      const riskLevel = this.assessRiskLevel(item);
      
      if (riskLevel === 'low') {
        categorized.lowRisk.push(item);
        categorized.statistics.byCategory.low++;
      } else if (riskLevel === 'medium') {
        categorized.mediumRisk.push(item);
        categorized.statistics.byCategory.medium++;
      } else {
        categorized.highRisk.push(item);
        categorized.statistics.byCategory.high++;
      }

      // Count by type
      const type = item.type || 'unknown';
      categorized.statistics.byType[type] = (categorized.statistics.byType[type] || 0) + 1;
    }

    return categorized;
  }

  private parseTPruneOutput(filePath: string): void {
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');

    for (const line of lines) {
      if (!line.trim()) continue;

      // Parse line format: "src/file.ts:123 - exportName (note)"
      const match = line.match(/^(.+):(\d+) - ([^\s]+)(\s+\((.+)\))?$/);
      if (match) {
        const [, file, lineNum, name, , note] = match;
        
        const item: DeadCodeItem = {
          file: file.trim(),
          line: parseInt(lineNum),
          name: name.trim(),
          note: note?.trim()
        };

        // Determine type from file/name
        item.type = this.determineType(item);
        this.deadCodeItems.push(item);
      }
    }
  }

  private determineType(item: DeadCodeItem): string {
    const { file, name } = item;

    // Test files
    if (file.includes('.test.ts') || file.includes('.spec.ts')) {
      return 'test';
    }

    // Mock/Test utilities
    if (file.includes('test-doubles') || file.includes('mocks') || name.startsWith('create')) {
      return 'test-util';
    }

    // Interfaces
    if (name.startsWith('I') && name[1] === name[1].toUpperCase()) {
      return 'interface';
    }

    // Types
    if (file.includes('types') || name.endsWith('Type') || name.endsWith('Config')) {
      return 'type';
    }

    // Classes
    if (name[0] === name[0].toUpperCase() && !name.includes('_')) {
      return 'class';
    }

    // Functions
    if (name[0] === name[0].toLowerCase()) {
      return 'function';
    }

    return 'unknown';
  }

  private assessRiskLevel(item: DeadCodeItem): 'low' | 'medium' | 'high' {
    const { file, name, note, type } = item;

    // HIGH RISK - Do not delete without careful review
    if (
      // DI tokens and registrations
      file.includes('di/tokens') ||
      file.includes('di/container') ||
      name.includes('TOKEN') ||
      name.includes('REGISTRY') ||
      
      // Strategy/Factory patterns (may be dynamically loaded)
      name.includes('Strategy') ||
      name.includes('Factory') ||
      file.includes('strategies') ||
      
      // Public API exports
      file.endsWith('/index.ts') && !note?.includes('used in module') ||
      
      // A2A protocol types
      file.includes('a2a-js/build') ||
      
      // Infrastructure interfaces
      file.includes('infrastructure/interfaces')
    ) {
      return 'high';
    }

    // LOW RISK - Safe to delete
    if (
      // Test utilities not used
      type === 'test-util' ||
      
      // Internal module usage only
      note === 'used in module' ||
      
      // Test files
      type === 'test' ||
      
      // Mock implementations
      name.startsWith('Mock') ||
      name.startsWith('createMock') ||
      
      // Deprecated or old files
      file.includes('.old.ts') ||
      file.includes('.backup')
    ) {
      return 'low';
    }

    // MEDIUM RISK - Default, needs review
    return 'medium';
  }

  generateReport(categorized: CategorizedDeadCode): string {
    const { lowRisk, mediumRisk, highRisk, statistics } = categorized;

    return `# 📊 Dead Code Risk Assessment Report

**Generated**: ${new Date().toISOString()}
**Total Dead Code Items**: ${statistics.total}

## 🎯 Risk Distribution

| Risk Level | Count | Percentage |
|------------|-------|------------|
| 🟢 LOW | ${statistics.byCategory.low} | ${(statistics.byCategory.low / statistics.total * 100).toFixed(1)}% |
| 🟡 MEDIUM | ${statistics.byCategory.medium} | ${(statistics.byCategory.medium / statistics.total * 100).toFixed(1)}% |
| 🔴 HIGH | ${statistics.byCategory.high} | ${(statistics.byCategory.high / statistics.total * 100).toFixed(1)}% |

## 📈 Type Distribution

| Type | Count |
|------|-------|
${Object.entries(statistics.byType)
  .sort(([, a], [, b]) => b - a)
  .map(([type, count]) => `| ${type} | ${count} |`)
  .join('\n')}

---

## 🟢 LOW RISK Items (${lowRisk.length})
**Safe to delete - mostly test utilities and internal module code**

${lowRisk.slice(0, 20).map(item => 
  `- \`${item.file}:${item.line}\` - **${item.name}** ${item.note ? `(${item.note})` : ''}`
).join('\n')}
${lowRisk.length > 20 ? `\n... and ${lowRisk.length - 20} more items` : ''}

---

## 🟡 MEDIUM RISK Items (${mediumRisk.length})
**Requires review before deletion**

${mediumRisk.slice(0, 20).map(item => 
  `- \`${item.file}:${item.line}\` - **${item.name}** [${item.type}]`
).join('\n')}
${mediumRisk.length > 20 ? `\n... and ${mediumRisk.length - 20} more items` : ''}

---

## 🔴 HIGH RISK Items (${highRisk.length})
**DO NOT DELETE without extensive review**

${highRisk.slice(0, 20).map(item => 
  `- \`${item.file}:${item.line}\` - **${item.name}** [${item.type}]`
).join('\n')}
${highRisk.length > 20 ? `\n... and ${highRisk.length - 20} more items` : ''}

---

## 🛠️ Recommended Actions

### Phase 1: LOW RISK Cleanup (Safe)
\`\`\`bash
# Review and delete test utilities
grep -r "createMock" src/ test/

# Remove "used in module" items
# These are only used internally and can be made private
\`\`\`

### Phase 2: MEDIUM RISK Review
1. Check each item for:
   - Dynamic imports
   - Reflection usage
   - External dependencies
2. Create PR for each batch

### Phase 3: HIGH RISK Analysis
1. Never delete DI tokens
2. Check strategy registration
3. Verify public API usage
4. Review with team

---

**Next Step**: Start with LOW RISK items for safe cleanup`;
  }
}

// Run if called directly
if (require.main === module) {
  const categorizer = new DeadCodeCategorizer();
  const tsPruneOutput = path.join(__dirname, 'report', 'ts-prune-output.txt');
  
  categorizer.categorize(tsPruneOutput).then(result => {
    const report = categorizer.generateReport(result);
    const reportPath = path.join(__dirname, 'report', 'dead-code-risk-assessment.md');
    fs.writeFileSync(reportPath, report);
    console.log(`✅ Risk assessment report generated: ${reportPath}`);
  });
}

export { DeadCodeItem, CategorizedDeadCode };