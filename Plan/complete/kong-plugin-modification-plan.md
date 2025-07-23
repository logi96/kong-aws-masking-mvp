# Kong Plugin Modification Implementation Plan

## 🔧 Kong 플러그인 수정 계획 (PLUGIN MODIFICATION PLAN)

### 목표 (GOAL)
기존 Kong AWS Masker 플러그인을 확장하여 새로운 패턴 시스템과 컨텍스트 기반 매칭을 지원

### 측정 기준 (METRIC)  
- 기존 5개 패턴 → 15개+ 패턴 확장
- 컨텍스트 기반 매칭 정확도: 95% 이상
- 성능 유지: < 100ms 마스킹 처리
- 하위 호환성: 100% 유지

## 📋 플러그인 구조 수정 계획

### 5.1 기존 파일 구조 개선
현재 구조를 다음과 같이 확장:

```
kong/plugins/aws-masker/
├── handler.lua              # (수정) 메인 핸들러
├── schema.lua               # (수정) 설정 스키마 확장
├── patterns/                # (신규) 패턴 모듈화
│   ├── patterns_v2.lua      # 개선된 기본 패턴
│   ├── vpc_patterns.lua     # VPC 관련 패턴
│   ├── iam_patterns.lua     # IAM 및 ARN 패턴
│   ├── network_storage_patterns.lua  # 네트워크/스토리지 패턴
│   └── loader.lua           # 패턴 로더
├── engine/                  # (신규) 처리 엔진
│   ├── context_matcher.lua  # 컨텍스트 매칭
│   ├── masker_v2.lua        # 마스킹 엔진 v2
│   └── mapping_store.lua    # 매핑 저장소
└── utils/                   # (신규) 유틸리티
    ├── json_parser.lua      # JSON 파싱 유틸
    ├── performance.lua      # 성능 측정
    └── validator.lua        # 값 검증
```

### 5.2 Handler.lua 수정 사항
**파일**: `/kong/plugins/aws-masker/handler.lua`

```lua
local aws_masker = {
    PRIORITY = 1000,
    VERSION = "2.0.0",
}

-- 새로운 엔진 로드
local masker_v2 = require "kong.plugins.aws-masker.engine.masker_v2"
local performance = require "kong.plugins.aws-masker.utils.performance"
local mapping_store = require "kong.plugins.aws-masker.engine.mapping_store"

-- 플러그인 초기화 (새 함수)
function aws_masker:init_worker()
    -- 패턴 로딩 및 컴파일
    masker_v2.initialize()
    
    -- TTL 정리 타이머 시작
    local ttl_timer = kong.timer:at(0, function(premature)
        if premature then return end
        
        -- 매 60초마다 만료된 매핑 정리
        ngx.timer.every(60, function()
            mapping_store.cleanup_expired_mappings(300) -- 5분 TTL
        end)
    end)
    
    kong.log.info("AWS Masker v2.0.0 initialized")
end

-- Access Phase: 요청 마스킹
function aws_masker:access(conf)
    -- 성능 측정 시작
    local perf_ctx = performance.start_timer("request_masking")
    
    -- 요청 버퍼링 활성화
    kong.service.request.enable_buffering()
    
    -- 현재 요청 컨텍스트 저장
    kong.ctx.plugin.masking_config = conf
    kong.ctx.plugin.request_id = kong.request.get_header("X-Request-ID") or ngx.var.request_id
    kong.ctx.plugin.performance_ctx = perf_ctx
    
    kong.log.debug("Request buffering enabled for AWS masking")
end

-- Body Filter Phase: 요청/응답 처리  
function aws_masker:body_filter(conf)
    local ctx = kong.ctx.plugin
    
    -- 요청 처리 (업스트림으로 가는 데이터)
    if not ctx.request_processed then
        local body = kong.service.request.get_raw_body()
        if body and #body > 0 then
            kong.log.info("Processing request body for masking", {
                size = #body,
                request_id = ctx.request_id
            })
            
            local masked_body, masking_context = masker_v2.mask_request(body, conf)
            
            if masked_body then
                kong.service.request.set_raw_body(masked_body)
                ctx.masking_context = masking_context
                
                kong.log.info("Request masking completed", {
                    masked_count = masking_context.masked_count or 0,
                    request_id = ctx.request_id
                })
            end
        end
        
        ctx.request_processed = true
    end
    
    -- 응답 처리 (다운스트림으로 가는 데이터)  
    if not ctx.response_processed then
        local body_chunk = kong.response.get_raw_body()
        if body_chunk and ctx.masking_context then
            kong.log.info("Processing response body for unmasking", {
                size = #body_chunk,
                request_id = ctx.request_id
            })
            
            local unmasked_body = masker_v2.unmask_response(body_chunk, ctx.masking_context)
            
            if unmasked_body then
                kong.response.set_raw_body(unmasked_body)
                
                kong.log.info("Response unmasking completed", {
                    request_id = ctx.request_id
                })
            end
        end
        
        ctx.response_processed = true
    end
end

-- Log Phase: 성능 로깅
function aws_masker:log(conf)
    local ctx = kong.ctx.plugin
    
    if ctx.performance_ctx then
        performance.end_timer(ctx.performance_ctx, "request_masking")
        
        -- 상세 성능 로그
        kong.log.info("AWS Masking performance metrics", {
            request_id = ctx.request_id,
            total_time_ms = ctx.performance_ctx.total_time,
            masked_count = ctx.masking_context and ctx.masking_context.masked_count or 0,
            memory_used_kb = ctx.performance_ctx.memory_used
        })
    end
end

return aws_masker
```

