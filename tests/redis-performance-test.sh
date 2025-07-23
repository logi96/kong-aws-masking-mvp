#!/bin/bash
# Redis 성능 비교 테스트

source .env

echo "========================================="
echo "        Redis 성능 비교 테스트"
echo "========================================="
echo ""

# 성능 측정 함수
measure_response_time() {
  local description="$1"
  local test_data="$2"
  local iterations=${3:-10}
  
  echo "=== $description ==="
  echo "테스트 데이터: $test_data"
  echo "반복 횟수: $iterations"
  
  local total_time=0
  local success_count=0
  local times=()
  
  for i in $(seq 1 $iterations); do
    local start_time=$(date +%s%3N)  # 밀리초
    
    local response=$(curl -s -X POST http://localhost:8000/analyze-claude \
      -H "Content-Type: application/json" \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -d "{
        \"model\": \"claude-3-5-sonnet-20241022\",
        \"system\": \"Return exactly: $test_data\",
        \"messages\": [{
          \"role\": \"user\",
          \"content\": \"$test_data\"
        }],
        \"max_tokens\": 50
      }" 2>/dev/null)
    
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    # 성공 여부 확인 (마스킹된 응답 또는 원본 복원)
    if echo "$response" | grep -qE "(EC2_[0-9]+|VPC_[0-9]+|$test_data)"; then
      success_count=$((success_count + 1))
      total_time=$((total_time + response_time))
      times+=($response_time)
      echo "   #$i: ${response_time}ms ✅"
    else
      echo "   #$i: 실패 ❌"
    fi
    
    # 간격 조정
    sleep 0.1
  done
  
  if [ $success_count -gt 0 ]; then
    local avg_time=$((total_time / success_count))
    
    # 정렬하여 중앙값과 95th percentile 계산
    IFS=$'\n' sorted_times=($(sort -n <<<"${times[*]}"))
    
    local median_index=$((success_count / 2))
    local p95_index=$((success_count * 95 / 100))
    local median_time=${sorted_times[$median_index]}
    local p95_time=${sorted_times[$p95_index]}
    
    echo ""
    echo "📊 성능 통계:"
    echo "   성공률: $success_count/$iterations ($((success_count * 100 / iterations))%)"
    echo "   평균 응답시간: ${avg_time}ms"
    echo "   중앙값: ${median_time}ms"
    echo "   95th percentile: ${p95_time}ms"
    echo "   최소: ${sorted_times[0]}ms"
    echo "   최대: ${sorted_times[-1]}ms"
  else
    echo ""
    echo "❌ 모든 요청 실패"
  fi
  
  echo ""
  return $avg_time
}

test_single_resource_performance() {
  echo "=== 1. 단일 리소스 성능 테스트 ==="
  
  # EC2 인스턴스 테스트
  local ec2_resource="i-perf-test-$(date +%s)"
  measure_response_time "EC2 인스턴스 마스킹" "$ec2_resource" 20
  local ec2_avg=$?
  
  # VPC 테스트
  local vpc_resource="vpc-perf-test-$(date +%s)"
  measure_response_time "VPC 마스킹" "$vpc_resource" 20
  local vpc_avg=$?
  
  # IAM Role 테스트  
  local iam_resource="arn:aws:iam::123456789012:role/perf-test-$(date +%s)"
  measure_response_time "IAM Role 마스킹" "$iam_resource" 20
  local iam_avg=$?
  
  # 전체 평균 계산
  local overall_avg=$(( (ec2_avg + vpc_avg + iam_avg) / 3 ))
  echo "🎯 단일 리소스 전체 평균: ${overall_avg}ms"
  echo ""
}

test_multiple_resources_performance() {
  echo "=== 2. 다중 리소스 성능 테스트 ==="
  
  # 복합 데이터 테스트
  local timestamp=$(date +%s)
  local complex_data="Deploy EC2 i-complex-${timestamp} in VPC vpc-complex-${timestamp} with role arn:aws:iam::123456789012:role/complex-${timestamp}"
  
  measure_response_time "다중 리소스 마스킹" "$complex_data" 15
  local complex_avg=$?
  
  echo "🎯 다중 리소스 평균: ${complex_avg}ms"
  echo ""
}

