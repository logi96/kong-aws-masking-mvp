# 50개 AWS 패턴 마스킹/언마스킹 플로우 테스트 리포트

**테스트 실행 시간**: 2025-07-25T10:34:44+09:00  
**테스트 스크립트**: 50-patterns-complete-flow.sh  
**목적**: 전체 AWS 리소스 패턴의 마스킹/언마스킹 완전성 검증

## 테스트 개요
- **총 패턴 수**: 46개 (복합 패턴 포함)
- **테스트 방식**: Backend API → Kong Gateway → Claude API → 언마스킹
- **검증 기준**: 원본 AWS 리소스가 사용자 응답에 완전 복원되는지 확인

## 상세 테스트 결과

### ❌ Test 1: EC2 Instance
- **원본**: `i-1234567890abcdef0`
- **응답**: `I notice the context provided is very limited, only mentioning "EC2_001" without specific configuration details. However, I'll provide a security analysis framework focusing on common EC2 security con...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 2: EC2 Instance
- **원본**: `i-0987654321fedcba0`
- **응답**: `I'll analyze the AWS_EC2_002 resource for security concerns.

**Critical Security Issues**
1. Security Group Configuration
   - Description: AWS_EC2_002 typically refers to overly permissive security ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 3: AMI
- **원본**: `ami-0abcdef1234567890`
- **응답**: `I apologize, but I notice that the context provided ("amAWS_EC2_004") is very limited and doesn't contain enough information about the actual EC2 configuration to perform a complete security analysis....`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 4: EBS Volume
- **원본**: `vol-0123456789abcdef0`
- **응답**: `I'll analyze the AWS EBS volume (AWS_EBS_VOL_002) security context specifically focusing on security aspects.

1. **Critical Security Issues**

a) Volume Encryption Status
- Description: If the EBS vo...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 5: Snapshot
- **원본**: `snap-0123456789abcdef0`
- **응답**: `I'll analyze the AWS snapshot (AWS_SNAPSHOT_003) focusing exclusively on security aspects.

1. **Critical Security Issues:**

   a) Snapshot Encryption Status Unknown
   - Description: Unable to verif...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 6: VPC
- **원본**: `vpc-0123456789abcdef0`
- **응답**: `I'll analyze the VPC (AWS_VPC_00389abcdef0) focusing exclusively on security aspects.

1. **Critical Security Issues**
   - Unable to determine Network ACL configurations
     - Impact: Potential unau...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 7: Subnet
- **원본**: `subnet-0123456789abcdef0`
- **응답**: `I'll analyze the AWS_SUBNET_004 from a security perspective.

1. **Critical Security Issues**
   - Network ACL Configuration
     - Description: Cannot determine if proper Network ACL rules are in pla...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 8: Security Group
- **원본**: `sg-0123456789abcdef0`
- **응답**: `I apologize, but I notice the context provided contains very limited information about AWS_SECURITY_GROUP_00589abcdef0. Without more details about the security group's rules, associated resources, and...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 9: Internet Gateway
- **원본**: `igw-0123456789abcdef0`
- **응답**: `I'll analyze the Internet Gateway (IGW) AWS_IGW_00689abcdef0 focusing exclusively on security concerns.

1. **Critical Security Issues**
   * Traffic Exposure
     - Description: Internet Gateways pro...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 10: NAT Gateway
- **원본**: `nat-0123456789abcdef0`
- **응답**: `I'll analyze the AWS NAT Gateway (AWS_NAT_GW_007) from a security perspective.

1. **Critical Security Issues**
- Description: NAT Gateway without proper security group or NACL controls
  - Impact: Co...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 11: VPN Connection
- **원본**: `vpn-0123456789abcdef0`
- **응답**: `I'll analyze the AWS VPN (ID: AWS_VPN_00889abcdef0) from a security perspective.

1. **Critical Security Issues**
   - Missing Tunnel Monitoring:
     - Description: If CloudWatch monitoring isn't con...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 12: Transit Gateway
- **원본**: `tgw-0123456789abcdef0`
- **응답**: `I'll analyze the AWS Transit Gateway (TGW-009) context for security concerns.

1. **Critical Security Issues**
   
   a) Transit Gateway Route Table Exposure
   - Description: Unrestricted route table...`
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
- **실행 시간**: 78초

### 🎯 분석
- **결과**: ❌ 부족 (70% 미만 성공률)
- **권고**: 대폭적인 패턴 개선 필수, 프로덕션 배포 부적합

**테스트 완료 시간**: 2025-07-25T10:36:02+09:00

*이 리포트는 Kong AWS Masker 50개 패턴 검증의 공식 결과입니다.*