### 5.3 Schema.lua 확장
**파일**: `/kong/plugins/aws-masker/schema.lua`

```lua
local typedefs = require "kong.db.schema.typedefs"

return {
    name = "aws-masker",
    fields = {
        { consumer = typedefs.no_consumer },
        { protocols = typedefs.protocols_http },
        { config = {
            type = "record",
            fields = {
                -- 기존 설정 (하위 호환성)
                { mask_ec2_instances = { type = "boolean", default = true } },
                { mask_s3_buckets = { type = "boolean", default = true } },
                { mask_rds_instances = { type = "boolean", default = true } },
                { mask_private_ips = { type = "boolean", default = true } },
                
                -- 신규 패턴 설정
                { mask_vpc_resources = { type = "boolean", default = true } },
                { mask_iam_resources = { type = "boolean", default = true } },
                { mask_account_ids = { type = "boolean", default = true } },
                { mask_additional_ips = { type = "boolean", default = true } },
                { mask_storage_resources = { type = "boolean", default = true } },
                
                -- 고급 설정
                { enable_context_matching = { type = "boolean", default = true } },
                { pattern_priority_mode = { 
                    type = "string", 
                    default = "strict",
                    one_of = { "strict", "permissive", "performance" }
                }},
                { max_json_size_mb = { type = "number", default = 10, between = { 1, 100 } } },
                { mapping_ttl_seconds = { type = "number", default = 300, between = { 60, 3600 } } },
                
                -- 성능 최적화
                { enable_pattern_cache = { type = "boolean", default = true } },
                { max_mappings_per_request = { type = "number", default = 10000, between = { 100, 50000 } } },
                
                -- 디버깅 및 로깅
                { log_masked_requests = { type = "boolean", default = false } },
                { detailed_performance_logs = { type = "boolean", default = false } },
                { save_masking_audit = { type = "boolean", default = false } },
                
                -- 커스텀 패턴 (향후 확장)
                { custom_patterns = { 
                    type = "array", 
                    default = {},
                    elements = {
                        type = "record",
                        fields = {
                            { name = { type = "string", required = true } },
                            { pattern = { type = "string", required = true } },
                            { replacement = { type = "string", required = true } },
                            { priority = { type = "number", default = 100 } },
                            { enabled = { type = "boolean", default = true } }
                        }
                    }
                }}
            }
        }}
    }
}
```

### 5.4 매핑 저장소 구현
**파일**: `/kong/plugins/aws-masker/engine/mapping_store.lua`

