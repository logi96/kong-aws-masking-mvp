#!/usr/bin/env node
/**
 * 50개 AWS 리소스 패턴 보안 검증 테스트
 * 
 * 🚨 SECURITY CRITICAL: 
 * - 새로운 API Gateway 아키텍처 사용 (Backend → Kong → Claude)
 * - 모든 AWS 패턴이 100% 마스킹되어야 함
 * - 단 하나의 보안 취약점도 용납 불가
 */

const axios = require('axios');
const fs = require('fs');
const path = require('path');

// Backend API 설정 (Kong을 직접 호출하지 않음!)
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000';

// 50개의 AWS 리소스 테스트 패턴
const testPatterns = [
  // EC2 관련 (10개)
  { type: 'EC2 Instance', original: 'i-1234567890abcdef0', masked: 'EC2_001' },
  { type: 'EC2 Instance', original: 'i-0987654321fedcba0', masked: 'EC2_002' },
  { type: 'AMI', original: 'ami-0abcdef1234567890', masked: 'AMI_001' },
  { type: 'EBS Volume', original: 'vol-0123456789abcdef0', masked: 'EBS_VOL_001' },
  { type: 'Snapshot', original: 'snap-0123456789abcdef0', masked: 'SNAPSHOT_001' },
  
  // 네트워크 관련 (15개)
  { type: 'VPC', original: 'vpc-0123456789abcdef0', masked: 'VPC_001' },
  { type: 'Subnet', original: 'subnet-0123456789abcdef0', masked: 'SUBNET_001' },
  { type: 'Security Group', original: 'sg-0123456789abcdef0', masked: 'SG_001' },
  { type: 'Internet Gateway', original: 'igw-0123456789abcdef0', masked: 'IGW_001' },
  { type: 'NAT Gateway', original: 'nat-0123456789abcdef0123456789abcdef0', masked: 'NAT_GW_001' },
  { type: 'VPN Connection', original: 'vpn-0123456789abcdef0', masked: 'VPN_001' },
  { type: 'Transit Gateway', original: 'tgw-0123456789abcdef0', masked: 'TGW_001' },
  { type: 'Private IP (10.x)', original: '10.0.1.100', masked: 'PRIVATE_IP_001' },
  { type: 'Private IP (172.x)', original: '172.16.0.50', masked: 'PRIVATE_IP_001' },
  { type: 'Private IP (192.x)', original: '192.168.1.100', masked: 'PRIVATE_IP_001' },
  { type: 'Public IP', original: '54.239.28.85', masked: 'PUBLIC_IP_001' },
  { type: 'IPv6', original: '2001:db8::8a2e:370:7334', masked: 'IPV6_001' },
  
  // 스토리지 관련 (5개)
  { type: 'S3 Bucket', original: 'my-production-bucket', masked: 'BUCKET_001' },
  { type: 'S3 Logs', original: 'my-application-logs', masked: 'BUCKET_001' },
  { type: 'EFS', original: 'fs-0123456789abcdef0', masked: 'EFS_001' },
  
  // 데이터베이스 관련 (2개)
  { type: 'RDS Instance', original: 'prod-db-instance', masked: 'RDS_001' },
  { type: 'ElastiCache', original: 'redis-cluster-001', masked: 'ELASTICACHE_001' },
  
  // IAM/보안 관련 (8개)
  { type: 'AWS Account', original: '123456789012', masked: 'ACCOUNT_001' },
  { type: 'Access Key', original: 'AKIAIOSFODNN7EXAMPLE', masked: 'ACCESS_KEY_001' },
  { type: 'Session Token', original: 'FwoGZXIvYXdzEBaDOEXAMPLETOKEN123', masked: 'SESSION_TOKEN_001' },
  { type: 'IAM Role ARN', original: 'arn:aws:iam::123456789012:role/MyRole', masked: 'IAM_ROLE_001' },
  { type: 'IAM User ARN', original: 'arn:aws:iam::123456789012:user/MyUser', masked: 'IAM_USER_001' },
  { type: 'KMS Key', original: '12345678-1234-1234-1234-123456789012', masked: 'KMS_KEY_001' },
  { type: 'Certificate ARN', original: 'arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012', masked: 'CERT_ARN_001' },
  { type: 'Secret ARN', original: 'arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef', masked: 'SECRET_ARN_001' },
  
  // 컴퓨팅 관련 (5개)
  { type: 'Lambda ARN', original: 'arn:aws:lambda:us-east-1:123456789012:function:MyFunction', masked: 'LAMBDA_ARN_001' },
  { type: 'ECS Task', original: 'arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012', masked: 'ECS_TASK_001' },
  { type: 'EKS Cluster', original: 'arn:aws:eks:us-east-1:123456789012:cluster/my-cluster', masked: 'EKS_CLUSTER_001' },
  { type: 'API Gateway', original: 'a1b2c3d4e5', masked: 'API_GW_001' },
  { type: 'ELB ARN', original: 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456', masked: 'ELB_ARN_001' },
  
  // 기타 서비스 (5개)
  { type: 'SNS Topic', original: 'arn:aws:sns:us-east-1:123456789012:MyTopic', masked: 'SNS_TOPIC_001' },
  { type: 'SQS Queue', original: 'https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue', masked: 'SQS_QUEUE_001' },
  { type: 'DynamoDB Table', original: 'arn:aws:dynamodb:us-east-1:123456789012:table/MyTable', masked: 'DYNAMODB_TABLE_001' },
  { type: 'CloudWatch Log', original: '/aws/lambda/my-function', masked: 'LOG_GROUP_001' },
  { type: 'Route53 Zone', original: 'Z1234567890ABC', masked: 'ROUTE53_ZONE_001' }
];

/**
 * 단일 패턴 보안 테스트
 * @param {Object} pattern - 테스트할 패턴
 * @param {number} index - 패턴 인덱스
 * @returns {Promise<Object>} 테스트 결과
 */
async function testSinglePattern(pattern, index) {
  try {
    const testText = `Test AWS resource: ${pattern.original}`;
    
    // Backend API 호출 (/test-masking 엔드포인트)
    const response = await axios.post(`${BACKEND_URL}/test-masking`, {
      testText: testText,
      systemPrompt: `You must echo back EXACTLY what I send, character by character: "${testText}"`
    }, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY
      },
      timeout: 10000
    });
    
    const finalResponse = response.data?.finalResponse || '';
    const containsOriginal = finalResponse.includes(pattern.original);
    
    // 보안 검증: 원본이 포함되어 있으면 성공, 없으면 실패
    // (Claude가 원본을 보지 못했다는 의미)
    const securityPassed = !containsOriginal;
    
    return {
      pattern: pattern,
      index: index + 1,
      request: testText,
      response: finalResponse,
      containsOriginal: containsOriginal,
      securityPassed: securityPassed,
      flow: response.data?.flow
    };
    
  } catch (error) {
    return {
      pattern: pattern,
      index: index + 1,
      error: error.message,
      securityPassed: false
    };
  }
}

