#!/usr/bin/env node

const fs = require('fs').promises;
const path = require('path');

/**
 * Test Monitor - 모든 테스트 결과를 수집하고 분석하여 최종 보고서 생성
 * @module test-monitor
 */

class TestMonitor {
  constructor() {
    this.testResultsPath = path.join(__dirname, '../test-results.json');
    this.trafficAnalysisPath = path.join(__dirname, '../traffic-analysis.txt');
    this.logsDir = path.join(__dirname, '../logs');
    this.finalReportPath = '/app/results/final-report.md';
    
    this.results = {
      testResults: null,
      trafficAnalysis: null,
      logs: {},
      metrics: {
        totalTests: 0,
        successfulTests: 0,
        failedTests: 0,
        successRate: 0,
        avgResponseTime: 0,
        proxySupport: {
          httpProxy: false,
          httpsProxy: false,
          envVarRecognition: false,
          requestInterception: false
        }
      }
    };
  }

  /**
   * 메인 실행 함수
   */
  async run() {
    try {
      console.log('🔍 테스트 결과 수집 시작...\n');
      
      // 1. 테스트 결과 수집
      await this.collectTestResults();
      
      // 2. 트래픽 분석 수집
      await this.collectTrafficAnalysis();
      
      // 3. 로그 파일 수집
      await this.collectLogs();
      
      // 4. 메트릭 분석
      await this.analyzeMetrics();
      
      // 5. 프록시 지원 상태 분석
      await this.analyzeProxySupport();
      
      // 6. 최종 보고서 생성
      await this.generateFinalReport();
      
      console.log('✅ 최종 보고서 생성 완료:', this.finalReportPath);
      
    } catch (error) {
      console.error('❌ 모니터링 실패:', error);
      process.exit(1);
    }
  }

  /**
   * 테스트 결과 JSON 파일 수집
   */
  async collectTestResults() {
    try {
      const data = await fs.readFile(this.testResultsPath, 'utf8');
      this.results.testResults = JSON.parse(data);
      console.log('✓ test-results.json 수집 완료');
    } catch (error) {
      console.error('⚠️  test-results.json 읽기 실패:', error.message);
      this.results.testResults = { error: error.message };
    }
  }

  /**
   * 트래픽 분석 파일 수집
   */
  async collectTrafficAnalysis() {
    try {
      const data = await fs.readFile(this.trafficAnalysisPath, 'utf8');
      this.results.trafficAnalysis = data;
      console.log('✓ traffic-analysis.txt 수집 완료');
    } catch (error) {
      console.error('⚠️  traffic-analysis.txt 읽기 실패:', error.message);
      this.results.trafficAnalysis = 'No traffic analysis available';
    }
  }

  /**
   * 로그 파일들 수집
   */
  async collectLogs() {
    try {
      const files = await fs.readdir(this.logsDir);
      const logFiles = files.filter(f => f.endsWith('.log'));
      
      for (const file of logFiles) {
        const filePath = path.join(this.logsDir, file);
        const content = await fs.readFile(filePath, 'utf8');
        this.results.logs[file] = content;
      }
      
      console.log(`✓ ${logFiles.length}개의 로그 파일 수집 완료`);
    } catch (error) {
      console.error('⚠️  로그 파일 수집 실패:', error.message);
    }
  }

  /**
   * 메트릭 분석
   */
  async analyzeMetrics() {
    if (this.results.testResults && this.results.testResults.tests) {
      const tests = this.results.testResults.tests;
      
      this.results.metrics.totalTests = tests.length;
      this.results.metrics.successfulTests = tests.filter(t => t.success).length;
      this.results.metrics.failedTests = tests.filter(t => !t.success).length;
      this.results.metrics.successRate = 
        (this.results.metrics.successfulTests / this.results.metrics.totalTests * 100).toFixed(2);
      
      // 평균 응답 시간 계산
      const responseTimes = tests
        .filter(t => t.responseTime)
        .map(t => t.responseTime);
      
      if (responseTimes.length > 0) {
        this.results.metrics.avgResponseTime = 
          (responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length).toFixed(2);
      }
    }
    
    console.log('✓ 메트릭 분석 완료');
  }

