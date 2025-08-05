#!/usr/bin/env lua

--
-- Day 4 Integration Test Runner
-- Executes comprehensive tests for Kong AWS-Masker Plugin ElastiCache integration
-- Validates traditional Redis vs ElastiCache functionality
--

-- Set up module paths
package.path = package.path .. ";/usr/local/share/lua/5.1/?.lua;./?.lua"

local cjson = require "cjson.safe"

-- Mock ngx environment for testing outside Kong
if not ngx then
  ngx = {
    log = function(level, ...)
      local args = {...}
      local message = table.concat(args, " ")
      local timestamp = os.date("%Y-%m-%d %H:%M:%S")
      print(string.format("[%s] %s", timestamp, message))
    end,
    now = function()
      return os.time()
    end,
    INFO = "INFO",
    ERR = "ERROR", 
    WARN = "WARN",
    DEBUG = "DEBUG"
  }
end

-- Load test framework
local test_framework = require "kong.plugins.aws-masker.day4_integration_test"

-- Test execution configuration
local TEST_CONFIG = {
  output_file = "/tmp/day4_integration_test_results.json",
  log_file = "/tmp/day4_integration_test.log",
  verbose = true
}

-- Redirect output to log file
local function setup_logging()
  if TEST_CONFIG.log_file then
    local log_file = io.open(TEST_CONFIG.log_file, "w")
    if log_file then
      -- Override ngx.log to write to file
      local original_log = ngx.log
      ngx.log = function(level, ...)
        local args = {...}
        local message = table.concat(args, " ")
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local log_entry = string.format("[%s] [%s] %s\n", timestamp, level, message)
        
        log_file:write(log_entry)
        log_file:flush()
        
        if TEST_CONFIG.verbose then
          original_log(level, ...)
        end
      end
      
      return log_file
    end
  end
  return nil
end

-- Generate JSON test report
local function generate_json_report(test_results, detailed_report)
  local json_report = {
    test_execution = {
      timestamp = os.date("%Y-%m-%dT%H:%M:%SZ"),
      duration_ms = test_results.duration_ms,
      kong_version = "3.9.0.1",
      plugin_version = "1.0.0",
      test_type = "Day 4 ElastiCache Integration"
    },
    test_results = test_results.stats,
    detailed_analysis = detailed_report,
    pass_criteria = {
      minimum_success_rate = 90,
      maximum_avg_latency_ms = 2.0,
      required_environments = {"EC2", "EKS-EC2", "EKS-Fargate", "ECS"}
    },
    overall_status = test_results.success and "PASSED" or "FAILED"
  }
  
  return cjson.encode(json_report)
end

-- Save results to file
local function save_results(json_report)
  if TEST_CONFIG.output_file then
    local output_file = io.open(TEST_CONFIG.output_file, "w")
    if output_file then
      output_file:write(json_report)
      output_file:close()
      print("Results saved to: " .. TEST_CONFIG.output_file)
      return true
    else
      print("ERROR: Could not open output file: " .. TEST_CONFIG.output_file)
      return false
    end
  end
  return true
end

-- Print test summary to console
local function print_summary(test_results, detailed_report)
  print("\n" .. string.rep("=", 60))
  print("DAY 4 KONG ELASTICACHE INTEGRATION TEST SUMMARY")
  print(string.rep("=", 60))
  
  print(string.format("Total Tests: %d", test_results.stats.total_tests))
  print(string.format("Passed: %d", test_results.stats.passed_tests))
  print(string.format("Failed: %d", test_results.stats.failed_tests))
  
  local success_rate = (test_results.stats.passed_tests / test_results.stats.total_tests) * 100
  print(string.format("Success Rate: %.1f%%", success_rate))
  print(string.format("Duration: %.2fms", test_results.duration_ms))
  
  print("\n" .. string.rep("-", 40))
  print("PERFORMANCE ANALYSIS")
  print(string.rep("-", 40))
  
  if detailed_report.performance_analysis.traditional_redis then
    local trad_perf = detailed_report.performance_analysis.traditional_redis
    print(string.format("Traditional Redis: %.2fms avg latency (%.1f%% success)", 
      trad_perf.avg_latency_ms, trad_perf.success_rate))
    if trad_perf.meets_target then
      print("✅ Traditional Redis meets < 2ms latency target")
    else
      print("❌ Traditional Redis exceeds 2ms latency target")
    end
  end
  
  if detailed_report.performance_analysis.elasticache then
    local ec_perf = detailed_report.performance_analysis.elasticache
    print(string.format("ElastiCache: Type=%s, SSL=%s, Structure Valid=%s",
      ec_perf.connection_type, tostring(ec_perf.ssl_enabled), tostring(ec_perf.structure_valid)))
  end
  
  print("\n" .. string.rep("-", 40))
  print("ENVIRONMENT COMPATIBILITY")
  print(string.rep("-", 40))
  
  for env, status in pairs(detailed_report.environment_compatibility) do
    print(string.format("%s: %s", env, status))
  end
  
  if #detailed_report.error_analysis > 0 then
    print("\n" .. string.rep("-", 40))
    print("ERROR ANALYSIS")
    print(string.rep("-", 40))
    
    for _, error_entry in ipairs(detailed_report.error_analysis) do
      print(string.format("❌ %s: %s", error_entry.test, error_entry.error))
    end
  end
  
  print("\n" .. string.rep("-", 40))
  print("RECOMMENDATIONS")
  print(string.rep("-", 40))
  
  for _, recommendation in ipairs(detailed_report.recommendations) do
    print("• " .. recommendation)
  end
  
  print("\n" .. string.rep("=", 60))
  if test_results.success then
    print("🎉 DAY 4 INTEGRATION TESTS: PASSED")
    print("✅ Ready to proceed with Day 5 comprehensive testing")
  else
    print("❌ DAY 4 INTEGRATION TESTS: FAILED")
    print("⚠️  Address issues before proceeding to Day 5")
  end
  print(string.rep("=", 60))
end

-- Main execution function
local function main()
  print("Starting Day 4 Kong ElastiCache Integration Tests...")
  print("Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"))
  
  -- Setup logging
  local log_file = setup_logging()
  
  -- Run comprehensive integration tests
  print("Executing integration test suite...")
  local test_results = test_framework.run_all_tests()
  
  -- Generate detailed report
  print("Generating detailed analysis...")
  local detailed_report = test_framework.generate_detailed_report()
  
  -- Create JSON report
  local json_report = generate_json_report(test_results, detailed_report)
  
  -- Save results
  local save_ok = save_results(json_report)
  
  -- Print summary
  print_summary(test_results, detailed_report)
  
  -- Cleanup
  if log_file then
    log_file:close()
    print("Detailed logs saved to: " .. TEST_CONFIG.log_file)
  end
  
  -- Return appropriate exit code
  os.exit(test_results.success and 0 or 1)
end

-- Error handling wrapper
local function safe_main()
  local ok, err = pcall(main)
  if not ok then
    print("ERROR: Test execution failed: " .. tostring(err))
    os.exit(1)
  end
end

-- Execute if run directly
if arg and arg[0] and string.match(arg[0], "run_day4_tests") then
  safe_main()
end

-- Export for module usage
return {
  run_tests = main,
  config = TEST_CONFIG
}