```lua
local mapping_store = {}

-- 공유 저장소 (worker 간 공유)
local shm_store = ngx.shared.aws_masking_store
if not shm_store then
    error("Shared memory 'aws_masking_store' not configured. Add 'lua_shared_dict aws_masking_store 50m;' to nginx.conf")
end

-- 로컬 캐시 (worker 내 고속 액세스)
local local_cache = {
    mappings = {},
    reverse_mappings = {},
    counters = {},
    last_cleanup = ngx.now()
}

-- 매핑 저장
function mapping_store.store_mapping(original, masked, pattern_type, ttl)
    ttl = ttl or 300  -- 5분 기본 TTL
    local now = ngx.now()
    local expires_at = now + ttl
    
    -- 로컬 캐시 저장
    local_cache.mappings[original] = {
        masked = masked,
        expires_at = expires_at,
        pattern_type = pattern_type,
        created_at = now
    }
    local_cache.reverse_mappings[masked] = original
    
    -- 공유 메모리 저장 (다른 worker와 공유)
    local key_prefix = "mapping:"
    local value = string.format("%s|%s|%d", masked, pattern_type, expires_at)
    
    local success, err = shm_store:set(key_prefix .. original, value, ttl)
    if not success then
        kong.log.warn("Failed to store mapping in shared memory", { error = err })
    end
    
    return true
end

-- 매핑 조회
function mapping_store.get_mapping(original)
    local now = ngx.now()
    
    -- 로컬 캐시 확인
    local cached = local_cache.mappings[original]
    if cached and cached.expires_at > now then
        return cached.masked, cached.pattern_type
    end
    
    -- 공유 메모리에서 조회
    local key_prefix = "mapping:"
    local value = shm_store:get(key_prefix .. original)
    if value then
        local masked, pattern_type, expires_at_str = value:match("([^|]+)|([^|]+)|(%d+)")
        local expires_at = tonumber(expires_at_str)
        
        if expires_at and expires_at > now then
            -- 로컬 캐시에 복사
            local_cache.mappings[original] = {
                masked = masked,
                expires_at = expires_at,
                pattern_type = pattern_type,
                created_at = now
            }
            local_cache.reverse_mappings[masked] = original
            
            return masked, pattern_type
        end
    end
    
    return nil, nil
end

-- 역매핑 조회
function mapping_store.get_original(masked)
    -- 로컬 캐시 확인
    local original = local_cache.reverse_mappings[masked]
    if original then
        local cached = local_cache.mappings[original]
        if cached and cached.expires_at > ngx.now() then
            return original
        end
    end
    
    -- 공유 메모리 전체 스캔 (비효율적이지만 필요시만)
    -- 실제로는 reverse mapping도 별도 키로 저장하는 것이 좋음
    return nil
end

-- 카운터 관리
function mapping_store.get_next_counter(pattern_type)
    local counter_key = "counter:" .. pattern_type
    local current = shm_store:get(counter_key) or 0
    local next_val = current + 1
    
    shm_store:set(counter_key, next_val, 0)  -- 만료 시간 없음
    return next_val
end

-- 만료된 매핑 정리
function mapping_store.cleanup_expired_mappings(max_cleanup_count)
    max_cleanup_count = max_cleanup_count or 1000
    local now = ngx.now()
    local cleaned = 0
    
    -- 로컬 캐시 정리
    for original, cached in pairs(local_cache.mappings) do
        if cached.expires_at <= now then
            local_cache.mappings[original] = nil
            local_cache.reverse_mappings[cached.masked] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- 공유 메모리 정리 (일부만)
    local keys_to_clean = {}
    local count = 0
    
    -- 키 나열 및 만료 확인
    for i = 1, max_cleanup_count do
        local key = shm_store:get_keys(1)  -- 하나씩 확인
        if not key then break end
        
        if key:match("^mapping:") then
            local value = shm_store:get(key)
            if value then
                local _, _, expires_at_str = value:match("([^|]+)|([^|]+)|(%d+)")
                local expires_at = tonumber(expires_at_str)
                
                if expires_at and expires_at <= now then
                    table.insert(keys_to_clean, key)
                    count = count + 1
                end
            end
        end
        
        if count >= max_cleanup_count then break end
    end
    
    -- 만료된 키 삭제
    for _, key in ipairs(keys_to_clean) do
        shm_store:delete(key)
    end
    
    local_cache.last_cleanup = now
    
    kong.log.debug("Mapping cleanup completed", {
        local_cleaned = cleaned,
        shared_cleaned = #keys_to_clean,
        total_cleaned = cleaned + #keys_to_clean
    })
    
    return cleaned + #keys_to_clean
end

-- 통계 정보
function mapping_store.get_statistics()
    local stats = {
        local_mappings = 0,
        shared_mappings = 0,
        memory_usage = {
            local_kb = 0,
            shared_kb = 0
        },
        last_cleanup = local_cache.last_cleanup
    }
    
    -- 로컬 캐시 통계
    for _ in pairs(local_cache.mappings) do
        stats.local_mappings = stats.local_mappings + 1
    end
    
    -- 공유 메모리 통계
    local used_size = shm_store:capacity() - shm_store:free_space()
    stats.memory_usage.shared_kb = used_size / 1024
    
    return stats
end

-- 헬스체크
function mapping_store.health_check()
    local health = {
        status = "healthy",
        issues = {}
    }
    
    -- 메모리 사용률 확인
    local capacity = shm_store:capacity()
    local free_space = shm_store:free_space()
    local usage_pct = ((capacity - free_space) / capacity) * 100
    
    if usage_pct > 90 then
        health.status = "warning"
        table.insert(health.issues, "High memory usage: " .. string.format("%.1f%%", usage_pct))
    end
    
    if usage_pct > 98 then
        health.status = "critical"
    end
    
    -- 정리 작업 필요 확인
    local time_since_cleanup = ngx.now() - local_cache.last_cleanup
    if time_since_cleanup > 300 then  -- 5분 이상
        table.insert(health.issues, "Cleanup overdue: " .. string.format("%.0fs", time_since_cleanup))
    end
    
    return health
end

return mapping_store
```

