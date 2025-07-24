--
-- AWS Masker Plugin Schema
-- Defines configuration options for the AWS masking plugin
-- Following 04-code-quality-assurance.md standards with JSDoc annotations
--

local typedefs = require "kong.db.schema.typedefs"

---
-- AWS Masker Plugin Configuration Schema
-- Defines all available configuration options for masking AWS resources
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
          }
        }
      }
    }
  }
}