#!/usr/bin/env node

/**
 * 품질 메트릭 수집 및 리포트 생성
 * @description 04-code-quality-assurance.md 품질 지표 추적
 */

const fs = require('fs');
const path = require('path');

/**
 * @typedef {Object} QualityMetrics
 * @property {string} date - 측정 날짜
 * @property {Object} coverage - 코드 커버리지
 * @property {Object} complexity - 코드 복잡도
 * @property {Object} security - 보안 메트릭
 * @property {Object} performance - 성능 메트릭
 */

/**
 * Jest 커버리지 결과 파싱
 * @returns {Object|null} 커버리지 데이터
 */
function getCoverageData() {
  const coveragePath = path.join(process.cwd(), 'coverage', 'coverage-summary.json');
  
  if (!fs.existsSync(coveragePath)) {
    console.log('⚠️  Coverage data not found. Run tests with coverage first.');
    return null;
  }
  
  try {
    const coverageData = JSON.parse(fs.readFileSync(coveragePath, 'utf8'));
    return coverageData.total;
  } catch (error) {
    console.error('Error reading coverage data:', error);
    return null;
  }
}

/**
 * Package.json에서 메트릭 추출
 * @returns {Object} 프로젝트 메트릭
 */
function getProjectMetrics() {
  const packagePath = path.join(process.cwd(), 'package.json');
  const packageData = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
  
  return {
    name: packageData.name,
    version: packageData.version,
    dependencies: Object.keys(packageData.dependencies || {}).length,
    devDependencies: Object.keys(packageData.devDependencies || {}).length
  };
}

/**
 * 코드 복잡도 계산 (간단한 버전)
 * @returns {Object} 복잡도 메트릭
 */
function calculateComplexity() {
  const srcPath = path.join(process.cwd(), 'src');
  let totalFiles = 0;
  let totalLines = 0;
  
  function countFiles(dir) {
    if (!fs.existsSync(dir)) return;
    
    const files = fs.readdirSync(dir);
    files.forEach(file => {
      const filePath = path.join(dir, file);
      const stat = fs.statSync(filePath);
      
      if (stat.isDirectory()) {
        countFiles(filePath);
      } else if (file.endsWith('.js')) {
        totalFiles++;
        const content = fs.readFileSync(filePath, 'utf8');
        totalLines += content.split('\n').length;
      }
    });
  }
  
  countFiles(srcPath);
  
  return {
    files: totalFiles,
    lines: totalLines,
    averageLinesPerFile: totalFiles > 0 ? Math.round(totalLines / totalFiles) : 0
  };
}

/**
 * 품질 메트릭 생성
 * @returns {QualityMetrics} 품질 지표
 */
function generateQualityMetrics() {
  const coverage = getCoverageData();
  const project = getProjectMetrics();
  const complexity = calculateComplexity();
  
  return {
    date: new Date().toISOString(),
    project,
    coverage,
    complexity,
    targets: {
      coverage: {
        statements: 70,
        branches: 70, 
        functions: 70,
        lines: 70
      },
      complexity: {
        maxLinesPerFile: 50,
        maxComplexity: 10
      }
    }
  };
}

/**
 * 품질 리포트 출력
 * @param {QualityMetrics} metrics - 품질 지표
 */
function printQualityReport(metrics) {
  console.log('\n📊 Quality Metrics Report');
  console.log('='.repeat(50));
  
  console.log(`📅 Date: ${new Date(metrics.date).toLocaleString()}`);
  console.log(`📦 Project: ${metrics.project.name} v${metrics.project.version}`);
  
  if (metrics.coverage) {
    console.log('\n📈 Test Coverage:');
    console.log(`  Statements: ${metrics.coverage.statements.pct}% (target: ${metrics.targets.coverage.statements}%)`);
    console.log(`  Branches:   ${metrics.coverage.branches.pct}% (target: ${metrics.targets.coverage.branches}%)`);
    console.log(`  Functions:  ${metrics.coverage.functions.pct}% (target: ${metrics.targets.coverage.functions}%)`);
    console.log(`  Lines:      ${metrics.coverage.lines.pct}% (target: ${metrics.targets.coverage.lines}%)`);
    
    // 목표 달성 여부
    const targetsAchieved = [
      metrics.coverage.statements.pct >= metrics.targets.coverage.statements,
      metrics.coverage.branches.pct >= metrics.targets.coverage.branches,
      metrics.coverage.functions.pct >= metrics.targets.coverage.functions,
      metrics.coverage.lines.pct >= metrics.targets.coverage.lines
    ];
    
    const achievedCount = targetsAchieved.filter(Boolean).length;
    console.log(`  Status: ${achievedCount}/4 targets achieved ${achievedCount === 4 ? '✅' : '⚠️'}`);
  }
  
  console.log('\n🔧 Code Complexity:');
  console.log(`  Files: ${metrics.complexity.files}`);
  console.log(`  Lines: ${metrics.complexity.lines}`);
  console.log(`  Average lines/file: ${metrics.complexity.averageLinesPerFile} (target: <${metrics.targets.complexity.maxLinesPerFile})`);
  
  const complexityOk = metrics.complexity.averageLinesPerFile < metrics.targets.complexity.maxLinesPerFile;
  console.log(`  Status: ${complexityOk ? '✅ Good' : '⚠️  High complexity'}`);
  
  console.log('\n📦 Dependencies:');
  console.log(`  Production: ${metrics.project.dependencies}`);
  console.log(`  Development: ${metrics.project.devDependencies}`);
  
  console.log('\n' + '='.repeat(50));
}

/**
 * 품질 리포트를 파일로 저장
 * @param {QualityMetrics} metrics - 품질 지표
 */
function saveQualityReport(metrics) {
  const reportsDir = path.join(process.cwd(), 'reports');
  if (!fs.existsSync(reportsDir)) {
    fs.mkdirSync(reportsDir, { recursive: true });
  }
  
  const timestamp = new Date().toISOString().slice(0, 10);
  const reportPath = path.join(reportsDir, `quality-${timestamp}.json`);
  
  fs.writeFileSync(reportPath, JSON.stringify(metrics, null, 2));
  console.log(`📄 Quality report saved to: ${reportPath}`);
}

// 메인 실행
if (require.main === module) {
  try {
    const metrics = generateQualityMetrics();
    printQualityReport(metrics);
    saveQualityReport(metrics);
  } catch (error) {
    console.error('Error generating quality metrics:', error);
    process.exit(1);
  }
}

module.exports = { generateQualityMetrics, printQualityReport };