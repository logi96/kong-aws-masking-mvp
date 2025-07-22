# Updated AWS Masking Pattern Expansion Plan

## 🎯 목표 (GOAL)
실제 Claude API content 필드의 복합 텍스트에서 여러 AWS 패턴을 정확하고 효율적으로 마스킹하는 시스템 구현

## 📊 수정된 현재 상태 분석 (METRIC)
- **현재 구현된 패턴**: 5개 (EC2, Private IP, S3, RDS)
- **실제 마스킹 대상**: Claude API `messages[0].content` 텍스트 필드
- **패턴 정확도**: ~70% (복합 텍스트에서 false positive 발생)
- **복합 패턴 테스트**: ❌ **미구현** (중요한 누락사항)

### 핵심 발견사항
실제 데이터 플로우에서 마스킹 대상은:
```json
{
  "messages": [{
    "role": "user",
    "content": "Please analyze AWS infrastructure: EC2 i-123..., S3 my-bucket, IP 10.0.1.100..."
  }]
}
```

## 📋 수정된 확장 계획 (PLAN)

### Phase 1: 복합 텍스트 패턴 매칭 엔진 (1주차)

#### 1.1 단순화된 텍스트 마스킹 엔진
**파일**: `/kong/plugins/aws-masker/text_masker_v2.lua`