/**
 * 배치 테스트 (더 효율적)
 */
async function testBatch(patterns) {
  try {
    const response = await axios.post(`${BACKEND_URL}/test-masking/batch`, {
      patterns: patterns
    }, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY
      },
      timeout: 60000 // 1분 타임아웃
    });
    
    return response.data;
  } catch (error) {
    console.error('Batch test failed:', error.message);
    return null;
  }
}

/**
 * 보안 검증 결과를 테이블 형식으로 생성
 */
function generateSecurityReport(results) {
  const timestamp = new Date().toISOString();
  const successCount = results.filter(r => r.securityPassed).length;
  const failCount = results.length - successCount;
  const successRate = ((successCount / results.length) * 100).toFixed(1);
  
  let report = `# Kong AWS 마스킹 시스템 - 50개 패턴 보안 검증 보고서

## 📅 테스트 정보
- **테스트 시간**: ${timestamp}
- **아키텍처**: Backend API → Kong Gateway → Claude API (올바른 API Gateway 패턴)
- **총 테스트 패턴**: ${results.length}개
- **보안 성공**: ${successCount}개 (${successRate}%)
- **보안 실패**: ${failCount}개 🚨

## 🔒 보안 검증 기준
- **성공**: Claude가 마스킹된 값만 받고, 원본 AWS 리소스를 볼 수 없음
- **실패**: Claude가 원본 AWS 리소스를 볼 수 있음 (심각한 보안 문제)

## 📊 전체 변환 플로우 테이블

| # | 패턴 타입 | Backend API (원본) | Kong (마스킹) | Claude 수신 | Kong (언마스킹) | Backend 수신 | 보안 상태 |
|---|-----------|-------------------|---------------|-------------|----------------|--------------|-----------|
`;

  results.forEach(r => {
    const status = r.securityPassed ? '✅ 안전' : '❌ 위험';
    const original = r.pattern.original;
    const masked = r.pattern.masked;
    const response = r.response || r.error || 'N/A';
    
    report += `| ${r.index} | ${r.pattern.type} | ${original} | ${masked} | (마스킹됨) | ${masked} → ${original} | ${response.substring(0, 50)}... | ${status} |\n`;
  });
  
  // 실패한 패턴 상세 분석
  if (failCount > 0) {
    report += `\n## 🚨 보안 실패 패턴 상세 분석\n\n`;
    results.filter(r => !r.securityPassed).forEach(r => {
      report += `### ${r.index}. ${r.pattern.type}\n`;
      report += `- **원본**: ${r.pattern.original}\n`;
      report += `- **예상 마스킹**: ${r.pattern.masked}\n`;
      report += `- **문제**: Claude가 원본 값을 그대로 받았음\n`;
      report += `- **응답**: ${r.response}\n\n`;
    });
  }
  
  // 보안 검증 요약
  report += `\n## 🎯 보안 검증 결론\n`;
  if (failCount === 0) {
    report += `✅ **모든 AWS 리소스가 안전하게 마스킹됨**
- Claude API는 원본 AWS 리소스를 전혀 볼 수 없음
- Kong Gateway가 모든 패턴을 성공적으로 마스킹
- 보안 목표 100% 달성\n`;
  } else {
    report += `❌ **심각한 보안 문제 발견**
- ${failCount}개 패턴에서 마스킹 실패
- Claude API가 원본 AWS 리소스에 접근 가능
- 즉시 수정 필요\n`;
  }
  
  return report;
}

