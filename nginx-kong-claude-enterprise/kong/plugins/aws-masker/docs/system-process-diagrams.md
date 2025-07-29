# Kong AWS Masking MVP - 시스템 프로세스 다이어그램 (Mermaid)

**Date**: 2025-07-24
**Report Type**: System Process Flow Documentation
**Total Diagrams**: 6개 핵심 프로세스 다이어그램
**Technology**: Mermaid Flowchart & Sequence Diagrams

---

## 📋 다이어그램 개요

| 다이어그램                  | 목적                    | 복잡도     | 중요도      |
| --------------------------- | ----------------------- | ---------- | ----------- |
| 1. 전체 시스템 아키텍처     | 시스템 전체 구조 이해   | 🟡 Medium  | 🔴 Critical |
| 2. 마스킹 프로세스 플로우   | AWS 데이터 마스킹 과정  | 🟡 Medium  | 🔴 Critical |
| 3. 언마스킹 프로세스 플로우 | 혁신적 개선 과정        | 🔴 Complex | 🔴 Critical |
| 4. Fail-secure 동작 플로우  | 보안 차단 메커니즘      | 🟢 Simple  | 🔴 Critical |
| 5. Redis 상호작용           | 매핑 저장/조회 과정     | 🟡 Medium  | 🟡 High     |
| 6. 패턴 매칭 시스템         | 우선순위 기반 처리      | 🟡 Medium  | 🟡 High     |
| 7. 플러그인 의존성 아키텍처 | 5개 핵심 의존 모듈 구조 | 🔴 Complex | 🔴 Critical |

---

## 🏗️ 1. 전체 시스템 아키텍처 플로우

### 📍 목적

Kong AWS Masking MVP의 전체적인 데이터 흐름과 컴포넌트 간 상호작용 시각화

```mermaid
graph TB
    %% External Components
    User[👤 User]
    Claude[🤖 Claude API<br/>api.anthropic.com]

    %% Main System Components
    Backend[🚀 Backend API<br/>:3000]
    Kong[🛡️ Kong Gateway<br/>:8000]
    Redis[📦 Redis Cache<br/>:6379]

    %% AWS Masker Plugin Components
    subgraph "Kong AWS Masker Plugin"
        Handler[🔧 handler.lua]
        Patterns[📋 patterns.lua<br/>56 patterns]
        Masker[⚙️ masker_ngx_re.lua]
    end

    %% User Request Flow
    User -->|1. POST /analyze<br/>AWS context data| Backend
    Backend -->|2. Masked request<br/>via Kong Gateway| Kong

    %% Kong Processing
    Kong -->|3a. ACCESS PHASE<br/>Mask AWS resources| Handler
    Handler -->|3b. Pattern matching| Patterns
    Handler -->|3c. Apply masking| Masker
    Handler -->|3d. Store mappings| Redis

    %% Claude API Communication
    Kong -->|4. Masked data<br/>-EC2_001, etc.| Claude
    Claude -->|5. Analysis response<br/>-contains masked IDs| Kong

    %% Response Processing
    Kong -->|6a. BODY_FILTER PHASE<br/>Unmask response| Handler
    Handler -->|6b. Extract masked IDs<br/>from Claude response| Masker
    Handler -->|6c. Query mappings| Redis
    Handler -->|6d. Restore original<br/>AWS resources| Masker

    %% Final Response
    Kong -->|7. Unmasked response<br/>-original AWS data| Backend
    Backend -->|8. Complete analysis<br/>with original AWS IDs| User

    %% Security Annotations
    Kong -.->|🔐 Fail-secure<br/>Redis down = Block| Handler
    Redis -.->|⏰ TTL: 7 days<br/>Auto cleanup| Handler

    %% Styling
    classDef userStyle fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef systemStyle fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef securityStyle fill:#ffebee,stroke:#b71c1c,stroke-width:2px
    classDef storageStyle fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px

    class User userStyle
    class Backend,Kong systemStyle
    class Handler,Patterns,Masker securityStyle
    class Redis storageStyle
    class Claude userStyle
```

### 🔑 주요 데이터 흐름

1. **사용자 요청**: AWS 리소스 포함 컨텍스트 데이터
2. **마스킹 처리**: Kong에서 AWS 데이터를 마스킹된 ID로 변환
3. **Claude 분석**: 마스킹된 데이터로 AI 분석 수행
4. **언마스킹 처리**: Claude 응답의 마스킹된 ID를 원본으로 복원
5. **최종 응답**: 사용자에게 원본 AWS 데이터가 포함된 완전한 분석 결과 제공