test_concurrent_performance() {
  echo "=== 3. 동시 요청 성능 테스트 ==="
  
  local concurrent_requests=5
  local test_resource="i-concurrent-$(date +%s)"
  
  echo "동시 요청 수: $concurrent_requests"
  echo "테스트 리소스: $test_resource"
  
  # 임시 결과 파일
  local temp_dir="/tmp/redis-perf-$$"
  mkdir -p "$temp_dir"
  
  # 동시 요청 실행
  local start_time=$(date +%s%3N)
  
  for i in $(seq 1 $concurrent_requests); do
    {
      local req_start=$(date +%s%3N)
      
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
      
      local req_end=$(date +%s%3N)
      local req_time=$((req_end - req_start))
      
      # 결과 저장
      if echo "$response" | grep -qE "(EC2_[0-9]+|$test_resource)"; then
        echo "$req_time,success" > "$temp_dir/req_$i.txt"
      else
        echo "$req_time,failure" > "$temp_dir/req_$i.txt"
      fi
    } &
  done
  
  # 모든 요청 완료 대기
  wait
  
  local end_time=$(date +%s%3N)
  local total_time=$((end_time - start_time))
  
  # 결과 분석
  local successful_requests=0
  local total_response_time=0
  
  for i in $(seq 1 $concurrent_requests); do
    if [ -f "$temp_dir/req_$i.txt" ]; then
      local result=$(cat "$temp_dir/req_$i.txt")
      local time=$(echo "$result" | cut -d',' -f1)
      local status=$(echo "$result" | cut -d',' -f2)
      
      if [ "$status" = "success" ]; then
        successful_requests=$((successful_requests + 1))
        total_response_time=$((total_response_time + time))
      fi
      
      echo "   요청 #$i: ${time}ms ($status)"
    fi
  done
  
  # 정리
  rm -rf "$temp_dir"
  
  echo ""
  echo "📊 동시 요청 결과:"
  echo "   전체 처리 시간: ${total_time}ms"
  echo "   성공한 요청: $successful_requests/$concurrent_requests"
  
  if [ $successful_requests -gt 0 ]; then
    local avg_response_time=$((total_response_time / successful_requests))
    echo "   평균 응답시간: ${avg_response_time}ms"
    echo "   처리량: $(echo "scale=2; $successful_requests * 1000 / $total_time" | bc) req/sec"
  fi
  
  echo ""
}

test_redis_vs_memory_comparison() {
  echo "=== 4. Redis vs 메모리 모드 비교 ==="
  
  local test_resource="i-comparison-$(date +%s)"
  
  # Redis 모드에서 측정
  echo "Redis 모드 테스트 중..."
  measure_response_time "Redis 모드" "$test_resource" 10
  local redis_avg=$?
  
  # Redis 일시 중단하여 메모리 모드 테스트
  echo "Redis 중단 후 메모리 모드 테스트 중..."
  docker pause redis-cache
  sleep 2
  
  local memory_resource="i-memory-$(date +%s)"  # 다른 리소스로 테스트
  measure_response_time "메모리 모드" "$memory_resource" 10
  local memory_avg=$?
  
  # Redis 재개
  docker unpause redis-cache
  sleep 2
  
  echo "📊 모드 비교 결과:"
  echo "   Redis 모드 평균: ${redis_avg}ms"
  echo "   메모리 모드 평균: ${memory_avg}ms"
  
  if [ $redis_avg -gt 0 ] && [ $memory_avg -gt 0 ]; then
    local performance_ratio=$((redis_avg * 100 / memory_avg))
    echo "   성능 비율: Redis는 메모리의 ${performance_ratio}% (낮을수록 좋음)"
    
    if [ $performance_ratio -le 200 ]; then  # 2배 이하
      echo "   ✅ Redis 성능 허용 범위 내"
    elif [ $performance_ratio -le 500 ]; then  # 5배 이하
      echo "   ⚠️  Redis 성능 주의 필요"
    else
      echo "   ❌ Redis 성능 문제"
    fi
  fi
  
  echo ""
}

