# 환경별 단순 설치 시스템 구현 계획

**프로젝트**: Kong AWS Masking Enterprise 2  
**계획 수립일**: 2025-01-30  
**담당자**: 개발팀  
**우선순위**: High  

## 🎯 배경 및 목적

### 배경
현재 Kong AWS Masking Enterprise 2는 4가지 배포 환경을 지원하지만, 각 환경별로 복잡한 설치 과정과 서로 다른 Redis 연동 방식으로 인해 고객 설치 시 어려움이 발생하고 있습니다.

### 현재 문제점
1. **복잡한 설치 과정**: 환경별로 다른 설치 방법과 설정 요구사항
2. **Redis 연동 일관성 부족**: IaaS Redis vs ElastiCache 연동 방식 혼재
3. **고객 편의성 부족**: 과도한 설정 입력 요구
4. **오버엔지니어링 위험**: 통합 설치 도구의 과도한 복잡성

### 목적
- **단순화**: 환경별 최적화된 단순한 설치 스크립트 제공
- **일관성**: Redis 연동 방식 통일 (IaaS vs Managed)
- **편의성**: 최소한의 입력으로 완전 자동 설치
- **유지보수성**: 환경별 독립적인 스크립트로 관리 부담 최소화

## 🏗️ 현재 상황 분석

### 지원 환경 및 Redis 방식
| 환경 | 현재 Redis 방식 | 목표 Redis 방식 | 변경 필요성 |
|------|---------------|---------------|-----------|
| **EC2 (IaaS)** | Docker Redis | Docker Redis | 변경 없음 |
| **EKS EC2** | StatefulSet | StatefulSet | 변경 없음 |
| **EKS Fargate** | 미지원 | **ElastiCache** | **신규 구현** |
| **ECS** | 미지원 | **ElastiCache** | **신규 구현** |

### 기술 스택 현황
- **Kong Gateway**: 3.9.0 (Lua Plugin)
- **Redis 연동**: 현재 IaaS Redis만 지원
- **배포 도구**: Docker Compose, Helm Charts
- **인프라**: Terraform 모듈 (EC2만)

## 🎯 환경별 설치 전략

### 1. EC2 (IaaS) - Docker Compose 기반
```bash
# 목표: 30줄 이내 스크립트
curl -sSL https://install.kong-masking.com/ec2 | bash

# 입력 정보
- License Key
- Claude API Key  
- Redis Password

# 설치 방식
- Docker, Docker Compose 자동 설치
- docker-compose.yml 다운로드 및 실행
- 환경변수 자동 설정
```

### 2. EKS EC2 - Helm Chart 기반
```bash
# 목표: 25줄 이내 스크립트
curl -sSL https://install.kong-masking.com/eks-ec2 | bash

# 전제 조건
- kubectl 설정 완료

# 입력 정보
- License Key
- Claude API Key
- Redis Password

# 설치 방식
- Helm Chart 설치
- StatefulSet Redis 사용
- 기본 values.yaml 적용
```

### 3. EKS Fargate - ElastiCache + Helm
```bash
# 목표: 30줄 이내 스크립트
curl -sSL https://install.kong-masking.com/eks-fargate | bash

# 전제 조건
- kubectl 설정 완료
- ElastiCache 클러스터 미리 생성

# 입력 정보
- License Key
- Claude API Key
- ElastiCache Endpoint

# 설치 방식
- values-fargate.yaml 사용
- ElastiCache 연동 설정
- Fargate Profile 활용
```

### 4. ECS - ElastiCache + Task Definition
```bash
# 목표: 35줄 이내 스크립트
curl -sSL https://install.kong-masking.com/ecs | bash

# 전제 조건
- AWS CLI 설정 완료
- ECS 클러스터 미리 생성
- ElastiCache 클러스터 미리 생성

# 입력 정보
- License Key
- Claude API Key
- ECS Cluster Name
- ElastiCache Endpoint

# 설치 방식
- Task Definition 등록
- ECS Service 생성
- ALB 연동 (선택적)
```

## 🔧 핵심 구현 사항

### 1. Kong Plugin ElastiCache 지원 구현

