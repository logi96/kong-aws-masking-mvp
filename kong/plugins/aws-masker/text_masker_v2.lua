-- text_masker_v2.lua
-- 보안 최우선: AWS 리소스 패턴을 완벽하게 마스킹하여 외부 API 노출 방지
-- 이 모듈은 Kong AWS Masking 시스템의 핵심 보안 컴포넌트입니다

local text_masker = {
    VERSION = "2.0.0",
    -- 보안 설정
    MAX_TEXT_SIZE = 10 * 1024 * 1024,  -- 10MB 제한
    MAX_MAPPINGS = 10000,              -- 메모리 보호
    MAPPING_TTL = 300,                 -- 5분 TTL
}

local cjson = require "cjson.safe"
local emergency_handler = require "kong.plugins.aws-masker.emergency_handler"

-- 보안 로깅
local function security_log(level, message, context)
    kong.log[level]("[AWS-MASKER] " .. message, context or {})
end

-- 우선순위 기반 패턴 정의 (보안 중요도 순)
local aws_patterns = {
    -- 최고 우선순위: 계정 및 인증 정보
    {
        name = "iam_access_key",
        pattern = "AKIA[A-Z0-9]{16}",
        replacement = "ACCESS_KEY_%03d",
        priority = 1,
        critical = true
    },
    {
        name = "aws_account_in_arn",
        pattern = "(arn:aws:[^:]+:[^:]*:)(%d{12})(:[^%s]+)",
        replacement = function(prefix, account, suffix, counter)
            return prefix .. "ACCOUNT_" .. string.format("%03d", counter) .. suffix
        end,
        priority = 2,
        critical = true
    },
    {
        name = "aws_account_standalone",
        pattern = "%d%d%d%d%d%d%d%d%d%d%d%d",
        replacement = "ACCOUNT_%03d",
        priority = 3,
        critical = true
    },
    
    -- 높은 우선순위: IAM 리소스
    {
        name = "iam_arn_full",
        pattern = "arn:aws:iam::[^%s]+",
        replacement = "IAM_ARN_%03d",
        priority = 4
    },
    
    -- 중간 우선순위: 컴퓨팅 리소스
    {
        name = "ec2_instance_id",
        pattern = "i%-[0-9a-f]{8,17}",
        replacement = "EC2_%03d",
        priority = 5
    },
    {
        name = "vpc_id",
        pattern = "vpc%-[0-9a-f]{8,17}",
        replacement = "VPC_%03d",
        priority = 6
    },
    {
        name = "subnet_id",
        pattern = "subnet%-[0-9a-f]{8,17}",
        replacement = "SUBNET_%03d",
        priority = 7
    },
    {
        name = "security_group_id",
        pattern = "sg%-[0-9a-f]{8,17}",
        replacement = "SG_%03d",
        priority = 8
    },
    
    -- 중간 우선순위: 스토리지
    {
        name = "s3_bucket_in_arn",
        pattern = "arn:aws:s3:::([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])",
        replacement = "arn:aws:s3:::BUCKET_%03d",
        priority = 9
    },
    {
        name = "s3_uri",
        pattern = "s3://([a-z0-9][a-z0-9%-%.]{1,61}[a-z0-9])",
        replacement = "s3://BUCKET_%03d",
        priority = 10
    },
    {
        name = "ebs_volume_id",
        pattern = "vol%-[0-9a-f]{8,17}",
        replacement = "VOLUME_%03d",
        priority = 11
    },
    {
        name = "ami_id",
        pattern = "ami%-[0-9a-f]{8,17}",
        replacement = "AMI_%03d",
        priority = 12
    },
    
    -- 낮은 우선순위: 일반 패턴
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
    
    -- 최저 우선순위: IP 주소
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

-- 매핑 저장소 (메모리 안전)
local mapping_store = {
    forward = {},   -- original -> masked
    reverse = {},   -- masked -> original
    counters = {},  -- pattern_name -> counter
    timestamps = {}, -- key -> timestamp (TTL 관리)
    size = 0
}

-- 보안 검증 함수
local function validate_input(text)
    -- 크기 제한
    if not text then
        return false, "Input is nil"
    end
    
    if type(text) ~= "string" then
        return false, "Input is not a string"
    end
    
    if #text > text_masker.MAX_TEXT_SIZE then
        return false, "Input too large: " .. #text .. " bytes"
    end
    
    -- 제어 문자 검사
    if text:match("[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]") then
        security_log("warn", "Control characters detected in input")
        -- 차단하지 않고 경고만 (정상적인 JSON에도 있을 수 있음)
    end
    
    return true
end

-- 매핑 저장 (메모리 안전)
local function store_mapping(original, masked, pattern_name)
    -- 크기 제한 확인
    if mapping_store.size >= text_masker.MAX_MAPPINGS then
        -- 오래된 매핑 정리
        text_masker.cleanup_old_mappings(100)
    end
    
    local key = ngx.encode_base64(original)
    local timestamp = ngx.now()
    
    mapping_store.forward[key] = masked
    mapping_store.reverse[masked] = original
    mapping_store.timestamps[key] = timestamp
    mapping_store.size = mapping_store.size + 1
    
    security_log("debug", "Mapping stored", {
        pattern = pattern_name,
        size = mapping_store.size
    })
end

-- 오래된 매핑 정리
function text_masker.cleanup_old_mappings(count)
    local current_time = ngx.now()
    local cleaned = 0
    
    for key, timestamp in pairs(mapping_store.timestamps) do
        if current_time - timestamp > text_masker.MAPPING_TTL then
            local masked = mapping_store.forward[key]
            if masked then
                mapping_store.reverse[masked] = nil
            end
            mapping_store.forward[key] = nil
            mapping_store.timestamps[key] = nil
            mapping_store.size = mapping_store.size - 1
            cleaned = cleaned + 1
            
            if cleaned >= count then
                break
            end
        end
    end
    
    security_log("info", "Cleaned old mappings", {
        cleaned = cleaned,
        remaining = mapping_store.size
    })
end

-- 텍스트 마스킹 함수 (핵심)
function text_masker.mask_text(text, request_id)
    -- 입력 검증
    local valid, err = validate_input(text)
    if not valid then
        return nil, { error = err, request_id = request_id }
    end
    
    local masked_text = text
    local total_masked = 0
    local pattern_stats = {}
    
    -- 패턴을 우선순위 순으로 정렬
    table.sort(aws_patterns, function(a, b) return a.priority < b.priority end)
    
    -- 각 패턴 순차 적용
    for _, pattern_def in ipairs(aws_patterns) do
        local pattern = pattern_def.pattern
        local replacement = pattern_def.replacement
        local pattern_name = pattern_def.name
        local pattern_count = 0
        
        -- 카운터 초기화
        mapping_store.counters[pattern_name] = mapping_store.counters[pattern_name] or 0
        
        -- 패턴 매칭 및 치환
        if type(replacement) == "function" then
            -- 복잡한 함수 기반 치환
            masked_text = masked_text:gsub(pattern, function(...)
                local matches = {...}
                mapping_store.counters[pattern_name] = mapping_store.counters[pattern_name] + 1
                local counter = mapping_store.counters[pattern_name]
                
                local original = table.concat(matches, "")
                local masked = replacement(matches[1], matches[2], matches[3], counter)
                
                -- 매핑 저장
                store_mapping(original, masked, pattern_name)
                total_masked = total_masked + 1
                pattern_count = pattern_count + 1
                
                return masked
            end)
        else
            -- 단순 문자열 치환
            masked_text = masked_text:gsub(pattern, function(match)
                -- 이미 매핑된 경우 재사용
                local key = ngx.encode_base64(match)
                if mapping_store.forward[key] then
                    mapping_store.timestamps[key] = ngx.now()  -- TTL 갱신
                    return mapping_store.forward[key]
                end
                
                mapping_store.counters[pattern_name] = mapping_store.counters[pattern_name] + 1
                local counter = mapping_store.counters[pattern_name]
                local masked = string.format(replacement, counter)
                
                -- 매핑 저장
                store_mapping(match, masked, pattern_name)
                total_masked = total_masked + 1
                pattern_count = pattern_count + 1
                
                return masked
            end)
        end
        
        -- 통계 기록
        if pattern_count > 0 then
            pattern_stats[pattern_name] = pattern_count
            
            -- Critical 패턴 감지 시 경고
            if pattern_def.critical then
                security_log("warn", "Critical pattern masked", {
                    pattern = pattern_name,
                    count = pattern_count,
                    request_id = request_id
                })
            end
        end
    end
    
    -- 마스킹 완료 로그
    security_log("info", "Text masking completed", {
        request_id = request_id,
        total_masked = total_masked,
        patterns = pattern_stats,
        text_length = #text
    })
    
    return masked_text, {
        masked_count = total_masked,
        pattern_stats = pattern_stats,
        request_id = request_id
    }
end

-- 텍스트 언마스킹 함수
function text_masker.unmask_text(text)
    if not text or type(text) ~= "string" then
        return text
    end
    
    local unmasked_text = text
    local unmask_count = 0
    
    -- 역매핑 적용
    for masked, original in pairs(mapping_store.reverse) do
        local new_text, count = unmasked_text:gsub(masked, function()
            unmask_count = unmask_count + 1
            return original
        end)
        if count > 0 then
            unmasked_text = new_text
        end
    end
    
    security_log("debug", "Text unmasking completed", {
        unmask_count = unmask_count
    })
    
    return unmasked_text
end

-- Claude 요청 마스킹 (모든 필드 처리)
function text_masker.mask_claude_request(body, config)
    if not body or #body == 0 then
        return body, { masked_count = 0 }
    end
    
    -- JSON 파싱
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        security_log("error", "Failed to parse Claude request", { error = data })
        return body, { error = "Invalid JSON", masked_count = 0 }
    end
    
    local request_id = kong.request.get_header("X-Request-ID") or ngx.var.request_id
    local total_masked = 0
    local field_stats = {}
    
    -- 1. System 프롬프트 마스킹
    if data.system then
        local masked, context = text_masker.mask_text(data.system, request_id)
        if masked then
            data.system = masked
            total_masked = total_masked + (context.masked_count or 0)
            field_stats.system = context.masked_count or 0
        end
    end
    
    -- 2. Messages 배열 처리
    if data.messages then
        field_stats.messages = {}
        for i, message in ipairs(data.messages) do
            -- 문자열 content
            if type(message.content) == "string" then
                local masked, context = text_masker.mask_text(message.content, request_id)
                if masked then
                    message.content = masked
                    total_masked = total_masked + (context.masked_count or 0)
                    field_stats.messages[i] = context.masked_count or 0
                end
            -- 멀티모달 content 배열
            elseif type(message.content) == "table" then
                for j, content_item in ipairs(message.content) do
                    if content_item.type == "text" and content_item.text then
                        local masked, context = text_masker.mask_text(content_item.text, request_id)
                        if masked then
                            content_item.text = masked
                            total_masked = total_masked + (context.masked_count or 0)
                            field_stats.messages[i] = (field_stats.messages[i] or 0) + (context.masked_count or 0)
                        end
                    end
                end
            end
        end
    end
    
    -- 3. Tools 설명 (선택적)
    if data.tools then
        field_stats.tools = {}
        for i, tool in ipairs(data.tools) do
            if tool.description then
                local masked, context = text_masker.mask_text(tool.description, request_id)
                if masked then
                    tool.description = masked
                    total_masked = total_masked + (context.masked_count or 0)
                    field_stats.tools[i] = context.masked_count or 0
                end
            end
        end
    end
    
    -- 마스킹 완료 로그
    security_log("info", "Claude request masked", {
        request_id = request_id,
        total_masked = total_masked,
        field_stats = field_stats
    })
    
    -- JSON 인코딩
    local encoded_ok, encoded_body = pcall(cjson.encode, data)
    if not encoded_ok then
        security_log("error", "Failed to encode masked request", { error = encoded_body })
        return body, { error = "Encoding failed", masked_count = 0 }
    end
    
    return encoded_body, {
        masked_count = total_masked,
        field_stats = field_stats,
        request_id = request_id
    }
end

-- Claude 응답 언마스킹
function text_masker.unmask_claude_response(body, context)
    if not body or #body == 0 then
        return body
    end
    
    -- JSON 파싱
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        -- JSON이 아닌 경우 텍스트로 처리
        return text_masker.unmask_text(body)
    end
    
    -- content 배열 처리
    if data.content then
        for i, content_item in ipairs(data.content) do
            if content_item.type == "text" and content_item.text then
                content_item.text = text_masker.unmask_text(content_item.text)
            end
        end
    end
    
    -- 에러 메시지도 언마스킹
    if data.error and data.error.message then
        data.error.message = text_masker.unmask_text(data.error.message)
    end
    
    -- JSON 인코딩
    local encoded_ok, encoded_body = pcall(cjson.encode, data)
    if not encoded_ok then
        security_log("error", "Failed to encode unmasked response")
        return body
    end
    
    security_log("info", "Claude response unmasked", {
        request_id = context.request_id
    })
    
    return encoded_body
end

-- 보안 체크포인트
function text_masker.security_checkpoint(text)
    -- Critical 패턴이 남아있는지 확인
    for _, pattern_def in ipairs(aws_patterns) do
        if pattern_def.critical then
            if text:match(pattern_def.pattern) then
                security_log("crit", "SECURITY BREACH: Unmasked critical pattern detected!", {
                    pattern = pattern_def.name
                })
                return false, "Critical pattern not masked: " .. pattern_def.name
            end
        end
    end
    
    return true
end

-- 초기화
function text_masker.init()
    -- 패턴 우선순위 검증
    local priorities = {}
    for _, pattern in ipairs(aws_patterns) do
        if priorities[pattern.priority] then
            error("Duplicate priority detected: " .. pattern.priority)
        end
        priorities[pattern.priority] = true
    end
    
    -- Emergency handler 초기화
    emergency_handler:init()
    
    security_log("info", "Text masker v2 initialized", {
        version = text_masker.VERSION,
        patterns = #aws_patterns,
        max_mappings = text_masker.MAX_MAPPINGS
    })
end

return text_masker