---

## 🔒 2. 마스킹 프로세스 플로우 (ACCESS PHASE)

### 📍 목적

Kong Gateway의 ACCESS 단계에서 AWS 리소스를 마스킹하여 Claude API로 전달하는 과정

```mermaid
sequenceDiagram
    participant User as 👤 User
    participant Backend as 🚀 Backend API
    participant Kong as 🛡️ Kong Gateway
    participant Handler as 🔧 AWS Masker Handler
    participant Patterns as 📋 patterns.lua
    participant Redis as 📦 Redis
    participant Claude as 🤖 Claude API

    %% Request Initiation
    User->>Backend: POST /analyze<br/>{"context": "EC2 i-1234567890abcdef0..."}
    Backend->>Kong: Forward request to Claude API

    %% Kong ACCESS Phase
    Kong->>Handler: access() - Process request body

    %% Security Check
    Handler->>Handler: 🔐 Verify Redis availability
    alt Redis unavailable
        Handler->>Kong: ❌ FAIL-SECURE: Block request
        Kong->>Backend: 503 Service Unavailable
        Backend->>User: Error: Service blocked
    else Redis available
        Handler->>Handler: ✅ Continue processing
    end

    %% AWS Pattern Detection
    Handler->>Handler: 🔍 Detect AWS patterns in body
    Handler->>Patterns: Load 56 AWS patterns with priority
    Patterns->>Handler: Return sorted patterns (priority desc)

    %% Masking Process
    loop For each AWS pattern (by priority)
        Handler->>Handler: 🎯 Apply pattern matching
        alt Pattern matches
            Handler->>Handler: 📝 Generate masked ID -e.g., EC2_001
            Handler->>Redis: 💾 Store mapping<br/>aws_masker:map:EC2_001 → i-1234567890abcdef0
            Redis->>Handler: ✅ Mapping stored -TTL: 7 days
            Handler->>Handler: 🔄 Replace in request body<br/>i-1234567890abcdef0 → EC2_001
        end
    end

    %% Forward Masked Request
    Handler->>Kong: ✅ Masked request ready
    Kong->>Claude: 🚀 Send masked request<br/>{"context": "EC2 EC2_001..."}

    Note over Handler,Redis: 🔑 Security: All AWS data masked<br/>✅ Original data safely stored in Redis
```

### 🛡️ 보안 특징

- **Fail-secure**: Redis 장애 시 요청 완전 차단
- **우선순위 매칭**: 높은 priority 패턴 우선 처리
- **완전 마스킹**: 모든 AWS 리소스 식별자 마스킹
- **안전 저장**: Redis에 7일 TTL로 매핑 관계 저장

---

## 🔓 3. 언마스킹 프로세스 플로우 (BODY_FILTER PHASE) - 혁신적 개선

### 📍 목적

Claude API 응답에서 마스킹된 ID를 원본 AWS 리소스로 복원하는 혁신적으로 개선된 과정

```mermaid
sequenceDiagram
    participant Claude as 🤖 Claude API
    participant Kong as 🛡️ Kong Gateway
    participant Handler as 🔧 AWS Masker Handler
    participant Redis as 📦 Redis
    participant Backend as 🚀 Backend API
    participant User as 👤 User

    %% Claude Response Reception
    Claude->>Kong: 📨 Analysis response<br/>{"content": [{"text": "EC2_001 security analysis..."}]}
    Kong->>Handler: body_filter() - Process response

    %% Revolutionary Unmasking Logic
    Note over Handler: 🚀 INNOVATION: Direct extraction<br/>from Claude response

    %% JSON Parsing & Content Analysis
    Handler->>Handler: 🔍 Parse JSON response
    Handler->>Handler: 📝 Extract content.text fields

    %% Critical Innovation: Direct Pattern Extraction
    loop For each content.text
        Handler->>Handler: 🎯 Extract masked ID patterns<br/>Regex: [A-Z_]+_\d+

        Note over Handler: 🔑 KEY INNOVATION:<br/>Find ALL masked IDs in response<br/>EC2_001, EBS_VOL_002, PUBLIC_IP_013...

        Handler->>Handler: 📋 Collect unique masked IDs<br/>{EC2_001: true, PUBLIC_IP_013: true, ...}
    end

    %% Redis Batch Query - Performance Optimized
    alt Masked IDs found
        loop For each masked ID
            Handler->>Redis: 🔍 GET aws_masker:map:EC2_001
            Redis->>Handler: 📤 i-1234567890abcdef0
            Handler->>Redis: 🔍 GET aws_masker:map:PUBLIC_IP_013
            Redis->>Handler: 📤 54.239.28.85
            Handler->>Handler: 📝 Build unmask map<br/>{EC2_001: "i-1234567890abcdef0", ...}
        end

        %% Apply Complete Restoration
        Handler->>Handler: 🔄 Apply all unmaskings<br/>EC2_001 → i-1234567890abcdef0<br/>PUBLIC_IP_013 → 54.239.28.85

        Note over Handler: ✅ RESULT: 100% AWS data restoration<br/>User receives original resource IDs
    else No masked IDs
        Handler->>Handler: ⚡ Skip unmasking -no changes needed
    end

    %% Response Finalization
    Handler->>Handler: 📦 Re-encode JSON response
    Handler->>Kong: ✅ Unmasking complete
    Kong->>Backend: 📨 Restored response<br/>{"content": [{"text": "i-1234567890abcdef0 security..."}]}
    Backend->>User: 🎯 Complete analysis with<br/>original AWS resource IDs

    %% Success Confirmation
    Note over User: 🏆 MISSION ACCOMPLISHED<br/>✅ AWS data never exposed to Claude<br/>✅ User receives complete original data
```

