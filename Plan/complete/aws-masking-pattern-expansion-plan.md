# AWS Masking Pattern Expansion Plan

## 🎯 목표 (GOAL)
Kong AWS Masking 시스템의 데이터 보호 범위를 확장하여 포괄적인 AWS 리소스 마스킹 구현

## 📊 현재 상태 및 문제점 분석 (METRIC)
- **현재 구현된 패턴**: 5개 (EC2, Private IP, S3, RDS)
- **문서화된 패턴**: 15개+ (VPC, IAM, Lambda 등 미구현)
- **패턴 정확도**: ~70% (false positive 발생)
- **보안 커버리지**: 60% (핵심 AWS 리소스 중)

### 식별된 주요 문제점

#### 1. 과도하게 광범위한 패턴
```lua
-- 문제가 있는 현재 패턴
pattern = "[a-z%-]*db[a-z%-]*"        -- 일반 텍스트도 매칭
pattern = "[a-z0-9][a-z0-9%-]*bucket[a-z0-9%-]*"  -- false positive 다수
```

#### 2. 컨텍스트 부족
- JSON 구조 내 키-값 관계 미고려
- ARN 내부 구성 요소 개별 처리 불가
- 데이터 타입별 검증 로직 부재

#### 3. 성능 및 메모리 이슈
- 매 요청마다 패턴 컴파일
- 메모리 사용량 최적화 부족
- 대용량 JSON 처리 시 지연 발생

## 📋 확장 계획 (PLAN)

### Phase 1: 핵심 패턴 정확도 개선 (1주차)

#### 1.1 기존 패턴 리팩터링
**파일**: `/kong/plugins/aws-masker/patterns_v2.lua`

```lua
-- 개선된 패턴 구조
local patterns_v2 = {
    -- EC2 인스턴스 (엄격한 패턴)
    {
        name = "ec2_instance_id",
        patterns = {
            "i%-[0-9a-f]{8}",      -- 8자리 (구형)
            "i%-[0-9a-f]{17}"      -- 17자리 (신형)
        },
        contexts = {"Instances", "InstanceId", "Instance"},
        replacement = "EC2_%03d",
        priority = 1,
        validation = function(value)
            return value:len() == 10 or value:len() == 19
        end
    },
    
    -- S3 버킷 (컨텍스트 기반)
    {
        name = "s3_bucket_name",
        patterns = {
            's3://([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])/',  -- S3 URI
            '"Bucket"%s*:%s*"([^"]+)"',                     -- JSON key
            'arn:aws:s3:::([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])'  -- ARN
        },
        replacement = "BUCKET_%03d",
        priority = 2,
        validation = function(value)
            -- S3 버킷 명명 규칙 검증
            return value:len() >= 3 and value:len() <= 63 and 
                   not value:match("%.%.") and
                   not value:match("^%d+%.%d+%.%d+%.%d+$")
        end
    }
}
```

#### 1.2 컨텍스트 기반 매칭 엔진
**파일**: `/kong/plugins/aws-masker/context_matcher.lua`

```lua
local context_matcher = {}

-- JSON 경로 추적
function context_matcher.parse_with_context(json_str)
    local success, data = pcall(cjson.decode, json_str)
    if not success then
        return nil, {}
    end
    
    local context_map = {}
    
    local function traverse(obj, path)
        if type(obj) == "table" then
            for k, v in pairs(obj) do
                local new_path = path == "" and k or path .. "." .. k
                
                if type(v) == "string" then
                    context_map[v] = {
                        path = new_path,
                        key = k,
                        parent_path = path
                    }
                end
                
                traverse(v, new_path)
            end
        end
    end
    
    traverse(data, "")
    return data, context_map
end

-- 컨텍스트 기반 매칭 결정
function context_matcher.should_mask(value, context, pattern_def)
    -- 1. 기본 패턴 매칭
    local matches = false
    for _, pattern in ipairs(pattern_def.patterns) do
        if value:match(pattern) then
            matches = true
            break
        end
    end
    
    if not matches then
        return false
    end
    
    -- 2. 컨텍스트 검증
    if pattern_def.contexts then
        local context_match = false
        for _, ctx_pattern in ipairs(pattern_def.contexts) do
            if context.path:match(ctx_pattern) or context.key:match(ctx_pattern) then
                context_match = true
                break
            end
        end
        
        if not context_match then
            return false
        end
    end
    
    -- 3. 값 검증
    if pattern_def.validation then
        return pattern_def.validation(value)
    end
    
    return true
end

return context_matcher
```

### Phase 2: 확장 패턴 구현 (2주차)

#### 2.1 VPC 관련 리소스 패턴
**파일**: `/kong/plugins/aws-masker/vpc_patterns.lua`

