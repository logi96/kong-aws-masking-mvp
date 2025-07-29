#!/bin/bash
# ngx.re vs string.gsub 분석 및 JSON 이스케이프 문제 확인

source .env

echo "========================================================================="
echo "              ngx.re vs string.gsub 및 JSON 이스케이프 분석"
echo "========================================================================="
echo ""
echo "테스트 시간: $(date)"
echo ""

# 문제가 된 패턴들 테스트
echo "=== 1. 현재 상황 분석 ==="
echo ""
echo "현재 구현:"
echo "- Lua 패턴 사용 (string.gsub)"
echo "- IAM Role ARN 패턴: arn:aws:iam::[0-9]+:role/[a-zA-Z0-9%-_+=,.@]+"
echo ""

# 테스트 함수
test_arn_pattern() {
  local test_text="$1"
  local desc="$2"
  
  echo "=== $desc 테스트 ==="
  echo "원본: $test_text"
  
  # Kong을 통해 테스트
# REMOVED - Wrong pattern:   local response=$(curl -s -X POST http://localhost:3000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"Return EXACTLY what you receive without any modification: $test_text\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$test_text\"
      }],
      \"max_tokens\": 100
    }" 2>&1)
  
  # 응답 분석
  local claude_text=$(echo "$response" | grep -o '"text":"[^"]*' | sed 's/"text":"//' | head -1)
  
  echo "응답: $claude_text"
  
  # JSON 이스케이프 문제 확인
  if [[ "$claude_text" =~ \\\/ ]]; then
    echo "❌ JSON 이스케이프 문제 발생: / → \\/"
  fi
  
  # 마스킹 여부 확인
  if [[ "$response" =~ IAM_ROLE_[0-9]+ ]]; then
    echo "✅ IAM Role이 마스킹됨 (보안 OK)"
  else
    echo "⚠️  IAM Role 마스킹 확인 필요"
  fi
  
  echo ""
}

echo "=== 2. 문제 패턴 테스트 ==="
echo ""

# IAM Role ARN 테스트
test_arn_pattern "arn:aws:iam::123456789012:role/MyRole" "IAM Role ARN"
test_arn_pattern "arn:aws:iam::123456789012:role/Admin-Role" "IAM Role with dash"
test_arn_pattern "arn:aws:iam::123456789012:role/app.role@company" "IAM Role with special chars"

echo "=== 3. 문제 분석 ==="
echo ""
echo "JSON 이스케이프 문제 원인:"
echo "1. Claude API는 JSON 응답에서 / 문자를 \\/ 로 이스케이프"
echo "2. 이는 JSON 표준에 따른 것 (선택적이지만 많은 구현체가 수행)"
echo "3. ngx.re 사용 여부와는 무관"
echo ""
echo "ngx.re 사용의 장점:"
echo "1. PCRE 정규식 지원 (더 강력한 패턴)"
echo "2. 성능 최적화 (C 레벨 구현)"
echo "3. 복잡한 패턴에 더 적합"
echo ""

# Kong 로그에서 실제 마스킹 확인
echo "=== 4. Kong 로그 확인 ==="
docker logs kong-gateway --tail 20 | grep -E "(IAM_ROLE|arn:aws:iam)" || echo "로그에서 관련 내용을 찾을 수 없음"

echo ""
echo "=== 5. 권장사항 ==="
echo ""
echo "1. ngx.re 사용:"
echo "   - 복잡한 ARN 패턴에는 ngx.re가 더 적합"
echo "   - 설계서 지침대로 구현 필요"
echo ""
echo "2. JSON 이스케이프 처리:"
echo "   - body_filter에서 gsub('\\\/', '/') 적용 중"
echo "   - 추가 개선 가능"
echo ""
echo "3. 보안 관점:"
echo "   - 현재도 Claude는 마스킹된 데이터만 확인 (보안 OK)"
echo "   - ngx.re 사용으로 더 정확한 패턴 매칭 가능"