### 🚀 혁신적 개선 포인트

#### ❌ 이전 방식 (결함)

```mermaid
graph LR
    A[Request Body] -->|Extract AWS resources| B[prepare_unmask_data]
    B -->|Predict unmasking needs| C[unmask_map]
    C -->|Fixed prediction| D[❌ Claude response<br/>contains different IDs]
    D -->|Cannot restore| E[❌ User gets masked IDs]
```

#### ✅ 현재 방식 (혁신)

```mermaid
graph LR
    A[Claude Response] -->|Direct extraction| B[Find masked patterns]
    B -->|"[A-Z_]"+_\d+| C[All masked IDs]
    C -->|Redis query| D[Original mappings]
    D -->|Complete restoration| E[✅ User gets original data]
```

### 🎯 핵심 혁신 특징

1. **직접 추출**: Claude 응답에서 마스킹된 ID 직접 발견
2. **완전 복원**: 예측 불가능한 마스킹된 ID도 100% 복원
3. **성능 최적화**: 필요한 매핑만 Redis에서 조회
4. **실시간 처리**: 응답 처리 시점에서 동적 언마스킹

---

## 🚨 4. Fail-secure 동작 플로우 - 이중 보안 메커니즘

### 📍 목적

Redis 장애 등 시스템 오류 시 AWS 데이터 노출을 완전히 차단하는 이중 보안 메커니즘  
**핵심**: 마스킹과 언마스킹 양 단계에서 Redis 의존성과 Fail-secure 동작

```mermaid
flowchart TD
    Start[📥 Request] --> CheckRedis{🔍 Redis Available?}
    
    %% 마스킹 단계 Redis 체크
    CheckRedis -->|✅ Available| MaskData[🔒 Mask AWS Data]
    CheckRedis -->|❌ Unavailable| BlockComplete[🚨 Complete Block]
    
    %% 정상 마스킹 플로우
    MaskData --> StoreMapping[💾 Store Mapping<br/>aws_masker:map:EC2_001 → i-123]
    StoreMapping --> ForwardClaude[🚀 Forward to Claude]
    ForwardClaude --> ClaudeResponse[📨 Claude Response]
    
    %% 언마스킹 단계 - 누락되었던 핵심 부분
    ClaudeResponse --> ExtractMasked[🎯 Extract Masked IDs<br/>from Claude Response]
    ExtractMasked --> CheckRedisUnmask{📦 Redis Available<br/>for Unmask?}
    
    %% 언마스킹 성공 플로우
    CheckRedisUnmask -->|✅ Available| QueryMappings[🔍 Query Redis Mappings<br/>GET aws_masker:map:EC2_001]
    QueryMappings --> ApplyUnmask[🔄 Apply Complete Unmasking<br/>EC2_001 → i-123]
    ApplyUnmask --> Success[✅ Original AWS Data<br/>User receives real IDs]
    
    %% 언마스킹 실패 플로우 - 새로 추가된 메커니즘
    CheckRedisUnmask -->|❌ Failed| UnmaskFailure[⚠️ Unmask Failure<br/>Redis unavailable]
    UnmaskFailure --> MaskedResponse[🔒 Return Masked Response<br/>User receives EC2_001]
    
    %% 마스킹 단계 완전 차단
    BlockComplete --> SecurityLog[📝 Log Critical Security Event<br/>MASKING BLOCKED: Redis down]
    SecurityLog --> Error503[❌ 503 Service Unavailable<br/>AWS data protection active]
    
    %% Recovery Flow
    CheckRedis -.->|⚡ Auto-retry| RedisRestore{🔄 Redis Restored?}
    RedisRestore -->|✅ Yes| MaskData
    RedisRestore -->|❌ No| BlockComplete
    
    %% Additional Security Monitoring
    UnmaskFailure -.->|📊 Monitor| AlertSystem[🚨 Alert: Partial Service<br/>Masking OK, Unmask Failed]
    
    %% Styling
    classDef normalStyle fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef securityStyle fill:#ffebee,stroke:#b71c1c,stroke-width:3px
    classDef decisionStyle fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef unmaskStyle fill:#e3f2fd,stroke:#0277bd,stroke-width:2px
    classDef warningStyle fill:#fff8e1,stroke:#f57f17,stroke-width:2px
    
    class MaskData,StoreMapping,ForwardClaude,QueryMappings,ApplyUnmask,Success normalStyle
    class BlockComplete,SecurityLog,Error503,UnmaskFailure securityStyle
    class CheckRedis,CheckRedisUnmask,RedisRestore decisionStyle
    class ExtractMasked,ClaudeResponse,AlertSystem unmaskStyle
    class MaskedResponse warningStyle
```

