# Claude API 마스킹 전략 - 공식 문서 기반

## 🎯 마스킹 대상 정리

### 1. 요청 (Request) 마스킹

#### 1.1 텍스트 필드 위치
```lua
-- 마스킹이 필요한 모든 텍스트 필드
local text_fields_to_mask = {
    -- 필수 마스킹
    "messages[*].content",           -- 문자열인 경우
    "messages[*].content[*].text",   -- 배열인 경우 (멀티모달)
    "system",                        -- 시스템 프롬프트
    
    -- 선택적 (도구 사용 시)
    "tools[*].description",          -- 도구 설명에 AWS 정보 포함 가능
    "tools[*].input_schema.properties[*].description"
}
```

#### 1.2 케이스별 처리 로직
```lua
function mask_claude_request(body)
    local data = cjson.decode(body)
    
    -- Case 1: system 프롬프트
    if data.system then
        data.system = mask_text(data.system)
    end
    
    -- Case 2: messages 배열
    if data.messages then
        for i, message in ipairs(data.messages) do
            -- Case 2-1: content가 문자열
            if type(message.content) == "string" then
                message.content = mask_text(message.content)
                
            -- Case 2-2: content가 배열 (멀티모달)
            elseif type(message.content) == "table" then
                for j, content_item in ipairs(message.content) do
                    if content_item.type == "text" and content_item.text then
                        content_item.text = mask_text(content_item.text)
                    end
                    -- 이미지는 건드리지 않음
                end
            end
        end
    end
    
    -- Case 3: tools (선택적)
    if data.tools then
        for i, tool in ipairs(data.tools) do
            if tool.description then
                tool.description = mask_text(tool.description)
            end
        end
    end
    
    return cjson.encode(data)
end
```

### 2. 응답 (Response) 언마스킹

#### 2.1 응답 구조 분석
```lua
function unmask_claude_response(body)
    local data = cjson.decode(body)
    
    -- content 배열 처리
    if data.content then
        for i, content_item in ipairs(data.content) do
            if content_item.type == "text" and content_item.text then
                content_item.text = unmask_text(content_item.text)
            end
            -- tool_use 타입은 별도 처리 필요
        end
    end
    
    -- 에러 메시지도 확인 (AWS 정보 포함 가능)
    if data.error and data.error.message then
        data.error.message = unmask_text(data.error.message)
    end
    
    return cjson.encode(data)
end
```

### 3. 패턴별 마스킹 방법

#### 3.1 단순 치환 패턴
```lua
-- EC2 Instance ID
"i-1234567890abcdef0" → "EC2_001"
"i-0987654321fedcba" → "EC2_002"

-- 복원 시 정확한 매칭 필요
"EC2_001" → "i-1234567890abcdef0"
```

#### 3.2 컨텍스트 보존 패턴
```lua
-- ARN 내부 Account ID
"arn:aws:iam::123456789012:role/MyRole" 
→ "arn:aws:iam::ACCOUNT_001:role/MyRole"

-- 구조 유지하면서 민감정보만 마스킹
```

#### 3.3 복합 텍스트 패턴
```lua
-- 원본
"Instance i-1234567890abcdef0 (IP: 10.0.1.100) in vpc-0987654321fedcba"

-- 마스킹 후
"Instance EC2_001 (IP: PRIVATE_IP_001) in VPC_001"

-- 언마스킹 시 정확한 순서와 매핑 유지 필요
```

### 4. 특수 케이스 처리

#### 4.1 대화 히스토리 처리
```lua
-- 이전 대화에서 마스킹된 내용이 다시 나타날 때
messages = [
    {role = "user", content = "Check instance i-1234567890abcdef0"},     -- EC2_001로 마스킹
    {role = "assistant", content = "Instance EC2_001 is running"},        -- 이미 마스킹됨
    {role = "user", content = "What about EC2_001's security group?"}    -- 사용자가 마스킹된 ID 사용
]

-- 일관성 유지 전략
function handle_conversation_context(messages, mapping_store)
    -- 전체 대화에서 동일한 매핑 사용
    local conversation_mappings = {}
    
    for _, message in ipairs(messages) do
        -- 이미 마스킹된 값 감지
        for masked, original in pairs(mapping_store) do
            if message.content:match(masked) then
                -- 이미 마스킹된 값은 그대로 유지
                conversation_mappings[masked] = original
            end
        end
    end
    
    return conversation_mappings
end
```

