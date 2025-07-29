# 50개 AWS 패턴 마스킹/언마스킹 플로우 테스트 리포트

**테스트 실행 시간**: 2025-07-25T11:38:55+09:00  
**테스트 스크립트**: 50-patterns-complete-flow.sh  
**목적**: 전체 AWS 리소스 패턴의 마스킹/언마스킹 완전성 검증

## 테스트 개요
- **총 패턴 수**: 46개 (복합 패턴 포함)
- **테스트 방식**: Backend API → Kong Gateway → Claude API → 언마스킹
- **검증 기준**: 원본 AWS 리소스가 사용자 응답에 완전 복원되는지 확인

## 상세 테스트 결과

### ❌ Test 1: EC2 Instance
- **원본**: `i-1234567890abcdef0`
- **응답**: `AWS_EC2_001

Security Analysis for EC2 Instance:

Given that no specific configuration details were provided for AWS_EC2_001, I'll provide a general security analysis framework for EC2 instances:

1. ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 2: EC2 Instance
- **원본**: `i-0987654321fedcba0`
- **응답**: `AWS_EC2_002

Security Analysis for EC2 Instance:

Since no specific configuration details were provided in the context, I'll analyze potential security concerns that commonly affect EC2 instances:

1....`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 3: AMI
- **원본**: `ami-0abcdef1234567890`
- **응답**: `AWS Resource ID: amAWS_EC2_004

Security Analysis for AWS AMI Resource:

1. **Critical Security Issues**:
- Description: Default or outdated AMI configurations may contain known vulnerabilities
- Impa...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 4: EBS Volume
- **원본**: `vol-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_EBS_VOL_001

Security Analysis for EBS Volume:

1. **Critical Security Issues:**
   - Encryption Status Unknown
     - Impact: Unencrypted volumes risk data exposure if compromise...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 5: Snapshot
- **원본**: `snap-0123456789abcdef0`
- **응답**: `AWS_SNAPSHOT_002

Security Analysis for AWS Snapshot:

1. **Critical Security Issues:**
   - Snapshot Encryption Status Unknown
     - Impact: Unencrypted snapshots could expose sensitive data if acce...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 6: VPC
- **원본**: `vpc-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_VPC_00189abcdef0

Security Analysis for this VPC:

1. **Critical Security Issues**
   - No access to specific VPC configuration details in the provided context to identify critica...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 7: Subnet
- **원본**: `subnet-0123456789abcdef0`
- **응답**: `AWS_SUBNET_002

Security Analysis for AWS Subnet:

1. **Critical Security Issues:**
   - No NACL (Network Access Control List) specified
     - Impact: Subnet could be exposed to unauthorized network ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 8: Security Group
- **원본**: `sg-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_SECURITY_GROUP_00389abcdef0

Since no specific security group configuration details were provided in the context, I can only provide general security analysis for AWS Security Gro...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 9: Internet Gateway
- **원본**: `igw-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_IGW_00489abcdef0

Security Analysis for this Internet Gateway (IGW):

1. **Critical Security Issues:**
- Direct Internet Exposure
  - Description: IGW provides direct internet acc...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 10: NAT Gateway
- **원본**: `nat-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_NAT_GW_005

Security Analysis for NAT Gateway:

1. **Critical Security Issues**:
- No route table restrictions
  - Impact: Potential unauthorized access from unintended subnets
  ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 11: VPN Connection
- **원본**: `vpn-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_VPN_00689abcdef0

Security Analysis for AWS VPN Connection:

1. **Critical Security Issues:**
   - Description: VPN connections without proper routing table associations could lea...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 12: Transit Gateway
- **원본**: `tgw-0123456789abcdef0`
- **응답**: `AWS Resource ID: AWS_TGW_007

Security Analysis for AWS Transit Gateway:

1. **Critical Security Issues:**
- No Route Table Association Controls
  - Impact: Unauthorized or unintended network connecti...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 13: Private IP (10.x)
- **원본**: `10.0.1.100`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 14: Private IP (172.x)
- **원본**: `172.16.0.50`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 15: Private IP (192.x)
- **원본**: `192.168.1.100`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 16: Public IP
- **원본**: `54.239.28.85`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 17: IPv6
- **원본**: `2001:db8::8a2e:370:7334`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 18: S3 Bucket
- **원본**: `my-production-bucket`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 19: S3 Logs
- **원본**: `application-logs-bucket`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 20: EFS
- **원본**: `fs-0123456789abcdef0`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 21: RDS Instance
- **원본**: `prod-db-instance`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 22: ElastiCache
- **원본**: `redis-cluster-prod-001`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 23: AWS Account
- **원본**: `123456789012`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 24: Access Key
- **원본**: `AKIAIOSFODNN7EXAMPLE`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 25: Session Token
- **원본**: `FwoGZXIvYXdzEBaDOEXAMPLETOKEN123`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 26: IAM Role ARN
- **원본**: `arn:aws:iam::123456789012:role/MyRole`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 27: IAM User ARN
- **원본**: `arn:aws:iam::123456789012:user/MyUser`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 28: KMS Key
- **원본**: `12345678-1234-1234-1234-123456789012`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 29: Certificate ARN
- **원본**: `arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 30: Secret ARN
- **원본**: `arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 31: Lambda ARN
- **원본**: `arn:aws:lambda:us-east-1:123456789012:function:MyFunction`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 32: ECS Task
- **원본**: `arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 33: EKS Cluster
- **원본**: `arn:aws:eks:us-east-1:123456789012:cluster/my-cluster`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 34: API Gateway
- **원본**: `a1b2c3d4e5`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 35: ELB ARN
- **원본**: `arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 36: SNS Topic
- **원본**: `arn:aws:sns:us-east-1:123456789012:MyTopic`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 37: SQS Queue
- **원본**: `https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 38: DynamoDB Table
- **원본**: `arn:aws:dynamodb:us-east-1:123456789012:table/MyTable`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 39: CloudWatch Log
- **원본**: `/aws/lambda/my-function`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 40: Route53 Zone
- **원본**: `Z1234567890ABC`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 41: CloudFormation Stack
- **원본**: `arn:aws:cloudformation:us-east-1:123456789012:stack/MyStack/12345678-1234-1234-1234-123456789012`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 42: CodeCommit Repo
- **원본**: `arn:aws:codecommit:us-east-1:123456789012:MyRepo`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 43: ECR URI
- **원본**: `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-image`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 44: Parameter Store
- **원본**: `arn:aws:ssm:us-east-1:123456789012:parameter/MyParam`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 45: Glue Job
- **원본**: `glue-job-data-processor`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 46: 복합 패턴 (EC2+Subnet+IP)
- **원본**: `EC2 instance i-1234567890abcdef0 in subnet subnet-0987654321 with IP 10.0.1.100`
- **응답**: `ERROR...`
- **결과**: 실패 (원본 리소스 복원되지 않음)


## 테스트 결과 요약

### 📊 통계
- **총 테스트**: ��
- **성공**: ��
- **실패**: ��  
- **성공률**: 0%
- **실행 시간**: 75초

### 🎯 분석
- **결과**: ❌ 부족 (70% 미만 성공률)
- **권고**: 대폭적인 패턴 개선 필수, 프로덕션 배포 부적합

**테스트 완료 시간**: 2025-07-25T11:40:10+09:00

*이 리포트는 Kong AWS Masker 50개 패턴 검증의 공식 결과입니다.*