  /**
   * 프록시 지원 상태 분석
   */
  async analyzeProxySupport() {
    // 트래픽 분석에서 프록시 지원 확인
    if (this.results.trafficAnalysis) {
      const analysis = this.results.trafficAnalysis.toLowerCase();
      
      this.results.metrics.proxySupport.httpProxy = 
        analysis.includes('http_proxy') || analysis.includes('proxy connection established');
      
      this.results.metrics.proxySupport.httpsProxy = 
        analysis.includes('https_proxy') || analysis.includes('ssl proxy');
      
      this.results.metrics.proxySupport.envVarRecognition = 
        analysis.includes('env var') || analysis.includes('environment variable');
      
      this.results.metrics.proxySupport.requestInterception = 
        analysis.includes('intercepted') || analysis.includes('request modified');
    }
    
    // 로그에서 추가 정보 확인
    Object.values(this.results.logs).forEach(log => {
      if (log.includes('Proxy connection established')) {
        this.results.metrics.proxySupport.requestInterception = true;
      }
    });
    
    console.log('✓ 프록시 지원 상태 분석 완료');
  }

  /**
   * 최종 보고서 생성
   */
  async generateFinalReport() {
    const report = `# SDK Proxy Test Final Report

## 📅 테스트 실행 정보
- **실행 시간**: ${new Date().toISOString()}
- **모니터링 버전**: 1.0.0
- **환경**: ${process.env.NODE_ENV || 'development'}

## 📊 전체 테스트 메트릭

| 메트릭 | 값 |
|--------|-----|
| 전체 테스트 수 | ${this.results.metrics.totalTests} |
| 성공한 테스트 | ${this.results.metrics.successfulTests} |
| 실패한 테스트 | ${this.results.metrics.failedTests} |
| 성공률 | ${this.results.metrics.successRate}% |
| 평균 응답 시간 | ${this.results.metrics.avgResponseTime}ms |

## 🔌 프록시 지원 상태

### 지원 여부
- **HTTP 프록시**: ${this.results.metrics.proxySupport.httpProxy ? '✅ 지원' : '❌ 미지원'}
- **HTTPS 프록시**: ${this.results.metrics.proxySupport.httpsProxy ? '✅ 지원' : '❌ 미지원'}
- **환경 변수 인식**: ${this.results.metrics.proxySupport.envVarRecognition ? '✅ 지원' : '❌ 미지원'}
- **요청 인터셉션**: ${this.results.metrics.proxySupport.requestInterception ? '✅ 가능' : '❌ 불가능'}

### 프록시 지원 점수
${this.calculateProxyScore()}/100점

## 📈 성공/실패 패턴 분석

${this.analyzeSuccessFailurePatterns()}

## 🔗 Kong 통합 가능성 평가

${this.evaluateKongIntegration()}

## 💡 실행 가능한 권고사항

${this.generateRecommendations()}

## 🔍 상세 테스트 결과

### 테스트별 결과
${this.generateDetailedTestResults()}

### 트래픽 분석 요약
\`\`\`
${this.summarizeTrafficAnalysis()}
\`\`\`

## 🚨 주요 이슈 및 경고

${this.identifyMajorIssues()}

## 📝 결론

${this.generateConclusion()}

---
*Generated by SDK Proxy Test Monitor v1.0.0*
`;

    // 결과 디렉토리 생성
    const resultsDir = path.dirname(this.finalReportPath);
    await fs.mkdir(resultsDir, { recursive: true });
    
    // 보고서 저장
    await fs.writeFile(this.finalReportPath, report, 'utf8');
  }

  /**
   * 프록시 지원 점수 계산
   */
  calculateProxyScore() {
    const support = this.results.metrics.proxySupport;
    let score = 0;
    
    if (support.httpProxy) score += 25;
    if (support.httpsProxy) score += 25;
    if (support.envVarRecognition) score += 25;
    if (support.requestInterception) score += 25;
    
    return score;
  }

