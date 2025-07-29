--
-- Unit tests for AWS Masker Patterns
--

describe("AWS Masker Patterns", function()
  local patterns
  
  setup(function()
    patterns = require("kong.plugins.aws-masker.patterns")
  end)
  
  describe("EC2 Instance Patterns", function()
    it("should match EC2 instance IDs", function()
      local test_cases = {
        ["i-1234567890abcdef0"] = true,
        ["i-0a1b2c3d4e5f6g7h8"] = true,
        ["i-abcdef1234567890"] = true,
        ["not-an-instance"] = false,
        ["i-123"] = false,  -- Too short
        ["i_1234567890abcdef0"] = false,  -- Wrong separator
      }
      
      for input, should_match in pairs(test_cases) do
        local matched = false
        for _, pattern in ipairs(patterns.AWS_PATTERNS) do
          if pattern.type == "ec2_instance" then
            if input:match(pattern.pattern) then
              matched = true
              break
            end
          end
        end
        assert.equals(should_match, matched, "Pattern match failed for: " .. input)
      end
    end)
  end)
  
  describe("S3 Bucket Patterns", function()
    it("should match S3 bucket names", function()
      local test_cases = {
        ["my-bucket-name"] = true,
        ["bucket.with.dots"] = true,
        ["bucket123"] = true,
        ["123bucket"] = true,
        ["my-bucket-name-with-long-name-under-63-chars"] = true,
        ["a"] = false,  -- Too short (min 3 chars)
        ["ab"] = false,  -- Too short
        ["UPPERCASE-BUCKET"] = false,  -- S3 buckets are lowercase
        ["bucket_with_underscore"] = false,  -- Underscores not allowed
        ["bucket-with-very-long-name-that-exceeds-sixty-three-characters-limit"] = false,
      }
      
      for input, should_match in pairs(test_cases) do
        local matched = false
        for _, pattern in ipairs(patterns.AWS_PATTERNS) do
          if pattern.type == "s3_bucket" then
            if input:match(pattern.pattern) then
              matched = true
              break
            end
          end
        end
        assert.equals(should_match, matched, "Pattern match failed for: " .. input)
      end
    end)
  end)
  
  describe("Private IP Patterns", function()
    it("should match private IP addresses", function()
      local test_cases = {
        -- 10.x.x.x range
        ["10.0.0.1"] = true,
        ["10.255.255.255"] = true,
        ["10.123.45.67"] = true,
        -- 172.16-31.x.x range
        ["172.16.0.1"] = true,
        ["172.31.255.255"] = true,
        ["172.20.10.5"] = true,
        -- 192.168.x.x range
        ["192.168.0.1"] = true,
        ["192.168.255.255"] = true,
        ["192.168.1.100"] = true,
        -- Non-private IPs
        ["8.8.8.8"] = false,
        ["172.15.0.1"] = false,  -- Outside private range
        ["172.32.0.1"] = false,  -- Outside private range
        ["192.169.0.1"] = false,  -- Outside private range
      }
      
      for input, should_match in pairs(test_cases) do
        local matched = false
        for _, pattern in ipairs(patterns.AWS_PATTERNS) do
          if pattern.type == "private_ip" then
            if input:match(pattern.pattern) then
              matched = true
              break
            end
          end
        end
        assert.equals(should_match, matched, "Pattern match failed for: " .. input)
      end
    end)
  end)
  
  describe("RDS Instance Patterns", function()
    it("should match RDS instance identifiers", function()
      local test_cases = {
        ["mydb-instance"] = true,
        ["prod-mysql-01"] = true,
        ["database1"] = true,
        ["my-very-long-rds-instance-name"] = true,
        ["123-starting-with-number"] = false,  -- Can't start with number
        [""] = false,  -- Empty
        ["a"] = false,  -- Too short
      }
      
      for input, should_match in pairs(test_cases) do
        local matched = false
        for _, pattern in ipairs(patterns.AWS_PATTERNS) do
          if pattern.type == "rds_instance" then
            if input:match(pattern.pattern) then
              matched = true
              break
            end
          end
        end
        assert.equals(should_match, matched, "Pattern match failed for: " .. input)
      end
    end)
  end)
  
  describe("Lambda Function Patterns", function()
    it("should match Lambda function names", function()
      local test_cases = {
        ["my-function"] = true,
        ["MyFunction"] = true,
        ["function_with_underscore"] = true,
        ["function-123"] = true,
        ["very-long-lambda-function-name-up-to-64-chars"] = true,
        ["arn:aws:lambda:us-east-1:123456789012:function:my-function"] = true,
        [""] = false,
        ["function with spaces"] = false,
        ["function@special"] = false,
      }
      
      for input, should_match in pairs(test_cases) do
        local matched = false
        for _, pattern in ipairs(patterns.AWS_PATTERNS) do
          if pattern.type == "lambda_function" or pattern.type == "lambda_arn" then
            if input:match(pattern.pattern) then
              matched = true
              break
            end
          end
        end
        assert.equals(should_match, matched, "Pattern match failed for: " .. input)
      end
    end)
  end)
  
  describe("IAM Patterns", function()
    it("should match IAM role names", function()
      local test_cases = {
        ["MyRole"] = true,
        ["my-role-name"] = true,
        ["role_with_underscore"] = true,
        ["EC2-Instance-Role"] = true,
        ["arn:aws:iam::123456789012:role/MyRole"] = true,
        ["arn:aws:iam::123456789012:user/MyUser"] = true,
        [""] = false,
        ["role with spaces"] = false,
      }
      
      for input, should_match in pairs(test_cases) do
        local matched = false
        for _, pattern in ipairs(patterns.AWS_PATTERNS) do
          if pattern.type == "iam_role" or pattern.type == "iam_user" or 
             pattern.type == "iam_role_arn" or pattern.type == "iam_user_arn" then
            if input:match(pattern.pattern) then
              matched = true
              break
            end
          end
        end
        assert.equals(should_match, matched, "Pattern match failed for: " .. input)
      end
    end)
  end)
  
  describe("Pattern Priority", function()
    it("should match patterns in correct priority order", function()
      -- ARNs should be matched before simple names
      local arn = "arn:aws:iam::123456789012:role/MyRole"
      local matched_type = nil
      
      for _, pattern in ipairs(patterns.AWS_PATTERNS) do
        if arn:match(pattern.pattern) then
          matched_type = pattern.type
          break
        end
      end
      
      -- Should match as ARN, not as simple role name
      assert.equals("iam_role_arn", matched_type)
    end)
  end)
  
  describe("Pattern Metadata", function()
    it("should have required fields for all patterns", function()
      for i, pattern in ipairs(patterns.AWS_PATTERNS) do
        assert.is_not_nil(pattern.pattern, "Pattern missing for index " .. i)
        assert.is_not_nil(pattern.type, "Type missing for index " .. i)
        assert.is_not_nil(pattern.replacement, "Replacement missing for index " .. i)
        assert.is_string(pattern.pattern, "Pattern should be string for index " .. i)
        assert.is_string(pattern.type, "Type should be string for index " .. i)
        assert.is_function(pattern.replacement, "Replacement should be function for index " .. i)
      end
    end)
  end)
end)