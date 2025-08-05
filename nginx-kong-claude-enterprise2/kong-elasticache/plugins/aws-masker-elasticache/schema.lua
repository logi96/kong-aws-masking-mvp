-- Kong AWS Masker ElastiCache Edition - Schema Configuration
-- Optimized for AWS ElastiCache Redis integration
-- Supports managed Redis features: AUTH, SSL/TLS, Cluster Mode

return {
  name = "aws-masker-elasticache",
  fields = {
    { config = {
        type = "record",
        fields = {
          -- Core masking features
          { enabled = { type = "boolean", default = true, description = "Enable/disable the plugin" } },
          { mask_ec2_instances = { type = "boolean", default = true, description = "Mask EC2 instance IDs" } },
          { mask_s3_buckets = { type = "boolean", default = true, description = "Mask S3 bucket names" } },
          { mask_rds_instances = { type = "boolean", default = true, description = "Mask RDS instance identifiers" } },
          { mask_private_ips = { type = "boolean", default = true, description = "Mask private IP addresses" } },
          { mask_vpc_ids = { type = "boolean", default = true, description = "Mask VPC identifiers" } },
          { mask_subnet_ids = { type = "boolean", default = true, description = "Mask subnet identifiers" } },
          { mask_security_groups = { type = "boolean", default = true, description = "Mask security group IDs" } },
          
          -- Behavior configuration
          { preserve_structure = { type = "boolean", default = true, description = "Preserve JSON/text structure while masking" } },
          { preserve_length = { type = "boolean", default = false, description = "Preserve original identifier length" } },
          { mask_type = { type = "string", default = "sequential", one_of = { "sequential", "random", "uuid" }, description = "Masking identifier type" } },
          { log_masked_requests = { type = "boolean", default = false, description = "Log masked request details (security sensitive)" } },
          
          -- ElastiCache Redis configuration (Required)
          { elasticache_endpoint = { type = "string", required = true, description = "ElastiCache Redis endpoint (e.g., my-cluster.redis.cache.amazonaws.com)" } },
          { elasticache_port = { type = "integer", default = 6379, description = "ElastiCache Redis port" } },
          { elasticache_auth_token = { type = "string", required = false, description = "ElastiCache Redis AUTH token (recommended for security)" } },
          { elasticache_ssl_enabled = { type = "boolean", default = true, description = "Enable SSL/TLS for ElastiCache connection" } },
          { elasticache_ssl_verify = { type = "boolean", default = true, description = "Verify ElastiCache SSL certificate" } },
          
          -- ElastiCache cluster configuration
          { elasticache_cluster_mode = { type = "boolean", default = false, description = "Enable Redis Cluster mode for ElastiCache" } },
          { elasticache_read_replicas = { type = "array", elements = { type = "string" }, description = "ElastiCache read replica endpoints" } },
          { elasticache_database = { type = "integer", default = 0, description = "Redis database number (0-15)" } },
          
          -- Connection pool and performance
          { connection_pool_size = { type = "integer", default = 100, description = "Redis connection pool size" } },
          { connection_timeout = { type = "integer", default = 2000, description = "Connection timeout in milliseconds" } },
          { keepalive_timeout = { type = "integer", default = 60000, description = "Keep-alive timeout in milliseconds" } },
          { socket_timeout = { type = "integer", default = 5000, description = "Socket timeout in milliseconds" } },
          
          -- Failover and reliability
          { enable_failover = { type = "boolean", default = true, description = "Enable automatic failover to read replicas" } },
          { max_retry_attempts = { type = "integer", default = 3, description = "Maximum retry attempts for Redis operations" } },
          { retry_delay = { type = "integer", default = 100, description = "Delay between retry attempts in milliseconds" } },
          { fail_secure = { type = "boolean", default = true, description = "Block requests when ElastiCache is unavailable" } },
          
          -- Data management
          { mapping_ttl = { type = "integer", default = 604800, description = "TTL for masking mappings in seconds (default: 7 days)" } },
          { max_entries = { type = "integer", default = 10000, description = "Maximum entries per masking session" } },
          { enable_compression = { type = "boolean", default = true, description = "Enable data compression for ElastiCache storage" } },
          
          -- API Authentication (Phase 1 Success Integration)
          { anthropic_api_key = { type = "string", required = false, description = "Anthropic API key for Claude authentication (Plugin Config priority)" } },
          
          -- Monitoring and observability
          { enable_metrics = { type = "boolean", default = true, description = "Enable performance metrics collection" } },
          { metrics_namespace = { type = "string", default = "aws_masker_elasticache", description = "CloudWatch metrics namespace" } },
          { enable_health_checks = { type = "boolean", default = true, description = "Enable ElastiCache health monitoring" } },
          
          -- AWS Integration
          { aws_region = { type = "string", default = "us-east-1", description = "AWS region for ElastiCache cluster" } },
          { use_iam_auth = { type = "boolean", default = false, description = "Use IAM authentication for ElastiCache (requires IAM role)" } },
          { iam_role_arn = { type = "string", required = false, description = "IAM role ARN for ElastiCache access" } },
          
          -- Development and debugging
          { debug_mode = { type = "boolean", default = false, description = "Enable debug logging (not for production)" } },
          { test_mode = { type = "boolean", default = false, description = "Enable test mode with mock ElastiCache" } },
        }
    }}
  }
}