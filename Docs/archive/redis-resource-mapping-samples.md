# Redis AWS Resource Mapping Samples

## Overview
Kong AWS Masking 플러그인이 Redis에 저장한 AWS 리소스 매핑 샘플입니다.  
각 리소스 타입별로 대표적인 예시를 하나씩 정리했습니다.

## Resource Type Mappings

| Resource Type | Masked ID | Original Value | Description |
|--------------|-----------|----------------|-------------|
| **EC2 Instance** | EC2_001 | i-abc123def456789 | EC2 인스턴스 ID |
| **S3 Bucket** | BUCKET_001 | my-production-bucket | S3 버킷 이름 |
| **RDS Instance** | RDS_001 | db | RDS 인스턴스 식별자 |
| **VPC** | VPC_001 | vpc-12345678 | VPC ID |
| **IAM Role** | IAM_ROLE_001 | arn:aws:iam::123456789012:role/MyRole | IAM Role ARN |
| **Security Group** | SG_005 | sg-01234567 | 보안 그룹 ID |
| **Subnet** | SUBNET_004 | subnet-01234567 | 서브넷 ID |
| **API Gateway** | API_GW_001 | 1234567890 | API Gateway ID |
| **Private IP** | PRIVATE_IP_001 | 10.20.30.40 | 프라이빗 IP 주소 |
| **Public IP** | PUBLIC_IP_013 | 54.239.28.85 | 퍼블릭 IP 주소 |
| **Access Key** | ACCESS_KEY_001 | AKIAIOSFODNN7EXAMPLE | AWS Access Key ID |
| **Account ID** | ACCOUNT_001 | 123456789012 | AWS 계정 ID |
| **AMI** | AMI_005 | ami-0abcdef1 | Amazon Machine Image ID |
| **EBS Volume** | EBS_VOL_001 | vol-0123456789abcdef0 | EBS 볼륨 ID |
| **EFS** | EFS_003 | fs-01234567 | Elastic File System ID |
| **Internet Gateway** | IGW_006 | igw-01234567 | 인터넷 게이트웨이 ID |
| **NAT Gateway** | NAT_GW_007 | nat-0123456789abcdef0 | NAT 게이트웨이 ID |
| **VPN Connection** | VPN_008 | vpn-01234567 | VPN 연결 ID |
| **Transit Gateway** | TGW_009 | tgw-0123456789abcdef0 | Transit Gateway ID |
| **IPv6 Address** | IPV6_011 | 2001:db8::8a2e:370:7334 | IPv6 주소 |
| **Session Token** | SESSION_TOKEN_002 | FwoGZXIvYXdzEBaDOEXAMPLETOKEN123 | AWS 세션 토큰 |
| **EBS Snapshot** | SNAPSHOT_002 | snap-0123456789abcdef0 | EBS 스냅샷 ID |
| **Redshift Cluster** | REDSHIFT_001 | redis-cluster | Redshift 클러스터 식별자 |
| **ARN** | ARN_003 | arn:aws:iam::123456789012:role/EC2-Role | AWS Resource Name |

## Statistics

- **총 매핑 수**: 239개
- **고유 리소스 타입**: 24종
- **가장 많이 마스킹된 타입**: 
  - Private IP: 26개
  - Public IP: 21개
  - API Gateway: 25개
  - Security Group: 6개
  - Account ID: 8개

## Key Naming Convention

- **매핑 키**: `aws_masker:map:{MASKED_VALUE}`
- **역매핑 키**: `aws_masker:rev:{BASE64_ENCODED_ORIGINAL}`
- **테스트 키**: `aws_masker:test:*`

## TTL Configuration

- **평균 TTL**: 약 6.9일 (597,533,483ms)
- **만료 설정된 키**: 227개 / 239개 (95%)

이 매핑들은 Kong Gateway가 AWS 리소스를 마스킹하고 Claude API 응답에서 다시 원본으로 복원할 때 사용됩니다.