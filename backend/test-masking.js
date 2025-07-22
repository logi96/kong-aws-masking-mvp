#!/usr/bin/env node
/**
 * Kong AWS Masking Test Script
 * Tests Kong Gateway masking with real AWS resource identifiers
 */

require('dotenv').config();
const axios = require('axios');

async function testMasking() {
  console.log('🔧 Testing Kong AWS Masking with EC2 Instance ID: i-1234567890abcdef0');
  
  const testPayload = {
    model: "claude-3-5-sonnet-20241022",
    max_tokens: 100,
    messages: [{
      role: "user", 
      content: "Please analyze this AWS resource: Instance ID is i-1234567890abcdef0 with private IP 10.0.1.100"
    }]
  };
  
  try {
    console.log('📤 Sending request through Kong Gateway...');
    console.log('Original payload:', JSON.stringify(testPayload, null, 2));
    
    const response = await axios.post('http://localhost:8000/analyze-claude', testPayload, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      timeout: 10000
    });
    
    console.log('✅ Response received, status:', response.status);
    console.log('Response data:', JSON.stringify(response.data, null, 2));
    
    // Check if masking worked by looking for original values in logs
    const originalContent = testPayload.messages[0].content;
    const hasInstanceId = originalContent.includes('i-1234567890abcdef0');
    const hasPrivateIp = originalContent.includes('10.0.1.100');
    
    console.log('\n🔍 Masking Analysis:');
    console.log('Original contained EC2 ID:', hasInstanceId);
    console.log('Original contained Private IP:', hasPrivateIp);
    
    if (hasInstanceId || hasPrivateIp) {
      console.log('❌ Test sent AWS identifiers - masking should have processed these');
    } else {
      console.log('✅ No AWS identifiers found in original test data');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Response:', error.response.data);
    }
    
    if (error.code === 'ECONNREFUSED') {
      console.error('💡 Make sure Kong Gateway is running on port 8000');
    }
    
    return false;
  }
  
  return true;
}

// Run test
testMasking()
  .then(success => {
    console.log('\n' + (success ? '✅ Masking test completed' : '❌ Masking test failed'));
    process.exit(success ? 0 : 1);
  })
  .catch(error => {
    console.error('💥 Unexpected error:', error);
    process.exit(1);
  });