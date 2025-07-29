-- Redis Integration Module for AWS Masker Plugin
-- Optimized for high-performance masking/unmasking operations

local redis = require "resty.redis"
local cjson = require "cjson.safe"
local ngx = ngx

local _M = {}
local mt = { __index = _M }

-- Redis connection pool configuration
local POOL_SIZE = 100
local KEEPALIVE_TIMEOUT = 60000  -- 60 seconds
local CONNECTION_TIMEOUT = 2000   -- 2 seconds

-- Namespaces
local MASKING_PREFIX = "aws:mask:"
local UNMASK_PREFIX = "aws:unmask:"
local STATS_PREFIX = "aws:stats:"
local LOCK_PREFIX = "aws:lock:"

-- Initialize Redis integration
function _M.new(config)
    local self = {
        host = config.redis_host or "redis",
        port = config.redis_port or 6379,
        password = config.redis_password,
        database = config.redis_database or 0,
        timeout = config.redis_timeout or CONNECTION_TIMEOUT,
        pool_size = config.redis_keepalive_pool_size or POOL_SIZE,
        keepalive_timeout = config.redis_keepalive_timeout or KEEPALIVE_TIMEOUT
    }
    return setmetatable(self, mt)
end

-- Get Redis connection from pool
function _M:get_connection()
    local red = redis:new()
    red:set_timeouts(self.timeout, self.timeout, self.timeout)
    
    local ok, err = red:connect(self.host, self.port)
    if not ok then
        return nil, "Failed to connect to Redis: " .. (err or "unknown error")
    end
    
    -- Authenticate if password is set
    if self.password and self.password ~= "" then
        local ok, err = red:auth(self.password)
        if not ok then
            return nil, "Redis authentication failed: " .. (err or "unknown error")
        end
    end
    
    -- Select database
    local ok, err = red:select(self.database)
    if not ok then
        return nil, "Failed to select Redis database: " .. (err or "unknown error")
    end
    
    return red, nil
end

-- Return connection to pool
function _M:return_connection(red)
    if not red then
        return
    end
    
    -- Put connection back to pool
    local ok, err = red:set_keepalive(self.keepalive_timeout, self.pool_size)
    if not ok then
        ngx.log(ngx.WARN, "Failed to set Redis keepalive: ", err)
    end
end

-- Store mapping with automatic expiration
function _M:store_mapping(original, masked, ttl)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    -- Use pipeline for atomic operations
    red:init_pipeline()
    
    -- Store bidirectional mapping
    red:setex(MASKING_PREFIX .. original, ttl or 86400, masked)
    red:setex(UNMASK_PREFIX .. masked, ttl or 86400, original)
    
    -- Update statistics
    red:hincrby(STATS_PREFIX .. "counts", "total_mappings", 1)
    red:hincrby(STATS_PREFIX .. "counts:" .. os.date("%Y%m%d"), "daily_mappings", 1)
    
    local results, err = red:commit_pipeline()
    self:return_connection(red)
    
    if not results then
        return nil, "Failed to store mapping: " .. (err or "unknown error")
    end
    
    return true, nil
end

-- Batch store multiple mappings
function _M:batch_store_mappings(mappings, ttl)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    red:init_pipeline()
    
    local count = 0
    for original, masked in pairs(mappings) do
        red:setex(MASKING_PREFIX .. original, ttl or 86400, masked)
        red:setex(UNMASK_PREFIX .. masked, ttl or 86400, original)
        count = count + 1
    end
    
    red:hincrby(STATS_PREFIX .. "counts", "total_mappings", count)
    red:hincrby(STATS_PREFIX .. "counts:" .. os.date("%Y%m%d"), "daily_mappings", count)
    
    local results, err = red:commit_pipeline()
    self:return_connection(red)
    
    if not results then
        return nil, "Failed to store batch mappings: " .. (err or "unknown error")
    end
    
    return count, nil
end

-- Get masked value for original
function _M:get_masked(original)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    local masked, err = red:get(MASKING_PREFIX .. original)
    self:return_connection(red)
    
    if not masked or masked == ngx.null then
        return nil, nil
    end
    
    return masked, nil
end

