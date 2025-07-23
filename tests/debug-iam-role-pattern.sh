#!/bin/bash
# IAM Role ARN 패턴 디버깅

echo "=== IAM Role ARN 패턴 디버깅 ==="
echo ""

# patterns.lua에서 IAM Role 패턴 확인
echo "1. patterns.lua의 IAM Role 패턴:"
grep -A3 "iam_role" /Users/tw.kim/Documents/AGA/test/Kong/kong/plugins/aws-masker/patterns.lua | grep pattern

echo ""
echo "2. 테스트할 IAM Role ARN:"
echo "   - arn:aws:iam::123456789012:role/MyRole"
echo "   - arn:aws:iam::123456789012:role/Admin-Role-2024"

echo ""
echo "3. Kong 로그에서 마스킹 과정 확인:"
docker logs kong-gateway --tail 100 | grep -E "(iam_role|IAM_ROLE|masking|role/MyRole)" | tail -10 || echo "관련 로그 없음"

echo ""
echo "4. ngx.re 패턴 직접 테스트:"

# Lua 스크립트로 직접 테스트
cat > /tmp/test_pattern.lua << 'EOF'
local pattern = "arn:aws:iam::[0-9]+:role/[a-zA-Z0-9%-_+=,.@]+"
local test_strings = {
  "arn:aws:iam::123456789012:role/MyRole",
  "arn:aws:iam::123456789012:role/Admin-Role-2024",
  "arn:aws:iam::987654321098:role/app.role@company"
}

print("Lua pattern test:")
for _, str in ipairs(test_strings) do
  if string.match(str, pattern) then
    print("  ✓ MATCH: " .. str)
  else
    print("  ✗ NO MATCH: " .. str)
  end
end

-- PCRE pattern for ngx.re
local pcre_pattern = "arn:aws:iam::[0-9]+:role/[a-zA-Z0-9\\-_+=,.@]+"
print("\nPCRE pattern: " .. pcre_pattern)
EOF

docker exec kong-gateway lua /tmp/test_pattern.lua 2>/dev/null || echo "직접 실행 실패"

echo ""
echo "5. 가능한 문제점:"
echo "   - Lua 패턴과 PCRE 패턴의 차이"
echo "   - 패턴 내 특수문자 이스케이프 문제"
echo "   - ngx.re.match 실행 오류"

echo ""
echo "6. 패턴 수정 제안:"
echo "   현재: arn:aws:iam::[0-9]+:role/[a-zA-Z0-9%-_+=,.@]+"
echo "   제안: arn:aws:iam::[0-9]+:role/[^[:space:]]+"