  /**
   * 성공/실패 패턴 분석
   */
  analyzeSuccessFailurePatterns() {
    if (!this.results.testResults || !this.results.testResults.tests) {
      return '테스트 결과를 분석할 수 없습니다.';
    }

    const tests = this.results.testResults.tests;
    const failedTests = tests.filter(t => !t.success);
    const successTests = tests.filter(t => t.success);

    let analysis = '### 성공 패턴\n';
    if (successTests.length > 0) {
      analysis += '- 기본 HTTP 요청은 정상 작동\n';
      analysis += '- 직접 API 호출 시 안정적인 응답\n';
      
      const avgSuccessTime = successTests
        .filter(t => t.responseTime)
        .reduce((sum, t) => sum + t.responseTime, 0) / successTests.length;
      
      analysis += `- 평균 성공 응답 시간: ${avgSuccessTime.toFixed(2)}ms\n`;
    }

    analysis += '\n### 실패 패턴\n';
    if (failedTests.length > 0) {
      const errorTypes = {};
      failedTests.forEach(test => {
        const errorType = test.error?.type || 'Unknown';
        errorTypes[errorType] = (errorTypes[errorType] || 0) + 1;
      });

      Object.entries(errorTypes).forEach(([type, count]) => {
        analysis += `- ${type}: ${count}건\n`;
      });
    } else {
      analysis += '- 실패한 테스트 없음\n';
    }

    return analysis;
  }

  /**
   * Kong 통합 가능성 평가
   */
  evaluateKongIntegration() {
    const proxyScore = this.calculateProxyScore();
    const successRate = parseFloat(this.results.metrics.successRate);

    let evaluation = '### 통합 가능성 점수: ';
    let integrationScore = 0;

    // 프록시 지원 점수 (40%)
    integrationScore += (proxyScore / 100) * 40;

    // 성공률 점수 (30%)
    integrationScore += (successRate / 100) * 30;

    // 성능 점수 (30%)
    const avgTime = parseFloat(this.results.metrics.avgResponseTime);
    if (avgTime < 100) {
      integrationScore += 30;
    } else if (avgTime < 500) {
      integrationScore += 20;
    } else if (avgTime < 1000) {
      integrationScore += 10;
    }

    evaluation += `${integrationScore.toFixed(1)}/100점\n\n`;

    evaluation += '### 통합 준비 상태\n';
    if (integrationScore >= 80) {
      evaluation += '✅ **즉시 통합 가능**: SDK는 Kong과의 통합에 적합한 상태입니다.\n';
    } else if (integrationScore >= 60) {
      evaluation += '⚠️ **부분 통합 가능**: 일부 기능 개선 후 통합 가능합니다.\n';
    } else {
      evaluation += '❌ **통합 준비 부족**: 상당한 개선이 필요합니다.\n';
    }

    evaluation += '\n### Kong 플러그인으로서의 적합성\n';
    if (this.results.metrics.proxySupport.requestInterception) {
      evaluation += '- ✅ 요청 인터셉션 가능\n';
    } else {
      evaluation += '- ❌ 요청 인터셉션 불가능\n';
    }

    if (this.results.metrics.proxySupport.envVarRecognition) {
      evaluation += '- ✅ 환경 변수 설정 지원\n';
    } else {
      evaluation += '- ❌ 환경 변수 설정 미지원\n';
    }

    return evaluation;
  }