-- Get original value from masked
function _M:get_original(masked)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    local original, err = red:get(UNMASK_PREFIX .. masked)
    self:return_connection(red)
    
    if not original or original == ngx.null then
        return nil, nil
    end
    
    return original, nil
end

-- Batch get multiple mappings
function _M:batch_get_mappings(keys, is_unmask)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    red:init_pipeline()
    
    local prefix = is_unmask and UNMASK_PREFIX or MASKING_PREFIX
    for _, key in ipairs(keys) do
        red:get(prefix .. key)
    end
    
    local results, err = red:commit_pipeline()
    self:return_connection(red)
    
    if not results then
        return nil, "Failed to get batch mappings: " .. (err or "unknown error")
    end
    
    -- Convert results to table
    local mappings = {}
    for i, key in ipairs(keys) do
        local value = results[i]
        if value and value ~= ngx.null then
            mappings[key] = value
        end
    end
    
    return mappings, nil
end

-- Distributed lock for concurrent operations
function _M:acquire_lock(resource, timeout)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    local lock_key = LOCK_PREFIX .. resource
    local lock_value = ngx.worker.id() .. ":" .. ngx.now()
    
    -- Try to acquire lock with timeout
    local ok, err = red:set(lock_key, lock_value, "NX", "EX", timeout or 5)
    self:return_connection(red)
    
    if ok == "OK" then
        return lock_value, nil
    end
    
    return nil, "Failed to acquire lock"
end

-- Release distributed lock
function _M:release_lock(resource, lock_value)
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    local lock_key = LOCK_PREFIX .. resource
    
    -- Use Lua script for atomic check and delete
    local script = [[
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
        else
            return 0
        end
    ]]
    
    local ok, err = red:eval(script, 1, lock_key, lock_value)
    self:return_connection(red)
    
    return ok == 1, err
end

-- Get performance statistics
function _M:get_stats()
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    red:init_pipeline()
    
    -- Get various statistics
    red:hgetall(STATS_PREFIX .. "counts")
    red:hgetall(STATS_PREFIX .. "counts:" .. os.date("%Y%m%d"))
    red:dbsize()
    red:info("memory")
    red:info("stats")
    
    local results, err = red:commit_pipeline()
    self:return_connection(red)
    
    if not results then
        return nil, "Failed to get statistics: " .. (err or "unknown error")
    end
    
    -- Parse results
    local stats = {
        total_counts = results[1] or {},
        daily_counts = results[2] or {},
        total_keys = results[3] or 0,
        memory_info = results[4] or "",
        stats_info = results[5] or ""
    }
    
    return stats, nil
end

-- Health check
function _M:health_check()
    local red, err = self:get_connection()
    if not red then
        return false, err
    end
    
    -- Ping Redis
    local ok, err = red:ping()
    self:return_connection(red)
    
    if not ok or ok == ngx.null then
        return false, "Redis ping failed: " .. (err or "no response")
    end
    
    return true, nil
end

-- Cleanup expired mappings (called periodically)
function _M:cleanup_expired()
    local red, err = self:get_connection()
    if not red then
        return nil, err
    end
    
    -- Use SCAN to find expired keys without blocking
    local cursor = "0"
    local cleaned = 0
    
    repeat
        local res, err = red:scan(cursor, "MATCH", MASKING_PREFIX .. "*", "COUNT", 100)
        if not res then
            self:return_connection(red)
            return nil, "Scan failed: " .. (err or "unknown error")
        end
        
        cursor = res[1]
        local keys = res[2]
        
        if #keys > 0 then
            red:init_pipeline()
            
            for _, key in ipairs(keys) do
                red:ttl(key)
            end
            
            local ttls = red:commit_pipeline()
            
            -- Delete keys with no TTL or negative TTL
            local to_delete = {}
            for i, ttl in ipairs(ttls or {}) do
                if ttl == -1 or ttl == -2 then
                    table.insert(to_delete, keys[i])
                end
            end
            
            if #to_delete > 0 then
                local deleted = red:del(unpack(to_delete))
                cleaned = cleaned + (deleted or 0)
            end
        end
    until cursor == "0"
    
    self:return_connection(red)
    return cleaned, nil
end

return _M