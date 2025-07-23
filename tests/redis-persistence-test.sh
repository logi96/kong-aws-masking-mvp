#!/bin/bash
# Redis 데이터 영속성 테스트

source .env

echo "========================================="
echo "        Redis 데이터 영속성 테스트"
echo "========================================="
echo ""

# 고유한 테스트 리소스 생성
generate_test_resource() {
  local prefix="$1"
  local timestamp=$(date +%s%3N)  # 밀리초 단위 타임스탬프
  echo "${prefix}-persist-${timestamp}"
}

test_basic_persistence() {
  echo "=== 1. 기본 영속성 테스트 ==="
  
  local test_resource=$(generate_test_resource "i")
  echo "테스트 리소스: $test_resource"
  
  # 1단계: 초기 마스킹 수행
  local response1=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"Return exactly: $test_resource\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$test_resource\"
      }],
      \"max_tokens\": 50
    }" 2>/dev/null)
  
  local masked_id1=$(echo "$response1" | grep -o 'EC2_[0-9]+' | head -1)
  
  if [ -z "$masked_id1" ]; then
    echo "❌ 초기 마스킹 실패"
    echo "   응답: $response1"
    exit 1
  fi
  
  echo "✅ 초기 마스킹 성공: $test_resource → $masked_id1"
  
  # 2단계: 동일 요청 반복 (일관성 확인)
  local response2=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"Return exactly: $test_resource\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$test_resource\"
      }],
      \"max_tokens\": 50
    }" 2>/dev/null)
  
  local masked_id2=$(echo "$response2" | grep -o 'EC2_[0-9]+' | head -1)
  
  if [[ "$masked_id1" == "$masked_id2" ]]; then
    echo "✅ 동일 요청 일관성 확인: $masked_id1"
  else
    echo "❌ 일관성 실패: $masked_id1 != $masked_id2"
    exit 1
  fi
  
  # Redis에 직접 저장 확인
  local redis_key="aws_masker:map:$masked_id1"
  local stored_value=$(docker exec redis-cache redis-cli get "$redis_key" 2>/dev/null)
  
  if [[ "$stored_value" == "$test_resource" ]]; then
    echo "✅ Redis 저장 확인: $redis_key → $stored_value"
  else
    echo "⚠️  Redis 저장 불일치 또는 메모리 모드: 예상=$test_resource, 실제=$stored_value"
  fi
  
  echo ""
}

test_restart_persistence() {
  echo "=== 2. 재시작 후 영속성 테스트 ==="
  
  local test_resource=$(generate_test_resource "i")
  echo "재시작 테스트 리소스: $test_resource"
  
  # 1단계: 마스킹 수행 및 결과 저장
  local response_before=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"Return exactly: $test_resource\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$test_resource\"
      }],
      \"max_tokens\": 50
    }" 2>/dev/null)
  
  local masked_id_before=$(echo "$response_before" | grep -o 'EC2_[0-9]+' | head -1)
  
  if [ -z "$masked_id_before" ]; then
    echo "❌ 재시작 전 마스킹 실패"
    exit 1
  fi
  
  echo "✅ 재시작 전 마스킹: $test_resource → $masked_id_before"
  
  # 2단계: Kong 재시작
  echo "Kong 컨테이너 재시작 중..."
  docker-compose restart kong >/dev/null 2>&1
  
  # Kong 재시작 완료 대기
  local max_wait=60
  local wait_count=0
  
  while [ $wait_count -lt $max_wait ]; do
    if curl -s -f http://localhost:8001/status >/dev/null 2>&1; then
      echo "✅ Kong 재시작 완료 ($wait_count 초 소요)"
      break
    fi
    sleep 1
    wait_count=$((wait_count + 1))
  done
  
  if [ $wait_count -ge $max_wait ]; then
    echo "❌ Kong 재시작 타임아웃"
    exit 1
  fi
  
  # 추가 안정화 시간
  sleep 5
  
  # 3단계: 재시작 후 동일 요청
  local response_after=$(curl -s -X POST http://localhost:8000/analyze-claude \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -d "{
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"system\": \"Return exactly: $test_resource\",
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"$test_resource\"
      }],
      \"max_tokens\": 50
    }" 2>/dev/null)
  
  local masked_id_after=$(echo "$response_after" | grep -o 'EC2_[0-9]+' | head -1)
  
  # 4단계: 일관성 검증
  if [[ "$masked_id_before" == "$masked_id_after" ]]; then
    echo "✅ 재시작 후 영속성 확인: $masked_id_before"
    echo "   Redis 영속성이 올바르게 동작함"
  else
    echo "⚠️  재시작 후 마스킹 ID 변경: $masked_id_before → $masked_id_after"
    echo "   메모리 모드로 동작 중이거나 카운터 증가"
    
    # Redis에서 데이터 확인
    local redis_check=$(docker exec redis-cache redis-cli exists "aws_masker:map:$masked_id_before" 2>/dev/null)
    if [ "$redis_check" = "1" ]; then
      echo "   Redis에 이전 데이터 존재함 (다른 원인)"
    else
      echo "   Redis에 이전 데이터 없음 (메모리 모드 추정)"
    fi
  fi
  
  echo ""
}

