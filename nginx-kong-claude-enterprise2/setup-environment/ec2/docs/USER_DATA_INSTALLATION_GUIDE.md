# Kong AWS Masking Enterprise 2 - user_data_full.sh 설치 가이드

**Version:** Phase 1 성공 버전  
**최종 업데이트:** 2025-07-31  
**스크립트 위치:** `/archive/05-alternative-solutions/terraform/ec2/user_data_full.sh`

---

## 📋 **개요**

`user_data_full.sh`는 Kong AWS Masking Enterprise 2를 AWS EC2 인스턴스에 **완전 자동 설치**하는 Production-ready 스크립트입니다.

### 🏆 **Phase 1 성공 버전 특징**
- ✅ **API 키 Plugin Config 방식**: Claude API 인증 문제 완전 해결
- ✅ **kong-traditional.yml**: Phase 1 성공 구성 적용
- ✅ **자동화된 헬스체크**: 설치 후 15회 자동 검증
- ✅ **완전한 로깅**: 모든 과정이 `/var/log/kong-install.log`에 기록
- ✅ **4개 서비스 통합**: Kong + Nginx + Redis + Claude Code SDK

### 🏗️ **설치되는 아키텍처**
```
[EC2 Instance]
├── Kong Gateway (8001 Admin, 8010 Proxy)
│   └── aws-masker plugin (Phase 1 성공 버전)
├── Nginx Proxy (8082)
├── Redis (6379, 인증 활성화)
└── Claude Code SDK (Interactive)
```

---

## 🚀 **빠른 시작**

### Terraform 사용 (권장)
```hcl
resource "aws_instance" "kong_enterprise" {
  ami           = "ami-0abcdef1234567890"  # Amazon Linux 2023
  instance_type = "t3.medium"
  key_name      = "your-key-pair"
  
  vpc_security_group_ids = [aws_security_group.kong_sg.id]
  subnet_id              = aws_subnet.public.id
  
  user_data = templatefile("${path.module}/user_data_full.sh", {
    environment        = "production"
    anthropic_api_key  = var.anthropic_api_key
    redis_password     = var.redis_password
    kong_admin_token   = var.kong_admin_token
  })
  
  tags = {
    Name = "Kong-AWS-Masking-Enterprise-2"
  }
}
```

### AWS CLI 사용
```bash
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --count 1 \
  --instance-type t3.medium \
  --key-name your-key-pair \
  --security-group-ids sg-1234567890abcdef0 \
  --subnet-id subnet-12345678 \
  --user-data file://user_data_full.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Kong-Enterprise-2}]'
```

---

## ⚙️ **필수 환경변수**

| 변수명 | 필수 | 설명 | 예시 |
|--------|------|------|------|
| `environment` | ✅ | 배포 환경 | `production`, `staging`, `development` |
| `anthropic_api_key` | ✅ | Claude API 인증 키 | `sk-ant-api03-...` |
| `redis_password` | ✅ | Redis 인증 비밀번호 | `SecureRedisPass123!` |
| `kong_admin_token` | ✅ | Kong Admin API 토큰 | `admin-token-12345` |

### 🔒 **보안 권장사항**
```bash
# 강력한 비밀번호 생성
REDIS_PASSWORD=$(openssl rand -base64 32)
KONG_ADMIN_TOKEN=$(openssl rand -hex 16)

# AWS Systems Manager Parameter Store 사용 (권장)
aws ssm put-parameter \
  --name "/kong/production/anthropic_api_key" \
  --value "sk-ant-api03-..." \
  --type SecureString
```

---

## 📋 **사전 요구사항**

### AWS EC2 요구사항
- **OS**: Amazon Linux 2023 (권장) 또는 RHEL/CentOS 계열
- **인스턴스 타입**: 최소 `t3.medium` (2 vCPU, 4GB RAM)
- **스토리지**: 최소 20GB GP3
- **네트워크**: 인터넷 게이트웨이 접근 가능