```lua
local vpc_patterns = {
    -- VPC ID
    {
        name = "vpc_id",
        patterns = {"vpc%-[0-9a-f]{8,17}"},
        contexts = {"VpcId", "Vpc", "VPC"},
        replacement = "VPC_%03d",
        priority = 3
    },
    
    -- Subnet ID
    {
        name = "subnet_id", 
        patterns = {"subnet%-[0-9a-f]{8,17}"},
        contexts = {"SubnetId", "Subnet"},
        replacement = "SUBNET_%03d",
        priority = 4
    },
    
    -- Security Group ID
    {
        name = "security_group_id",
        patterns = {"sg%-[0-9a-f]{8,17}"},
        contexts = {"SecurityGroupId", "GroupId", "SecurityGroup"},
        replacement = "SG_%03d",
        priority = 5
    }
}

return vpc_patterns
```

#### 2.2 IAM 및 ARN 패턴
**파일**: `/kong/plugins/aws-masker/iam_patterns.lua`

```lua
local iam_patterns = {
    -- AWS Account ID (ARN 내부)
    {
        name = "aws_account_id",
        patterns = {
            "(arn:aws:[^:]+:[^:]*:)(%d{12})(:[^%s]+)",  -- ARN 내부
            '"Account"%s*:%s*"(%d{12})"'                -- JSON 키
        },
        replacement = function(match_groups)
            if #match_groups == 3 then
                -- ARN 내부: prefix + masked_id + suffix
                return match_groups[1] .. "ACCOUNT_%03d" .. match_groups[3]
            else
                -- 단순 매칭
                return "ACCOUNT_%03d"
            end
        end,
        priority = 1  -- 높은 우선순위
    },
    
    -- IAM Role ARN
    {
        name = "iam_role_arn",
        patterns = {"arn:aws:iam::[^:]+:role/([^%s,]+)"},
        replacement = "IAM_ROLE_%03d", 
        priority = 6
    },
    
    -- Access Key ID
    {
        name = "aws_access_key",
        patterns = {"AKIA[0-9A-Z]{16}"},
        replacement = "ACCESS_KEY_%03d",
        priority = 2  -- 높은 우선순위 (보안 중요)
    }
}

return iam_patterns
```

#### 2.3 추가 네트워크 및 스토리지 패턴
**파일**: `/kong/plugins/aws-masker/network_storage_patterns.lua`

```lua
local network_storage_patterns = {
    -- 추가 Private IP 범위
    {
        name = "private_ip_172", 
        patterns = {"172%.1[6-9]%.%d+%.%d+", "172%.2[0-9]%.%d+%.%d+", "172%.3[01]%.%d+%.%d+"},
        replacement = "PRIVATE_IP_%03d",
        priority = 7
    },
    
    {
        name = "private_ip_192",
        patterns = {"192%.168%.%d+%.%d+"},
        replacement = "PRIVATE_IP_%03d", 
        priority = 8
    },
    
    -- EBS Volume ID
    {
        name = "ebs_volume_id",
        patterns = {"vol%-[0-9a-f]{8,17}"},
        contexts = {"VolumeId", "Volume"},
        replacement = "VOL_%03d",
        priority = 9
    },
    
    -- AMI ID
    {
        name = "ami_id",
        patterns = {"ami%-[0-9a-f]{8,17}"},
        contexts = {"ImageId", "AMI", "Image"},
        replacement = "AMI_%03d",
        priority = 10
    }
}

return network_storage_patterns
```

### Phase 3: 고성능 매칭 엔진 구현 (3주차)

#### 3.1 최적화된 메인 마스킹 엔진
**파일**: `/kong/plugins/aws-masker/masker_v2.lua`

