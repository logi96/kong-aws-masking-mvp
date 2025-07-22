# Kong DB-less AWS Multi-Resource Masking MVP - 메모리 설정 가이드 (간소화)

## 요약
MVP에서는 복잡한 메모리 관리 대신 충분한 기본 설정으로 시작합니다.

## 1. MVP 메모리 설정

### 1.1 권장 설정
```yaml
# kong.yml
_format_version: "3.0"
_transform: false

# 간단한 메모리 설정
plugins:
  - name: aws-masker
    config:
      # MVP에는 이 정도면 충분
      cache_size: "256m"     # 여유있게 설정
      ttl: 300               # 5분 (3600초는 너무 김)
```

### 1.2 Docker 리소스 설정
```yaml
# docker-compose.yml
services:
  kong:
    image: kong:3.9.0.1
    deploy:
      resources:
        limits:
          memory: 1G    # 충분한 메모리
        reservations:
          memory: 512M  # 최소 보장
```

## 2. 간단한 캐시 구현

### 2.1 MVP용 단순 캐시
```lua
-- handler.lua에 추가
local cache = ngx.shared.masking_cache or {}
local TTL = 300  -- 5분

-- 저장
function save_mapping(key, value)
  cache:set(key, value, TTL)
end

-- 조회
function get_mapping(key)
  return cache:get(key)
end
```

### 2.2 메모리 부족 시 대응
```lua
-- 단순 처리: 오래된 항목 자동 삭제
if not cache:set(key, value, TTL) then
  kong.log.warn("Cache full, clearing old entries")
  cache:flush_expired()  -- 만료된 항목만 삭제
end
```

## 3. MVP에서 제외할 사항

### ❌ 불필요한 복잡성
- 적응형 TTL
- 메모리 압박 모니터링
- 복잡한 정리 알고리즘
- 통계 수집

### ✅ MVP 포커스
- 기본 캐싱만
- 고정 TTL
- 간단한 에러 처리

## 4. 모니터링 (선택사항)

### 4.1 기본 로그만
```lua
-- 필요시 로그 확인
kong.log.info("Cached items: ", cache:free_space())
```

### 4.2 수동 확인
```bash
# Kong Admin API로 상태 확인
curl http://localhost:8001/status
```

## 5. 테스트 시나리오

### 5.1 기본 부하 테스트
```bash
# 간단한 테스트 (복잡한 도구 불필요)
for i in {1..100}; do
  curl -X POST http://localhost:3000/analyze &
done
wait
```

### 5.2 예상 결과
- 100개 동시 요청: 문제 없음
- 메모리 사용: 50% 이하
- 응답 시간: 5초 이내

## 6. 문제 해결

### 메모리 부족 시
1. TTL을 300초 → 120초로 감소
2. 캐시 크기를 256m → 512m로 증가
3. 그래도 문제면 Kong 재시작

```bash
docker-compose restart kong
```

## 7. 결론

MVP에서는:
- **기본 설정으로 충분**: 256MB 캐시, 5분 TTL
- **복잡한 관리 불필요**: 자동 만료로 충분
- **문제 발생 시**: 설정값 조정으로 해결

이 설정으로 수천 개의 마스킹 항목을 처리할 수 있으며, MVP 검증에 충분합니다.

## 8. 다음 단계 (MVP 이후)

MVP 성공 후 필요시:
1. 메모리 사용 패턴 분석
2. 동적 TTL 도입 검토
3. 모니터링 도구 추가

---
*MVP 우선: 작동하는 제품 먼저, 최적화는 나중에*