### 네트워크 요구사항
```bash
# 필수 아웃바운드 포트
HTTPS (443) → api.anthropic.com        # Claude API
HTTPS (443) → github.com               # Docker Compose 다운로드
HTTP (80)   → package repositories    # 패키지 설치

# 필수 인바운드 포트 (Security Group)
8001 → Kong Admin API
8010 → Kong Proxy  
8082 → Nginx Proxy (메인 엔트리포인트)
6379 → Redis (내부 통신만)
```

### Security Group 예시
```hcl
resource "aws_security_group" "kong_sg" {
  name_description = "Kong AWS Masking Enterprise 2"
  
  # Kong Admin API
  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # VPC 내부만
  }
  
  # Kong Proxy
  ingress {
    from_port   = 8010
    to_port     = 8010  
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  # Nginx Proxy (메인 엔트리포인트)
  ingress {
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # 외부 접근
  }
  
  # SSH 접근
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["your-ip/32"]
  }
  
  # 모든 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## 🔧 **설치 과정 상세**

### Phase 1: 시스템 준비 (2-3분)
```bash
# 수행 작업
- yum update -y
- Docker 설치 및 시작
- Docker Compose v2.24.1 설치
- 사용자 권한 설정
```

### Phase 2: 프로젝트 구조 생성 (30초)
```bash
# 생성되는 구조
/home/ec2-user/kong-app/
├── docker-compose.yml           # 메인 구성
├── kong/
│   ├── kong-traditional.yml     # Phase 1 성공 Kong 설정
│   └── plugins/aws-masker/      # 커스텀 플러그인
├── nginx/nginx.conf             # Nginx 프록시 설정
├── logs/                        # 서비스별 로그 디렉토리
└── .env                         # 환경변수 파일
```

### Phase 3: 서비스 시작 (3-5분)
```bash
# 서비스 시작 순서
1. Redis (비밀번호 인증 활성화)
2. Kong Gateway (Redis 연결 확인 후)
3. Nginx Proxy (Kong 연결 확인 후)
4. Claude Code SDK (전체 스택 준비 후)
```

### Phase 4: 자동 검증 (3-4분)
```bash
# 15회 반복 헬스체크
- Kong Admin API (8001) 상태 확인
- Kong Proxy (8010) 응답 확인  
- Nginx Proxy (8082) 헬스체크
- Claude Code SDK 컨테이너 상태 확인
```

**총 설치 시간: 8-12분**

---

## ✅ **설치 후 검증**

### 자동 검증 (스크립트 내장)
설치 스크립트가 자동으로 다음을 확인합니다:
- ✅ 모든 서비스 정상 시작
- ✅ Kong Admin API 응답 확인
- ✅ Nginx 헬스체크 통과
- ✅ Docker 컨테이너 상태 검증

### 수동 검증 방법

#### 1. 서비스 상태 확인
```bash
# EC2 인스턴스 접속 후
cd /home/ec2-user/kong-app
docker-compose ps

# 예상 출력
NAME                        IMAGE                       COMMAND                   SERVICE   CREATED          STATUS                    PORTS
claude-redis                redis:7-alpine              "docker-entrypoint.s…"   redis     30 minutes ago   Up 30 minutes (healthy)   0.0.0.0:6379->6379/tcp
claude-kong                 kong/kong-gateway:3.9.0.1   "/entrypoint.sh kong…"   kong      30 minutes ago   Up 30 minutes (healthy)   8000/tcp, 8002-8004/tcp, 8443-8447/tcp, 0.0.0.0:8001->8001/tcp, 0.0.0.0:8010->8010/tcp
claude-nginx                nginx:alpine                "nginx -g 'daemon of…"   nginx     30 minutes ago   Up 30 minutes             0.0.0.0:8082->8082/tcp
claude-code-sdk             alpine:latest               "sh -c 'apk add --n…"   claude-code-sdk   30 minutes ago   Up 30 minutes             
```

#### 2. 엔드포인트 테스트
```bash
# EC2 Public IP 확인
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# 헬스체크 엔드포인트
curl http://$PUBLIC_IP:8082/health
# 응답: {"status":"healthy"}