#### 4.2 스트리밍 응답 처리
```lua
-- 스트리밍 모드에서는 부분 텍스트 처리 필요
function handle_streaming_response(chunk, context)
    -- 버퍼링 필요 (완전한 패턴 매칭을 위해)
    context.buffer = context.buffer .. chunk
    
    -- 완전한 단어/패턴이 형성되었는지 확인
    local complete_patterns = extract_complete_patterns(context.buffer)
    
    -- 언마스킹 적용
    for _, pattern in ipairs(complete_patterns) do
        context.buffer = unmask_pattern(context.buffer, pattern)
    end
    
    -- 처리된 부분 반환
    return flush_processed_buffer(context)
end
```

### 5. 안전성 검증

#### 5.1 마스킹 완전성 검증
```lua
function verify_masking_completeness(original, masked)
    -- 알려진 AWS 패턴이 남아있는지 확인
    local aws_patterns = {
        "i%-[0-9a-f]{8,17}",      -- EC2
        "%d%d%d%d%d%d%d%d%d%d%d%d", -- 12자리 account
        "10%.%d+%.%d+%.%d+",      -- Private IP
        "arn:aws:[^%s]+",         -- ARN
    }
    
    for _, pattern in ipairs(aws_patterns) do
        if masked:match(pattern) then
            return false, "Unmasked pattern found: " .. pattern
        end
    end
    
    return true
end
```

#### 5.2 언마스킹 정확성 검증
```lua
function verify_unmasking_accuracy(original, final)
    -- 왕복 변환 후 동일한지 확인
    if original ~= final then
        -- 차이점 분석
        local diff = calculate_diff(original, final)
        log_error("Unmasking mismatch", {
            original_sample = original:sub(1, 100),
            final_sample = final:sub(1, 100),
            diff = diff
        })
        return false
    end
    return true
end
```

### 6. 성능 최적화

#### 6.1 캐싱 전략
```lua
-- 자주 사용되는 매핑은 LRU 캐시에 저장
local lru_cache = {
    max_size = 1000,
    cache = {},
    access_order = {}
}

function cached_mask_text(text)
    local cache_key = calculate_hash(text)
    
    if lru_cache.cache[cache_key] then
        -- 캐시 히트
        update_access_order(cache_key)
        return lru_cache.cache[cache_key]
    end
    
    -- 캐시 미스 - 실제 마스킹 수행
    local masked = mask_text(text)
    add_to_cache(cache_key, masked)
    
    return masked
end
```

#### 6.2 배치 처리
```lua
-- 여러 메시지를 한 번에 처리
function batch_mask_messages(messages)
    -- 모든 텍스트 수집
    local all_texts = collect_all_texts(messages)
    
    -- 중복 제거
    local unique_texts = deduplicate(all_texts)
    
    -- 일괄 마스킹
    local masked_map = {}
    for _, text in ipairs(unique_texts) do
        masked_map[text] = mask_text(text)
    end
    
    -- 결과 적용
    apply_masked_texts(messages, masked_map)
end
```

### 7. 모니터링 지표

```lua
-- 마스킹 성능 및 정확도 추적
local metrics = {
    -- 요청 처리
    request_masking_time = histogram("claude_request_masking_ms"),
    request_fields_masked = counter("claude_request_fields_masked_total"),
    
    -- 응답 처리
    response_unmasking_time = histogram("claude_response_unmasking_ms"),
    response_fields_unmasked = counter("claude_response_fields_unmasked_total"),
    
    -- 정확도
    masking_completeness = gauge("claude_masking_completeness_ratio"),
    unmasking_accuracy = gauge("claude_unmasking_accuracy_ratio"),
    
    -- 캐시 효율
    cache_hit_rate = gauge("claude_masking_cache_hit_ratio"),
    cache_size = gauge("claude_masking_cache_size_bytes")
}
```

## 결론

Claude API의 공식 문서 기반으로 분석한 결과:

1. **주요 마스킹 대상**:
   - `messages[].content` (문자열 또는 배열)
   - `system` 프롬프트
   - `content[].text` (멀티모달의 텍스트 부분)

2. **핵심 고려사항**:
   - 대화 히스토리 전체의 일관성 유지
   - 멀티모달 콘텐츠에서 텍스트만 선택적 처리
   - 스트리밍 응답 시 버퍼링 필요

3. **안전성 보장**:
   - 마스킹 완전성 검증 필수
   - 언마스킹 정확성 100% 보장
   - 성능과 보안의 균형 유지