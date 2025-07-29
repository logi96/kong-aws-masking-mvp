# Kong AWS 마스킹 시스템 - 50개 패턴 보안 검증 보고서

## 📅 테스트 정보
- **테스트 시간**: 2025-07-23T23:46:20.982Z
- **아키텍처**: Backend API → Kong Gateway → Claude API (올바른 API Gateway 패턴)
- **총 테스트 패턴**: 40개
- **보안 성공**: 16개 (40.0%)
- **보안 실패**: 24개 🚨

## 🔒 보안 검증 기준
- **성공**: Claude가 마스킹된 값만 받고, 원본 AWS 리소스를 볼 수 없음
- **실패**: Claude가 원본 AWS 리소스를 볼 수 있음 (심각한 보안 문제)

## 📊 전체 변환 플로우 테이블

| # | 패턴 타입 | Backend API (원본) | Kong (마스킹) | Claude 수신 | Kong (언마스킹) | Backend 수신 | 보안 상태 |
|---|-----------|-------------------|---------------|-------------|----------------|--------------|-----------|
| 1 | EC2 Instance | i-1234567890abcdef0 | EC2_001 | (마스킹됨) | EC2_001 → i-1234567890abcdef0 | Test AWS resource: EC2_002... | ✅ 안전 |
| 2 | EC2 Instance | i-0987654321fedcba0 | EC2_002 | (마스킹됨) | EC2_002 → i-0987654321fedcba0 | Test AWS resource: EC2_003... | ✅ 안전 |
| 3 | AMI | ami-0abcdef1234567890 | AMI_001 | (마스킹됨) | AMI_001 → ami-0abcdef1234567890 | Based on the provided AWS infrastructure data show... | ✅ 안전 |
| 4 | EBS Volume | vol-0123456789abcdef0 | EBS_VOL_001 | (마스킹됨) | EBS_VOL_001 → vol-0123456789abcdef0 | Based on the provided test_masking AWS infrastruct... | ✅ 안전 |
| 5 | Snapshot | snap-0123456789abcdef0 | SNAPSHOT_001 | (마스킹됨) | SNAPSHOT_001 → snap-0123456789abcdef0 | Test AWS resource: SNAPSHOT_002... | ✅ 안전 |
| 6 | VPC | vpc-0123456789abcdef0 | VPC_001 | (마스킹됨) | VPC_001 → vpc-0123456789abcdef0 | Test AWS resource: VPC_00389abcdef0... | ✅ 안전 |
| 7 | Subnet | subnet-0123456789abcdef0 | SUBNET_001 | (마스킹됨) | SUBNET_001 → subnet-0123456789abcdef0 | Test AWS resource: SUBNET_00489abcdef0... | ✅ 안전 |
| 8 | Security Group | sg-0123456789abcdef0 | SG_001 | (마스킹됨) | SG_001 → sg-0123456789abcdef0 | Test AWS resource: SG_00589abcdef0... | ✅ 안전 |
| 9 | Internet Gateway | igw-0123456789abcdef0 | IGW_001 | (마스킹됨) | IGW_001 → igw-0123456789abcdef0 | Test AWS resource: IGW_00689abcdef0... | ✅ 안전 |
| 10 | NAT Gateway | nat-0123456789abcdef0123456789abcdef0 | NAT_GW_001 | (마스킹됨) | NAT_GW_001 → nat-0123456789abcdef0123456789abcdef0 | Based on the provided data which shows an empty re... | ✅ 안전 |
| 11 | VPN Connection | vpn-0123456789abcdef0 | VPN_001 | (마스킹됨) | VPN_001 → vpn-0123456789abcdef0 | Test AWS resource: VPN_00889abcdef0... | ✅ 안전 |
| 12 | Transit Gateway | tgw-0123456789abcdef0 | TGW_001 | (마스킹됨) | TGW_001 → tgw-0123456789abcdef0 | Test AWS resource: TGW_009... | ✅ 안전 |
| 13 | Private IP (10.x) | 10.0.1.100 | PRIVATE_IP_001 | (마스킹됨) | PRIVATE_IP_001 → 10.0.1.100 | Test AWS resource: PRIVATE_IP_007... | ✅ 안전 |
| 14 | Private IP (172.x) | 172.16.0.50 | PRIVATE_IP_001 | (마스킹됨) | PRIVATE_IP_001 → 172.16.0.50 | Test AWS resource: PRIVATE_IP_010... | ✅ 안전 |
| 15 | Private IP (192.x) | 192.168.1.100 | PRIVATE_IP_001 | (마스킹됨) | PRIVATE_IP_001 → 192.168.1.100 | Test AWS resource: PRIVATE_IP_009... | ✅ 안전 |
| 16 | Public IP | 54.239.28.85 | PUBLIC_IP_001 | (마스킹됨) | PUBLIC_IP_001 → 54.239.28.85 | Test AWS resource: 54.239.28.85... | ❌ 위험 |
| 17 | IPv6 | 2001:db8::8a2e:370:7334 | IPV6_001 | (마스킹됨) | IPV6_001 → 2001:db8::8a2e:370:7334 | Request failed with status code 500... | ❌ 위험 |
| 18 | S3 Bucket | my-production-bucket | BUCKET_001 | (마스킹됨) | BUCKET_001 → my-production-bucket | Request failed with status code 500... | ❌ 위험 |
| 19 | S3 Logs | my-application-logs | BUCKET_001 | (마스킹됨) | BUCKET_001 → my-application-logs | Request failed with status code 500... | ❌ 위험 |
| 20 | EFS | fs-0123456789abcdef0 | EFS_001 | (마스킹됨) | EFS_001 → fs-0123456789abcdef0 | Request failed with status code 500... | ❌ 위험 |
| 21 | RDS Instance | prod-db-instance | RDS_001 | (마스킹됨) | RDS_001 → prod-db-instance | Request failed with status code 500... | ❌ 위험 |
| 22 | ElastiCache | redis-cluster-001 | ELASTICACHE_001 | (마스킹됨) | ELASTICACHE_001 → redis-cluster-001 | Request failed with status code 500... | ❌ 위험 |
| 23 | AWS Account | 123456789012 | ACCOUNT_001 | (마스킹됨) | ACCOUNT_001 → 123456789012 | Request failed with status code 500... | ❌ 위험 |
| 24 | Access Key | AKIAIOSFODNN7EXAMPLE | ACCESS_KEY_001 | (마스킹됨) | ACCESS_KEY_001 → AKIAIOSFODNN7EXAMPLE | Request failed with status code 500... | ❌ 위험 |
| 25 | Session Token | FwoGZXIvYXdzEBaDOEXAMPLETOKEN123 | SESSION_TOKEN_001 | (마스킹됨) | SESSION_TOKEN_001 → FwoGZXIvYXdzEBaDOEXAMPLETOKEN123 | Request failed with status code 500... | ❌ 위험 |
| 26 | IAM Role ARN | arn:aws:iam::123456789012:role/MyRole | IAM_ROLE_001 | (마스킹됨) | IAM_ROLE_001 → arn:aws:iam::123456789012:role/MyRole | Request failed with status code 500... | ❌ 위험 |
| 27 | IAM User ARN | arn:aws:iam::123456789012:user/MyUser | IAM_USER_001 | (마스킹됨) | IAM_USER_001 → arn:aws:iam::123456789012:user/MyUser | Request failed with status code 500... | ❌ 위험 |
| 28 | KMS Key | 12345678-1234-1234-1234-123456789012 | KMS_KEY_001 | (마스킹됨) | KMS_KEY_001 → 12345678-1234-1234-1234-123456789012 | Based on the provided AWS infrastructure data whic... | ✅ 안전 |
| 29 | Certificate ARN | arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 | CERT_ARN_001 | (마스킹됨) | CERT_ARN_001 → arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 | Request failed with status code 500... | ❌ 위험 |
| 30 | Secret ARN | arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef | SECRET_ARN_001 | (마스킹됨) | SECRET_ARN_001 → arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef | Request failed with status code 500... | ❌ 위험 |
| 31 | Lambda ARN | arn:aws:lambda:us-east-1:123456789012:function:MyFunction | LAMBDA_ARN_001 | (마스킹됨) | LAMBDA_ARN_001 → arn:aws:lambda:us-east-1:123456789012:function:MyFunction | Request failed with status code 500... | ❌ 위험 |
| 32 | ECS Task | arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012 | ECS_TASK_001 | (마스킹됨) | ECS_TASK_001 → arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012 | Request failed with status code 500... | ❌ 위험 |
| 33 | EKS Cluster | arn:aws:eks:us-east-1:123456789012:cluster/my-cluster | EKS_CLUSTER_001 | (마스킹됨) | EKS_CLUSTER_001 → arn:aws:eks:us-east-1:123456789012:cluster/my-cluster | Request failed with status code 500... | ❌ 위험 |
| 34 | API Gateway | a1b2c3d4e5 | API_GW_001 | (마스킹됨) | API_GW_001 → a1b2c3d4e5 | Request failed with status code 500... | ❌ 위험 |
| 35 | ELB ARN | arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456 | ELB_ARN_001 | (마스킹됨) | ELB_ARN_001 → arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456 | Request failed with status code 500... | ❌ 위험 |
| 36 | SNS Topic | arn:aws:sns:us-east-1:123456789012:MyTopic | SNS_TOPIC_001 | (마스킹됨) | SNS_TOPIC_001 → arn:aws:sns:us-east-1:123456789012:MyTopic | Request failed with status code 500... | ❌ 위험 |
| 37 | SQS Queue | https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue | SQS_QUEUE_001 | (마스킹됨) | SQS_QUEUE_001 → https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue | Request failed with status code 500... | ❌ 위험 |
| 38 | DynamoDB Table | arn:aws:dynamodb:us-east-1:123456789012:table/MyTable | DYNAMODB_TABLE_001 | (마스킹됨) | DYNAMODB_TABLE_001 → arn:aws:dynamodb:us-east-1:123456789012:table/MyTable | Request failed with status code 500... | ❌ 위험 |
| 39 | CloudWatch Log | /aws/lambda/my-function | LOG_GROUP_001 | (마스킹됨) | LOG_GROUP_001 → /aws/lambda/my-function | Request failed with status code 500... | ❌ 위험 |
| 40 | Route53 Zone | Z1234567890ABC | ROUTE53_ZONE_001 | (마스킹됨) | ROUTE53_ZONE_001 → Z1234567890ABC | Request failed with status code 500... | ❌ 위험 |