### 5.5 성능 측정 유틸리티
**파일**: `/kong/plugins/aws-masker/utils/performance.lua`

```lua
local performance = {}

-- 성능 컨텍스트
local function create_context(name)
    return {
        name = name,
        start_time = ngx.now(),
        start_memory = collectgarbage("count"),
        checkpoints = {}
    }
end

-- 타이머 시작
function performance.start_timer(name)
    return create_context(name)
end

-- 체크포인트 추가
function performance.checkpoint(ctx, checkpoint_name)
    local now = ngx.now()
    local memory = collectgarbage("count")
    
    table.insert(ctx.checkpoints, {
        name = checkpoint_name,
        time = now,
        elapsed_ms = (now - ctx.start_time) * 1000,
        memory_kb = memory,
        memory_delta_kb = memory - ctx.start_memory
    })
end

-- 타이머 종료
function performance.end_timer(ctx, final_name)
    local end_time = ngx.now()
    local end_memory = collectgarbage("count")
    
    ctx.total_time = (end_time - ctx.start_time) * 1000  -- ms
    ctx.memory_used = end_memory - ctx.start_memory      -- KB
    ctx.end_time = end_time
    
    if final_name then
        performance.checkpoint(ctx, final_name)
    end
    
    return ctx
end

-- 성능 로그 출력
function performance.log_metrics(ctx, level)
    level = level or "info"
    
    local metrics = {
        operation = ctx.name,
        total_time_ms = ctx.total_time,
        memory_used_kb = ctx.memory_used,
        checkpoints = ctx.checkpoints
    }
    
    kong.log[level]("Performance metrics", metrics)
end

-- 성능 임계값 검사
function performance.check_thresholds(ctx, thresholds)
    local warnings = {}
    
    if thresholds.max_time_ms and ctx.total_time > thresholds.max_time_ms then
        table.insert(warnings, string.format("Slow operation: %.2fms > %.2fms", 
            ctx.total_time, thresholds.max_time_ms))
    end
    
    if thresholds.max_memory_kb and ctx.memory_used > thresholds.max_memory_kb then
        table.insert(warnings, string.format("High memory usage: %.2fKB > %.2fKB",
            ctx.memory_used, thresholds.max_memory_kb))
    end
    
    if #warnings > 0 then
        kong.log.warn("Performance thresholds exceeded", {
            operation = ctx.name,
            warnings = warnings,
            metrics = {
                time_ms = ctx.total_time,
                memory_kb = ctx.memory_used
            }
        })
    end
    
    return #warnings == 0
end

return performance
```

### 5.6 설치 및 배포 스크립트
**파일**: `/scripts/deploy-plugin-v2.sh`

