# 50개 AWS 패턴 마스킹/언마스킹 플로우 테스트 리포트

**테스트 실행 시간**: 2025-07-25T11:26:40+09:00  
**테스트 스크립트**: 50-patterns-complete-flow.sh  
**목적**: 전체 AWS 리소스 패턴의 마스킹/언마스킹 완전성 검증

## 테스트 개요
- **총 패턴 수**: 46개 (복합 패턴 포함)
- **테스트 방식**: Backend API → Kong Gateway → Claude API → 언마스킹
- **검증 기준**: 원본 AWS 리소스가 사용자 응답에 완전 복원되는지 확인

## 상세 테스트 결과

### ❌ Test 1: EC2 Instance
- **원본**: `i-1234567890abcdef0`
- **응답**: `I apologize, but I notice that the provided context only mentions "EC2_001" without any specific configuration details or attributes about the EC2 instance. To perform a thorough security analysis, I ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 2: EC2 Instance
- **원본**: `i-0987654321fedcba0`
- **응답**: `I'll analyze the AWS EC2 security context (AWS_EC2_002) with a focus on security issues.

1. **Critical Security Issues**

a) Public IP Address Exposure
- Description: EC2 instances with public IP add...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 3: AMI
- **원본**: `ami-0abcdef1234567890`
- **응답**: `I apologize, but I notice that the context provided ("amAWS_EC2_004") is very limited and lacks specific details about the EC2 instance configuration. However, I'll provide a security analysis framewo...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 4: EBS Volume
- **원본**: `vol-0123456789abcdef0`
- **응답**: `I'll analyze AWS_EBS_VOL_002 (EBS Volume) specifically for security concerns.

1. **Critical Security Issues**
   - Unencrypted EBS Volume
     - Description: EBS volumes without encryption expose dat...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 5: Snapshot
- **원본**: `snap-0123456789abcdef0`
- **응답**: `I apologize, but I notice that the provided context "AWS_SNAPSHOT_003" lacks specific details about the snapshot's configuration, settings, or attributes. However, I can provide a security analysis fo...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 6: VPC
- **원본**: `vpc-0123456789abcdef0`
- **응답**: `I'll analyze the AWS VPC (AWS_VPC_00389abcdef0) focusing exclusively on security aspects.

1. **Critical Security Issues**

   a) Default VPC Configuration
   - Description: If this is a default VPC, ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 7: Subnet
- **원본**: `subnet-0123456789abcdef0`
- **응답**: `I'll analyze AWS_SUBNET_004 from a security perspective.

1. **Critical Security Issues**
   - No direct critical security issues identified since subnet information is limited in the provided context...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 8: Security Group
- **원본**: `sg-0123456789abcdef0`
- **응답**: `I apologize, but I notice that the provided context contains very limited information about the security group "AWS_SECURITY_GROUP_00589abcdef0". Without more details about its inbound/outbound rules,...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 9: Internet Gateway
- **원본**: `igw-0123456789abcdef0`
- **응답**: `I'll analyze the Internet Gateway (IGW) AWS_IGW_00689abcdef0 from a security perspective.

1. **Critical Security Issues**
   - Issue: Unrestricted Internet Access
     - Description: Internet Gateway...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 10: NAT Gateway
- **원본**: `nat-0123456789abcdef0`
- **응답**: `I'll analyze the AWS NAT Gateway (AWS_NAT_GW_007) for security concerns.

1. **Critical Security Issues**
- Description: NAT Gateway route configurations may allow unauthorized outbound traffic
- Impa...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 11: VPN Connection
- **원본**: `vpn-0123456789abcdef0`
- **응답**: `I'll analyze the AWS VPN (ID: AWS_VPN_00889abcdef0) from a security perspective.

1. **Critical Security Issues**
   - Unable to determine VPN tunnel encryption settings
     - Impact: Potential data ...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 12: Transit Gateway
- **원본**: `tgw-0123456789abcdef0`
- **응답**: `I'll analyze AWS_TGW_009 (Transit Gateway) from a security perspective.

1. **Critical Security Issues**
   
   a) Routing Table Exposure
   - Description: Improperly configured routing tables in Tran...`
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