## 🚨 보안 실패 패턴 상세 분석

### 16. Public IP
- **원본**: 54.239.28.85
- **예상 마스킹**: PUBLIC_IP_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: Test AWS resource: 54.239.28.85

### 17. IPv6
- **원본**: 2001:db8::8a2e:370:7334
- **예상 마스킹**: IPV6_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 18. S3 Bucket
- **원본**: my-production-bucket
- **예상 마스킹**: BUCKET_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 19. S3 Logs
- **원본**: my-application-logs
- **예상 마스킹**: BUCKET_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 20. EFS
- **원본**: fs-0123456789abcdef0
- **예상 마스킹**: EFS_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 21. RDS Instance
- **원본**: prod-db-instance
- **예상 마스킹**: RDS_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 22. ElastiCache
- **원본**: redis-cluster-001
- **예상 마스킹**: ELASTICACHE_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 23. AWS Account
- **원본**: 123456789012
- **예상 마스킹**: ACCOUNT_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 24. Access Key
- **원본**: AKIAIOSFODNN7EXAMPLE
- **예상 마스킹**: ACCESS_KEY_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 25. Session Token
- **원본**: FwoGZXIvYXdzEBaDOEXAMPLETOKEN123
- **예상 마스킹**: SESSION_TOKEN_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 26. IAM Role ARN
- **원본**: arn:aws:iam::123456789012:role/MyRole
- **예상 마스킹**: IAM_ROLE_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 27. IAM User ARN
- **원본**: arn:aws:iam::123456789012:user/MyUser
- **예상 마스킹**: IAM_USER_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 29. Certificate ARN
- **원본**: arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012
- **예상 마스킹**: CERT_ARN_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 30. Secret ARN
- **원본**: arn:aws:secretsmanager:us-east-1:123456789012:secret:MySecret-abcdef
- **예상 마스킹**: SECRET_ARN_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 31. Lambda ARN
- **원본**: arn:aws:lambda:us-east-1:123456789012:function:MyFunction
- **예상 마스킹**: LAMBDA_ARN_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 32. ECS Task
- **원본**: arn:aws:ecs:us-east-1:123456789012:task/12345678-1234-1234-1234-123456789012
- **예상 마스킹**: ECS_TASK_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 33. EKS Cluster
- **원본**: arn:aws:eks:us-east-1:123456789012:cluster/my-cluster
- **예상 마스킹**: EKS_CLUSTER_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 34. API Gateway
- **원본**: a1b2c3d4e5
- **예상 마스킹**: API_GW_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 35. ELB ARN
- **원본**: arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/1234567890123456
- **예상 마스킹**: ELB_ARN_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 36. SNS Topic
- **원본**: arn:aws:sns:us-east-1:123456789012:MyTopic
- **예상 마스킹**: SNS_TOPIC_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 37. SQS Queue
- **원본**: https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue
- **예상 마스킹**: SQS_QUEUE_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 38. DynamoDB Table
- **원본**: arn:aws:dynamodb:us-east-1:123456789012:table/MyTable
- **예상 마스킹**: DYNAMODB_TABLE_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 39. CloudWatch Log
- **원본**: /aws/lambda/my-function
- **예상 마스킹**: LOG_GROUP_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined

### 40. Route53 Zone
- **원본**: Z1234567890ABC
- **예상 마스킹**: ROUTE53_ZONE_001
- **문제**: Claude가 원본 값을 그대로 받았음
- **응답**: undefined


## 🎯 보안 검증 결론
❌ **심각한 보안 문제 발견**
- 24개 패턴에서 마스킹 실패
- Claude API가 원본 AWS 리소스에 접근 가능
- 즉시 수정 필요