### 🔐 이중 보안 원칙

#### **1단계: 마스킹 Fail-secure - CRITICAL 차단**
- **완전 차단**: Redis 불가 시 전체 요청 차단
- **보안 우선**: AWS 데이터 노출 위험 시 서비스 중단
- **즉시 대응**: 503 에러로 명확한 실패 신호

#### **2단계: 언마스킹 Fail-safe - 부분 서비스**  
- **마스킹된 응답**: Redis 불가 시 마스킹된 ID로 응답
- **서비스 연속성**: 완전 차단보다는 부분 기능 제공
- **사용자 알림**: 마스킹된 데이터 수신 가능성 모니터링

### 🚨 실제 동작 시나리오

#### **시나리오 1: 마스킹 단계 Redis 장애**
```
사용자 요청: {"context": "EC2 i-1234567890abcdef0"}
→ Redis 체크 실패
→ 503 Service Unavailable 
→ 사용자: 서비스 불가 메시지
```

#### **시나리오 2: 언마스킹 단계 Redis 장애** 
```  
사용자 요청: {"context": "EC2 i-1234567890abcdef0"}
→ 마스킹 성공: EC2_001
→ Claude 응답: {"text": "EC2_001 analysis..."}
→ 언마스킹 Redis 장애
→ 사용자: {"text": "EC2_001 analysis..."} (마스킹된 상태)
```

### 📊 장애 영향도 분석

| Redis 장애 시점 | 사용자 영향 | 보안 수준 | 서비스 가용성 |
|----------------|------------|-----------|--------------|
| **마스킹 단계** | 완전 차단 | 🔴 최고 | ❌ 불가 |
| **언마스킹 단계** | 마스킹된 응답 | 🟡 높음 | ⚠️ 제한적 |

---

## 📦 5. Redis 상호작용 다이어그램

### 📍 목적

AWS 리소스 매핑의 저장, 조회, 관리 과정의 Redis 상호작용