curl http://$PUBLIC_IP:8001/status  
# 응답: Kong Admin API 상태 정보

# Kong 플러그인 확인
curl http://$PUBLIC_IP:8001/plugins
# aws-masker 플러그인 확인
```

#### 3. Phase 1 성공 버전 검증
```bash
# Kong 설정 확인
curl http://$PUBLIC_IP:8001/config
# kong-traditional.yml 로드 확인

# aws-masker 플러그인 설정 확인
curl http://$PUBLIC_IP:8001/plugins | jq '.data[] | select(.name=="aws-masker")'
# anthropic_api_key 설정 확인 (값은 마스킹됨)
```

#### 4. Claude Code SDK 테스트
```bash
# Claude Code SDK 컨테이너 접속
docker exec -it claude-code-sdk sh

# 컨테이너 내에서 프록시 테스트
curl http://nginx:8082/health
# 응답: {"status":"healthy"}
```

---

## 📝 **로그 및 모니터링**

### 설치 로그
```bash
# 설치 과정 전체 로그
tail -f /var/log/kong-install.log

# 설치 완료 후 로그 위치
/home/ec2-user/kong-app/logs/
├── kong/          # Kong Gateway 로그
├── nginx/         # Nginx 프록시 로그
├── redis/         # Redis 로그
└── claude-code-sdk/  # Claude Code SDK 로그
```

### 실시간 모니터링
```bash
# 전체 서비스 로그 실시간 확인
cd /home/ec2-user/kong-app
docker-compose logs -f

# 특정 서비스 로그
docker-compose logs -f kong
docker-compose logs -f nginx
docker-compose logs -f redis
```

### 중요 로그 파일들
```bash
# Kong Gateway
/home/ec2-user/kong-app/logs/kong/access.log     # 요청 로그
/home/ec2-user/kong-app/logs/kong/error.log      # 오류 로그

# Nginx
/home/ec2-user/kong-app/logs/nginx/access.log    # Nginx 접근 로그
/home/ec2-user/kong-app/logs/nginx/error.log     # Nginx 오류 로그

# Redis
/home/ec2-user/kong-app/logs/redis/              # Redis 로그
```

---

## 🚨 **트러블슈팅**

### 일반적인 문제 및 해결방법

#### 1. 설치 스크립트 실행 실패
**증상:** 스크립트가 중간에 중단됨
```bash
# 해결방법
1. 로그 확인
   tail -100 /var/log/kong-install.log

2. 권한 확인
   ls -la /var/log/kong-install.log
   
3. 재실행 (환경변수 설정 후)
   export environment="production"
   export anthropic_api_key="sk-ant-api03-..."
   export redis_password="your-redis-password"  
   export kong_admin_token="your-admin-token"
   bash user_data_full.sh
```

#### 2. Docker 서비스 시작 실패
**증상:** Docker 컨테이너가 시작되지 않음
```bash
# 진단
docker-compose ps
docker-compose logs

# 해결방법
1. Docker 서비스 상태 확인
   systemctl status docker
   
2. Docker 재시작
   systemctl restart docker
   
3. 서비스 재시작
   cd /home/ec2-user/kong-app
   docker-compose down
   docker-compose up -d
```

#### 3. Kong 플러그인 로딩 실패
**증상:** aws-masker 플러그인을 찾을 수 없음
```bash
# 진단
curl http://localhost:8001/plugins
docker-compose logs kong

# 해결방법
1. 플러그인 파일 확인
   ls -la /home/ec2-user/kong-app/kong/plugins/aws-masker/
   
2. Kong 컨테이너 재시작
   docker-compose restart kong
   
3. Kong 로그 상세 확인
   docker-compose logs kong | grep -i error
```

#### 4. Redis 연결 실패
**증상:** Kong이 Redis에 연결할 수 없음
```bash
# 진단
docker-compose logs redis
docker exec claude-redis redis-cli -a $REDIS_PASSWORD ping

# 해결방법
1. Redis 비밀번호 확인
   cat /home/ec2-user/kong-app/.env | grep REDIS_PASSWORD
   