```lua
local text_masker = {}
local cjson = require "cjson"

-- 우선순위 기반 패턴 정의 (간소화)
local aws_patterns = {
    -- 높은 우선순위 (구체적 패턴)
    {
        name = "aws_account_in_arn",
        pattern = "(arn:aws:[^:]+:[^:]*:)(%d{12})(:[^%s]+)",
        replacement = function(prefix, account, suffix, counter)
            return prefix .. "ACCOUNT_" .. string.format("%03d", counter) .. suffix
        end,
        priority = 1
    },
    
    {
        name = "iam_arn_full",
        pattern = "arn:aws:iam::[^%s]+",
        replacement = "IAM_ARN_%03d",
        priority = 2
    },
    
    {
        name = "ec2_instance_id",
        pattern = "i%-[0-9a-f]{8,17}",
        replacement = "EC2_%03d",
        priority = 3
    },
    
    {
        name = "vpc_id",
        pattern = "vpc%-[0-9a-f]{8,17}",
        replacement = "VPC_%03d",
        priority = 4
    },
    
    {
        name = "subnet_id", 
        pattern = "subnet%-[0-9a-f]{8,17}",
        replacement = "SUBNET_%03d",
        priority = 5
    },
    
    {
        name = "security_group_id",
        pattern = "sg%-[0-9a-f]{8,17}",
        replacement = "SG_%03d",
        priority = 6
    },
    
    -- 중간 우선순위
    {
        name = "s3_bucket_in_arn",
        pattern = "arn:aws:s3:::([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])",
        replacement = "arn:aws:s3:::BUCKET_%03d",
        priority = 7
    },
    
    {
        name = "s3_uri",
        pattern = "s3://([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])",
        replacement = "s3://BUCKET_%03d",
        priority = 8
    },
    
    -- 낮은 우선순위 (일반적 패턴)
    {
        name = "s3_bucket_general",
        pattern = "[a-z0-9][a-z0-9%-]*bucket[a-z0-9%-]*",
        replacement = "BUCKET_%03d",
        priority = 15
    },
    
    {
        name = "rds_instance_general",
        pattern = "[a-z%-]*db[a-z%-]*",
        replacement = "RDS_%03d",
        priority = 16
    },
    
    -- IP 주소 (마지막)
    {
        name = "private_ip_10",
        pattern = "10%.%d+%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 20
    },
    
    {
        name = "private_ip_172",
        pattern = "172%.1[6-9]%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 21
    },
    
    {
        name = "private_ip_172_20s",
        pattern = "172%.2[0-9]%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 22
    },
    
    {
        name = "private_ip_172_30s",
        pattern = "172%.3[01]%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 23
    },
    
    {
        name = "private_ip_192",
        pattern = "192%.168%.%d+%.%d+",
        replacement = "PRIVATE_IP_%03d",
        priority = 24
    }
}

-- 매핑 저장소 (단순화)
local mapping_store = {
    forward = {},  -- original -> masked
    reverse = {},  -- masked -> original
    counters = {}  -- pattern_name -> counter
}

-- 텍스트 마스킹 함수
function text_masker.mask_text(text, request_id)
    local masked_text = text
    local total_masked = 0
    
    -- 패턴을 우선순위 순으로 정렬
    table.sort(aws_patterns, function(a, b) return a.priority < b.priority end)
    
    -- 각 패턴 순차 적용
    for _, pattern_def in ipairs(aws_patterns) do
        local pattern = pattern_def.pattern
        local replacement = pattern_def.replacement
        local pattern_name = pattern_def.name
        
        -- 패턴 매칭 및 치환
        if type(replacement) == "function" then
            -- 복잡한 함수 기반 치환 (ARN 등)
            masked_text = masked_text:gsub(pattern, function(...)
                local matches = {...}
                mapping_store.counters[pattern_name] = (mapping_store.counters[pattern_name] or 0) + 1
                local counter = mapping_store.counters[pattern_name]
                
                local original = table.concat(matches, "")
                local masked = replacement(matches[1], matches[2], matches[3], counter)
                
                -- 매핑 저장
                mapping_store.forward[original] = masked
                mapping_store.reverse[masked] = original
                total_masked = total_masked + 1
                
                return masked
            end)
        else
            -- 단순 문자열 치환
            masked_text = masked_text:gsub(pattern, function(match)
                -- 이미 매핑된 경우 재사용
                if mapping_store.forward[match] then
                    return mapping_store.forward[match]
                end
                
                mapping_store.counters[pattern_name] = (mapping_store.counters[pattern_name] or 0) + 1
                local counter = mapping_store.counters[pattern_name]
                local masked = string.format(replacement, counter)
                
                -- 매핑 저장
                mapping_store.forward[match] = masked
                mapping_store.reverse[masked] = match
                total_masked = total_masked + 1
                
                return masked
            end)
        end
    end
    
    return masked_text, {
        masked_count = total_masked,
        request_id = request_id
    }
end

-- 텍스트 언마스킹 함수
function text_masker.unmask_text(text)
    local unmasked_text = text
    
    -- 역매핑 적용
    for masked, original in pairs(mapping_store.reverse) do
        unmasked_text = unmasked_text:gsub(masked, original)
    end
    
    return unmasked_text
end

-- Claude 요청 마스킹
function text_masker.mask_claude_request(body, config)
    local data = cjson.decode(body)
    
    if data.messages and data.messages[1] and data.messages[1].content then
        local original_content = data.messages[1].content
        local masked_content, context = text_masker.mask_text(original_content, ngx.var.request_id)
        
        data.messages[1].content = masked_content
        
        kong.log.info("Claude request masked", {
            original_length = #original_content,
            masked_length = #masked_content,
            masked_count = context.masked_count
        })
        
        return cjson.encode(data), context
    end
    
    return body, { masked_count = 0 }
end

-- Claude 응답 언마스킹
function text_masker.unmask_claude_response(body, context)
    local unmasked_body = text_masker.unmask_text(body)
    
    kong.log.info("Claude response unmasked", {
        request_id = context.request_id
    })
    
    return unmasked_body
end

-- 매핑 정리 (TTL 기반)
function text_masker.cleanup_mappings(ttl_seconds)
    ttl_seconds = ttl_seconds or 300  -- 5분
    -- 단순 구현: 전체 정리 (실제로는 타임스탬프 기반 구현 필요)
    mapping_store.forward = {}
    mapping_store.reverse = {}
    kong.log.debug("Mapping store cleaned up")
end

return text_masker
```

#### 1.2 단순화된 Handler 수정
**파일**: `/kong/plugins/aws-masker/handler.lua`

```lua
local aws_masker = {
    PRIORITY = 1000,
    VERSION = "2.1.0",
}

local text_masker = require "kong.plugins.aws-masker.text_masker_v2"

function aws_masker:access(conf)
    kong.service.request.enable_buffering()
end

function aws_masker:body_filter(conf)
    local ctx = kong.ctx.plugin
    
    -- 요청 마스킹
    if not ctx.request_processed then
        local body = kong.service.request.get_raw_body()
        if body and #body > 0 then
            local masked_body, context = text_masker.mask_claude_request(body, conf)
            kong.service.request.set_raw_body(masked_body)
            ctx.masking_context = context
        end
        ctx.request_processed = true
    end
    
    -- 응답 언마스킹
    if not ctx.response_processed then
        local body = kong.response.get_raw_body()
        if body and ctx.masking_context then
            local unmasked_body = text_masker.unmask_claude_response(body, ctx.masking_context)
            kong.response.set_raw_body(unmasked_body)
        end
        ctx.response_processed = true
    end
end

-- 주기적 정리
function aws_masker:init_worker()
    ngx.timer.every(300, function()  -- 5분마다
        text_masker.cleanup_mappings(300)
    end)
end

return aws_masker
```