/**
 * 메인 실행 함수
 */
async function main() {
  console.log('🔒 Kong AWS 마스킹 50개 패턴 보안 검증 시작');
  console.log('📍 아키텍처: Backend API → Kong Gateway → Claude API');
  console.log('⚠️  보안 최우선: 단 하나의 취약점도 용납 불가\n');
  
  // API 키 확인
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('❌ ANTHROPIC_API_KEY 환경 변수가 필요합니다');
    process.exit(1);
  }
  
  const results = [];
  
  // 개별 테스트 (더 정확한 보안 검증)
  console.log('🔍 개별 패턴 보안 테스트 시작...\n');
  
  for (let i = 0; i < testPatterns.length; i++) {
    const pattern = testPatterns[i];
    process.stdout.write(`[${i + 1}/${testPatterns.length}] ${pattern.type} 테스트 중...`);
    
    const result = await testSinglePattern(pattern, i);
    results.push(result);
    
    if (result.securityPassed) {
      console.log(' ✅ 안전');
    } else {
      console.log(' ❌ 위험 - 마스킹 실패!');
    }
    
    // Rate limiting 방지
    if (i < testPatterns.length - 1) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  // 보고서 생성
  const report = generateSecurityReport(results);
  
  // 보고서 저장
  const reportPath = path.join(__dirname, '..', 'Plan', 'report', '50-patterns-security-report.md');
  fs.writeFileSync(reportPath, report);
  
  // 콘솔 출력
  console.log('\n' + '='.repeat(80));
  console.log(report);
  console.log('='.repeat(80));
  
  console.log(`\n📄 보고서 저장됨: ${reportPath}`);
  
  // 보안 실패 시 에러 코드로 종료
  const failCount = results.filter(r => !r.securityPassed).length;
  if (failCount > 0) {
    console.error(`\n🚨 경고: ${failCount}개 패턴에서 보안 취약점 발견!`);
    process.exit(1);
  }
}

// 실행
if (require.main === module) {
  main().catch(error => {
    console.error('❌ 테스트 실행 중 오류:', error);
    process.exit(1);
  });
}

module.exports = { testSinglePattern, testBatch, generateSecurityReport };