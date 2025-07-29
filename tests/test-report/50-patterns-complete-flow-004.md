# 50개 AWS 패턴 마스킹/언마스킹 플로우 테스트 리포트

**테스트 실행 시간**: 2025-07-25T10:29:51+09:00  
**테스트 스크립트**: 50-patterns-complete-flow.sh  
**목적**: 전체 AWS 리소스 패턴의 마스킹/언마스킹 완전성 검증

## 테스트 개요
- **총 패턴 수**: 46개 (복합 패턴 포함)
- **테스트 방식**: Backend API → Kong Gateway → Claude API → 언마스킹
- **검증 기준**: 원본 AWS 리소스가 사용자 응답에 완전 복원되는지 확인

## 상세 테스트 결과

### ❌ Test 1: EC2 Instance
- **원본**: `i-1234567890abcdef0`
- **응답**: `I apologize, but I notice that the provided context lacks specific details about the EC2_001 instance. To perform a thorough security analysis, I'll provide a general EC2 security assessment framework...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 2: EC2 Instance
- **원본**: `i-0987654321fedcba0`
- **응답**: `I'll analyze the AWS_EC2_002 security context. This identifier typically relates to EC2 instance security group configurations.

### Critical Security Issues
1. **Over-Permissive Security Group Rules*...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 3: AMI
- **원본**: `ami-0abcdef1234567890`
- **응답**: `I notice the provided context is very limited (only mentioning "amAWS_EC2_004" which appears to be related to EC2), but I'll provide a security analysis focusing on common EC2 security concerns:

1. *...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 4: EBS Volume
- **원본**: `vol-0123456789abcdef0`
- **응답**: `I'll analyze the AWS EBS volume (AWS_EBS_VOL_002) for security concerns.

1. **Critical Security Issues**

a) Encryption Status
- Description: EBS volumes should be encrypted at rest
- Impact: Unencry...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

### ❌ Test 5: Snapshot
- **원본**: `snap-0123456789abcdef0`
- **응답**: `I apologize, but I notice that the provided context "AWS_SNAPSHOT_003" lacks specific details about the snapshot configuration, settings, or attributes. However, I can provide a security analysis focu...`
- **결과**: 실패 (원본 리소스 복원되지 않음)