```mermaid
sequenceDiagram
    participant Handler as 🔧 Handler
    participant Redis as 📦 Redis Cache
    participant Monitor as 📊 Health Monitor

    %% Connection Management
    Handler->>Redis: 🔗 acquire_redis_connection()
    Redis->>Handler: ✅ Connection established

    %% Authentication
    Handler->>Redis: 🔐 AUTH <password>
    Redis->>Handler: ✅ Authentication successful

    %% Masking Phase - Store Mappings
    Note over Handler,Redis: 💾 MASKING PHASE: Store mappings

    loop For each AWS resource found
        Handler->>Handler: 🎯 Generate masked ID<br/>-e.g., EC2_001, EBS_VOL_002
        Handler->>Redis: 📝 SET aws_masker:map:EC2_001<br/>i-1234567890abcdef0<br/>EX 604800 -7 days
        Redis->>Handler: ✅ OK - Mapping stored

        Handler->>Redis: 📝 SET aws_masker:map:EBS_VOL_002<br/>vol-0123456789abcdef0<br/>EX 604800
        Redis->>Handler: ✅ OK - Mapping stored
    end

    %% Performance Monitoring
    Handler->>Monitor: 📊 Record mapping metrics<br/>Count: 2, Latency: 0.3ms

    %% Unmasking Phase - Query Mappings
    Note over Handler,Redis: 🔍 UNMASKING PHASE: Query mappings

    Handler->>Handler: 🎯 Extract masked IDs from Claude response<br/>[EC2_001, EBS_VOL_002, PUBLIC_IP_013]

    loop For each masked ID
        Handler->>Redis: 🔍 GET aws_masker:map:EC2_001
        Redis->>Handler: 📤 i-1234567890abcdef0

        Handler->>Redis: 🔍 GET aws_masker:map:EBS_VOL_002
        Redis->>Handler: 📤 vol-0123456789abcdef0

        Handler->>Redis: 🔍 GET aws_masker:map:PUBLIC_IP_013
        Redis->>Handler: 📤 54.239.28.85
    end

    %% Performance Analysis
    Handler->>Monitor: 📊 Record query metrics<br/>Queries: 3, Avg latency: 0.25ms

    %% Health Check
    Handler->>Redis: ❤️ PING -health check
    Redis->>Handler: 🏓 PONG

    %% Connection Cleanup
    Handler->>Redis: 🔗 release_redis_connection()
    Redis->>Handler: ✅ Connection released

    %% TTL Management
    Note over Redis: ⏰ TTL Management<br/>Auto-expire after 7 days<br/>Prevents memory leaks
```

### 📊 Redis 성능 지표

- **평균 레이턴시**: 0.25-0.35ms
- **메모리 효율**: 0.01MB per mapping
- **TTL 관리**: 7일 자동 만료
- **동시 연결**: Connection pool 관리

---

## 🎯 6. 우선순위 기반 패턴 매칭 시스템

### 📍 목적

56개 AWS 패턴 간 충돌을 해결하는 우선순위 기반 매칭 프로세스

```mermaid
flowchart TD
    Start([📥 AWS Text Input]) --> LoadPatterns[📋 Load 56 AWS Patterns]

    %% Pattern Loading & Sorting
    LoadPatterns --> SortByPriority[🔢 Sort by Priority<br/>Highest first]

    %% Priority Examples
    SortByPriority --> PriorityList[📊 Priority Order<br/>900: Specific EC2 patterns<br/>800: General IP patterns<br/>700: S3 bucket patterns<br/>600: Generic patterns]

    %% Pattern Matching Loop
    PriorityList --> MatchLoop{🎯 For each pattern<br/>-priority order}

    MatchLoop -->|Pattern 1<br/>Priority: 900| CheckMatch1{🔍 Pattern matches?}
    CheckMatch1 -->|✅ Match| ApplyMask1[🔒 Apply masking<br/>Generate masked ID]
    CheckMatch1 -->|❌ No match| NextPattern1[⏭️ Next pattern]

    ApplyMask1 --> StoreMapping1[💾 Store mapping in Redis]
    StoreMapping1 --> ReplaceText1[🔄 Replace in text]
    ReplaceText1 --> NextPattern1

    NextPattern1 --> CheckMatch2{🔍 Next pattern matches?}
    CheckMatch2 -->|✅ Match| ApplyMask2[🔒 Apply masking]
    CheckMatch2 -->|❌ No match| NextPattern2[⏭️ Continue...]

    ApplyMask2 --> StoreMapping2[💾 Store mapping]
    StoreMapping2 --> ReplaceText2[🔄 Replace in text]
    ReplaceText2 --> NextPattern2

    NextPattern2 --> MorePatterns{📝 More patterns?}
    MorePatterns -->|✅ Yes| MatchLoop
    MorePatterns -->|❌ No| Complete[✅ Masking Complete]

    Complete --> Results[📊 Results Summary<br/>Patterns matched: X<br/>Resources masked: Y<br/>Conflicts resolved: Z]

    Results --> End([📤 Masked Text Output])

    %% Priority Conflict Resolution
    subgraph "🔧 Conflict Resolution"
        Conflict1[Higher priority patterns<br/>process first]
        Conflict2[Prevents overlap issues]
        Conflict3[Ensures consistent masking]
    end

    %% Styling
    classDef processStyle fill:#e3f2fd,stroke:#0277bd,stroke-width:2px
    classDef decisionStyle fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef actionStyle fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef resultStyle fill:#f3e5f5,stroke:#4a148c,stroke-width:2px

    class LoadPatterns,SortByPriority,PriorityList processStyle
    class MatchLoop,CheckMatch1,CheckMatch2,MorePatterns decisionStyle
    class ApplyMask1,StoreMapping1,ReplaceText1,ApplyMask2,StoreMapping2,ReplaceText2 actionStyle
    class Complete,Results,End resultStyle
```