```lua
local masker_v2 = {}
local cjson = require "cjson"
local context_matcher = require "kong.plugins.aws-masker.context_matcher"

-- 패턴 로더 (모든 패턴 파일 통합)
local function load_all_patterns()
    local patterns_v2 = require "kong.plugins.aws-masker.patterns_v2"
    local vpc_patterns = require "kong.plugins.aws-masker.vpc_patterns" 
    local iam_patterns = require "kong.plugins.aws-masker.iam_patterns"
    local network_storage_patterns = require "kong.plugins.aws-masker.network_storage_patterns"
    
    local all_patterns = {}
    
    -- 패턴 통합 및 우선순위 정렬
    for _, pattern_set in ipairs({patterns_v2, vpc_patterns, iam_patterns, network_storage_patterns}) do
        for _, pattern in ipairs(pattern_set) do
            table.insert(all_patterns, pattern)
        end
    end
    
    -- 우선순위 기준 정렬 (낮은 숫자 = 높은 우선순위)
    table.sort(all_patterns, function(a, b)
        return a.priority < b.priority
    end)
    
    return all_patterns
end

-- 매핑 스토리지 (TTL 포함)
local mapping_store = {
    mappings = {},
    reverse_mappings = {},
    counters = {},
    timestamps = {}
}

-- 최적화된 마스킹 함수
function masker_v2.mask_request(body, config)
    local start_time = ngx.now()
    
    -- JSON 파싱 및 컨텍스트 추출
    local data, context_map = context_matcher.parse_with_context(body)
    if not data then
        kong.log.warn("Failed to parse JSON body for masking")
        return body, {}
    end
    
    local patterns = load_all_patterns()
    local masked_count = 0
    local mapping_id = ngx.var.request_id or tostring(ngx.now())
    
    -- 재귀적 마스킹
    local function mask_value(obj)
        if type(obj) == "table" then
            for k, v in pairs(obj) do
                obj[k] = mask_value(v)
            end
        elseif type(obj) == "string" then
            local context = context_map[obj]
            
            -- 패턴별 매칭 시도 (우선순위 순)
            for _, pattern_def in ipairs(patterns) do
                if context_matcher.should_mask(obj, context or {}, pattern_def) then
                    local masked_value = masker_v2.apply_masking(obj, pattern_def, mapping_id)
                    if masked_value ~= obj then
                        masked_count = masked_count + 1
                        return masked_value
                    end
                end
            end
        end
        
        return obj
    end
    
    local masked_data = mask_value(data)
    local processing_time = (ngx.now() - start_time) * 1000
    
    kong.log.info("Masking completed", {
        masked_count = masked_count,
        processing_time_ms = processing_time,
        mapping_id = mapping_id
    })
    
    return cjson.encode(masked_data), {
        mapping_id = mapping_id,
        masked_count = masked_count
    }
end

-- 마스킹 적용 함수
function masker_v2.apply_masking(original_value, pattern_def, mapping_id)
    -- 기존 매핑 확인
    local existing_mapping = mapping_store.mappings[original_value]
    if existing_mapping then
        return existing_mapping
    end
    
    -- 새 마스킹 생성
    local counter_key = pattern_def.name
    mapping_store.counters[counter_key] = (mapping_store.counters[counter_key] or 0) + 1
    
    local masked_value
    if type(pattern_def.replacement) == "function" then
        -- 복잡한 함수 기반 치환 (ARN 등)
        masked_value = pattern_def.replacement(original_value, mapping_store.counters[counter_key])
    else
        -- 간단한 문자열 치환
        masked_value = string.format(pattern_def.replacement, mapping_store.counters[counter_key])
    end
    
    -- 매핑 저장
    mapping_store.mappings[original_value] = masked_value
    mapping_store.reverse_mappings[masked_value] = original_value
    mapping_store.timestamps[original_value] = ngx.now()
    
    return masked_value
end

-- 언마스킹 함수
function masker_v2.unmask_response(body, mapping_context)
    if not mapping_context.mapping_id then
        return body
    end
    
    local start_time = ngx.now()
    local unmasked_count = 0
    
    -- 역매핑 적용
    for masked_value, original_value in pairs(mapping_store.reverse_mappings) do
        if body:find(masked_value, 1, true) then
            body = body:gsub(masked_value, original_value)
            unmasked_count = unmasked_count + 1
        end
    end
    
    local processing_time = (ngx.now() - start_time) * 1000
    
    kong.log.info("Unmasking completed", {
        unmasked_count = unmasked_count,
        processing_time_ms = processing_time
    })
    
    return body
end

-- TTL 기반 정리
function masker_v2.cleanup_expired_mappings(ttl_seconds)
    ttl_seconds = ttl_seconds or 300  -- 5분 기본값
    local current_time = ngx.now()
    local cleaned_count = 0
    
    for original_value, timestamp in pairs(mapping_store.timestamps) do
        if current_time - timestamp > ttl_seconds then
            local masked_value = mapping_store.mappings[original_value]
            
            mapping_store.mappings[original_value] = nil
            mapping_store.reverse_mappings[masked_value] = nil
            mapping_store.timestamps[original_value] = nil
            
            cleaned_count = cleaned_count + 1
        end
    end
    
    if cleaned_count > 0 then
        kong.log.debug("Cleaned up expired mappings", {count = cleaned_count})
    end
end

return masker_v2
```

### Phase 4: 패턴 테스트 모듈 구현 (3주차)

#### 4.1 패턴 테스트 프레임워크
**파일**: `/tests/pattern-matcher-test.lua`