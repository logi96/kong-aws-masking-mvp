#!/usr/bin/env node
/**
 * Mapping Consistency Test
 * Tests if same AWS resources get same masked IDs regardless of order
 */

require('dotenv').config();
const axios = require('axios');

async function testMappingConsistency() {
  console.log('🔍 Kong AWS Masking - Mapping Consistency Test');
  console.log('==============================================');

  const instances = [
    'i-0a1b2c3d4e5f67890',
    'i-abcdef123456789ab', 
    'i-98765432109876543'
  ];

  // Test 1: Original order
  console.log('\n📋 Test 1: Original Order');
  console.log('Input:', instances.join(', '));
  
  const test1Response = await sendRequest(
    `Analyze these instances: ${instances.join(', ')}`
  );
  
  if (test1Response.success) {
    console.log('Claude Response:', test1Response.content.substring(0, 200) + '...');
    const test1Mappings = extractMappings(test1Response.content);
    console.log('Extracted Mappings:', test1Mappings);
  }

  // Small delay to ensure separate request
  await sleep(2000);

  // Test 2: Changed order
  const reorderedInstances = [
    'i-0a1b2c3d4e5f67890',  // Same as position 0
    'i-98765432109876543',  // Was position 2
    'i-abcdef123456789ab'   // Was position 1
  ];

  console.log('\n📋 Test 2: Changed Order');
  console.log('Input:', reorderedInstances.join(', '));
  
  const test2Response = await sendRequest(
    `Analyze these instances: ${reorderedInstances.join(', ')}`
  );
  
  if (test2Response.success) {
    console.log('Claude Response:', test2Response.content.substring(0, 200) + '...');
    const test2Mappings = extractMappings(test2Response.content);
    console.log('Extracted Mappings:', test2Mappings);
    
    // Analysis
    console.log('\n🔍 Consistency Analysis:');
    console.log('=======================');
    
    if (test1Response.success && test2Response.success) {
      const test1Maps = extractMappings(test1Response.content);
      const test2Maps = extractMappings(test2Response.content);
      
      console.log('\nTest 1 EC2 IDs found:', test1Maps);
      console.log('Test 2 EC2 IDs found:', test2Maps);
      
      // Check if same original resources got same masked IDs
      const consistency = analyzeConsistency(test1Maps, test2Maps, instances, reorderedInstances);
      
      if (consistency.isConsistent) {
        console.log('\n✅ CONSISTENT MAPPING: Same resources → Same masked IDs');
        console.log('📊 Mapping behavior: GLOBAL PERSISTENCE');
      } else {
        console.log('\n❌ INCONSISTENT MAPPING: Same resources → Different masked IDs');  
        console.log('📊 Mapping behavior: REQUEST-SCOPED');
      }
      
      console.log('\nDetailed Analysis:');
      consistency.details.forEach(detail => console.log(detail));
    }
  }

  console.log('\n🏁 Mapping Consistency Test Complete');
}

async function sendRequest(content) {
  try {
    const response = await axios.post('http://localhost:8000/analyze-claude', {
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 150,
      messages: [{
        role: "user",
        content: content
      }]
    }, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      timeout: 10000
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

function extractMappings(content) {
  const ec2Pattern = /EC2_\d{3}/g;
  return content.match(ec2Pattern) || [];
}

function analyzeConsistency(test1Maps, test2Maps, originalOrder, reorderedOrder) {
  const details = [];
  let isConsistent = true;
  
  // Check each original instance across both tests
  for (let i = 0; i < originalOrder.length; i++) {
    const originalInstance = originalOrder[i];
    const test1Position = i;
    const test2Position = reorderedOrder.indexOf(originalInstance);
    
    const test1MaskedId = test1Maps[test1Position];
    const test2MaskedId = test2Maps[test2Position];
    
    if (test1MaskedId === test2MaskedId) {
      details.push(`✅ ${originalInstance} → ${test1MaskedId} (consistent)`);
    } else {
      details.push(`❌ ${originalInstance} → Test1: ${test1MaskedId}, Test2: ${test2MaskedId} (inconsistent)`);
      isConsistent = false;
    }
  }
  
  return { isConsistent, details };
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Run test
testMappingConsistency().catch(console.error);