```bash
#!/bin/bash
set -euo pipefail

PLUGIN_NAME="aws-masker"
KONG_PLUGINS_DIR="/usr/local/share/lua/5.1/kong/plugins"
BACKUP_DIR="/tmp/kong-plugin-backup-$(date +%Y%m%d_%H%M%S)"

echo "🚀 Kong AWS Masker Plugin v2.0 Deployment"
echo "=========================================="

# 1. 백업 생성
if [ -d "$KONG_PLUGINS_DIR/$PLUGIN_NAME" ]; then
    echo "📦 Creating backup of existing plugin..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$KONG_PLUGINS_DIR/$PLUGIN_NAME" "$BACKUP_DIR/"
    echo "   Backup saved to: $BACKUP_DIR"
fi

# 2. 플러그인 파일 복사
echo "📁 Deploying new plugin files..."
mkdir -p "$KONG_PLUGINS_DIR/$PLUGIN_NAME"
cp -r ./kong/plugins/aws-masker/* "$KONG_PLUGINS_DIR/$PLUGIN_NAME/"

# 3. 권한 설정
chmod -R 644 "$KONG_PLUGINS_DIR/$PLUGIN_NAME"
chmod 755 "$KONG_PLUGINS_DIR/$PLUGIN_NAME"
find "$KONG_PLUGINS_DIR/$PLUGIN_NAME" -type d -exec chmod 755 {} \;

# 4. Kong 설정 업데이트
echo "⚙️  Updating Kong configuration..."

# nginx.conf에 shared dictionary 추가 확인
NGINX_CONF="/etc/kong/nginx-kong.conf"
if [ -f "$NGINX_CONF" ]; then
    if ! grep -q "lua_shared_dict aws_masking_store" "$NGINX_CONF"; then
        echo "   Adding shared memory configuration..."
        sed -i '/http {/a\    lua_shared_dict aws_masking_store 50m;' "$NGINX_CONF"
        echo "   ✅ Shared memory configuration added"
    fi
fi

# 5. Kong 플러그인 목록 업데이트
KONG_CONF="/etc/kong/kong.conf"
if [ -f "$KONG_CONF" ]; then
    if grep -q "^plugins" "$KONG_CONF"; then
        # 기존 plugins 라인에 aws-masker 추가 (없다면)
        if ! grep "plugins.*aws-masker" "$KONG_CONF"; then
            sed -i 's/^plugins = \(.*\)/plugins = \1,aws-masker/' "$KONG_CONF"
            echo "   ✅ aws-masker added to plugins list"
        fi
    else
        # plugins 라인이 없으면 추가
        echo "plugins = bundled,aws-masker" >> "$KONG_CONF"
        echo "   ✅ plugins configuration added"
    fi
fi

# 6. 설정 검증
echo "🔍 Validating Kong configuration..."
if kong check; then
    echo "   ✅ Kong configuration is valid"
else
    echo "   ❌ Kong configuration validation failed"
    echo "   🔄 Restoring backup..."
    rm -rf "$KONG_PLUGINS_DIR/$PLUGIN_NAME"
    cp -r "$BACKUP_DIR/$PLUGIN_NAME" "$KONG_PLUGINS_DIR/"
    exit 1
fi

# 7. Kong 재시작
echo "🔄 Restarting Kong..."
if systemctl is-active --quiet kong; then
    systemctl reload kong
    echo "   ✅ Kong reloaded successfully"
else
    echo "   ⚠️  Kong is not running. Please start Kong manually:"
    echo "      systemctl start kong"
fi

# 8. 배포 검증
echo "✅ Deployment verification..."
sleep 5

# Kong Admin API를 통한 플러그인 확인
if curl -s "http://localhost:8001/plugins/available" | grep -q "aws-masker"; then
    echo "   ✅ aws-masker plugin is available in Kong"
else
    echo "   ❌ aws-masker plugin not found in Kong"
fi

echo ""
echo "🎉 Kong AWS Masker v2.0 deployment completed!"
echo ""
echo "📋 Next Steps:"
echo "   1. Update your service configurations to use the new plugin options"
echo "   2. Test the new pattern matching with: POST /test-masking"
echo "   3. Monitor performance logs for any issues"
echo "   4. Backup location: $BACKUP_DIR"
echo ""
echo "📖 Documentation:"
echo "   - Pattern test UI: http://localhost:8080/ (after starting test server)"
echo "   - Plugin config: /etc/kong/kong.conf"
echo "   - Logs: /var/log/kong/"

```

이 수정 계획을 통해:

1. **기존 호환성 유지**: 현재 설정이 그대로 작동
2. **점진적 업그레이드**: 새 기능을 선택적으로 활성화
3. **성능 모니터링**: 상세한 메트릭과 임계값 경고
4. **안전한 배포**: 백업과 롤백 메커니즘 포함
5. **실시간 테스트**: 배포 후 즉시 테스트 가능

다음은 이 계획의 실행 순서입니다:
1. Phase 1: 패턴 정확도 개선 (1주)
2. Phase 2: 확장 패턴 구현 (1주)  
3. Phase 3: 성능 엔진 구현 (1주)
4. Phase 4: 테스트 및 배포 (1주)

총 4주 계획으로 단계별 검증이 가능한 구조입니다.