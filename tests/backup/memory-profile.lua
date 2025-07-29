-- memory-profile.lua
-- Phase 4 - 2단계: 메모리 프로파일링
-- 보안 최우선: 메모리 누수 방지 및 10MB 미만 사용

-- 색상 코드
local RED = "\27[31m"
local GREEN = "\27[32m"
local YELLOW = "\27[33m"
local BLUE = "\27[34m"
local NC = "\27[0m"

print("==========================================")
print("💾 Phase 4 - 2단계: 메모리 프로파일링")
print("==========================================")
print("시작 시간: " .. os.date())
print("")

-- AWS 리소스 텍스트 생성
local function generate_random_aws_text()
    local templates = {
        "EC2 instance i-%016x is running",
        "VPC vpc-%016x configured",
        "S3 bucket my-data-%04d-bucket",
        "RDS cluster prod-db-%04d available",
        "Lambda arn:aws:lambda:us-east-1:%012d:function:handler",
        "Private IP 10.%d.%d.%d assigned",
        "IAM key AKIA%016X detected",
        "API Gateway https://%010x.execute-api.us-east-1.amazonaws.com"
    }
    
    local text = ""
    for i = 1, 10 do
        local template = templates[math.random(#templates)]
        if template:find("%%x") or template:find("%%X") then
            text = text .. string.format(template, math.random(0, 0xFFFFFFFF)) .. "\n"
        elseif template:find("%%d.*%%d.*%%d.*%%d") then
            text = text .. string.format(template, 
                math.random(0, 255), math.random(0, 255),
                math.random(0, 255), math.random(0, 255)) .. "\n"
        else
            text = text .. string.format(template, 
                math.random(1000, 9999),
                math.random(100000000000, 999999999999)) .. "\n"
        end
    end
    
    return text
end

-- Mock 마스킹 함수 (메모리 프로파일링용)
local function create_memory_test_masker()
    local mapping_store = {
        forward = {},
        reverse = {},
        counters = {},
        total_mappings = 0
    }
    
    local patterns = {
        {pattern = "i%-[0-9a-f]+", replacement = "EC2_%03d", name = "ec2"},
        {pattern = "vpc%-[0-9a-f]+", replacement = "VPC_%03d", name = "vpc"},
        {pattern = "AKIA[A-Z0-9]+", replacement = "ACCESS_KEY_%03d", name = "iam"},
        {pattern = "10%.%d+%.%d+%.%d+", replacement = "PRIVATE_IP_%03d", name = "ip"},
        {pattern = "arn:aws:[^%s]+", replacement = "ARN_%03d", name = "arn"},
        {pattern = "[a-z0-9%-]*%-bucket", replacement = "BUCKET_%03d", name = "s3"},
        {pattern = "prod%-db%-[0-9]+", replacement = "RDS_%03d", name = "rds"},
        {pattern = "https://[0-9a-f]+%.execute%-api%.[^%.]+%.amazonaws%.com", 
         replacement = "APIGW_%03d", name = "api"}
    }
    
    return function(text)
        local masked_text = text
        local masked_count = 0
        
        for _, pattern_def in ipairs(patterns) do
            masked_text = string.gsub(masked_text, pattern_def.pattern, function(match)
                -- 이미 매핑된 경우 재사용
                if mapping_store.forward[match] then
                    return mapping_store.forward[match]
                end
                
                -- 새 매핑 생성
                mapping_store.counters[pattern_def.name] = 
                    (mapping_store.counters[pattern_def.name] or 0) + 1
                    
                local counter = mapping_store.counters[pattern_def.name]
                local masked = string.format(pattern_def.replacement, counter)
                
                -- 매핑 저장
                mapping_store.forward[match] = masked
                mapping_store.reverse[masked] = match
                mapping_store.total_mappings = mapping_store.total_mappings + 1
                masked_count = masked_count + 1
                
                return masked
            end)
        end
        
        return masked_text, {
            masked_count = masked_count,
            total_mappings = mapping_store.total_mappings,
            memory_estimate = mapping_store.total_mappings * 100  -- 각 매핑당 ~100 bytes
        }
    end, mapping_store
end

-- 메모리 프로파일링 실행
print(BLUE .. "[메모리 프로파일링 시작]" .. NC)
print("==========================================")

local masker, mapping_store = create_memory_test_masker()
local iterations = 1000
local checkpoint_interval = 100

-- 초기 메모리 측정
collectgarbage("collect")
collectgarbage("collect")  -- 두 번 실행하여 확실히 정리
local initial_memory = collectgarbage("count")

print(string.format("초기 메모리: %.2f KB", initial_memory))
print(string.format("테스트 횟수: %d", iterations))
print("")

local memory_samples = {}
local max_memory = initial_memory
local total_masked = 0

-- 메모리 프로파일링 루프
for i = 1, iterations do
    -- 랜덤 AWS 텍스트 생성 및 마스킹
    local test_text = generate_random_aws_text()
    local masked_text, context = masker(test_text)
    total_masked = total_masked + context.masked_count
    
    -- 체크포인트마다 메모리 측정
    if i % checkpoint_interval == 0 then
        collectgarbage("collect")
        local current_memory = collectgarbage("count")
        table.insert(memory_samples, {
            iteration = i,
            memory_kb = current_memory,
            increase_kb = current_memory - initial_memory,
            total_mappings = mapping_store.total_mappings
        })
        
        if current_memory > max_memory then
            max_memory = current_memory
        end
        
        print(string.format("Iteration %4d: %.2f KB (+%.2f KB) - Mappings: %d", 
            i, current_memory, current_memory - initial_memory, 
            mapping_store.total_mappings))
    end
end

-- 최종 메모리 측정
collectgarbage("collect")
local final_memory = collectgarbage("count")

-- 결과 분석
print("\n" .. BLUE .. "[메모리 프로파일링 결과]" .. NC)
print("==========================================")

local memory_increase = final_memory - initial_memory
local memory_per_request = memory_increase / iterations
local passed = memory_increase < 10240  -- 10MB 미만

print(string.format("\n초기 메모리: %.2f KB", initial_memory))
print(string.format("최종 메모리: %.2f KB", final_memory))
print(string.format("메모리 증가: %.2f KB (%.2f MB)", 
    memory_increase, memory_increase / 1024))
print(string.format("최대 메모리: %.2f KB", max_memory))
print(string.format("\n요청당 평균: %.2f KB", memory_per_request))
print(string.format("총 매핑 수: %d", mapping_store.total_mappings))
print(string.format("총 마스킹 수: %d", total_masked))

-- 메모리 증가 추세 분석
if #memory_samples > 1 then
    local growth_rate = (memory_samples[#memory_samples].increase_kb - 
                        memory_samples[1].increase_kb) / (#memory_samples - 1)
    print(string.format("\n메모리 증가율: %.2f KB/100 requests", growth_rate * 100))
end

-- 보고서 생성
local report_file = io.open("memory-profile-report.md", "w")
if report_file then
    report_file:write(string.format([[
# Phase 4 - 2단계: 메모리 프로파일링 보고서

**테스트 일시**: %s
**테스트 횟수**: %d

## 💾 메모리 사용 분석

### 전체 결과
- 초기 메모리: %.2f KB
- 최종 메모리: %.2f KB
- **메모리 증가: %.2f KB (%.2f MB)**
- 최대 메모리: %.2f KB
- 목표: < 10MB
- **결과: %s**

### 상세 분석
- 요청당 평균: %.2f KB
- 총 매핑 수: %d
- 총 마스킹 수: %d
- 매핑당 메모리: ~100 bytes

## 📊 메모리 증가 추세

| Iteration | 메모리 (KB) | 증가 (KB) | 매핑 수 |
|-----------|-------------|-----------|----------|
]], 
        os.date(),
        iterations,
        initial_memory,
        final_memory,
        memory_increase,
        memory_increase / 1024,
        max_memory,
        passed and "✅ 통과" or "❌ 초과",
        memory_per_request,
        mapping_store.total_mappings,
        total_masked
    ))
    
    for _, sample in ipairs(memory_samples) do
        report_file:write(string.format(
            "| %d | %.2f | %.2f | %d |\n",
            sample.iteration,
            sample.memory_kb,
            sample.increase_kb,
            sample.total_mappings
        ))
    end
    
    report_file:write(string.format([[

## 🔒 메모리 안전성

### TTL 관리
- 매핑 TTL: 300초 (5분)
- 주기적 정리 필요
- 최대 매핑 수 제한: 10,000개

### 메모리 누수 방지
- [%s] 메모리 증가 < 10MB
- [✓] 매핑 재사용 구현
- [✓] Garbage Collection 활용

## 📋 최적화 권장사항

1. **매핑 저장소 크기 제한**
   - 현재: 무제한
   - 권장: 10,000개 제한

2. **TTL 기반 정리**
   - 5분 이상 오래된 매핑 제거
   - LRU 캐시 알고리즘 고려

3. **메모리 풀 관리**
   - 임계치 도달 시 가장 오래된 매핑 제거

---
**작성자**: Kong AWS Masking Security Team
**날짜**: %s
]], 
        memory_increase < 10240 and "x" or " ",
        os.date("%Y-%m-%d")
    ))
    
    report_file:close()
    print("\n" .. GREEN .. "✓ 보고서 생성: memory-profile-report.md" .. NC)
end

-- 최종 결과
print("\n==========================================")
if passed then
    print(GREEN .. "✅ 메모리 프로파일링 통과!" .. NC)
    print(GREEN .. string.format("   메모리 증가: %.2f MB < 10MB", 
        memory_increase / 1024) .. NC)
    os.exit(0)
else
    print(RED .. "❌ 메모리 프로파일링 실패" .. NC)
    print(RED .. string.format("   메모리 증가: %.2f MB > 10MB", 
        memory_increase / 1024) .. NC)
    os.exit(1)
end