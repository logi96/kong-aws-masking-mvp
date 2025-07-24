-- Test patterns
local patterns = {
  ec2_exact = "i%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]",
  ec2_simple = "i%-[0-9a-f]+",
  vpc_exact = "vpc%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]",
  vpc_simple = "vpc%-[0-9a-f]+"
}

local test_string = "EC2 i-1234567890abcdef0, VPC vpc-12345678"

for name, pattern in pairs(patterns) do
  local match = string.match(test_string, pattern)
  print(name .. ": " .. tostring(match))
end
