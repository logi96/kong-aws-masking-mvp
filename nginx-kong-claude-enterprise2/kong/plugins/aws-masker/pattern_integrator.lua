-- pattern_integrator.lua
-- Phase 3: 기존 패턴과 확장 패턴 통합
-- 보안 최우선: 모든 패턴의 안전한 통합 및 우선순위 관리

local pattern_integrator = {
    VERSION = "1.0.0",
    -- 통합된 패턴 저장소
    integrated_patterns = {},
    -- 패턴 충돌 검사 결과
    conflicts = {},
    -- 통계
    stats = {
        original_count = 0,
        extension_count = 0,
        total_count = 0,
        conflict_count = 0
    }
}

local patterns_extension = require "kong.plugins.aws-masker.patterns_extension"

-- 패턴 우선순위 재조정
local function adjust_priorities(patterns, start_priority)
    local adjusted = {}
    local current_priority = start_priority
    
    for _, pattern in ipairs(patterns) do
        local new_pattern = {}
        for k, v in pairs(pattern) do
            new_pattern[k] = v
        end
        new_pattern.priority = current_priority
        current_priority = current_priority + 1
        table.insert(adjusted, new_pattern)
    end
    
    return adjusted, current_priority
end

-- 패턴 충돌 검사
function pattern_integrator.check_conflicts(pattern1, pattern2)
    -- 같은 이름 검사
    if pattern1.name == pattern2.name then
        return true, "duplicate_name"
    end
    
    -- 우선순위 충돌 검사
    if pattern1.priority == pattern2.priority then
        return true, "priority_conflict"
    end
    
    -- 패턴 중복 검사 (간단한 버전)
    if pattern1.pattern == pattern2.pattern then
        return true, "duplicate_pattern"
    end
    
    return false
end

-- 기존 패턴과 확장 패턴 통합
function pattern_integrator.integrate_patterns(original_patterns)
    local integrated = {}
    local conflicts = {}
    
    -- 원본 패턴 복사
    for _, pattern in ipairs(original_patterns) do
        table.insert(integrated, pattern)
    end
    pattern_integrator.stats.original_count = #original_patterns
    
    -- 확장 패턴 가져오기
    local extension_patterns = patterns_extension.get_all_patterns()
    pattern_integrator.stats.extension_count = #extension_patterns
    
    -- 우선순위 조정 (기존 패턴의 최대 우선순위 찾기)
    local max_priority = 0
    for _, pattern in ipairs(original_patterns) do
        if pattern.priority > max_priority then
            max_priority = pattern.priority
        end
    end
    
    -- 확장 패턴 우선순위 재조정
    local adjusted_extensions = adjust_priorities(extension_patterns, max_priority + 1)
    
    -- 충돌 검사 및 통합
    for _, ext_pattern in ipairs(adjusted_extensions) do
        local has_conflict = false
        
        -- 기존 패턴과 충돌 검사
        for _, orig_pattern in ipairs(original_patterns) do
            local conflict, reason = pattern_integrator.check_conflicts(orig_pattern, ext_pattern)
            if conflict then
                table.insert(conflicts, {
                    original = orig_pattern.name,
                    extension = ext_pattern.name,
                    reason = reason
                })
                has_conflict = true
                pattern_integrator.stats.conflict_count = pattern_integrator.stats.conflict_count + 1
                break
            end
        end
        
        -- 충돌이 없으면 추가
        if not has_conflict then
            table.insert(integrated, ext_pattern)
        else
            kong.log.warn("[PATTERN-INTEGRATOR] Pattern conflict detected", {
                pattern = ext_pattern.name,
                conflicts = conflicts
            })
        end
    end
    
    -- 우선순위로 정렬
    table.sort(integrated, function(a, b) return a.priority < b.priority end)
    
    pattern_integrator.integrated_patterns = integrated
    pattern_integrator.conflicts = conflicts
    pattern_integrator.stats.total_count = #integrated
    
    kong.log.info("[PATTERN-INTEGRATOR] Integration completed", {
        stats = pattern_integrator.stats
    })
    
    return integrated, conflicts
end

-- 패턴 검증
function pattern_integrator.validate_patterns(patterns)
    local validation_results = {
        valid = true,
        errors = {},
        warnings = {}
    }
    
    local seen_names = {}
    local seen_priorities = {}
    
    for i, pattern in ipairs(patterns) do
        -- 필수 필드 검사
        if not pattern.name then
            table.insert(validation_results.errors, "Pattern at index " .. i .. " missing name")
            validation_results.valid = false
        end
        
        if not pattern.pattern then
            table.insert(validation_results.errors, "Pattern " .. (pattern.name or i) .. " missing pattern")
            validation_results.valid = false
        end
        
        if not pattern.replacement then
            table.insert(validation_results.errors, "Pattern " .. (pattern.name or i) .. " missing replacement")
            validation_results.valid = false
        end
        
        if not pattern.priority then
            table.insert(validation_results.errors, "Pattern " .. (pattern.name or i) .. " missing priority")
            validation_results.valid = false
        end
        
        -- 중복 검사
        if pattern.name and seen_names[pattern.name] then
            table.insert(validation_results.errors, "Duplicate pattern name: " .. pattern.name)
            validation_results.valid = false
        else
            seen_names[pattern.name] = true
        end
        
        if pattern.priority and seen_priorities[pattern.priority] then
            table.insert(validation_results.warnings, "Duplicate priority " .. pattern.priority .. " for " .. (pattern.name or i))
        else
            seen_priorities[pattern.priority] = true
        end
        
        -- Critical 패턴 검증
        if pattern.critical then
            table.insert(validation_results.warnings, "Critical pattern: " .. pattern.name)
        end
    end
    
    return validation_results
end

-- 통합된 패턴 내보내기
function pattern_integrator.export_patterns()
    return pattern_integrator.integrated_patterns
end

-- 통계 조회
function pattern_integrator.get_stats()
    local extension_stats = patterns_extension.get_stats()
    
    return {
        integration = pattern_integrator.stats,
        extension = extension_stats,
        conflicts = pattern_integrator.conflicts
    }
end

-- 특정 카테고리의 패턴만 가져오기
function pattern_integrator.get_patterns_by_category(category)
    local patterns = {}
    
    if patterns_extension[category .. "_patterns"] then
        patterns = patterns_extension[category .. "_patterns"]
    end
    
    return patterns
end

-- 초기화
function pattern_integrator.init()
    kong.log.info("[PATTERN-INTEGRATOR] Initialized", {
        version = pattern_integrator.VERSION,
        extension_patterns = patterns_extension.get_stats().total_patterns
    })
end

return pattern_integrator