  /**
   * 권고사항 생성
   */
  generateRecommendations() {
    const recommendations = [];
    const proxyScore = this.calculateProxyScore();
    const successRate = parseFloat(this.results.metrics.successRate);

    // 프록시 관련 권고사항
    if (!this.results.metrics.proxySupport.httpProxy) {
      recommendations.push({
        priority: 'HIGH',
        category: 'PROXY',
        action: 'HTTP_PROXY 환경 변수 지원 구현',
        reason: 'Kong 통합을 위해 필수적인 기능입니다.'
      });
    }

    if (!this.results.metrics.proxySupport.httpsProxy) {
      recommendations.push({
        priority: 'HIGH',
        category: 'PROXY',
        action: 'HTTPS_PROXY 환경 변수 지원 구현',
        reason: 'SSL/TLS 트래픽 처리를 위해 필요합니다.'
      });
    }

    if (!this.results.metrics.proxySupport.requestInterception) {
      recommendations.push({
        priority: 'CRITICAL',
        category: 'ARCHITECTURE',
        action: 'SDK 아키텍처 재설계 - 요청 인터셉션 레이어 추가',
        reason: 'Kong 플러그인으로 작동하기 위한 핵심 요구사항입니다.'
      });
    }

    // 성능 관련 권고사항
    const avgTime = parseFloat(this.results.metrics.avgResponseTime);
    if (avgTime > 1000) {
      recommendations.push({
        priority: 'MEDIUM',
        category: 'PERFORMANCE',
        action: '응답 시간 최적화 - 캐싱 메커니즘 구현',
        reason: `현재 평균 응답 시간(${avgTime}ms)이 목표치(1000ms)를 초과합니다.`
      });
    }

    // 안정성 관련 권고사항
    if (successRate < 95) {
      recommendations.push({
        priority: 'HIGH',
        category: 'RELIABILITY',
        action: '에러 처리 개선 및 재시도 로직 구현',
        reason: `현재 성공률(${successRate}%)이 프로덕션 기준(95%)에 미달합니다.`
      });
    }

    // 권고사항 포맷팅
    let output = '';
    const criticalRecs = recommendations.filter(r => r.priority === 'CRITICAL');
    const highRecs = recommendations.filter(r => r.priority === 'HIGH');
    const mediumRecs = recommendations.filter(r => r.priority === 'MEDIUM');

    if (criticalRecs.length > 0) {
      output += '### 🚨 긴급 조치 필요 (CRITICAL)\n';
      criticalRecs.forEach(rec => {
        output += `- **[${rec.category}]** ${rec.action}\n  - 이유: ${rec.reason}\n`;
      });
      output += '\n';
    }

    if (highRecs.length > 0) {
      output += '### ⚠️ 높은 우선순위 (HIGH)\n';
      highRecs.forEach(rec => {
        output += `- **[${rec.category}]** ${rec.action}\n  - 이유: ${rec.reason}\n`;
      });
      output += '\n';
    }

    if (mediumRecs.length > 0) {
      output += '### 📌 중간 우선순위 (MEDIUM)\n';
      mediumRecs.forEach(rec => {
        output += `- **[${rec.category}]** ${rec.action}\n  - 이유: ${rec.reason}\n`;
      });
    }

    if (recommendations.length === 0) {
      output = '✅ 현재 구성으로 Kong 통합에 적합합니다. 추가 개선사항 없음.';
    }

    return output;
  }

  /**
   * 상세 테스트 결과 생성
   */
  generateDetailedTestResults() {
    if (!this.results.testResults || !this.results.testResults.tests) {
      return '테스트 결과가 없습니다.';
    }

    let output = '';
    this.results.testResults.tests.forEach((test, index) => {
      output += `\n#### Test ${index + 1}: ${test.name || 'Unnamed Test'}\n`;
      output += `- 상태: ${test.success ? '✅ 성공' : '❌ 실패'}\n`;
      if (test.responseTime) {
        output += `- 응답 시간: ${test.responseTime}ms\n`;
      }
      if (test.error) {
        output += `- 에러: ${test.error.message || test.error}\n`;
      }
    });

    return output || '상세 테스트 결과가 없습니다.';
  }

  /**
   * 트래픽 분석 요약
   */
  summarizeTrafficAnalysis() {
    if (!this.results.trafficAnalysis) {
      return '트래픽 분석 데이터가 없습니다.';
    }

    const lines = this.results.trafficAnalysis.split('\n');
    const summary = lines.slice(0, 20).join('\n');
    
    if (lines.length > 20) {
      return summary + '\n... (총 ' + lines.length + '줄)';
    }
    
    return summary;
  }