2. Redis 컨테이너 상태 확인
   docker-compose ps redis
   
3. 네트워크 연결 테스트
   docker exec claude-kong ping redis
```

#### 5. 포트 충돌 문제
**증상:** 포트가 이미 사용 중
```bash
# 진단
netstat -tlnp | grep -E ':(8001|8010|8082|6379)'
lsof -i :8082

# 해결방법
1. 충돌하는 프로세스 종료
   sudo pkill -f 'process-name'
   
2. 포트 변경 (docker-compose.yml 수정)
   "18082:8082"  # 포트 18082로 변경
   
3. 서비스 재시작
   docker-compose down && docker-compose up -d
```

#### 6. Claude API 통신 실패
**증상:** Claude API 응답 없음 (401, 403 오류)
```bash
# 진단
curl -X POST http://localhost:8082/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d '{"model":"claude-3-sonnet-20240229","max_tokens":100,"messages":[{"role":"user","content":"Hello"}]}'

# 해결방법
1. API 키 확인
   echo $ANTHROPIC_API_KEY
   # sk-ant-api03- 로 시작하는지 확인
   
2. Kong 플러그인 설정 확인
   curl http://localhost:8001/plugins | jq '.data[] | select(.name=="aws-masker") | .config'
   
3. 네트워크 연결 확인
   curl -I https://api.anthropic.com
```

### 로그 기반 문제 진단

#### Kong 관련 오류
```bash
# Kong 시작 실패
docker-compose logs kong | grep -i "error\|failed"

# 일반적인 오류 패턴
- "plugin 'aws-masker' not found" → 플러그인 파일 확인
- "database connection failed" → Redis 연결 문제
- "invalid config" → kong-traditional.yml 문법 오류
```

#### Nginx 관련 오류
```bash
# Nginx 설정 오류
docker-compose logs nginx | grep -i error

# 일반적인 오류 패턴  
- "upstream backend not found" → Kong 서비스 연결 실패
- "bind() failed" → 포트 충돌
- "permission denied" → 권한 문제
```

### 완전 재설치 방법
```bash
# 1. 모든 서비스 중지 및 제거
cd /home/ec2-user/kong-app
docker-compose down -v
docker system prune -f

# 2. 애플리케이션 디렉토리 제거
rm -rf /home/ec2-user/kong-app

# 3. 환경변수 재설정 후 스크립트 재실행
export environment="production"
export anthropic_api_key="sk-ant-api03-..."
export redis_password="new-redis-password"
export kong_admin_token="new-admin-token"

# 4. 스크립트 재실행
bash user_data_full.sh
```

---

## 🔒 **보안 고려사항**

### API 키 보안 관리
```bash
# ❌ 잘못된 방법 - 평문 저장
export anthropic_api_key="sk-ant-api03-plaintext"

# ✅ 올바른 방법 - AWS Systems Manager
aws ssm put-parameter \
  --name "/kong/prod/anthropic_api_key" \
  --value "sk-ant-api03-..." \
  --type SecureString

# 스크립트에서 사용
anthropic_api_key=$(aws ssm get-parameter \
  --name "/kong/prod/anthropic_api_key" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)
```

### 네트워크 보안
```bash
# Security Group 최소 권한 원칙
- Kong Admin API (8001): VPC 내부만 접근
- Kong Proxy (8010): 필요한 경우만 외부 접근
- Nginx Proxy (8082): 메인 엔트리포인트
- Redis (6379): 내부 통신만
```

### 로그 보안
```bash
# 민감 정보 로그 필터링
# Kong과 Nginx는 자동으로 API 키를 마스킹하지만
# 추가 보안을 위해 로그 로테이션 설정

# /etc/logrotate.d/kong-enterprise
/home/ec2-user/kong-app/logs/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 ec2-user ec2-user
}
```

### 컨테이너 보안
```bash
# 정기적인 이미지 업데이트
docker-compose pull
docker-compose up -d