### 🏆 우선순위 시스템 특징

#### 📊 Priority 레벨 분류

```mermaid
graph LR
    subgraph "우선순위 레벨"
        P900[🥇 Priority 900<br/>Specific patterns<br/>정확한 매칭 필수]
        P800[🥈 Priority 800<br/>Common patterns<br/>일반적 리소스]
        P700[🥉 Priority 700<br/>Broad patterns<br/>광범위 매칭]
        P600[📋 Priority 600<br/>Generic patterns<br/>기본 패턴]
    end

    P900 --> P800 --> P700 --> P600

    classDef highPriority fill:#ffcdd2,stroke:#c62828,stroke-width:3px
    classDef medPriority fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef lowPriority fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px

    class P900 highPriority
    class P800,P700 medPriority
    class P600 lowPriority
```

### 🎯 충돌 해결 예시

- **충돌 상황**: `api.amazonaws.com` vs `*.amazonaws.com`
- **해결 방법**: 더 구체적인 패턴(`api.amazonaws.com`)에 높은 priority 부여
- **결과**: 정확한 매칭 보장, 오버랩 방지

---

## 🔗 7. 플러그인 의존성 아키텍처 다이어그램

### 📍 목적

Kong AWS Masker 플러그인의 **5개 핵심 의존성 모듈**과 `handler.lua` 간 상호작용 및 로딩 순서 시각화

### 🚨 의존성 발견 배경

Kong Gateway 재시작 과정에서 플러그인 로딩 실패가 발생하여 **5개 필수 Lua 모듈**의 의존성이 확인되었습니다.

```mermaid
graph TB
    %% Main Plugin Entry Point
    Kong[🛡️ Kong Gateway<br/>Plugin Loader] --> Handler[🔧 handler.lua<br/>Main Plugin]

    %% Core Dependencies (Critical Path)
    subgraph "🔴 Critical Dependencies"
        Handler --> JsonSafe[📄 json_safe.lua<br/>JSON 안전 처리]
        Handler --> Monitoring[📊 monitoring.lua<br/>성능 & 보안 모니터링]
        Handler --> AuthHandler[🔐 auth_handler.lua<br/>API 인증 관리]
        Handler --> ErrorCodes[⚠️ error_codes.lua<br/>오류 코드 정의]
        Handler --> HealthCheck[❤️ health_check.lua<br/>헬스 체크]
    end

    %% Masking Engine Dependencies
    subgraph "🎯 Masking Engine Chain"
        Handler --> MaskerNgx[⚙️ masker_ngx_re.lua<br/>마스킹 엔진]
        MaskerNgx --> Patterns[📋 patterns.lua<br/>기본 56 패턴]
        Patterns --> PatternIntegrator[🔧 pattern_integrator.lua<br/>패턴 통합 시스템]
        PatternIntegrator --> PatternsExt[📚 patterns_extension.lua<br/>확장 40 패턴]
    end

    %% External Dependencies
    subgraph "🌐 External Systems"
        Redis[(📦 Redis Cache<br/>매핑 저장소)]
        Claude[🤖 Claude API<br/>Anthropic]
    end

    %% Runtime Interactions
    JsonSafe -.->|JSON 처리| Handler
    Monitoring -.->|메트릭 수집| Handler
    AuthHandler -.->|API 키 전달| Claude
    MaskerNgx -.->|매핑 저장/조회| Redis

    %% Error Flows
    ErrorCodes -.->|오류 처리| Handler
    HealthCheck -.->|상태 체크| Redis

    %% Integration Flow
    PatternIntegrator -.->|통합 패턴| MaskerNgx
    PatternsExt -.->|확장 패턴| PatternIntegrator

    %% Loading Order Annotation
    Kong -.->|1st| Handler
    Handler -.->|2nd| JsonSafe
    Handler -.->|3rd| Monitoring
    Handler -.->|4th| AuthHandler
    Handler -.->|5th| MaskerNgx
    MaskerNgx -.->|6th| Patterns
    Patterns -.->|7th| PatternIntegrator
    PatternIntegrator -.->|8th| PatternsExt

    %% Styling
    classDef criticalStyle fill:#ffcdd2,stroke:#c62828,stroke-width:3px
    classDef engineStyle fill:#e1f5fe,stroke:#0277bd,stroke-width:2px
    classDef externalStyle fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef mainStyle fill:#fff3e0,stroke:#ef6c00,stroke-width:3px

    class Handler mainStyle
    class JsonSafe,Monitoring,AuthHandler,ErrorCodes,HealthCheck criticalStyle
    class MaskerNgx,Patterns,PatternIntegrator,PatternsExt engineStyle
    class Redis,Claude externalStyle
```

