# Kong AWS Masking Enterprise 2 - EC2 Terraform 모듈

Kong AWS Masking Enterprise 2를 EC2 인스턴스에 배포하기 위한 Terraform 모듈입니다.

## 🏗️ 아키텍처

```
Internet Gateway
        │
        │
    VPC (10.0.0.0/16)
        │
        ├── Public Subnet 1 (10.0.1.0/24) - AZ: us-east-1a
        ├── Public Subnet 2 (10.0.2.0/24) - AZ: us-east-1b
        │
        │
    Application Load Balancer
        │
        ├── EC2 Instance 1 (Kong + Nginx + Redis)
        └── EC2 Instance 2 (Kong + Nginx + Redis) [선택사항]
```

## 📋 구성 요소

### 네트워크 리소스
- **VPC**: 격리된 네트워크 환경
- **Public Subnets**: 인터넷 접근 가능한 서브넷 (멀티 AZ)
- **Internet Gateway**: 인터넷 연결
- **Route Tables**: 라우팅 설정
- **Security Groups**: 방화벽 규칙

### 컴퓨팅 리소스  
- **EC2 Instances**: Kong 애플리케이션 실행
- **Application Load Balancer**: 트래픽 분산 (선택사항)
- **CloudWatch Logs**: 로그 수집 및 모니터링

### 보안 및 권한
- **IAM Role/Policy**: EC2 인스턴스 권한
- **Security Groups**: 네트워크 보안
- **Instance Profile**: EC2-IAM 연결

## 🚀 사용 방법

### 1. 사전 요구사항

- Terraform >= 1.0
- LocalStack Pro (테스트용) 또는 AWS 계정
- Anthropic API 키

### 2. LocalStack에서 테스트

```bash
# LocalStack 시작 (Kong 프로젝트 루트에서)
docker-compose -f docker-compose.localstack.yml up -d

# Terraform 디렉토리로 이동
cd terraform/ec2

# 변수 파일 설정
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 파일 편집 (Anthropic API 키 등 설정)

# Terraform 초기화
terraform init

# 계획 확인
terraform plan

# 배포
terraform apply
```

### 3. 실제 AWS에서 배포

```bash
# terraform.tfvars 파일에서 LocalStack 설정 비활성화
localstack_enabled = false
aws_access_key = "your-actual-access-key"
aws_secret_key = "your-actual-secret-key"

# 키 페어 생성 (EC2 SSH 접근용)
aws ec2 create-key-pair --key-name kong-keypair --query 'KeyMaterial' --output text > ~/.ssh/kong-keypair.pem
chmod 400 ~/.ssh/kong-keypair.pem

# terraform.tfvars 파일에 키 페어 이름 설정
key_pair_name = "kong-keypair"

# 배포
terraform apply
```

## 🔧 설정 옵션

### 인스턴스 설정

| 변수 | 설명 | 기본값 | 예시 |
|------|------|---------|------|
| `instance_type` | EC2 인스턴스 타입 | `t3.medium` | `t3.large`, `m5.xlarge` |
| `instance_count` | 인스턴스 수량 | `1` | `2`, `3` |
| `root_volume_size` | 루트 볼륨 크기 (GB) | `20` | `50`, `100` |

### 네트워크 설정

| 변수 | 설명 | 기본값 |
|------|------|---------|
| `vpc_cidr` | VPC CIDR 블록 | `10.0.0.0/16` |
| `allowed_ssh_cidrs` | SSH 접근 허용 CIDR | `["0.0.0.0/0"]` |
| `allowed_admin_cidrs` | Kong Admin API 접근 허용 CIDR | `["10.0.0.0/16"]` |

### 애플리케이션 설정

| 변수 | 설명 | 필수 |
|------|------|------|
| `anthropic_api_key` | Anthropic API 키 | ✅ |
| `redis_password` | Redis 패스워드 | ✅ |
| `kong_admin_token` | Kong Admin 토큰 | ✅ |

## 📊 출력값

배포 완료 후 다음 정보를 확인할 수 있습니다:

```bash
# 배포 정보 확인
terraform output

# 주요 출력값:
# - instance_public_ips: EC2 인스턴스 퍼블릭 IP
# - kong_admin_urls: Kong Admin API URL
# - kong_proxy_urls: Kong Proxy URL  
# - nginx_proxy_urls: Nginx Proxy URL
# - ssh_connection_commands: SSH 연결 명령어
```

## 🔍 헬스체크

배포 후 서비스 상태 확인:

```bash
# Kong Admin API
curl http://<instance-ip>:8001/status

# Kong Proxy 
curl http://<instance-ip>:8000/health

# Nginx Proxy
curl http://<instance-ip>:8082/health

# Load Balancer (활성화된 경우)
curl http://<alb-dns>/health
```

## 📝 로그 확인

### EC2 인스턴스 로그

```bash
# SSH 접속
ssh -i ~/.ssh/kong-keypair.pem ec2-user@<instance-ip>

# 설치 로그 확인
sudo tail -f /var/log/kong-install.log

# 애플리케이션 로그 확인
cd /home/ec2-user/kong-app
docker-compose logs -f
```

### CloudWatch 로그

AWS Console에서 CloudWatch > 로그 그룹으로 이동하여 `/aws/ec2/kong/<environment>` 확인

## 🛠️ 문제 해결

### 일반적인 문제

1. **인스턴스에 SSH 접속 불가**
   - 보안 그룹에서 SSH(22) 포트 허용 확인
   - 키 페어 파일 권한 확인 (`chmod 400`)

2. **Kong 서비스 접근 불가**
   - 보안 그룹에서 해당 포트 허용 확인
   - 인스턴스 상태 및 헬스체크 확인

3. **Docker 서비스 실행 안됨**
   - EC2 인스턴스 로그 확인: `/var/log/kong-install.log`
   - Docker 서비스 상태 확인: `systemctl status docker`

### LocalStack 관련 문제

1. **LocalStack 연결 불가**
   - LocalStack 컨테이너 상태 확인
   - 네트워크 설정 확인 (Docker bridge)

2. **리소스 생성 실패**
   - LocalStack Pro 라이센스 확인
   - 지원되는 서비스인지 확인

## 💰 비용 추정

출력값에서 `estimated_hourly_cost`를 통해 대략적인 시간당 비용을 확인할 수 있습니다.

예시 (미국 동부 기준):
- `t3.medium` 1대 + ALB: 약 $0.06/시간
- `t3.large` 2대 + ALB: 약 $0.19/시간

## 🔄 정리

```bash
# 리소스 삭제
terraform destroy

# LocalStack도 정리하려면
docker-compose -f ../../docker-compose.localstack.yml down
```

## 📚 참고 자료

- [Kong Gateway 문서](https://docs.konghq.com/gateway/)
- [AWS EC2 사용자 가이드](https://docs.aws.amazon.com/ec2/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [LocalStack 문서](https://docs.localstack.cloud/)