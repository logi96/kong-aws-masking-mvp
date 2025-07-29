--
-- Busted Test Helper for AWS Masker Plugin
-- Sets up test environment and common utilities
--

-- Test configuration
local test_config = {
  timeout = 5000,
  coverage = {
    enabled = true,
    target = 80
  }
}

-- Common test utilities
local helpers = {}

/**
 * Creates a mock Kong context for testing
 * @returns {table} Mock Kong context
 */
function helpers.mock_kong_context()
  return {
    log = {
      info = function() end,
      error = function() end,
      warn = function() end,
      debug = function() end
    },
    ctx = {
      shared = {}
    },
    request = {
      get_raw_body = function() 
        return '{"test": "i-1234567890abcdef0"}'
      end,
      set_raw_body = function() end
    },
    response = {
      get_raw_body = function() 
        return '{"result": "EC2_001"}'
      end,
      set_raw_body = function() end
    }
  }
end

/**
 * Creates sample AWS resource data for testing
 * @returns {table} Sample AWS data
 */
function helpers.sample_aws_data()
  return {
    ec2_instances = {
      "i-1234567890abcdef0",
      "i-0987654321fedcba0"
    },
    private_ips = {
      "10.0.1.100",
      "10.0.2.200"
    },
    s3_buckets = {
      "my-test-bucket",
      "another-bucket.s3.amazonaws.com"
    },
    rds_instances = {
      "mydb-instance-1",
      "prod-database-cluster"
    }
  }
end

/**
 * Asserts that AWS resources are properly masked
 * @param {string} original - Original data
 * @param {string} masked - Masked data
 * @param {string} resource_type - Type of AWS resource
 */
function helpers.assert_masked(original, masked, resource_type)
  assert.is_not.equal(original, masked)
  
  if resource_type == "ec2" then
    assert.matches("EC2_%d%d%d", masked)
  elseif resource_type == "ip" then
    assert.matches("PRIVATE_IP_%d%d%d", masked)
  elseif resource_type == "s3" then
    assert.matches("BUCKET_%d%d%d", masked)
  elseif resource_type == "rds" then
    assert.matches("RDS_%d%d%d", masked)
  end
end

-- Set up Kong mocks before requiring modules
require("spec.mock_kong")

-- Global test setup
_G.kong = _G.kong or helpers.mock_kong_context()
_G.test_helpers = helpers
_G.test_config = test_config

return helpers