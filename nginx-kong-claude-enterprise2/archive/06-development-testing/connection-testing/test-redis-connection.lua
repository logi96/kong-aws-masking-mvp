-- Redis connection test script for Kong
local redis = require "resty.redis"

-- Redis configuration from environment
local redis_host = os.getenv("REDIS_HOST") or "redis"
local redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379
local redis_password = os.getenv("REDIS_PASSWORD")

print("Testing Redis connection...")
print(string.format("Host: %s, Port: %d", redis_host, redis_port))

-- Create Redis instance
local red = redis:new()

-- Set timeout (1 second for connect, 2 seconds for send, 2 seconds for read)
red:set_timeout(1000)

-- Connect to Redis
local ok, err = red:connect(redis_host, redis_port)
if not ok then
    print("ERROR: Failed to connect to Redis: " .. (err or "unknown"))
    return false
end

print("SUCCESS: Connected to Redis")

-- Authenticate if password is provided
if redis_password and redis_password ~= "" then
    local res, err = red:auth(redis_password)
    if not res then
        print("ERROR: Failed to authenticate with Redis: " .. (err or "unknown"))
        return false
    elseif res == ngx.null then
        print("ERROR: Redis authentication returned null")
        return false
    end
    print("SUCCESS: Authenticated with Redis")
end

-- Test PING
local res, err = red:ping()
if not res then
    print("ERROR: Redis PING failed: " .. (err or "unknown"))
    return false
end

print("SUCCESS: Redis PING response: " .. tostring(res))

-- Test SET operation
local res, err = red:set("kong_redis_test", "test_value_" .. os.time())
if not res then
    print("ERROR: Redis SET failed: " .. (err or "unknown"))
    return false
end

print("SUCCESS: Redis SET operation completed")

-- Test GET operation
local res, err = red:get("kong_redis_test")
if not res then
    print("ERROR: Redis GET failed: " .. (err or "unknown"))
    return false
end

print("SUCCESS: Redis GET operation returned: " .. tostring(res))

-- Test DEL operation
local res, err = red:del("kong_redis_test")
if not res then
    print("ERROR: Redis DEL failed: " .. (err or "unknown"))
    return false
end

print("SUCCESS: Redis DEL operation completed, deleted " .. tostring(res) .. " keys")

-- Close connection
local ok, err = red:close()
if not ok then
    print("WARNING: Failed to close Redis connection: " .. (err or "unknown"))
else
    print("SUCCESS: Redis connection closed properly")
end

print("Redis connection test completed successfully!")
return true