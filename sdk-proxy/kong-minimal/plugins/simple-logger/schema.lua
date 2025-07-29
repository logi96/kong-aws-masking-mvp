-- Schema definition for Simple Logger Plugin

local typedefs = require "kong.db.schema.typedefs"

return {
    name = "simple-logger",
    fields = {
        {
            -- 플러그인이 적용될 범위
            protocols = typedefs.protocols_http
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        -- 응답 본문 미리보기 크기 (기본값: 200자)
                        body_preview_size = {
                            type = "integer",
                            default = 200,
                            between = { 0, 10000 },
                            description = "Maximum characters to log from response body"
                        }
                    },
                    {
                        -- 헤더 로깅 여부
                        log_headers = {
                            type = "boolean",
                            default = true,
                            description = "Whether to log request and response headers"
                        }
                    },
                    {
                        -- 요청 본문 로깅 여부
                        log_request_body = {
                            type = "boolean",
                            default = false,
                            description = "Whether to log request body (POST only)"
                        }
                    },
                    {
                        -- 파일 로깅 경로 (옵션)
                        log_file = {
                            type = "string",
                            required = false,
                            description = "Path to log file (optional)"
                        }
                    },
                    {
                        -- 민감한 헤더 마스킹 패턴
                        sensitive_headers = {
                            type = "array",
                            default = { "authorization", "x-api-key", "cookie", "set-cookie" },
                            elements = {
                                type = "string"
                            },
                            description = "Headers to mask in logs"
                        }
                    }
                },
            },
        },
    },
    entity_checks = {
        -- 추가 검증 로직 (필요시)
        {
            custom_entity_check = {
                field_sources = { "config" },
                fn = function(entity)
                    -- 파일 경로가 제공된 경우 검증
                    if entity.config.log_file then
                        local dir = entity.config.log_file:match("(.*/)")
                        if dir and dir:match("%.%.") then
                            return nil, "log_file path cannot contain '..' for security reasons"
                        end
                    end
                    return true
                end
            }
        }
    }
}