#!/usr/bin/env node
/**
 * Simple Mapping Consistency Test
 * Clear test with simple requests to check mapping behavior
 */

require('dotenv').config();
const axios = require('axios');

async function testSimpleConsistency() {
  console.log('🧪 Simple Kong AWS Masking Consistency Test');
  console.log('============================================');

  // Test 1: Single instance
  console.log('\n🔬 Test 1: Single EC2 Instance');
  console.log('Input: i-1234567890abcdef0');
  
  const test1 = await sendSimpleRequest('List resource: i-1234567890abcdef0');
  console.log('Claude Response:', test1.content);
  const test1Mapping = extractFirstEC2(test1.content);
  console.log('Extracted Mapping:', test1Mapping);

  await sleep(1000);

  // Test 2: Same instance again
  console.log('\n🔬 Test 2: Same EC2 Instance (Repeat)');
  console.log('Input: i-1234567890abcdef0');
  
  const test2 = await sendSimpleRequest('Identify resource: i-1234567890abcdef0');
  console.log('Claude Response:', test2.content);
  const test2Mapping = extractFirstEC2(test2.content);
  console.log('Extracted Mapping:', test2Mapping);

  // Analysis
  console.log('\n📊 Mapping Consistency Analysis:');
  console.log('=================================');
  console.log(`Test 1 mapping: i-1234567890abcdef0 → ${test1Mapping}`);
  console.log(`Test 2 mapping: i-1234567890abcdef0 → ${test2Mapping}`);
  
  if (test1Mapping && test2Mapping && test1Mapping === test2Mapping) {
    console.log('\n✅ CONSISTENT: Same resource got same masked ID');
    console.log('🔒 Mapping Behavior: GLOBAL PERSISTENCE (Same resource → Same mask)');
  } else {
    console.log('\n❌ INCONSISTENT: Same resource got different masked IDs');
    console.log('🔄 Mapping Behavior: REQUEST-SCOPED (New mask each time)');
  }

  await sleep(1000);

  // Test 3: Different instance
  console.log('\n🔬 Test 3: Different EC2 Instance');
  console.log('Input: i-abcdef1234567890');
  
  const test3 = await sendSimpleRequest('Show resource: i-abcdef1234567890');
  console.log('Claude Response:', test3.content);
  const test3Mapping = extractFirstEC2(test3.content);
  console.log('Extracted Mapping:', test3Mapping);
  
  console.log('\n📈 Counter Behavior Analysis:');
  console.log('============================');
  console.log(`First instance (i-1234567890abcdef0): ${test1Mapping}`);
  console.log(`Second instance (i-abcdef1234567890): ${test3Mapping}`);
  
  if (test1Mapping && test3Mapping) {
    const firstNum = parseInt(test1Mapping.replace('EC2_', ''));
    const secondNum = parseInt(test3Mapping.replace('EC2_', ''));
    
    if (secondNum > firstNum) {
      console.log('✅ INCREMENTAL: Counter increases for new resources');
    } else {
      console.log('❓ UNEXPECTED: Counter behavior is unclear');
    }
  }
}

async function sendSimpleRequest(content) {
  try {
    const response = await axios.post('http://localhost:8000/analyze-claude', {
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 50,
      messages: [{ role: "user", content: content }]
    }, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      timeout: 8000
    });

    return {
      success: true,
      content: response.data.content[0].text
    };
  } catch (error) {
    console.error(`❌ Request failed: ${error.message}`);
    return { success: false, error: error.message };
  }
}

function extractFirstEC2(content) {
  const match = content.match(/EC2_\d{3}/);
  return match ? match[0] : null;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

testSimpleConsistency().catch(console.error);