-- Redis Integration Module for AWS Masker Plugin
-- Optimized for high-performance masking/unmasking operations
-- Enhanced with ElastiCache support for SSL/TLS, IAM auth, and cluster mode

local redis = require "resty.redis"
local cjson = require "cjson.safe"
local ssl = require "ngx.ssl"
local ngx = ngx

local _M = {}
local mt = { __index = _M }

-- Redis connection pool configuration
local POOL_SIZE = 100
local KEEPALIVE_TIMEOUT = 60000  -- 60 seconds
local CONNECTION_TIMEOUT = 2000   -- 2 seconds
local SSL_HANDSHAKE_TIMEOUT = 5000 -- 5 seconds for SSL handshake

-- ElastiCache SSL/TLS configuration constants
local DEFAULT_SSL_PROTOCOLS = "TLSv1.2 TLSv1.3"
local PREFERRED_CIPHERS = "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS"

-- Namespaces
local MASKING_PREFIX = "aws:mask:"
local UNMASK_PREFIX = "aws:unmask:"
local STATS_PREFIX = "aws:stats:"
local LOCK_PREFIX = "aws:lock:"

-- Initialize Redis integration with ElastiCache support
function _M.new(config)
    local self = {
        host = config.redis_host or "redis",
        port = config.redis_port or 6379,
        password = config.redis_password,
        database = config.redis_database or 0,
        timeout = config.redis_timeout or CONNECTION_TIMEOUT,
        pool_size = config.redis_keepalive_pool_size or POOL_SIZE,
        keepalive_timeout = config.redis_keepalive_timeout or KEEPALIVE_TIMEOUT,
        -- ElastiCache specific configuration
        redis_type = config.redis_type or "traditional",
        ssl_enabled = config.redis_ssl_enabled,
        ssl_verify = config.redis_ssl_verify ~= false, -- default true
        auth_token = config.redis_auth_token,
        username = config.redis_user,
        cluster_mode = config.redis_cluster_mode,
        cluster_endpoint = config.redis_cluster_endpoint
    }
    return setmetatable(self, mt)
end

-- Get Redis connection from pool with ElastiCache support
function _M:get_connection()
    if self.redis_type == "managed" then
        return self:get_elasticache_connection()
    else
        return self:get_traditional_connection()
    end
end

-- Get traditional Redis connection (existing logic)
function _M:get_traditional_connection()
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

-- Get ElastiCache connection with SSL/TLS and authentication
function _M:get_elasticache_connection()
    local red = redis:new()
    
    -- Set timeouts with additional time for SSL handshake
    local connect_timeout = self.ssl_enabled and SSL_HANDSHAKE_TIMEOUT or self.timeout
    red:set_timeouts(connect_timeout, self.timeout, self.timeout)
    
    local ok, err
    
    -- Connect with SSL/TLS if enabled
    if self.ssl_enabled then
        ok, err = self:connect_with_ssl(red)
    else
        ok, err = red:connect(self.host, self.port)
    end
    
    if not ok then
        return nil, "ElastiCache connection failed: " .. (err or "unknown error")
    end
    
    -- ElastiCache authentication
    if self.auth_token and self.auth_token ~= "" then
        ok, err = self:authenticate_elasticache(red)
        if not ok then
            red:close()
            return nil, "ElastiCache authentication failed: " .. (err or "unknown error")
        end
    end
    
    -- Select database (if not in cluster mode)
    if not self.cluster_mode then
        local ok, err = red:select(self.database)
        if not ok then
            red:close()
            return nil, "Failed to select ElastiCache database: " .. (err or "unknown error")
        end
    end
    
    return red, nil
end

-- Connect to ElastiCache with SSL/TLS
function _M:connect_with_ssl(red)
    -- Prepare SSL options
    local ssl_opts = {
        verify = self.ssl_verify,
        server_name = self.host, -- SNI support
        protocols = DEFAULT_SSL_PROTOCOLS,
        ciphers = PREFERRED_CIPHERS,
        depth = 2, -- Certificate chain depth
        handshake_timeout = SSL_HANDSHAKE_TIMEOUT
    }
    
    -- Log SSL connection attempt
    ngx.log(ngx.INFO, "[ElastiCache] Attempting SSL connection to ", self.host, ":", self.port)
    
    -- Connect with SSL
    local ok, err = red:connect(self.host, self.port, ssl_opts)
    if not ok then
        ngx.log(ngx.ERR, "[ElastiCache] SSL connection failed: ", err or "unknown error")
        return nil, err
    end
    
    ngx.log(ngx.INFO, "[ElastiCache] SSL connection established successfully")
    return true, nil