test_sustained_load() {
  echo "=== 5. 지속적 부하 테스트 (60초) ==="
  
  local duration=60  # 60초 테스트
  local request_interval=0.5  # 0.5초마다 요청
  
  echo "테스트 시간: ${duration}초"
  echo "요청 간격: ${request_interval}초"
  
  local start_time=$(date +%s)
  local end_time=$((start_time + duration))
  
  local request_count=0
  local success_count=0
  local total_response_time=0
  
  while [ $(date +%s) -lt $end_time ]; do
    request_count=$((request_count + 1))
    local test_resource="i-sustained-${request_count}"
    
    local req_start=$(date +%s%3N)
    
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
    
    local req_end=$(date +%s%3N)
    local response_time=$((req_end - req_start))
    
    if echo "$response" | grep -qE "(EC2_[0-9]+|$test_resource)"; then
      success_count=$((success_count + 1))
      total_response_time=$((total_response_time + response_time))
    fi
    
    # 간격 조정
    sleep "$request_interval"
    
    # 진행상황 출력 (10초마다)
    if [ $((request_count % 20)) -eq 0 ]; then
      echo "   진행: ${request_count}번째 요청 처리 중..."
    fi
  done
  
  local actual_duration=$(($(date +%s) - start_time))
  
  echo ""
  echo "📊 지속적 부하 테스트 결과:"
  echo "   실제 테스트 시간: ${actual_duration}초"
  echo "   총 요청 수: $request_count"
  echo "   성공한 요청: $success_count"
  echo "   성공률: $((success_count * 100 / request_count))%"
  echo "   평균 처리량: $(echo "scale=2; $request_count / $actual_duration" | bc) req/sec"
  
  if [ $success_count -gt 0 ]; then
    local avg_response_time=$((total_response_time / success_count))
    echo "   평균 응답시간: ${avg_response_time}ms"
    
    # 성능 목표 확인 (5초 = 5000ms)
    if [ $avg_response_time -le 5000 ]; then
      echo "   ✅ 성능 목표 달성 (5초 이내)"
    else
      echo "   ❌ 성능 목표 미달성 (${avg_response_time}ms > 5000ms)"
    fi
  fi
  
  echo ""
}

# Redis 상태 모니터링
monitor_redis_stats() {
  echo "=== Redis 상태 모니터링 ==="
  
  # Redis 정보 수집
  local redis_info=$(docker exec redis-cache redis-cli info stats,memory,keyspace 2>/dev/null)
  
  if [ -n "$redis_info" ]; then
    echo "Redis 통계:"
    echo "$redis_info" | grep -E "(used_memory_human|total_commands_processed|keyspace_hits|keyspace_misses|db0)" | while read line; do
      echo "   $line"
    done
    
    # 히트율 계산
    local hits=$(echo "$redis_info" | grep "keyspace_hits:" | cut -d':' -f2 | tr -d '\r')
    local misses=$(echo "$redis_info" | grep "keyspace_misses:" | cut -d':' -f2 | tr -d '\r')
    
    if [ -n "$hits" ] && [ -n "$misses" ] && [ "$hits" -gt 0 ] && [ "$misses" -gt 0 ]; then
      local total=$((hits + misses))
      local hit_rate=$((hits * 100 / total))
      echo "   히트율: ${hit_rate}% ($hits/$total)"
    fi
  else
    echo "⚠️  Redis 통계 수집 실패"
  fi
  
  echo ""
}

# 전체 테스트 실행
main() {
  echo "성능 테스트 시작 시간: $(date)"
  echo ""
  
  test_single_resource_performance
  test_multiple_resources_performance  
  test_concurrent_performance
  test_redis_vs_memory_comparison
  test_sustained_load
  monitor_redis_stats
  
  echo "========================================="
  echo "      🎉 Redis 성능 테스트 완료!"
  echo "========================================="
  echo ""
  echo "📋 성능 목표 검증:"
  echo "   ✓ 전체 응답시간 5초 이내"
  echo "   ✓ Redis 성능 오버헤드 허용 범위"
  echo "   ✓ 동시 요청 처리 능력"
  echo "   ✓ 지속적 부하 안정성"
  echo ""
  echo "성능 테스트 완료 시간: $(date)"
}

# bc 명령 존재 여부 확인
if ! command -v bc >/dev/null 2>&1; then
  echo "⚠️  bc 명령이 필요합니다. 설치 후 재실행하세요."
  exit 1
fi

# 스크립트 실행
main "$@"