# 취약점 스캔 (권장)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image kong/kong-gateway:3.9.0.1
```

---

## 📊 **성능 튜닝 가이드**

### 리소스 권장사항

#### 인스턴스 크기별 성능
| 인스턴스 타입 | vCPU | 메모리 | 동시 요청 | 용도 |
|---------------|------|--------|-----------|------|
| t3.medium | 2 | 4GB | 100-500 | 개발/테스트 |
| t3.large | 2 | 8GB | 500-1000 | 스테이징 |
| c5.xlarge | 4 | 8GB | 1000-2000 | 프로덕션 |  
| c5.2xlarge | 8 | 16GB | 2000+ | 고부하 |

#### Kong 메모리 튜닝
```yaml
# docker-compose.yml에서 Kong 환경변수 조정
environment:
  - KONG_MEM_CACHE_SIZE=4096m        # 인스턴스 메모리의 50%
  - KONG_WORKER_PROCESSES=4          # vCPU 수와 동일
  - KONG_WORKER_CONNECTIONS=1024     # 동시 연결 수
```

#### Redis 성능 최적화
```yaml
# Redis 설정 최적화
redis:
  command: redis-server --requirepass ${REDIS_PASSWORD} 
    --maxmemory 2gb                   # 최대 메모리 사용량
    --maxmemory-policy allkeys-lru    # 메모리 회수 정책
    --tcp-keepalive 60                # TCP 연결 유지
```

### 모니터링 메트릭
```bash
# Kong 성능 모니터리
curl http://localhost:8001/status

# Redis 성능 모니터링
docker exec claude-redis redis-cli -a $REDIS_PASSWORD info stats

# 시스템 리소스 모니터링
htop
df -h
free -h
```

---

## 🔄 **업데이트 및 유지보수**

### 서비스 업데이트
```bash
# 1. 백업 생성
cd /home/ec2-user/kong-app
docker-compose exec redis redis-cli -a $REDIS_PASSWORD --rdb backup.rdb
cp -r . /home/ec2-user/kong-app-backup-$(date +%Y%m%d)

# 2. 이미지 업데이트
docker-compose pull

# 3. 순차적 재시작
docker-compose up -d --force-recreate

# 4. 헬스체크 확인
curl http://localhost:8082/health
```

### Kong 플러그인 업데이트
```bash
# 1. 플러그인 파일 백업
cp -r kong/plugins/aws-masker kong/plugins/aws-masker.backup

# 2. 새 플러그인 파일 복사
# (새 handler.lua, schema.lua 등)

# 3. Kong 재시작
docker-compose restart kong

# 4. 플러그인 로드 확인
curl http://localhost:8001/plugins | jq '.data[] | select(.name=="aws-masker")'
```

### 정기 유지보수 작업
```bash
# 주간 작업
- 로그 로테이션 확인
- 디스크 사용량 모니터링  
- 보안 패치 적용
- 백업 상태 확인

# 월간 작업  
- 전체 시스템 백업
- 성능 리포트 생성
- 취약점 스캔
- 용량 계획 검토
```

---

## 📚 **추가 리소스**

### 관련 문서
- **[CLAUDE.md](./CLAUDE.md)** - 전체 프로젝트 가이드
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - 배포 전략 가이드
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - 상세 트러블슈팅
- **[FINAL-INSTALLATION-VERIFICATION-REPORT.md](./localstack-deployment/FINAL-INSTALLATION-VERIFICATION-REPORT.md)** - 검증 결과

### 외부 참조
- **[Kong Gateway 문서](https://docs.konghq.com/gateway/latest/)**
- **[Docker Compose 문서](https://docs.docker.com/compose/)**
- **[Anthropic Claude API 문서](https://docs.anthropic.com/)**
- **[Redis 문서](https://redis.io/documentation)**

### 지원 및 문의
- **프로젝트 이슈**: GitHub Issues
- **기술 지원**: 프로젝트 README 참조
- **보안 문제**: 별도 보안 채널 사용

---

**🎉 축하합니다! Kong AWS Masking Enterprise 2가 성공적으로 설치되었습니다.**

**다음 단계**: [EKS 환경 설치 가이드](./EKS_INSTALLATION_GUIDE.md) (예정)