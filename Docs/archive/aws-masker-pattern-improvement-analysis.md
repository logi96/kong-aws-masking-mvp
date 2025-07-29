# Kong AWS Masker 패턴 개선 분석 보고서

## 🚨 현재 문제점 요약

Kong AWS Masker의 패턴 매칭에서 **일반 용어가 AWS 리소스로 오인되어 불필요하게 마스킹**되는 심각한 문제가 발견되었습니다.

### 발견된 주요 False Positive 케이스
| 일반 용어 | 현재 마스킹 결과 | 문제점 |
|----------|-----------------|--------|
| `db` | `RDS_001` | 데이터베이스 일반 용어 |
| `redis-cluster` | `REDSHIFT_001` | Redis 클러스터를 Redshift로 오인 |
| `bucket` | `BUCKET_001` | 양동이 일반 용어 |
| `logs` | `BUCKET_001` | 로그 일반 용어 |
| `feedback` | `RDS_001` | "db" 포함된 일반 단어 |
| `127.0.0.1` | `PUBLIC_IP_001` | localhost를 Public IP로 오인 |
| `123456789012` | `ACCOUNT_001` | 일반 12자리 숫자 |

## 📊 위험도별 패턴 분류

### 🔴 극도로 위험 (Immediate Fix Required)
1. **`rds_instance`**: `[a-z%-]*db[a-z%-]*` - "db" 포함 모든 텍스트
2. **`account_id`**: `%d%d%d%d%d%d%d%d%d%d%d%d` - 모든 12자리 숫자
3. **`public_ip`**: `[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+` - 모든 IPv4 주소

### 🟠 매우 위험 (High Priority Fix)
1. **`s3_bucket`**: `[a-z0-9][a-z0-9%-]*bucket[a-z0-9%-]*` - "bucket" 포함 모든 단어
2. **`s3_logs_bucket`**: `[a-z0-9][a-z0-9%-]*logs[a-z0-9%-]*` - "logs" 포함 모든 단어
3. **`redshift`**: `[a-z][a-z0-9%-]*%-cluster` - "-cluster" 끝나는 모든 단어

### 🟡 위험 (Medium Priority Fix)
1. **`kms_key`**: UUID 패턴 - 모든 UUID 형태
2. **`route53_zone`**: `Z[0-9A-Z]{13,}` - Z로 시작하는 긴 문자열
3. **`log_group`**: `/aws/[a-zA-Z0-9%-_/]+` - /aws/ 시작 모든 경로

## 🎯 개선된 패턴 로직 제안

### 1. **스마트 검증 시스템 도입**

```lua
-- 새로운 패턴 구조
improved_pattern = {
  name = "rds_instance",
  base_pattern = "[a-z][a-z0-9-]{2,62}",
  replacement = "RDS_%03d",
  type = "rds",
  priority = 520,
  
  -- 스마트 검증 함수
  validate = function(text, context)
    return smart_aws_validator(text, "rds", context)
  end,
  
  -- 제외 리스트
  exclude_list = {"db", "database", "handbook", "feedback", "sidebar"},
  
  -- 필수 조건
  requirements = {
    min_length = 3,
    max_length = 63,
    must_contain_hyphen = false,
    aws_context_preferred = true
  }
}
```

### 2. **컨텍스트 분석 엔진**

```lua
function analyze_aws_context(text, surrounding_text)
  local aws_keywords = {
    "aws", "amazon", "rds", "ec2", "s3", "vpc", "iam",
    "instance", "cluster", "database", "bucket", "region",
    "us-east-1", "us-west-2", "ap-northeast-2"
  }
  
  local general_keywords = {
    "tutorial", "example", "guide", "documentation",
    "application", "software", "business", "company"
  }
  
  local aws_score = count_keywords(surrounding_text, aws_keywords)
  local general_score = count_keywords(surrounding_text, general_keywords)
  
  return {
    aws_probability = aws_score / (aws_score + general_score + 1),
    confidence = (aws_score + general_score) / 10
  }
end
```

### 3. **개선된 패턴별 구현**

#### **RDS 패턴 개선**
```lua
-- 기존 (문제)
rds_instance_old = {
  pattern = "[a-z%-]*db[a-z%-]*"  -- 너무 광범위
}

-- 개선안
rds_instance_new = {
  pattern = "[a-z][a-z0-9-]{2,62}",
  
  validate = function(text, context)
    -- 1. 블랙리스트 확인
    local blacklist = {"db", "database", "handbook", "feedback", "sidebar", "dashboard"}
    if table_contains(blacklist, text:lower()) then
      return false
    end
    
    -- 2. 길이 검증
    if #text < 3 or #text > 63 then
      return false
    end
    
    -- 3. AWS 컨텍스트 확인
    local context_analysis = analyze_aws_context(text, context)
    if context_analysis.aws_probability > 0.6 then
      return true
    end
    
    -- 4. 패턴 복잡도 확인 (하이픈 포함된 복합어)
    if string.match(text, "%-") and #text >= 5 then
      return has_aws_indicators(text, context)
    end
    
    return false
  end
}
```