  /**
   * 주요 이슈 식별
   */
  identifyMajorIssues() {
    const issues = [];

    // 프록시 미지원 이슈
    if (this.calculateProxyScore() === 0) {
      issues.push({
        severity: 'CRITICAL',
        issue: '프록시 기능 전체 미지원',
        impact: 'Kong 통합 불가능'
      });
    }

    // 높은 실패율 이슈
    if (this.results.metrics.failedTests > this.results.metrics.successfulTests) {
      issues.push({
        severity: 'HIGH',
        issue: '50% 이상의 테스트 실패',
        impact: '프로덕션 배포 위험'
      });
    }

    // 성능 이슈
    const avgTime = parseFloat(this.results.metrics.avgResponseTime);
    if (avgTime > 3000) {
      issues.push({
        severity: 'MEDIUM',
        issue: '매우 느린 응답 시간',
        impact: '사용자 경험 저하'
      });
    }

    if (issues.length === 0) {
      return '✅ 주요 이슈가 발견되지 않았습니다.';
    }

    let output = '';
    issues.forEach(issue => {
      output += `### ${issue.severity === 'CRITICAL' ? '🔴' : issue.severity === 'HIGH' ? '🟡' : '🟠'} ${issue.issue}\n`;
      output += `- 영향: ${issue.impact}\n\n`;
    });

    return output;
  }

  /**
   * 결론 생성
   */
  generateConclusion() {
    const proxyScore = this.calculateProxyScore();
    const successRate = parseFloat(this.results.metrics.successRate);
    const integrationScore = this.calculateIntegrationScore();

    let conclusion = '';

    if (integrationScore >= 80) {
      conclusion += '### ✅ Kong 통합 준비 완료\n\n';
      conclusion += 'SDK는 Kong과의 통합을 위한 모든 요구사항을 충족합니다. ';
      conclusion += '즉시 프로덕션 환경에서 사용 가능합니다.\n\n';
      conclusion += '**다음 단계**: Kong 플러그인 설정 및 배포 진행';
    } else if (integrationScore >= 60) {
      conclusion += '### ⚠️ 부분적 통합 가능\n\n';
      conclusion += 'SDK는 기본적인 기능은 제공하지만, 완전한 통합을 위해서는 ';
      conclusion += '일부 개선이 필요합니다.\n\n';
      conclusion += '**다음 단계**: 권고사항에 따른 개선 작업 후 재평가';
    } else {
      conclusion += '### ❌ 통합 준비 부족\n\n';
      conclusion += 'SDK는 현재 Kong과의 통합에 적합하지 않습니다. ';
      conclusion += '핵심 기능 구현이 필요합니다.\n\n';
      conclusion += '**다음 단계**: 아키텍처 재설계 및 핵심 기능 구현';
    }

    conclusion += '\n\n### 핵심 지표 요약\n';
    conclusion += `- 프록시 지원: ${proxyScore}%\n`;
    conclusion += `- 테스트 성공률: ${successRate}%\n`;
    conclusion += `- 통합 준비도: ${integrationScore}%\n`;

    return conclusion;
  }

  /**
   * 통합 점수 계산
   */
  calculateIntegrationScore() {
    const proxyScore = this.calculateProxyScore();
    const successRate = parseFloat(this.results.metrics.successRate);
    const avgTime = parseFloat(this.results.metrics.avgResponseTime);

    let score = 0;
    score += (proxyScore / 100) * 40;
    score += (successRate / 100) * 30;

    if (avgTime < 100) score += 30;
    else if (avgTime < 500) score += 20;
    else if (avgTime < 1000) score += 10;

    return score.toFixed(1);
  }
}

// 메인 실행
if (require.main === module) {
  const monitor = new TestMonitor();
  monitor.run().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

module.exports = TestMonitor;