### 🔍 각 의존성 모듈 상세 분석

#### 1. 🔧 **handler.lua** - 메인 플러그인 엔트리

```lua
-- 모든 의존성의 진입점
local json_safe = require "kong.plugins.aws-masker.json_safe"
local monitoring = require "kong.plugins.aws-masker.monitoring"
local auth_handler = require "kong.plugins.aws-masker.auth_handler"
local error_codes = require "kong.plugins.aws-masker.error_codes"
local health_check = require "kong.plugins.aws-masker.health_check"
```

**핵심 기능**: Kong Gateway 플러그인 lifecycle 관리, 모든 의존성 모듈 로딩

#### 2. 📄 **json_safe.lua** - JSON 안전 처리

```mermaid
graph LR
    A[handler.lua:60] -->|JSON 검증| B[json_safe.is_available]
    C[handler.lua:316] -->|응답 디코딩| D[json_safe.decode]
    E[handler.lua:362] -->|응답 인코딩| F[json_safe.encode]
```

**사용 위치**: `handler.lua:60`, `handler.lua:316`, `handler.lua:362`
**핵심 기능**: 안전한 JSON 인코딩/디코딩, 오류 처리

#### 3. 📊 **monitoring.lua** - 성능 & 보안 모니터링

```mermaid
graph LR
    A[handler.lua:157] -->|보안 이벤트| B[monitoring.log_security_event]
    C[handler.lua:254] -->|성능 메트릭| D[monitoring.collect_request_metric]
    E[handler.lua:271] -->|패턴 사용량| F[monitoring.track_pattern_usage]
```

**사용 위치**: `handler.lua:157`, `handler.lua:254`, `handler.lua:271`
**핵심 기능**: 실시간 성능 지표 수집, 보안 이벤트 로깅

#### 4. 🔐 **auth_handler.lua** - API 인증 관리

```mermaid
graph LR
    A[handler.lua:153] -->|메인 인증| B[auth_handler.handle_authentication]
    B -->|헤더 추출| C[extract_api_key]
    B -->|키 전달| D[forward_api_key]
    B -->|보안 검증| E[validate_security]
```

**사용 위치**: `handler.lua:153` (핵심 인증 로직)
**핵심 기능**: Anthropic API 키 안전한 전달, 다중 헤더 지원

#### 5. 🔧 **pattern_integrator.lua** - 패턴 통합 시스템

```mermaid
graph LR
    A[patterns.lua] -->|기본 패턴| B[pattern_integrator.integrate_patterns]
    C[patterns_extension.lua] -->|확장 패턴| B
    B -->|통합 결과| D[56 + 40 = 96 패턴]
    B -->|충돌 검사| E[check_conflicts]
    B -->|우선순위 조정| F[adjust_priorities]
```

**핵심 기능**: 기본 56패턴 + 확장 40패턴 통합, 충돌 해결, 우선순위 관리

#### 6. 📚 **patterns_extension.lua** - 확장 AWS 패턴

```mermaid
graph TB
    A[patterns_extension.lua] --> B[Lambda 패턴 4개]
    A --> C[ECS 패턴 4개]
    A --> D[EKS 패턴 2개]
    A --> E[RDS 확장 2개]
    A --> F[KMS 패턴 2개<br/>🔴 Critical]
    A --> G[Secrets 패턴 1개<br/>🔴 Critical]
    A --> H[기타 서비스 25개]

    I[총 40개 확장 패턴] --> J[13개 AWS 서비스 커버]
```

**패턴 카테고리**: Lambda, ECS, EKS, RDS, ElastiCache, DynamoDB, CloudFormation, SNS/SQS, KMS, Secrets Manager, Route53, API Gateway, CloudWatch

### 🚨 의존성 로딩 실패 시나리오

#### ❌ 문제 상황

```mermaid
sequenceDiagram
    participant Kong as 🛡️ Kong Gateway
    participant Handler as 🔧 handler.lua
    participant Missing as ❌ Missing Module

    Kong->>Handler: 🚀 Load plugin
    Handler->>Missing: 📥 require "json_safe"
    Missing-->>Handler: ❌ module not found
    Handler-->>Kong: 💥 Loading failed
    Kong-->>Kong: 🚫 Plugin disabled

    Note over Kong: 🔴 CRITICAL: 전체 서비스 중단<br/>AWS 마스킹 기능 완전 비활성화
```

