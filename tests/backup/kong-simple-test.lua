-- kong-simple-test.lua
-- 간단한 Kong 환경 테스트

print("=======================================")
print("Kong 환경 테스트")
print("=======================================")

-- Kong 모듈 확인
local ok, kong = pcall(require, "kong")
if ok then
    print("✓ Kong 모듈 로드 성공")
else
    print("✗ Kong 모듈 로드 실패: " .. tostring(kong))
end

-- cjson 확인
local cjson_modules = {"cjson", "cjson.safe", "resty.cjson"}
for _, module_name in ipairs(cjson_modules) do
    local ok, mod = pcall(require, module_name)
    if ok then
        print("✓ " .. module_name .. " 로드 성공")
        break
    else
        print("✗ " .. module_name .. " 로드 실패")
    end
end

-- 플러그인 디렉토리 확인
local plugin_path = "/usr/local/share/lua/5.1/kong/plugins/aws-masker/"
print("\n플러그인 경로: " .. plugin_path)

-- handler.lua 로드 테스트
local ok, handler = pcall(require, "kong.plugins.aws-masker.handler")
if ok then
    print("✓ handler.lua 로드 성공")
else
    print("✗ handler.lua 로드 실패: " .. tostring(handler))
end

print("\n테스트 완료")