#### handler.lua 수정
```lua
-- redis 연결 방식 분기 로직 추가
local function connect_redis(config)
  if config.redis_type == "managed" then
    return connect_elasticache(config)
  else
    return connect_traditional_redis(config) -- 기존 방식
  end
end

-- ElastiCache 연결 함수 신규 추가
local function connect_elasticache(config)
  local redis = require "resty.redis"
  local red = redis:new()
  
  local ok, err = red:connect(
    config.redis_host,
    config.redis_port or 6379,
    {
      ssl = config.ssl_enabled or true,
      ssl_verify = false,  -- ElastiCache SSL 검증 비활성화
      pool_size = config.pool_size or 10,
      timeout = config.timeout or 2000
    }
  )
  
  if config.auth_token then
    red:auth(config.auth_token)
  end
  
  return red, err
end
```

#### schema.lua 확장
```lua
-- ElastiCache 설정 스키마 추가
{ redis_type = { 
    type = "string", 
    default = "traditional",
    one_of = { "managed", "traditional" }
}},
{ redis_host = { type = "string" }},
{ redis_port = { type = "integer", default = 6379 }},
{ auth_token = { type = "string" }},
{ ssl_enabled = { type = "boolean", default = false }},
{ pool_size = { type = "integer", default = 10 }},
{ timeout = { type = "integer", default = 2000 }}
```

### 2. Helm Charts 확장

#### values-fargate.yaml 신규 생성
```yaml
global:
  environment: fargate
  
redis:
  enabled: false  # StatefulSet 비활성화
  type: managed
  
# ElastiCache 설정
elasticache:
  enabled: true
  endpoint: ""  # 고객 입력값
  port: 6379
  ssl: true
  
# Fargate 노드 선택기
nodeSelector:
  kubernetes.io/compute-type: fargate
  
kong:
  config:
    redis_type: managed
    redis_host: "${ELASTICACHE_ENDPOINT}"
    ssl_enabled: true
    auth_token: "${ELASTICACHE_AUTH_TOKEN}"
```

### 3. ECS Task Definition 템플릿

#### ecs-task-definition.json
```json
{
  "family": "kong-masking",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "containerDefinitions": [
    {
      "name": "kong",
      "image": "kong:3.9.0-ubuntu",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8010,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "KONG_DATABASE",
          "value": "off"
        },
        {
          "name": "KONG_PLUGINS",
          "value": "aws-masker"
        },
        {
          "name": "REDIS_TYPE",
          "value": "managed"
        },
        {
          "name": "REDIS_HOST",
          "value": "${ELASTICACHE_ENDPOINT}"
        },
        {
          "name": "SSL_ENABLED",
          "value": "true"
        }
      ]
    }
  ]
}
```

## 📅 구현 일정

### Week 1: 핵심 인프라 구현
- **Day 1-2**: Kong Plugin ElastiCache 지원 구현
  - handler.lua 수정
  - schema.lua 확장
  - 단위 테스트 작성
- **Day 3-4**: Helm Charts 확장
  - values-fargate.yaml 생성
  - ElastiCache 연동 테스트
- **Day 5**: 통합 테스트 및 검증

### Week 2: 환경별 설치 스크립트 (1차)
- **Day 1-2**: EC2 설치 스크립트
  - Docker 자동 설치 로직
  - Docker Compose 파일 생성
  - 환경변수 설정 자동화
- **Day 3-4**: EKS EC2 설치 스크립트
  - Helm Chart 자동 설치
  - kubectl 전제조건 검증
  - StatefulSet Redis 설정
- **Day 5**: 1차 스크립트 테스트

### Week 3: 환경별 설치 스크립트 (2차)
- **Day 1-3**: EKS Fargate 설치 스크립트
  - ElastiCache 전제조건 검증
  - values-fargate.yaml 적용
  - Fargate Profile 확인
- **Day 4-5**: ECS 설치 스크립트
  - Task Definition 등록
  - ECS Service 생성
  - ALB 연동 (선택적)
- **Day 6-7**: 전체 통합 테스트

### Week 4: 배포 및 문서화
- **Day 1-2**: 설치 스크립트 호스팅 구성
- **Day 3-4**: 사용자 가이드 작성
- **Day 5**: 최종 검증 및 배포

## 📊 리소스 및 예상 공수

