# 🚀 Kong AWS Masking 실시간 이벤트 구독 - 빠른 시작 가이드

**대상**: 외부 Node.js TypeScript 시스템 개발자
**목적**: Kong AWS Masking 실시간 이벤트를 구독하여 모니터링 및 알림 구현

## 📋 사전 요구사항

### 1. 기술 스택
- Node.js 18+ 
- TypeScript 4.5+
- Redis 클라이언트 접근 권한

### 2. 네트워크 접근성
- Kong Redis 서버 (기본: localhost:6379)에 접근 가능
- Redis 패스워드 필요시 사전 확보

## ⚡ 5분 빠른 설정

### 1단계: 프로젝트 설정
```bash
# 새 프로젝트 생성 (기존 프로젝트면 생략)
mkdir kong-event-monitor
cd kong-event-monitor
npm init -y

# TypeScript 및 의존성 설치
npm install typescript @types/node ts-node nodemon
npm install ioredis @types/ioredis winston dotenv

# TypeScript 설정
npx tsc --init
```

### 2단계: 파일 복사
```bash
# 이 가이드의 파일들을 프로젝트에 복사
cp kong-events.types.ts ./src/
cp KongEventSubscriber.ts ./src/
cp example-usage.ts ./src/
cp external-system.env.example ./.env
```

### 3단계: 환경 설정
```bash
# .env 파일 편집
nano .env

# 최소 필수 설정:
KONG_REDIS_HOST=localhost
KONG_REDIS_PORT=6379
KONG_REDIS_PASSWORD=your-kong-redis-password
ENABLE_MASKING_EVENTS=true
ENABLE_UNMASKING_EVENTS=true
LOG_LEVEL=info
```

### 4단계: 실행
```bash
# TypeScript 컴파일 및 실행
npx ts-node src/example-usage.ts

# 또는 개발 모드
npx nodemon src/example-usage.ts
```

### 5단계: 확인
```bash
# Kong에서 마스킹 작업 수행시 실시간 로그 확인
# 다른 터미널에서 Kong 테스트
curl -X POST http://localhost:8000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: test-key" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"EC2 instance i-1234567890abcdef0"}]}'
```

## 🎯 실행 결과 예시

```bash
🚀 Starting Kong Event Subscriber...
📋 Configuration: {
  redis: { host: 'localhost', port: 6379, db: 0 },
  channels: { masking: true, unmasking: true, alerts: true, metrics: false }
}
🔌 Connecting to Kong Redis...
📡 Subscribed to Kong channels: { channels: ['aws-masker:events:masking', 'aws-masker:events:unmasking'], count: 2 }
✅ Successfully connected to Kong Redis and subscribed to channels
✅ Kong Event Subscriber started successfully

# Kong에서 마스킹 작업 수행시:
🎯 Masking Event: {
  eventId: 'mask_1738123456_12345',
  requestId: 'req-abc-123',
  success: true,
  patternsApplied: 1,
  processingTime: '45ms',
  requestSize: 256
}
🎯 Custom Masking Handler: { requestId: 'req-abc-123', success: true, patterns: 1, time: 45 }
💾 Saving masking event to database: mask_1738123456_12345
```

## 🔧 커스터마이징

### 이벤트 핸들러 수정
```typescript
// src/example-usage.ts에서 핸들러 수정
const handlers: EventHandlers = {
  onMaskingEvent: async (event) => {
    // 사용자 정의 로직 추가
    console.log('우리 시스템에서 마스킹 이벤트 처리:', event.event_id);
    
    // 데이터베이스에 저장
    await yourDatabase.saveMaskingEvent(event);
    
    // 마스킹 실패시 알림
    if (!event.success) {
      await yourAlertSystem.sendAlert(`마스킹 실패: ${event.request_id}`);
    }
  },

  onSecurityAlert: async (alert) => {
    // 보안 알림 처리
    await yourSecurityTeam.notify(alert);
  }
};
```

### 채널 선택적 구독
```bash
# .env에서 필요한 채널만 활성화
ENABLE_MASKING_EVENTS=true      # 마스킹 이벤트
ENABLE_UNMASKING_EVENTS=false   # 언마스킹 이벤트 (비활성화)
ENABLE_ALERT_EVENTS=true        # 보안 알림
ENABLE_METRICS_EVENTS=false     # 성능 메트릭 (비활성화)
```

## 🏥 모니터링 및 관리

### 헬스체크 API
```bash
# 서비스 상태 확인
curl http://localhost:3001/health

# 응답 예시:
{
  "status": "healthy",
  "details": {
    "connected": true,
    "stats": {
      "totalEvents": 150,
      "maskingEvents": 120,
      "errors": 0,
      "uptime": "3600s"
    }
  }
}
```

### 통계 API
```bash
# 이벤트 통계 확인
curl http://localhost:3001/stats

# 응답 예시:
{
  "totalEvents": 150,
  "maskingEvents": 120,
  "unmaskingEvents": 30,
  "alerts": 0,
  "errors": 0,
  "uptime": "3600s",
  "eventsPerSecond": 0.04,
  "bufferSize": 0,
  "isConnected": true
}
```

## 🚨 트러블슈팅

### 연결 실패
```bash
# Redis 연결 테스트
redis-cli -h localhost -p 6379 -a your-password ping

# Kong Redis 설정 확인
docker logs claude-redis
```

### 이벤트 수신 안됨
```bash
# Kong 플러그인 상태 확인
curl http://localhost:8001/plugins | grep aws-masker

# Kong 로그 확인
docker logs claude-kong | grep "EVENT_PUBLISHER"

# Redis 채널 확인
redis-cli -h localhost -p 6379 -a your-password
> PUBSUB CHANNELS aws-masker*
```

### 성능 이슈
```bash
# 버퍼 크기 조정
EVENT_BUFFER_SIZE=2000
BATCH_PROCESS_SIZE=100
PROCESS_INTERVAL_MS=500
```

## 📧 지원 및 문의

### 체크리스트
- [ ] Redis 연결 가능한가요?
- [ ] Kong이 정상 실행 중인가요?
- [ ] 환경 변수가 올바르게 설정되었나요?
- [ ] TypeScript 컴파일 오류가 없나요?

### 일반적인 오류
1. **ECONNREFUSED**: Redis 서버 연결 실패 → Redis 서버 상태 확인
2. **AUTH failed**: Redis 패스워드 오류 → .env의 KONG_REDIS_PASSWORD 확인
3. **No events received**: Kong 플러그인 미작동 → Kong 설정 확인

---

**성공적인 연동 완료시 Kong의 모든 마스킹 작업이 실시간으로 외부 시스템에 전달됩니다! 🎉**