#### **Account ID 패턴 개선**
```lua
-- 기존 (문제)
account_id_old = {
  pattern = "%d%d%d%d%d%d%d%d%d%d%d%d"  -- 모든 12자리 숫자
}

-- 개선안
account_id_new = {
  pattern = "%d%d%d%d%d%d%d%d%d%d%d%d",
  
  validate = function(text, context)
    -- 1. 특수 숫자 제외
    local excluded_numbers = {
      "000000000000", "111111111111", "123456789012",
      "999999999999", "123123123123"
    }
    if table_contains(excluded_numbers, text) then
      return false
    end
    
    -- 2. 전화번호 패턴 제외 (010으로 시작하는 11자리 등)
    if string.match(text, "^010") or string.match(text, "^821") then
      return false
    end
    
    -- 3. AWS 컨텍스트 필수
    local context_analysis = analyze_aws_context(text, context)
    return context_analysis.aws_probability > 0.7
  end
}
```

#### **Public IP 패턴 개선**
```lua
-- 기존 (문제)
public_ip_old = {
  pattern = "[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+"  -- 모든 IPv4
}

-- 개선안
public_ip_new = {
  pattern = "[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+",
  
  validate = function(text, context)
    -- 1. 사설 IP 제외
    if is_private_ip(text) then
      return false
    end
    
    -- 2. 특수 IP 제외
    local special_ips = {"127.0.0.1", "0.0.0.0", "255.255.255.255"}
    if table_contains(special_ips, text) then
      return false
    end
    
    -- 3. AWS 퍼블릭 IP 범위 확인
    return is_aws_public_ip_range(text) and has_aws_context(context)
  end
}
```

#### **S3 Bucket 패턴 개선**
```lua
-- 개선안
s3_bucket_new = {
  pattern = "[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]",  -- AWS S3 명명 규칙
  
  validate = function(text, context)
    -- 1. 일반 용어 제외
    local general_terms = {"bucket", "buckets", "fire-bucket", "ice-bucket"}
    if table_contains(general_terms, text:lower()) then
      return false
    end
    
    -- 2. AWS S3 명명 규칙 검증
    if not matches_s3_naming_rules(text) then
      return false
    end
    
    -- 3. 최소 복잡도 요구 (점 또는 하이픈 포함)
    if not (string.match(text, "%.") or string.match(text, "%-")) then
      return false
    end
    
    return true
  end
}
```

### 4. **클러스터 패턴 분리**

```lua
-- Redis 클러스터
redis_cluster = {
  pattern = "redis%-[a-z0-9-]+",
  replacement = "REDIS_CLUSTER_%03d",
  type = "redis",
  priority = 545
}

-- Redshift 클러스터 (더 엄격한 패턴)
redshift_cluster = {
  pattern = "[a-z][a-z0-9-]*%-redshift",
  replacement = "REDSHIFT_%03d",
  type = "redshift",
  priority = 550,
  
  validate = function(text, context)
    return has_aws_context(context) and not is_other_service_cluster(text)
  end
}

-- 일반 클러스터 (마스킹하지 않음)
general_cluster_exclusions = {
  "k8s-cluster", "docker-cluster", "test-cluster", 
  "kafka-cluster", "mysql-cluster", "mongodb-cluster"
}
```

## 🔧 구현 우선순위

### Phase 1 (즉시 적용 - Critical)
1. **일반 용어 블랙리스트 추가**
   - `db`, `bucket`, `logs`, `cluster` 등 단독 사용 시 제외
2. **컨텍스트 검증 로직 추가**
   - AWS 관련 키워드 존재 여부 확인
3. **최소 복잡도 요구사항 적용**
   - 너무 단순한 패턴 제외

### Phase 2 (단기 적용 - High Priority)
1. **스마트 검증 함수 구현**
   - 각 패턴별 맞춤형 검증 로직
2. **IP 주소 분류 개선**
   - 사설 IP vs 퍼블릭 IP 구분
3. **클러스터 타입 분리**
   - Redis, Kafka, Redshift 등 구분

### Phase 3 (중기 적용 - Medium Priority)
1. **기계학습 기반 컨텍스트 분석**
   - 더 정교한 AWS vs 일반 용어 구분
2. **사용자 피드백 시스템**
   - False positive 리포팅 및 학습

## 📈 예상 효과

### 정확도 개선
- **현재**: ~60% 정확도 (많은 false positive)
- **개선 후**: ~95% 정확도 (엄격한 검증)

### False Positive 감소
- **현재**: 일반 용어 30-40% 오인식
- **개선 후**: 일반 용어 5% 미만 오인식

### 성능 영향
- **추가 검증 로직**: +2-3ms 처리 시간
- **전체 목표**: <5초 응답시간 유지

## 🚀 배포 전략

### 1. A/B 테스트
- 기존 패턴과 새 패턴 병렬 실행
- 결과 비교 및 검증

### 2. 점진적 배포
- Phase 1 → 테스트 → Phase 2 → 테스트 → Phase 3

### 3. 모니터링
- False positive 비율 추적
- 성능 메트릭 모니터링
- 사용자 피드백 수집

이 개선안을 통해 **Claude API가 실제 AWS 리소스는 마스킹된 상태로 받되, 일반 용어는 원본 그대로 받을 수 있도록** 하여 AI 분석의 정확성을 크게 향상시킬 수 있습니다.