### 개발 리소스
- **백엔드 개발자**: 1명 (Kong Plugin 수정)
- **DevOps 엔지니어**: 1명 (스크립트 및 인프라)
- **QA 엔지니어**: 0.5명 (테스트 및 검증)

### 예상 공수
| 작업 항목 | 예상 시간 | 담당자 |
|----------|----------|-------|
| Kong Plugin 수정 | 5일 | 백엔드 |
| Helm Charts 확장 | 3일 | DevOps |
| EC2 설치 스크립트 | 3일 | DevOps |
| EKS 설치 스크립트 | 5일 | DevOps |
| ECS 설치 스크립트 | 7일 | DevOps |
| 테스트 및 검증 | 5일 | QA |
| **총 공수** | **28일** | **2.5명** |

## 🚨 리스크 관리

### 높은 위험도
| 리스크 | 영향도 | 대응 방안 |
|-------|-------|----------|
| **ElastiCache SSL 연결 이슈** | 높음 | Kong OpenResty SSL 모듈 사전 검증 |
| **ECS Task Definition 복잡성** | 높음 | 단계별 검증 및 CloudFormation 활용 |
| **Fargate 네트워킹 제약** | 중간 | 사전 Fargate Profile 테스트 |

### 중간 위험도
| 리스크 | 영향도 | 대응 방안 |
|-------|-------|----------|
| **설치 스크립트 권한 이슈** | 중간 | sudo 권한 사전 확인 로직 |
| **AWS 자격증명 부족** | 중간 | 명확한 전제조건 문서화 |
| **Docker 설치 실패** | 낮음 | 수동 설치 가이드 제공 |

### 대응 전략
1. **단계별 검증**: 주요 리스크 항목별 사전 PoC 진행
2. **롤백 계획**: 설치 실패 시 자동 정리 로직 포함
3. **문서화**: 전제조건 및 트러블슈팅 가이드 상세 작성

## 🎯 성공 기준

### 기능적 요구사항
- [x] 4개 환경 모두에서 30-35줄 이내 설치 스크립트
- [x] License Key, API Key, 필수 엔드포인트만 입력 요구
- [x] ElastiCache 연동 완전 자동화
- [x] 설치 성공률 95% 이상

### 비기능적 요구사항
- [x] 설치 시간 각 환경별 5분 이내
- [x] 스크립트 실행 시 사용자 대기 시간 최소화
- [x] 명확한 에러 메시지 및 해결 방안 제시
- [x] 기존 시스템과의 호환성 보장

### 품질 기준
- [x] 단위 테스트: Kong Plugin 수정사항 100% 커버리지
- [x] 통합 테스트: 4개 환경 모두 설치 검증
- [x] 문서화: 사용자 가이드 및 트러블슈팅 완료
- [x] 코드 리뷰: 모든 수정사항 리뷰 완료

## 📚 관련 문서

### 기술 문서
- [Kong Plugin Development Guide](../../../Docs/Standards/17-kong-plugin-development-guide.md)
- [AWS Resource Masking Patterns](../../../Docs/Standards/18-aws-resource-masking-patterns.md)
- [Docker Compose Best Practices](../../../Docs/Standards/19-docker-compose-best-practices.md)

### 테스트 문서
- [Test Suite Documentation](../../../tests/README.md)
- [Performance Validation Guide](../../../kong/plugins/aws-masker/docs/performance-security-validation-detailed.md)

### 배포 문서
- [EKS Deployment Guide](../../../archive/05-alternative-solutions/kubernetes/EKS-DEPLOYMENT-GUIDE.md)
- [Production Deployment Guide](../deployment/PRODUCTION-DEPLOYMENT-GUIDE.md)

## ✅ 승인 및 검토

### 계획 승인
- **기술 검토**: 승인 필요
- **리소스 승인**: 승인 필요  
- **일정 승인**: 승인 필요

### 진행 상황 추적
- **주간 진행 보고**: 매주 금요일
- **마일스톤 리뷰**: Week 1, 2, 3 종료 시
- **최종 검수**: Week 4 완료 시

---

**계획 수립자**: 개발팀  
**검토자**: 기술 리더  
**승인자**: 프로젝트 매니저  
**최종 업데이트**: 2025-01-30