end

-- Authenticate with ElastiCache using IAM tokens or username/password
function _M:authenticate_elasticache(red)
    local auth_cmd
    
    if self.username and self.username ~= "" then
        -- RBAC authentication with username and auth token
        auth_cmd = {"AUTH", self.username, self.auth_token}
        ngx.log(ngx.INFO, "[ElastiCache] Authenticating with username: ", self.username)
    else
        -- Simple auth token authentication  
        auth_cmd = {"AUTH", self.auth_token}
        ngx.log(ngx.INFO, "[ElastiCache] Authenticating with auth token")
    end
    
    local ok, err = red:auth(unpack(auth_cmd))
    if not ok then
        ngx.log(ngx.ERR, "[ElastiCache] Authentication failed: ", err or "unknown error")
        return nil, err
    end
    
    ngx.log(ngx.INFO, "[ElastiCache] Authentication successful")
    return true, nil
end

-- ElastiCache cluster mode discovery and connection
function _M:discover_cluster_nodes()
    if not self.cluster_mode or not self.cluster_endpoint then
        return nil, "Cluster mode not enabled or no cluster endpoint provided"
    end
    
    -- Create a temporary connection to the cluster endpoint for discovery
    local red = redis:new()
    red:set_timeouts(self.timeout, self.timeout, self.timeout)
    
    local ok, err
    if self.ssl_enabled then
        ok, err = self:connect_with_ssl(red)
    else
        ok, err = red:connect(self.cluster_endpoint, self.port)
    end
    
    if not ok then
        return nil, "Failed to connect to cluster endpoint: " .. (err or "unknown error")
    end
    
    -- Authenticate for cluster discovery
    if self.auth_token and self.auth_token ~= "" then
        ok, err = self:authenticate_elasticache(red)
        if not ok then
            red:close()
            return nil, "Cluster discovery authentication failed: " .. (err or "unknown error")
        end
    end
    
    -- Get cluster nodes information
    local nodes_info, err = red:cluster("nodes")
    red:close()
    
    if not nodes_info then
        return nil, "Failed to get cluster nodes: " .. (err or "unknown error")
    end
    
    -- Parse cluster nodes (simplified - in production would need full parsing)
    local nodes = {}
    for line in string.gmatch(nodes_info, "[^\r\n]+") do
        -- Extract node endpoint from cluster nodes output
        local host, port = string.match(line, "(%S+):(%d+)")
        if host and port then
            table.insert(nodes, {host = host, port = tonumber(port)})
        end
    end
    
    if #nodes == 0 then
        return nil, "No cluster nodes discovered"
    end
    
    ngx.log(ngx.INFO, "[ElastiCache] Discovered ", #nodes, " cluster nodes")
    return nodes, nil
end

-- Validate ElastiCache connection configuration
function _M:validate_elasticache_config()
    if self.redis_type ~= "managed" then
        return true, nil -- Not ElastiCache, skip validation
    end
    
    -- Validate SSL configuration
    if self.ssl_enabled then
        -- Check if ngx.ssl is available
        local ssl_available = pcall(require, "ngx.ssl")
        if not ssl_available then
            return false, "SSL/TLS support not available in this OpenResty build"
        end
        
        -- Validate SSL verify setting
        if self.ssl_verify and not self.host then
            return false, "Host must be specified for SSL certificate verification"
        end
    end
    
    -- Validate cluster configuration
    if self.cluster_mode and not self.cluster_endpoint then
        return false, "Cluster endpoint required when cluster mode is enabled"
    end
    
    if self.cluster_endpoint and not self.cluster_mode then
        return false, "Cluster mode must be enabled when cluster endpoint is provided"
    end
    
    -- Validate authentication configuration
    if self.username and not self.auth_token then
        return false, "Auth token required when username is specified for RBAC"
    end
    
    -- Validate auth token format (basic validation)
    if self.auth_token then
        if string.len(self.auth_token) < 8 then
            return false, "Auth token appears to be too short (minimum 8 characters)"
        end
        
        -- Check for obvious test/dummy tokens
        local dummy_tokens = {"password", "123456", "test", "admin", "redis"}
        for _, dummy in ipairs(dummy_tokens) do
            if string.lower(self.auth_token) == dummy then
                return false, "Auth token appears to be a dummy/test value: " .. dummy
            end
        end
    end
    
    return true, nil
end

-- Enhanced connection health check for ElastiCache
function _M:elasticache_health_check()
    local red, err = self:get_connection()
    if not red then
        return false, "Connection failed: " .. (err or "unknown error")
    end
    
    -- Test basic connectivity
    local ok, err = red:ping()
    if not ok or ok == ngx.null then
        self:return_connection(red)
        return false, "Ping failed: " .. (err or "no response")
    end
    
    -- Test authentication if configured
    if self.auth_token then
        -- Try a simple operation that requires auth
        local info, err = red:info("server")
        if not info then
            self:return_connection(red)
            return false, "Authentication test failed: " .. (err or "no response")
        end
    end
    
    -- Test cluster mode if enabled
    if self.cluster_mode then
        local cluster_info, err = red:cluster("info")
        if not cluster_info then
            self:return_connection(red)
            return false, "Cluster mode test failed: " .. (err or "no response")
        end
        
        -- Check cluster state
        if not string.find(cluster_info, "cluster_state:ok") then
            self:return_connection(red)
            return false, "Cluster is not in healthy state"
        end
    end
    
    self:return_connection(red)
    ngx.log(ngx.INFO, "[ElastiCache] Health check passed")
    return true, nil
end

-- Return connection to pool with SSL optimization
function _M:return_connection(red)
    if not red then
        return
    end
    
    -- For ElastiCache SSL connections, use optimized pool settings
    local keepalive_timeout = self.keepalive_timeout
    local pool_size = self.pool_size
    
    if self.redis_type == "managed" and self.ssl_enabled then
        -- Optimize SSL connection pooling
        keepalive_timeout = math.max(self.keepalive_timeout, 120000) -- 2 minutes minimum for SSL
        pool_size = math.min(self.pool_size, 50) -- Smaller pool for SSL connections
        
        -- Use connection-specific pool name for SSL connections
        local pool_name = string.format("elasticache_ssl_%s_%d", self.host, self.port)
        local ok, err = red:set_keepalive(keepalive_timeout, pool_size, pool_name)
        if not ok then
            ngx.log(ngx.WARN, "[ElastiCache] Failed to set SSL keepalive: ", err)
        else
            ngx.log(ngx.DEBUG, "[ElastiCache] SSL connection returned to pool: ", pool_name)
        end
    else
        -- Standard connection pooling
        local ok, err = red:set_keepalive(keepalive_timeout, pool_size)
        if not ok then
            ngx.log(ngx.WARN, "Failed to set Redis keepalive: ", err)
        end
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

-- Health check with ElastiCache support
function _M:health_check()
    -- Validate configuration first
    local config_ok, config_err = self:validate_elasticache_config()
    if not config_ok then
        return false, "Configuration validation failed: " .. (config_err or "unknown error")
    end
    
    -- Use appropriate health check based on Redis type
    if self.redis_type == "managed" then
        return self:elasticache_health_check()
    else
        return self:traditional_health_check()
    end
end

-- Traditional Redis health check (original logic)
function _M:traditional_health_check()
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

-- Performance benchmarking for ElastiCache vs Traditional Redis
function _M:benchmark_connection_performance(iterations)
    iterations = iterations or 100
    local results = {
        connection_type = self.redis_type,
        ssl_enabled = self.ssl_enabled,
        total_iterations = iterations,
        successful_connections = 0,
        failed_connections = 0,
        total_time_ms = 0,
        min_time_ms = math.huge,
        max_time_ms = 0,
        connection_times = {}
    }
    
    ngx.log(ngx.INFO, "[Benchmark] Starting connection performance test - Type: ", 
        self.redis_type, ", SSL: ", tostring(self.ssl_enabled), ", Iterations: ", iterations)
    
    for i = 1, iterations do
        local start_time = ngx.now() * 1000 -- Convert to milliseconds
        
        local red, err = self:get_connection()
        if red then
            -- Perform a simple operation
            local ok, ping_err = red:ping()
            self:return_connection(red)
            
            if ok then
                local end_time = ngx.now() * 1000
                local elapsed = end_time - start_time
                
                results.successful_connections = results.successful_connections + 1
                results.total_time_ms = results.total_time_ms + elapsed
                results.min_time_ms = math.min(results.min_time_ms, elapsed)
                results.max_time_ms = math.max(results.max_time_ms, elapsed)
                table.insert(results.connection_times, elapsed)
            else
                results.failed_connections = results.failed_connections + 1
                ngx.log(ngx.WARN, "[Benchmark] Ping failed in iteration ", i, ": ", ping_err or "unknown")
            end
        else
            results.failed_connections = results.failed_connections + 1
            ngx.log(ngx.WARN, "[Benchmark] Connection failed in iteration ", i, ": ", err or "unknown")
        end
        
        -- Small delay between iterations to avoid overwhelming
        if i % 10 == 0 then
            ngx.sleep(0.001) -- 1ms delay every 10 iterations
        end
    end
    
    -- Calculate statistics
    if results.successful_connections > 0 then
        results.avg_time_ms = results.total_time_ms / results.successful_connections
        results.success_rate = (results.successful_connections / iterations) * 100
        
        -- Calculate median
        table.sort(results.connection_times)
        local mid = math.floor(results.successful_connections / 2)
        if results.successful_connections % 2 == 0 then
            results.median_time_ms = (results.connection_times[mid] + results.connection_times[mid + 1]) / 2
        else
            results.median_time_ms = results.connection_times[mid + 1]
        end
    else
        results.avg_time_ms = 0
        results.median_time_ms = 0
        results.success_rate = 0
    end
    
    -- Log results
    ngx.log(ngx.INFO, "[Benchmark] Results for ", self.redis_type, " Redis:")
    ngx.log(ngx.INFO, "[Benchmark] Success Rate: ", string.format("%.2f%%", results.success_rate))
    ngx.log(ngx.INFO, "[Benchmark] Average Time: ", string.format("%.2fms", results.avg_time_ms))
    ngx.log(ngx.INFO, "[Benchmark] Median Time: ", string.format("%.2fms", results.median_time_ms))
    ngx.log(ngx.INFO, "[Benchmark] Min Time: ", string.format("%.2fms", results.min_time_ms))
    ngx.log(ngx.INFO, "[Benchmark] Max Time: ", string.format("%.2fms", results.max_time_ms))
    
    return results
end

-- Get comprehensive ElastiCache connection statistics
function _M:get_elasticache_stats()
    if self.redis_type ~= "managed" then
        return nil, "ElastiCache stats only available for managed Redis type"
    end
    
    local red, err = self:get_connection()
    if not red then
        return nil, "Failed to get connection for stats: " .. (err or "unknown error")
    end
    
    red:init_pipeline()
    
    -- Gather ElastiCache-specific statistics
    red:info("server")
    red:info("memory")
    red:info("stats")
    red:info("clients")
    red:info("keyspace")
    
    if self.cluster_mode then
        red:cluster("info")
        red:cluster("nodes")
    end
    
    local results, err = red:commit_pipeline()
    self:return_connection(red)
    
    if not results then
        return nil, "Failed to get ElastiCache stats: " .. (err or "unknown error")
    end
    
    local stats = {
        redis_type = "managed",
        ssl_enabled = self.ssl_enabled,
        cluster_mode = self.cluster_mode,
        server_info = results[1] or "",
        memory_info = results[2] or "",
        stats_info = results[3] or "",
        clients_info = results[4] or "",
        keyspace_info = results[5] or ""
    }
    
    if self.cluster_mode then
        stats.cluster_info = results[6] or ""
        stats.cluster_nodes = results[7] or ""
    end
    
    return stats, nil
end

return _M