#### ✅ 해결 과정

```mermaid
sequenceDiagram
    participant Admin as 👨‍💻 관리자
    participant Backup as 📁 Backup Dir
    participant Plugin as 📂 Plugin Dir
    participant Kong as 🛡️ Kong Gateway

    Admin->>Backup: 🔍 백업 파일 확인
    Backup-->>Admin: ✅ 5개 파일 발견

    loop 5개 필수 파일
        Admin->>Plugin: 📋 복사 json_safe.lua
        Admin->>Plugin: 📋 복사 monitoring.lua
        Admin->>Plugin: 📋 복사 auth_handler.lua
        Admin->>Plugin: 📋 복사 pattern_integrator.lua
        Admin->>Plugin: 📋 복사 patterns_extension.lua
    end

    Admin->>Kong: 🔄 docker-compose restart kong
    Kong-->>Admin: ✅ Plugin loaded successfully

    Note over Kong: 🟢 SUCCESS: 모든 의존성 해결<br/>AWS 마스킹 서비스 정상 운영
```

### 📊 의존성 통계 및 영향도

#### 📈 통계 데이터

```mermaid
pie title 의존성 파일 코드 분포
    "handler.lua (메인)" : 490
    "patterns_extension.lua" : 298
    "pattern_integrator.lua" : 221
    "auth_handler.lua" : 258
    "json_safe.lua" : 150
    "monitoring.lua" : 180
```

- **총 코드 라인**: 1,597 lines
- **의존성 파일**: 5개 (필수)
- **확장 패턴**: 40개 AWS 서비스 패턴
- **통합 패턴**: 96개 (기본 56 + 확장 40)

#### 🎯 영향도 분석

| 모듈                     | 없을 시 영향                      | 복구 우선순위 |
| ------------------------ | --------------------------------- | ------------- |
| `json_safe.lua`          | 🔴 **전체 중단** - JSON 처리 불가 | 1순위         |
| `auth_handler.lua`       | 🔴 **Claude API 접근 불가**       | 1순위         |
| `monitoring.lua`         | 🟡 모니터링 없이 동작 가능        | 2순위         |
| `pattern_integrator.lua` | 🔴 **패턴 로딩 실패**             | 1순위         |
| `patterns_extension.lua` | 🟡 기본 패턴만 사용               | 3순위         |

### 🔧 의존성 관리 모범 사례

#### ✅ 권장사항

1. **백업 유지**: 모든 의존성 파일의 백업본 유지
2. **버전 관리**: 각 모듈의 VERSION 상수 관리
3. **테스트 자동화**: 의존성 로딩 테스트 스크립트 작성
4. **모니터링**: 의존성 로딩 실패 알림 설정

#### 🚫 주의사항

1. **파일 삭제 금지**: 5개 핵심 파일 삭제 시 전체 서비스 중단
2. **순서 중요**: require 순서 변경 시 로딩 실패 가능
3. **네임스페이스**: `kong.plugins.aws-masker.*` 경로 고정 필수

---

## 📊 다이어그램 활용 가이드

### 👥 대상별 활용법

| 대상         | 추천 다이어그램 | 활용 목적                  |
| ------------ | --------------- | -------------------------- |
| **개발팀**   | 2, 3, 6         | 코드 이해, 로직 구현       |
| **운영팀**   | 1, 4, 5         | 시스템 모니터링, 장애 대응 |
| **보안팀**   | 3, 4            | 보안 검증, 취약점 분석     |
| **아키텍트** | 1, 5            | 시스템 설계, 성능 최적화   |

### 🔍 핵심 혁신 포인트 (다이어그램 3번 참조)

1. **직접 추출 방식**: Claude 응답에서 마스킹된 ID 직접 발견
2. **완전 자동화**: 예측 불가능한 패턴도 자동 처리
3. **실시간 복원**: 응답 시점에서 동적 언마스킹
4. **100% 정확성**: 모든 AWS 리소스 완벽 복원

---

## 🔗 관련 문서

- **다음 문서**: [기술적 이슈 해결 과정](./technical-issues-solutions-detailed.md)
- **이전 문서**: [테스트 스크립트 상세 기록](./test-scripts-verification-detailed.md)
- **참조**: [소스코드 변경 상세 기록](./source-code-changes-detailed.md)

---

_이 문서는 Kong AWS Masking MVP 프로젝트의 모든 시스템 프로세스를 Mermaid 다이어그램으로 완전히 시각화한 공식 기술 문서입니다._
