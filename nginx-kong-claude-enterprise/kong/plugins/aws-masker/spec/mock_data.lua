--
-- Mock Data for AWS Masker Plugin Testing
-- Contains sample AWS resource data for comprehensive testing
--

local mock_data = {}

/**
 * Sample AWS EC2 instances for testing
 * @type {table}
 */
mock_data.ec2_instances = {
  valid = {
    "i-1234567890abcdef0",
    "i-0987654321fedcba0", 
    "i-abcdef1234567890",
    "i-1111111111111111",
    "i-22222222"
  },
  invalid = {
    "invalid-instance",
    "i-",
    "i-xyz",
    "instance-123"
  }
}

/**
 * Sample private IP addresses for testing
 * @type {table}
 */
mock_data.private_ips = {
  valid = {
    "10.0.0.1",
    "10.255.255.255", 
    "10.10.10.10",
    "10.0.1.100",
    "10.172.16.254"
  },
  invalid = {
    "192.168.1.1",
    "8.8.8.8",
    "10.256.0.1",
    "10.0.0"
  }
}

/**
 * Sample S3 bucket names for testing
 * @type {table}
 */
mock_data.s3_buckets = {
  valid = {
    "my-test-bucket",
    "production-logs-2024",
    "user-uploads.example.com",
    "backup-db-001",
    "analytics-data-warehouse",
    "my-bucket.s3.amazonaws.com",
    "another-bucket.s3.us-east-1.amazonaws.com"
  },
  invalid = {
    "UPPERCASE-BUCKET",
    "bucket_with_underscores",
    "bucket-",
    "-bucket",
    "a"
  }
}

/**
 * Sample RDS instance identifiers for testing
 * @type {table}
 */
mock_data.rds_instances = {
  valid = {
    "mydb-instance-1",
    "prod-database-cluster",
    "dev-mysql-db",
    "analytics-postgresql",
    "cache-redis-001"
  },
  invalid = {
    "DB_INVALID",
    "db-",
    "-db",
    "123456789012345678901234567890123456789012345678901234567890123"  -- too long
  }
}

/**
 * Sample request payloads containing AWS resources
 * @type {table}
 */
mock_data.request_payloads = {
  simple_ec2 = {
    action = "analyze",
    data = "Please analyze instance i-1234567890abcdef0 performance"
  },
  
  multiple_resources = {
    instances = {"i-1234567890abcdef0", "i-0987654321fedcba0"},
    ips = {"10.0.1.100", "10.0.2.200"},
    buckets = {"my-test-bucket", "backup-logs"}
  },
  
  nested_structure = {
    infrastructure = {
      compute = {
        instances = {
          {id = "i-1234567890abcdef0", ip = "10.0.1.100"},
          {id = "i-0987654321fedcba0", ip = "10.0.2.200"}
        }
      },
      storage = {
        buckets = {"my-test-bucket.s3.amazonaws.com"}
      }
    }
  },
  
  mixed_content = {
    message = "Instance i-1234567890abcdef0 in bucket my-test-bucket has IP 10.0.1.100",
    metadata = {
      source = "aws-cli",
      timestamp = "2024-01-01T00:00:00Z"
    }
  }
}

/**
 * Expected masked responses for testing
 * @type {table}
 */
mock_data.expected_masked = {
  simple_ec2 = {
    action = "analyze", 
    data = "Please analyze instance EC2_001 performance"
  },
  
  multiple_resources = {
    instances = {"EC2_001", "EC2_002"},
    ips = {"PRIVATE_IP_001", "PRIVATE_IP_002"},
    buckets = {"BUCKET_001", "BUCKET_002"}
  },
  
  consistency_check = {
    -- Same resource should get same mask
    first = "Instance i-1234567890abcdef0 analysis",
    second = "Check i-1234567890abcdef0 status", 
    expected_first = "Instance EC2_001 analysis",
    expected_second = "Check EC2_001 status"
  }
}

/**
 * Mock Claude API responses for testing
 * @type {table}
 */
mock_data.claude_responses = {
  success = {
    content = {
      {
        type = "text",
        text = "Analysis of EC2_001 shows good performance with PRIVATE_IP_001 configuration."
      }
    },
    usage = {
      input_tokens = 100,
      output_tokens = 50
    }
  },
  
  error = {
    error = {
      type = "invalid_request_error",
      message = "Invalid request format"
    }
  }
}

/**
 * Performance test data
 * @type {table}
 */
mock_data.performance = {
  large_payload = {
    instances = {},
    generated_size = "10KB"  -- Will be populated dynamically
  },
  
  complex_nesting = {
    level1 = {
      level2 = {
        level3 = {
          level4 = {
            instances = {"i-1234567890abcdef0"}
          }
        }
      }
    }
  }
}

-- Generate large payload for performance testing
for i = 1, 100 do
  table.insert(mock_data.performance.large_payload.instances, 
    "i-" .. string.format("%016x", i))
end

/**
 * Returns a deep copy of mock data to prevent test interference
 * @param {string} data_type - Type of mock data to return
 * @returns {table} Deep copy of requested mock data
 */
function mock_data.get(data_type)
  local function deep_copy(orig)
    local copy = {}
    for k, v in pairs(orig) do
      if type(v) == "table" then
        copy[k] = deep_copy(v)
      else
        copy[k] = v
      end
    end
    return copy
  end
  
  if data_type and mock_data[data_type] then
    return deep_copy(mock_data[data_type])
  end
  
  return deep_copy(mock_data)
end

return mock_data