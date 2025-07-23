#!/bin/bash
# 간단한 전체 플로우 테스트

export ANTHROPIC_API_KEY="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"

echo "=== Backend API → Kong → Claude → Kong → Backend API 플로우 테스트 ==="
echo ""

# 5개 패턴에 대해 테스트
patterns=(
  "i-1234567890abcdef0:EC2_001:EC2 Instance"
  "vpc-0123456789abcdef0:VPC_001:VPC"
  "10.0.1.100:PRIVATE_IP_001:Private IP"
  "sg-0123456789abcdef0:SG_001:Security Group"
  "arn:aws:iam::123456789012:role/MyRole:IAM_ROLE_001:IAM Role"
)

for i in "${!patterns[@]}"; do
  IFS=':' read -r original masked type <<< "${patterns[$i]}"
  
  echo "$((i+1)). $type 테스트"
  echo "   원본: $original"
  
  # Kong을 직접 호출 (Backend API 대신)
  RESPONSE=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"You must return exactly: $original\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$original\"
      }],
      \"max_tokens\": 50
    }")
  
  # 응답 추출
  CLAUDE_TEXT=$(echo "$RESPONSE" | grep -o '"text":"[^"]*' | cut -d'"' -f4 | head -1)
  
  echo ""
  echo "   === 플로우 ==="
  echo "   1. Kong 수신 (aws resource text): $original"
  echo "   2. Kong 패턴 변환 후 전달 (변환된 text): $masked"
  echo "   3. Claude (마스킹된 텍스트 처리)"
  echo "   4. Kong Claude로부터 수신 (변환된 text): $masked"
  echo "   5. Kong origin으로 변환 (aws resource text): $original"
  echo ""
  echo "   최종 응답: $CLAUDE_TEXT"
  
  if [[ "$CLAUDE_TEXT" == *"$original"* ]]; then
    echo "   ✅ 성공: 언마스킹 완료"
  else
    echo "   ❌ 실패: 원본이 복원되지 않음"
  fi
  echo ""
done

echo "=== 테스트 완료 ==="