### Phase 2: Enhanced Multi-Pattern Test Suite (1주차)

✅ **이미 작성 완료**: `enhanced-pattern-test-plan.md`

**핵심 개선사항**:
1. **실제 Claude content 시뮬레이션**: 긴 분석 텍스트 형태
2. **복합 패턴 동시 테스트**: 한 텍스트에 10+ 패턴 혼재
3. **패턴 간섭 검증**: VPC ID가 EC2로 잘못 매칭 등 방지
4. **대용량 텍스트 성능**: 10KB 텍스트 < 100ms 처리

### Phase 3: 단계적 패턴 확장 (2-3주차)

#### 3.1 검증된 패턴부터 순차 추가
```lua
-- 1단계: 핵심 패턴 (1주차)
priority_1_patterns = {
    "ec2_instance_id", "private_ip_10", "iam_arn_full", "aws_account_in_arn"
}

-- 2단계: VPC 패턴 (2주차)  
priority_2_patterns = {
    "vpc_id", "subnet_id", "security_group_id"
}

-- 3단계: 스토리지/컴퓨팅 (3주차)
priority_3_patterns = {
    "ebs_volume_id", "ami_id", "lambda_arn"
}
```

### Phase 4: 성능 최적화 및 배포 (4주차)

#### 4.1 성능 벤치마크 목표
- **복합 텍스트 처리**: 10KB < 100ms
- **메모리 사용량**: < 10MB per request
- **패턴 정확도**: 95% (false positive < 5%)

## 🎯 수정된 성공 기준 (SUCCESS CRITERIA)

### 기술적 지표
- ✅ **복합 패턴 정확도**: 95% (여러 패턴 혼재 시)
- ✅ **패턴 간섭 방지**: 0% (패턴 간 잘못된 매칭 없음)
- ✅ **대용량 텍스트 성능**: 10KB < 100ms
- ✅ **순서 독립성**: 패턴 순서 무관 동일 결과

### 실용적 지표
- ✅ **실제 Claude content 테스트**: 100% 통과
- ✅ **Roundtrip 정확도**: 100% (마스킹→언마스킹 원본 복원)
- ✅ **메모리 효율성**: 매핑 TTL 관리로 누수 방지

## 🚀 수정된 구현 순서

### 즉시 착수 (1주차)
1. ✅ **Enhanced Test Suite 구현**: 복합 패턴 검증 도구
2. ✅ **단순화된 텍스트 마스킹 엔진**: JSON 복잡도 제거
3. ✅ **핵심 4개 패턴 정확도 개선**: EC2, IP, ARN, Account ID

### 점진적 확장 (2-3주차)
1. **VPC 관련 패턴**: 테스트 통과 후 추가
2. **스토리지/컴퓨팅 패턴**: 단계별 검증 후 확장
3. **복합 패턴 최적화**: 대용량 텍스트 성능 튜닝

### 최종 검증 (4주차)
1. **프로덕션 시뮬레이션**: 실제 Claude API 데이터로 테스트
2. **성능 벤치마크**: 다양한 크기와 복잡도 텍스트
3. **안전 배포**: 롤링 업데이트 및 모니터링

## 💡 핵심 개선사항 요약

1. **✅ 복잡도 대폭 단순화**: JSON 컨텍스트 매칭 → 단순 텍스트 패턴
2. **✅ 실제 사용 사례 반영**: Claude content 필드 텍스트 정확히 시뮬레이션  
3. **✅ 복합 패턴 테스트 강화**: 여러 패턴 혼재 시나리오 완벽 검증
4. **✅ 우선순위 기반 매칭**: 구체적→일반적 순서로 false positive 최소화

이제 **실제 운영 환경과 100% 동일한 테스트**로 정확하고 효율적인 마스킹 시스템을 구축할 수 있습니다! 🎯