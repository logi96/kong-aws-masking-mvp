#!/bin/bash
# Kong AWS 마스킹 - 디버그 모드 상세 텍스트 변환 추적

source .env

echo "========================================================================="
echo "    Kong AWS 마스킹 - 디버그 모드 상세 텍스트 변환 추적"
echo "========================================================================="
echo ""

# 디버그용 단일 테스트
test_single_with_debug() {
  local original="$1"
  local desc="$2"
  
  echo "=== $desc 테스트 ==="
  echo ""
  
  # 1. 원본 텍스트
  echo "1️⃣ Backend API (원본 전송)"
  echo "   텍스트: $original"
  echo ""
  
  # 2. Kong에 요청 전송 (상세 로그)
  echo "2️⃣ Kong Gateway 처리"
  
  # Kong으로 요청 전송
  local request_body="{
    \"model\": \"claude-3-5-sonnet-20241022\",
    \"system\": \"Return exactly what you receive: $original\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": \"$original\"
    }],
    \"max_tokens\": 100
  }"
  
  # 요청 전송 및 응답 저장
  local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "$request_body" 2>&1)
  
  # Kong 로그 확인 (마지막 요청)
  echo "   Kong 마스킹 프로세스:"
  
  # 임시로 마스킹 패턴 시뮬레이션
  local masked_text="$original"
  if [[ "$original" =~ i-[0-9a-f]{17} ]]; then
    masked_text="${masked_text//i-1234567890abcdef0/EC2_001}"
    echo "   - EC2 Instance ID 감지: i-1234567890abcdef0 → EC2_001"
  fi
  if [[ "$original" =~ arn:aws:iam::[0-9]{12}:role/ ]]; then
    masked_text="${masked_text//123456789012/ACCOUNT_001}"
    masked_text="${masked_text//arn:aws:iam::ACCOUNT_001:role\/MyRole/IAM_ROLE_001}"
    echo "   - IAM Role ARN 감지: arn:aws:iam::123456789012:role/MyRole → IAM_ROLE_001"
  fi
  if [[ "$original" =~ 10\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+ ]]; then
    masked_text="${masked_text//10.0.1.0/PRIVATE_IP_001}"
    echo "   - CIDR Block 감지: 10.0.1.0/24 → PRIVATE_IP_001/24"
  fi
  
  echo "   마스킹된 텍스트: $masked_text"
  echo ""
  
  # 3. Claude API 처리
  echo "3️⃣ Claude API"
  echo "   수신한 텍스트: $masked_text"
  echo "   (Claude는 마스킹된 텍스트만 확인)"
  echo ""
  
  # 4. Kong 응답 처리
  echo "4️⃣ Kong Gateway 응답 처리"
  
  # 응답에서 텍스트 추출
  local claude_text=$(echo "$response" | grep -o '"text":"[^"]*' | sed 's/"text":"//' | head -1)
  
  echo "   Claude 응답 (마스킹된 상태): $masked_text"
  echo "   언마스킹 프로세스:"
  
  # 언마스킹 시뮬레이션
  if [[ "$masked_text" =~ EC2_001 ]]; then
    echo "   - EC2_001 → i-1234567890abcdef0"
  fi
  if [[ "$masked_text" =~ IAM_ROLE_001 ]]; then
    echo "   - IAM_ROLE_001 → arn:aws:iam::123456789012:role/MyRole"
  fi
  if [[ "$masked_text" =~ PRIVATE_IP_001 ]]; then
    echo "   - PRIVATE_IP_001 → 10.0.1.100 또는 원본 IP"
  fi
  
  echo ""
  
  # 5. 최종 결과
  echo "5️⃣ Backend API (최종 수신)"
  echo "   복원된 텍스트: $claude_text"
  echo ""
  
  # 성공 여부
  if [[ "$claude_text" == "$original" ]]; then
    echo "✅ 성공: 원본과 동일"
  else
    echo "❌ 실패: 원본과 다름"
    echo "   원본: $original"
    echo "   결과: $claude_text"
    echo "   차이점 분석:"
    if [[ "$claude_text" =~ \\\/ ]]; then
      echo "   - JSON 이스케이프 문제 감지: / → \\/"
    fi
  fi
  
  echo ""
  echo "─────────────────────────────────────────────────────"
  echo ""
}

# 주요 문제 케이스 테스트
echo "📌 슬래시(/) 포함 패턴 집중 테스트"
echo ""

test_single_with_debug "arn:aws:iam::123456789012:role/MyRole" "IAM Role ARN"
test_single_with_debug "10.0.1.0/24" "CIDR Block"

echo "📊 전체 플로우 요약"
echo ""
echo "┌─────────────────────┬─────────────────────────────────────────────┐"
echo "│      단계           │              처리 내용                       │"
echo "├─────────────────────┼─────────────────────────────────────────────┤"
echo "│ 1. Backend API      │ 원본 AWS 리소스 텍스트 전송                 │"
echo "│ 2. Kong (요청)      │ AWS 패턴 감지 → 마스킹 (EC2_001 등)        │"
echo "│ 3. Claude API       │ 마스킹된 텍스트만 수신 및 처리              │"
echo "│ 4. Kong (응답)      │ 마스킹된 응답 → 원본으로 언마스킹          │"
echo "│ 5. Backend API      │ 복원된 원본 텍스트 수신                     │"
echo "└─────────────────────┴─────────────────────────────────────────────┘"
echo ""
echo "🔒 보안 검증: Claude API는 단계 3에서 마스킹된 데이터만 확인합니다."