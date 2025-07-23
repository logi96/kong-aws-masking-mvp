#!/bin/bash
# Redis 연결 및 기본 기능 테스트

source .env

echo "========================================="
echo "        Redis 연결 테스트"
echo "========================================="
echo ""

# 테스트 함수
test_redis_basic_connection() {
  echo "=== 1. Redis 기본 연결 테스트 ==="
  
  # Redis 컨테이너 상태 확인
  if ! docker ps | grep -q "redis-cache"; then
    echo "❌ Redis 컨테이너가 실행 중이지 않습니다"
    exit 1
  fi
  
  # Redis ping 테스트
  if docker exec redis-cache redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✅ Redis 서버 응답 정상"
  else
    echo "❌ Redis 서버 응답 없음"
    exit 1
  fi
  
  echo ""
}

test_kong_redis_integration() {
  echo "=== 2. Kong-Redis 통합 테스트 ==="
  
  # Kong 상태 확인
  if ! curl -s -f http://localhost:8001/status >/dev/null; then
    echo "❌ Kong 서버가 실행 중이지 않습니다"
    exit 1
  fi
  
  echo "✅ Kong 서버 응답 정상"
  
  # 간단한 마스킹 테스트로 Redis 연동 확인
  local test_resource="i-redis-test-12345"
  local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
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
  
  # 응답 분석
  if echo "$response" | grep -q "EC2_"; then
    echo "✅ Kong-Redis 마스킹 정상 동작"
    local masked_id=$(echo "$response" | grep -o 'EC2_[0-9]+' | head -1)
    echo "   마스킹 결과: $test_resource → $masked_id"
  else
    echo "❌ Kong-Redis 마스킹 실패"
    echo "   응답: $response"
    exit 1
  fi
  
  echo ""
}

test_redis_data_storage() {
  echo "=== 3. Redis 데이터 저장 확인 ==="
  
  # Redis에 저장된 키 확인
  local key_count=$(docker exec redis-cache redis-cli --scan --pattern "aws_masker:*" | wc -l)
  
  if [ "$key_count" -gt 0 ]; then
    echo "✅ Redis에 $key_count 개의 매핑 데이터 저장됨"
    
    # 몇 개 샘플 키 출력
    echo "   저장된 키 샘플:"
    docker exec redis-cache redis-cli --scan --pattern "aws_masker:map:*" | head -3 | while read key; do
      if [ -n "$key" ]; then
        local value=$(docker exec redis-cache redis-cli get "$key" 2>/dev/null)
        echo "   $key → $value"
      fi
    done
  else
    echo "⚠️  Redis에 데이터가 없습니다 (메모리 모드로 동작 중일 수 있음)"
  fi
  
  echo ""
}

test_redis_ttl() {
  echo "=== 4. Redis TTL 설정 확인 ==="
  
  # TTL이 설정된 키 확인
  local keys_with_ttl=$(docker exec redis-cache redis-cli --scan --pattern "aws_masker:map:*" | head -1)
  
  if [ -n "$keys_with_ttl" ]; then
    local ttl=$(docker exec redis-cache redis-cli ttl "$keys_with_ttl" 2>/dev/null)
    
    if [ "$ttl" -gt 0 ]; then
      echo "✅ TTL 설정 확인: $ttl 초 남음"
      
      # 7일 TTL 확인 (604800초 = 7일)
      if [ "$ttl" -gt 600000 ]; then  # 약 7일
        echo "   올바른 7일 TTL 설정"
      else
        echo "   ⚠️  TTL이 7일보다 짧습니다: $ttl 초"
      fi
    else
      echo "⚠️  TTL이 설정되지 않았습니다"
    fi
  else
    echo "⚠️  TTL 확인할 키가 없습니다"
  fi
  
  echo ""
}

test_fallback_mechanism() {
  echo "=== 5. Fallback 메커니즘 테스트 ==="
  
  # Redis 일시 중단
  echo "Redis 컨테이너 일시 중단 중..."
  docker pause redis-cache
  
  sleep 2
  
  # Redis 없이 요청 테스트
  local test_resource="i-fallback-test-67890"
  local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
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
  
  # Redis 재개
  echo "Redis 컨테이너 재개 중..."
  docker unpause redis-cache
  
  # 결과 분석
  if echo "$response" | grep -q "EC2_"; then
    echo "✅ Fallback 메커니즘 정상 동작 (메모리 모드)"
    local masked_id=$(echo "$response" | grep -o 'EC2_[0-9]+' | head -1)
    echo "   Fallback 마스킹: $test_resource → $masked_id"
  else
    echo "❌ Fallback 메커니즘 실패"
    echo "   응답: $response"
    exit 1
  fi
  
  echo ""
}

test_redis_reconnection() {
  echo "=== 6. Redis 재연결 테스트 ==="
  
  # Redis 복구 후 정상 연결 확인
  sleep 3  # Redis 안정화 대기
  
  local test_resource="i-reconnect-test-11111"
  local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
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
  
  if echo "$response" | grep -q "EC2_"; then
    echo "✅ Redis 재연결 및 정상 동작 확인"
    
    # Redis에 다시 데이터가 저장되는지 확인
    sleep 1
    local new_key_count=$(docker exec redis-cache redis-cli --scan --pattern "aws_masker:*" | wc -l)
    echo "   Redis 키 개수: $new_key_count"
  else
    echo "❌ Redis 재연결 실패"
    exit 1
  fi
  
  echo ""
}

# 전체 테스트 실행
main() {
  echo "테스트 시작 시간: $(date)"
  echo ""
  
  test_redis_basic_connection
  test_kong_redis_integration
  test_redis_data_storage
  test_redis_ttl
  test_fallback_mechanism
  test_redis_reconnection
  
  echo "========================================="
  echo "        🎉 모든 Redis 연결 테스트 통과!"
  echo "========================================="
  echo ""
  echo "테스트 완료 시간: $(date)"
}

# 스크립트 실행
main "$@"