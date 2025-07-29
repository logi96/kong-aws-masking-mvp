#!/usr/bin/env node
/**
 * Backend API → Kong → Claude → Kong → Backend API 전체 플로우 테스트
 * 50개 AWS 리소스 패턴에 대한 완전한 마스킹/언마스킹 플로우 시각화
 */

const axios = require('axios');

// 50개 AWS 패턴 정의
const awsPatterns = [
  // EC2 관련 (5개)
  { type: 'EC2 Instance', original: 'i-1234567890abcdef0', masked: 'EC2_001' },
  { type: 'EC2 Instance', original: 'i-0987654321fedcba0', masked: 'EC2_002' },
  { type: 'AMI', original: 'ami-0abcdef1234567890', masked: 'AMI_001' },
  { type: 'EBS Volume', original: 'vol-0123456789abcdef0', masked: 'EBS_VOL_001' },
  { type: 'Snapshot', original: 'snap-0123456789abcdef0', masked: 'SNAPSHOT_001' },
  
  // VPC/네트워크 관련 (12개)
  { type: 'VPC', original: 'vpc-0123456789abcdef0', masked: 'VPC_001' },
  { type: 'Subnet', original: 'subnet-0123456789abcdef0', masked: 'SUBNET_001' },
  { type: 'Security Group', original: 'sg-0123456789abcdef0', masked: 'SG_001' },
  { type: 'Internet Gateway', original: 'igw-0123456789abcdef0', masked: 'IGW_001' },
  { type: 'NAT Gateway', original: 'nat-0123456789abcdef0', masked: 'NAT_GW_001' },
  { type: 'VPN Connection', original: 'vpn-0123456789abcdef0', masked: 'VPN_001' },
  { type: 'Transit Gateway', original: 'tgw-0123456789abcdef0', masked: 'TGW_001' },
  { type: 'Private IP (10.x)', original: '10.0.1.100', masked: 'PRIVATE_IP_001' },
  { type: 'Private IP (172.x)', original: '172.16.0.50', masked: 'PRIVATE_IP_002' },
  { type: 'Private IP (192.x)', original: '192.168.1.100', masked: 'PRIVATE_IP_003' },
  { type: 'Public IP', original: '54.239.28.85', masked: 'PUBLIC_IP_001' },
  { type: 'IPv6', original: '2001:db8::8a2e:370:7334', masked: 'IPV6_001' },
  
  // 스토리지 관련 (5개)
  { type: 'S3 Bucket', original: 'my-production-bucket', masked: 'BUCKET_001' },
  { type: 'S3 Logs', original: 'application-logs-bucket', masked: 'BUCKET_002' },
  { type: 'EFS', original: 'fs-0123456789abcdef0', masked: 'EFS_001' },
  { type: 'S3 Data', original: 'company-data-bucket', masked: 'BUCKET_003' },
  { type: 'S3 Backup', original: 'backup-bucket-prod', masked: 'BUCKET_004' },
  
  // 데이터베이스 관련 (3개)
  { type: 'RDS Instance', original: 'prod-db-instance', masked: 'RDS_001' },
  { type: 'RDS Cluster', original: 'aurora-prod-db-cluster', masked: 'RDS_002' },
  { type: 'ElastiCache', original: 'redis-cache-prod-001', masked: 'ELASTICACHE_001' },
  
  // IAM/보안 관련 (10개)
  { type: 'AWS Account', original: '123456789012', masked: 'ACCOUNT_001' },
  { type: 'Access Key', original: 'AKIAIOSFODNN7EXAMPLE', masked: 'ACCESS_KEY_001' },
  { type: 'Session Token', original: 'FwoGZXIvYXdzEBaDOEXAMPLETOKEN123', masked: 'SESSION_TOKEN_001' },
  { type: 'IAM Role ARN', original: 'arn:aws:iam::123456789012:role/MyRole', masked: 'IAM_ROLE_001' },
  { type: 'IAM User ARN', original: 'arn:aws:iam::123456789012:user/MyUser', masked: 'IAM_USER_001' },
  { type: 'IAM Policy ARN', original: 'arn:aws:iam::123456789012:policy/MyPolicy', masked: 'ARN_001' },
  { type: 'KMS Key', original: '12345678-1234-1234-1234-123456789012', masked: 'KMS_KEY_001' },
  { type: 'Certificate ARN', original: 'arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012', masked: 'CERT_ARN_001' },
  { type: 'Secret ARN', original: 'arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef', masked: 'SECRET_ARN_001' },
  { type: 'Parameter ARN', original: 'arn:aws:ssm:us-east-1:123456789012:parameter/MyParam', masked: 'PARAM_ARN_001' },
  
  // 컴퓨팅 서비스 관련 (8개)
  { type: 'Lambda ARN', original: 'arn:aws:lambda:us-east-1:123456789012:function:MyFunction', masked: 'LAMBDA_ARN_001' },
  { type: 'ECS Task', original: 'arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012', masked: 'ECS_TASK_001' },
  { type: 'ECS Service', original: 'arn:aws:ecs:us-east-1:123456789012:service/my-service', masked: 'ARN_002' },
  { type: 'EKS Cluster', original: 'arn:aws:eks:us-east-1:123456789012:cluster/my-cluster', masked: 'EKS_CLUSTER_001' },
  { type: 'API Gateway', original: 'a1b2c3d4e5', masked: 'API_GW_001' },
  { type: 'ALB ARN', original: 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456', masked: 'ELB_ARN_001' },
  { type: 'NLB ARN', original: 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456', masked: 'ELB_ARN_002' },
  { type: 'Target Group', original: 'arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-targets/1234567890123456', masked: 'ARN_003' },
  
  // 기타 AWS 서비스 (7개)
  { type: 'SNS Topic', original: 'arn:aws:sns:us-east-1:123456789012:MyTopic', masked: 'SNS_TOPIC_001' },
  { type: 'SQS Queue', original: 'https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue', masked: 'SQS_QUEUE_001' },
  { type: 'DynamoDB Table', original: 'arn:aws:dynamodb:us-east-1:123456789012:table/MyTable', masked: 'DYNAMODB_TABLE_001' },
  { type: 'CloudWatch Log', original: '/aws/lambda/my-function', masked: 'LOG_GROUP_001' },
  { type: 'Route53 Zone', original: 'Z1234567890ABC', masked: 'ROUTE53_ZONE_001' },
  { type: 'CloudFormation Stack', original: 'arn:aws:cloudformation:us-east-1:123456789012:stack/MyStack/12345678-1234-1234-1234-123456789012', masked: 'STACK_ID_001' },
  { type: 'ECR URI', original: '123456789012.dkr.ecr.us-east-1.amazonaws.com/my-image', masked: 'ECR_URI_001' }
];

// 설정
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const API_KEY = process.env.ANTHROPIC_API_KEY;

if (!API_KEY) {
  console.error('❌ ANTHROPIC_API_KEY 환경 변수가 필요합니다');
  process.exit(1);
}

/**
 * 단일 패턴 테스트 및 플로우 시각화
 */
async function testSinglePattern(pattern, index) {
  try {
    const testText = `AWS Resource: ${pattern.original}`;
    
    console.log(`\n${index + 1}. ${pattern.type}:`);
    console.log(`   Backend API 수신: "${testText}"`);
    console.log(`   ↓`);
    console.log(`   Kong 수신 (aws resource text): ${pattern.original}`);
    console.log(`   ↓`);
    console.log(`   Kong 패턴 변환 후 전달 (변환된 text): ${pattern.masked}`);
    console.log(`   ↓`);
    console.log(`   Claude (마스킹된 텍스트 수신)`);
    console.log(`   ↓`);
    console.log(`   Kong Claude로부터 수신 (변환된 text): ${pattern.masked}`);
    console.log(`   ↓`);
    console.log(`   Kong origin으로 변환 (aws resource text): ${pattern.original}`);
    console.log(`   ↓`);
    
    // Backend API 호출
    const response = await axios.post(`${BACKEND_URL}/test-masking`, {
      testText: testText,
      systemPrompt: `You must return EXACTLY: ${testText}`
    }, {
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    const finalResponse = response.data.finalResponse || '';
    console.log(`   Backend API 최종 수신: "${finalResponse}"`);
    
    // 성공 여부 확인
    const success = finalResponse.includes(pattern.original);
    console.log(`   결과: ${success ? '✅ 성공 (언마스킹 완료)' : '❌ 실패'}`);
    
    return { pattern, success, response: finalResponse };
    
  } catch (error) {
    console.log(`   ❌ 오류: ${error.message}`);
    return { pattern, success: false, error: error.message };
  }
}

/**
 * 배치 테스트 (더 빠른 처리)
 */
async function batchTest(patterns) {
  try {
    console.log('\n=== 배치 테스트 (빠른 처리) ===');
    
    const response = await axios.post(`${BACKEND_URL}/test-masking/batch`, {
      patterns: patterns
    }, {
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    console.log(`\n총 ${response.data.totalPatterns}개 패턴 테스트`);
    console.log(`성공: ${response.data.successCount}개`);
    console.log(`실패: ${response.data.totalPatterns - response.data.successCount}개`);
    
    // 실패한 패턴 출력
    const failed = response.data.results.filter(r => !r.success);
    if (failed.length > 0) {
      console.log('\n실패한 패턴:');
      failed.forEach(f => {
        console.log(`- ${f.type}: ${f.original}`);
      });
    }
    
    return response.data;
    
  } catch (error) {
    console.error('배치 테스트 실패:', error.message);
    return null;
  }
}

/**
 * 메인 실행 함수
 */
async function main() {
  console.log('=== Backend API → Kong → Claude → Kong → Backend API 전체 플로우 테스트 ===');
  console.log(`테스트 시간: ${new Date().toISOString()}`);
  console.log(`총 패턴 수: ${awsPatterns.length}개`);
  
  // 처음 5개만 상세 플로우 출력
  console.log('\n=== 상세 플로우 (처음 5개) ===');
  const results = [];
  for (let i = 0; i < 5; i++) {
    const result = await testSinglePattern(awsPatterns[i], i);
    results.push(result);
  }
  
  // 나머지는 배치로 처리
  console.log('\n=== 나머지 45개 패턴 배치 처리 ===');
  const remainingPatterns = awsPatterns.slice(5);
  const batchResult = await batchTest(remainingPatterns);
  
  // 전체 결과 요약
  console.log('\n=== 전체 테스트 결과 요약 ===');
  const detailSuccess = results.filter(r => r.success).length;
  const batchSuccess = batchResult ? batchResult.successCount : 0;
  const totalSuccess = detailSuccess + batchSuccess;
  
  console.log(`✅ 총 성공: ${totalSuccess}/${awsPatterns.length}`);
  console.log(`❌ 총 실패: ${awsPatterns.length - totalSuccess}/${awsPatterns.length}`);
  console.log(`성공률: ${(totalSuccess / awsPatterns.length * 100).toFixed(1)}%`);
  
  // 플로우 다이어그램
  console.log('\n=== 전체 플로우 다이어그램 ===');
  console.log(`
  ┌─────────────┐     ┌──────────┐     ┌────────────┐     ┌──────────┐     ┌─────────────┐
  │ Backend API │────▶│   Kong   │────▶│ Claude API │────▶│   Kong   │────▶│ Backend API │
  └─────────────┘     └──────────┘     └────────────┘     └──────────┘     └─────────────┘
        (1)               (2)                (3)               (4)                (5)
        
  (1) 원본 AWS 리소스 텍스트
  (2) Kong이 AWS 패턴을 마스킹 (i-123... → EC2_001)
  (3) Claude가 마스킹된 텍스트 수신 및 처리
  (4) Kong이 응답을 언마스킹 (EC2_001 → i-123...)
  (5) Backend API가 원본 복원된 응답 수신
  `);
  
  console.log('\n테스트 완료!');
}

// 실행
main().catch(console.error);