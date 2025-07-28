-- Redis Optimization Script for Kong AWS Masker
-- This script optimizes Redis operations for high-performance masking/unmasking

-- Namespace for AWS masking mappings
local MASKING_PREFIX = "aws:mask:"
local UNMASK_PREFIX = "aws:unmask:"
local STATS_PREFIX = "aws:stats:"

-- Batch operations for performance
local function batch_set_mappings(mappings)
    local pipeline = {}
    for original, masked in pairs(mappings) do
        -- Store bidirectional mapping
        table.insert(pipeline, {"SET", MASKING_PREFIX .. original, masked, "EX", 86400})
        table.insert(pipeline, {"SET", UNMASK_PREFIX .. masked, original, "EX", 86400})
        -- Update statistics
        table.insert(pipeline, {"HINCRBY", STATS_PREFIX .. "counts", "total_mappings", 1})
    end
    return pipeline
end

-- Efficient batch retrieval
local function batch_get_mappings(keys, prefix)
    local pipeline = {}
    for _, key in ipairs(keys) do
        table.insert(pipeline, {"GET", prefix .. key})
    end
    return pipeline
end

-- Clean expired mappings
local function cleanup_expired_mappings()
    -- Use Redis SCAN to avoid blocking
    local cursor = "0"
    local count = 0
    repeat
        local result = redis.call("SCAN", cursor, "MATCH", MASKING_PREFIX .. "*", "COUNT", 100)
        cursor = result[1]
        local keys = result[2]
        
        for _, key in ipairs(keys) do
            -- Check TTL and remove if expired
            local ttl = redis.call("TTL", key)
            if ttl == -2 or ttl == -1 then
                redis.call("DEL", key)
                -- Also remove the reverse mapping
                local masked = redis.call("GET", key)
                if masked then
                    redis.call("DEL", UNMASK_PREFIX .. masked)
                end
                count = count + 1
            end
        end
    until cursor == "0"
    
    return count
end

-- Performance monitoring
local function get_performance_stats()
    local stats = {}
    stats.total_mappings = redis.call("HGET", STATS_PREFIX .. "counts", "total_mappings") or 0
    stats.memory_usage = redis.call("INFO", "memory")
    stats.connected_clients = redis.call("CLIENT", "LIST")
    stats.slow_queries = redis.call("SLOWLOG", "GET", 10)
    return stats
end

-- Export functions for Kong plugin use
return {
    batch_set_mappings = batch_set_mappings,
    batch_get_mappings = batch_get_mappings,
    cleanup_expired_mappings = cleanup_expired_mappings,
    get_performance_stats = get_performance_stats,
    MASKING_PREFIX = MASKING_PREFIX,
    UNMASK_PREFIX = UNMASK_PREFIX,
    STATS_PREFIX = STATS_PREFIX
}