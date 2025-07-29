# Simple Logger Plugin for Kong

간단한 요청/응답 로깅을 위한 Kong 플러그인입니다.

## 기능

- 요청 메서드, 경로, 헤더 로깅
- 응답 상태 코드 및 헤더 로깅
- 응답 본문 미리보기 (첫 200자)
- 민감한 헤더 자동 마스킹 (Authorization, X-API-Key 등)
- JSON 형식의 구조화된 로깅
- 파일 로깅 지원 (옵션)

## 설치

1. 플러그인 파일을 Kong 플러그인 디렉토리에 복사:
```bash
cp -r plugins/simple-logger /usr/local/share/lua/5.1/kong/plugins/
```

2. Kong 설정에서 플러그인 활성화:
```yaml
plugins:
  - name: simple-logger
    service: your-service-name
    config:
      body_preview_size: 200
      log_headers: true
      log_request_body: false
      log_file: /tmp/simple-logger.log
```

## 설정 옵션

| 옵션 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `body_preview_size` | integer | 200 | 응답 본문 미리보기 최대 문자 수 |
| `log_headers` | boolean | true | 헤더 로깅 여부 |
| `log_request_body` | boolean | false | 요청 본문 로깅 여부 (POST만) |
| `log_file` | string | null | 로그 파일 경로 (옵션) |
| `sensitive_headers` | array | ["authorization", "x-api-key", "cookie", "set-cookie"] | 마스킹할 헤더 목록 |

## 로그 형식

```json
{
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": 1635360000.123,
  "request": {
    "method": "POST",
    "path": "/v1/messages",
    "headers": {
      "content-type": "application/json",
      "authorization": "***masked***"
    },
    "client_ip": "192.168.1.100"
  },
  "response": {
    "status": 200,
    "headers": {
      "content-type": "application/json"
    },
    "body_preview": "{\"id\":\"msg_123\",\"content\":[{\"type\":\"text\",\"text\":\"Hello! How can I help you today?\"}],\"model\":\"claude-3-5-sonnet... (truncated)",
    "latency_ms": 1234.56
  },
  "upstream_latency": "1200",
  "proxy_latency": "34"
}
```

## 사용 예시

### 기본 설정
```yaml
plugins:
  - name: simple-logger
    service: anthropic-api
```

### 상세 로깅 설정
```yaml
plugins:
  - name: simple-logger
    service: anthropic-api
    config:
      body_preview_size: 500
      log_headers: true
      log_request_body: true
      log_file: /var/log/kong/simple-logger.log
```

### 최소 로깅 설정
```yaml
plugins:
  - name: simple-logger
    service: anthropic-api
    config:
      body_preview_size: 100
      log_headers: false
      log_request_body: false
```

## 성능 고려사항

- 응답 본문을 버퍼링하므로 대용량 응답에서는 메모리 사용량이 증가할 수 있습니다
- `body_preview_size`를 적절히 설정하여 메모리 사용량을 제한하세요
- 파일 로깅 (`log_file`) 사용 시 I/O 오버헤드가 발생할 수 있습니다

## 디버깅

로그가 제대로 출력되지 않는 경우:

1. Kong 로그 레벨 확인:
```bash
kong start --log-level=info
```

2. 플러그인 로드 확인:
```bash
curl http://localhost:8001/plugins
```

3. 로그 파일 권한 확인:
```bash
ls -la /tmp/simple-logger.log
```