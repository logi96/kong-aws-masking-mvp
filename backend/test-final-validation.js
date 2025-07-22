#!/usr/bin/env node
/**
 * Final Kong AWS Masking Validation
 * Comprehensive test to validate all AWS resource patterns work correctly
 */

require('dotenv').config();
const axios = require('axios');

async function finalValidation() {
  console.log('🚀 Final Kong AWS Masking Validation');
  console.log('=====================================');
  console.log('Testing all supported AWS resource patterns...\n');

  const comprehensiveTest = `
AWS Infrastructure Analysis Request:
- EC2 instances: i-1234567890abcdef0, i-abcdef1234567890
- Private IPs: 10.0.1.100, 10.255.255.255, 10.1.2.3
- S3 storage: my-app-logs-bucket, user-data-bucket-2024
- RDS databases: production-mysql-db, staging-postgres-db
- Additional resources: vpc-abc123, subnet-def456
`.trim();

  console.log('📋 Test Content:');
  console.log(comprehensiveTest);
  console.log('\n📤 Sending to Kong Gateway → Claude API...');
  
  const payload = {
    model: "claude-3-5-sonnet-20241022",
    max_tokens: 200,
    messages: [{
      role: "user", 
      content: `Please identify and list all AWS resources mentioned in the following infrastructure description: ${comprehensiveTest}`
    }]
  };
  
  try {
    const startTime = Date.now();
    
    const response = await axios.post('http://localhost:8000/analyze-claude', payload, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      timeout: 10000
    });
    
    const duration = Date.now() - startTime;
    console.log(`✅ Response received in ${duration}ms`);
    
    const claudeContent = response.data.content[0].text;
    console.log('\n📄 Claude Response:');
    console.log('─'.repeat(60));
    console.log(claudeContent);
    console.log('─'.repeat(60));
    
    // Comprehensive masking analysis
    const maskingResults = {
      EC2: claudeContent.match(/EC2_\d{3}/g) || [],
      PrivateIP: claudeContent.match(/PRIVATE_IP_\d{3}/g) || [],
      S3: claudeContent.match(/BUCKET_\d{3}/g) || [],
      RDS: claudeContent.match(/RDS_\d{3}/g) || []
    };
    
    console.log('\n🎯 Masking Results Summary:');
    console.log('═'.repeat(40));
    
    let totalMasked = 0;
    Object.entries(maskingResults).forEach(([type, masks]) => {
      if (masks.length > 0) {
        console.log(`✅ ${type}: ${masks.length} masked (${masks.join(', ')})`);
        totalMasked += masks.length;
      } else {
        console.log(`⚠️  ${type}: 0 masked`);
      }
    });
    
    console.log('─'.repeat(40));
    console.log(`📊 Total Resources Masked: ${totalMasked}`);
    
    // Check for any original identifiers that shouldn't be there
    const originalPatterns = [
      /i-[0-9a-f]{8,}/g,                    // EC2 instances (8+ chars)
      /10\.\d+\.\d+\.\d+/g,                 // Private IPs  
      /my-app-logs-bucket|user-data-bucket-2024/gi, // Specific S3 buckets from test
      /production-mysql-db|staging-postgres-db/gi   // Specific RDS from test
    ];
    
    console.log('\n🔒 Security Check (Original Identifiers):');
    console.log('─'.repeat(40));
    
    let securityPassed = true;
    originalPatterns.forEach((pattern, index) => {
      const found = claudeContent.match(pattern);
      const types = ['EC2', 'Private IP', 'S3', 'RDS'][index];
      if (found) {
        console.log(`❌ ${types}: Found original identifiers: ${found.join(', ')}`);
        securityPassed = false;
      } else {
        console.log(`✅ ${types}: No original identifiers leaked`);
      }
    });
    
    // Performance check
    console.log('\n⚡ Performance Analysis:');
    console.log('─'.repeat(40));
    console.log(`Request Duration: ${duration}ms`);
    console.log(`Performance Target: < 5000ms (CLAUDE.md requirement)`);
    console.log(duration < 5000 ? '✅ Performance: PASS' : '❌ Performance: FAIL');
    
    // Final verdict
    console.log('\n🏆 Final Assessment:');
    console.log('═'.repeat(40));
    console.log(`Resources Masked: ${totalMasked > 0 ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Security: ${securityPassed ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Performance: ${duration < 5000 ? '✅ PASS' : '❌ FAIL'}`);
    
    const overallStatus = (totalMasked > 0 && securityPassed && duration < 5000) ? 'PASS' : 'FAIL';
    console.log(`Overall Status: ${overallStatus === 'PASS' ? '🎉 PASS' : '💥 FAIL'}`);
    
    console.log('\n💡 Kong AWS Masking MVP - Test Complete!');
    
  } catch (error) {
    console.error(`❌ Validation failed: ${error.message}`);
    
    if (error.response) {
      console.error(`HTTP Status: ${error.response.status}`);
      console.error(`Response: ${JSON.stringify(error.response.data, null, 2)}`);
    }
    
    if (error.code === 'ECONNREFUSED') {
      console.error('💡 Check that Kong Gateway is running on port 8000');
    }
    
    if (error.code === 'ECONNABORTED') {
      console.error('💡 Request timed out - check Kong and Claude API connectivity');
    }
  }
}

finalValidation().catch(console.error);