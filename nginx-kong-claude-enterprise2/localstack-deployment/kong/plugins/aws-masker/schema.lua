--
-- AWS Masker Plugin Schema
-- Defines configuration options for the AWS masking plugin
-- Following 04-code-quality-assurance.md standards with JSDoc annotations
--

local typedefs = require "kong.db.schema.typedefs"

---
-- Conditional validation for ElastiCache configuration fields
-- Validates that ElastiCache-specific fields are properly configured when redis_type = "managed"
-- @param config table The plugin configuration
-- @return boolean, string validation result and error message if any
local function validate_elasticache_config(config)
  -- Smart validation: Support both Traditional and Managed Redis
  local redis_type = config.redis_type or "traditional"
  
  if redis_type == "managed" then
    -- Managed Redis (ElastiCache) - Enable all features
    
    -- Validate cluster mode configuration
    if config.redis_cluster_mode and not config.redis_cluster_endpoint then
      return false, "redis_cluster_endpoint is required when redis_cluster_mode is enabled"
    end
    
    if config.redis_cluster_endpoint and not config.redis_cluster_mode then
      return false, "redis_cluster_mode must be enabled when redis_cluster_endpoint is provided"
    end
    
    -- Validate authentication configuration  
    if config.redis_user and not config.redis_auth_token then
      return false, "redis_auth_token is required when redis_user is specified"
    end
    
  else
    -- Traditional Redis - Allow all fields but they will be ignored at runtime
    -- This provides forward compatibility for migration to ElastiCache
    -- Fields like redis_ssl_verify, redis_auth_token etc. are allowed but unused
  end
  
  return true
end

---
-- AWS Masker Plugin Configuration Schema
-- Defines all available configuration options for masking AWS resources
-- Enhanced with ElastiCache support and conditional validation
-- @type table
return {
  name = "aws-masker",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          -- EC2 Instance Masking Configuration
          {
            mask_ec2_instances = {
              type = "boolean",
              default = true,
              description = "Enable masking of EC2 instance IDs (i-xxxxxxxxxxxxxxxxx format)"
            }
          },
          
          -- S3 Bucket Masking Configuration  
          {
            mask_s3_buckets = {
              type = "boolean",
              default = true,
              description = "Enable masking of S3 bucket names and ARNs"
            }
          },
          
          -- RDS Instance Masking Configuration
          {
            mask_rds_instances = {
              type = "boolean",
              default = true,
              description = "Enable masking of RDS instance identifiers and cluster names"
            }
          },
          
          -- Private IP Address Masking Configuration
          {
            mask_private_ips = {
              type = "boolean",
              default = true,
              description = "Enable masking of private IP addresses (10.x.x.x range)"
            }
          },
          
          -- Structure Preservation Configuration
          {
            preserve_structure = {
              type = "boolean",
              default = true,
              description = "Preserve the original structure/format of masked identifiers for consistency"
            }
          },
          
          -- Logging Configuration
          {
            log_masked_requests = {
              type = "boolean",
              default = false,
              description = "Enable logging of requests that contain masked content (security audit trail)"
            }
          },
          
          -- API Authentication Configuration
          {
            anthropic_api_key = {
              type = "string",
              required = false,
              description = "Anthropic API key for authentication (if not provided in request headers)"
            }
          },
          
          -- Redis Storage Configuration
          {
            use_redis = {
              type = "boolean",
              default = true,
              description = "Enable Redis storage for masked value mappings (7-day persistence)"
            }
          },
          
          -- Mapping TTL Configuration
          {
            mapping_ttl = {
              type = "number",
              default = 604800,  -- 7 days in seconds
              description = "TTL for masked value mappings in seconds"
            }
          },
          
          -- Max Entries Configuration
          {
            max_entries = {
              type = "number",
              default = 10000,
              description = "Maximum number of masked mappings to store"
            }
          },
          
          -- Redis Connection Type Configuration (ElastiCache Support)
          {
            redis_type = {
              type = "string",
              default = "traditional",
              one_of = {"traditional", "managed"},
              description = "Redis connection type: traditional (self-hosted) or managed (ElastiCache)"
            }
          },
          
          -- Basic Redis Connection Configuration (Traditional Mode)
          {
            redis_host = {
              type = "string",
              default = "localhost",
              description = "Redis server hostname or IP address"
            }
          },
          
          {
            redis_port = {
              type = "integer",
              default = 6379,
              description = "Redis server port number"
            }
          },
          
          {
            redis_password = {
              type = "string",
              required = false,
              default = nil,
              description = "Redis server password for authentication"
            }
          },
          
          {
            redis_database = {
              type = "integer",
              default = 0,
              description = "Redis database number to use"
            }
          },
          
          -- Redis SSL/TLS Configuration (compatible with both traditional and managed Redis)
          {
            redis_ssl_enabled = {
              type = "boolean",
              default = false,
              description = "Enable SSL/TLS for Redis connections"
            }
          },
          
          {
            redis_ssl_verify = {
              type = "boolean",
              required = false,
              default = false,
              description = "Verify SSL certificates for Redis connections"
            }
          },
          
          -- Redis Authentication Configuration (compatible with both traditional and managed Redis)
          {
            redis_auth_token = {
              type = "string",
              required = false,
              default = nil,
              description = "Redis auth token for password authentication"
            }
          },
          
          {
            redis_user = {
              type = "string",
              required = false,
              default = nil,
              description = "Redis username for RBAC authentication"
            }
          },
          
          -- Redis Cluster Mode Configuration (compatible with both traditional and managed Redis)
          {
            redis_cluster_mode = {
              type = "boolean",
              default = false,
              description = "Enable Redis Cluster mode"
            }
          },
          
          {
            redis_cluster_endpoint = {
              type = "string",
              required = false,
              default = nil,
              description = "Redis cluster configuration endpoint"
            }
          }
        },
        -- Custom validation for ElastiCache configuration
        custom_validator = validate_elasticache_config
      }
    }
  }
}