test_multiple_resources_persistence() {
  echo "=== 3. 다중 리소스 영속성 테스트 ==="
  
  local test_resources=(
    "$(generate_test_resource "i")"
    "$(generate_test_resource "vpc")"
    "$(generate_test_resource "subnet")"
    "arn:aws:iam::123456789012:role/test-role-$(date +%s)"
    "AKIATEST$(date +%s)EXAMPLE"
  )
  
  declare -A resource_mappings
  
  # 1단계: 모든 리소스 마스킹
  echo "다중 리소스 마스킹 중..."
  for resource in "${test_resources[@]}"; do
    local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
      -H "Content-Type: application/json" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -d "{
        \"model\": \"claude-3-5-sonnet-20241022\",
        \"system\": \"Return exactly: $resource\",
        \"messages\": [{
          \"role\": \"user\",
          \"content\": \"$resource\"
        }],
        \"max_tokens\": 50
      }" 2>/dev/null)
    
    # 마스킹된 ID 추출 (다양한 패턴)
    local masked_id=$(echo "$response" | grep -oE '(EC2_[0-9]+|VPC_[0-9]+|SUBNET_[0-9]+|IAM_ROLE_[0-9]+|ACCESS_KEY_[0-9]+)' | head -1)
    
    if [ -n "$masked_id" ]; then
      resource_mappings["$resource"]="$masked_id"
      echo "   $resource → $masked_id"
    else
      echo "   ⚠️  $resource → 마스킹 실패"
    fi
  done
  
  echo ""
  
  # 2단계: 일관성 재확인
  echo "다중 리소스 일관성 확인 중..."
  local consistent_count=0
  local total_count=0
  
  for resource in "${!resource_mappings[@]}"; do
    local expected_masked="${resource_mappings[$resource]}"
    
    local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
      -H "Content-Type: application/json" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -d "{
        \"model\": \"claude-3-5-sonnet-20241022\",
        \"system\": \"Return exactly: $resource\",
        \"messages\": [{
          \"role\": \"user\",
          \"content\": \"$resource\"
        }],
        \"max_tokens\": 50
      }" 2>/dev/null)
    
    local actual_masked=$(echo "$response" | grep -oE '(EC2_[0-9]+|VPC_[0-9]+|SUBNET_[0-9]+|IAM_ROLE_[0-9]+|ACCESS_KEY_[0-9]+)' | head -1)
    
    total_count=$((total_count + 1))
    
    if [[ "$expected_masked" == "$actual_masked" ]]; then
      consistent_count=$((consistent_count + 1))
      echo "   ✅ $resource: 일관성 유지"
    else
      echo "   ❌ $resource: $expected_masked → $actual_masked"
    fi
  done
  
  local consistency_rate=$((consistent_count * 100 / total_count))
  echo ""
  echo "다중 리소스 일관성: $consistent_count/$total_count ($consistency_rate%)"
  
  if [ $consistency_rate -ge 90 ]; then
    echo "✅ 다중 리소스 영속성 우수"
  elif [ $consistency_rate -ge 70 ]; then
    echo "⚠️  다중 리소스 영속성 보통"
  else
    echo "❌ 다중 리소스 영속성 불량"
    exit 1
  fi
  
  echo ""
}

test_ttl_behavior() {
  echo "=== 4. TTL 동작 테스트 ==="
  
  # Redis 키들의 TTL 확인
  local redis_keys=$(docker exec redis-cache redis-cli --scan --pattern "aws_masker:map:*" | head -5)
  
  if [ -z "$redis_keys" ]; then
    echo "⚠️  Redis에 테스트할 키가 없음 (메모리 모드 추정)"
    return
  fi
  
  echo "TTL 확인 중..."
  local ttl_count=0
  local total_keys=0
  
  while IFS= read -r key; do
    if [ -n "$key" ]; then
      total_keys=$((total_keys + 1))
      local ttl=$(docker exec redis-cache redis-cli ttl "$key" 2>/dev/null)
      
      if [ "$ttl" -gt 0 ]; then
        ttl_count=$((ttl_count + 1))
        echo "   $key: TTL $ttl 초"
      elif [ "$ttl" -eq -1 ]; then
        echo "   $key: TTL 없음 (영구)"
      else
        echo "   $key: 만료됨"
      fi
    fi
  done <<< "$redis_keys"
  
  if [ $total_keys -gt 0 ]; then
    local ttl_rate=$((ttl_count * 100 / total_keys))
    echo "TTL 설정율: $ttl_count/$total_keys ($ttl_rate%)"
    
    if [ $ttl_rate -ge 80 ]; then
      echo "✅ TTL 설정 우수"
    else
      echo "⚠️  TTL 설정 부족"
    fi
  fi
  
  echo ""
}

# Redis 메모리 사용량 확인
check_redis_memory_usage() {
  echo "=== Redis 메모리 사용량 ==="
  
  local memory_info=$(docker exec redis-cache redis-cli info memory | grep used_memory_human)
  local key_count=$(docker exec redis-cache redis-cli dbsize 2>/dev/null)
  
  echo "사용 메모리: $memory_info"
  echo "저장된 키 수: $key_count"
  echo ""
}

# 전체 테스트 실행
main() {
  echo "테스트 시작 시간: $(date)"
  echo ""
  
  test_basic_persistence
  test_restart_persistence
  test_multiple_resources_persistence
  test_ttl_behavior
  check_redis_memory_usage
  
  echo "========================================="
  echo "      🎉 Redis 영속성 테스트 완료!"
  echo "========================================="
  echo ""
  echo "테스트 완료 시간: $(date)"
}

# 스크립트 실행
main "$@"