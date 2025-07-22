#!/usr/bin/env node
/**
 * S3 and RDS Masking Test
 * Focused test for S3 bucket and RDS database name masking
 */

require('dotenv').config();
const axios = require('axios');

async function testS3AndRDS() {
  console.log('🪣 Testing S3 and RDS Masking');
  console.log('=============================');

  const testContent = "Store data in my-app-logs-bucket and production-mysql-db database";
  console.log(`\nOriginal: ${testContent}`);
  
  const payload = {
    model: "claude-3-5-sonnet-20241022",
    max_tokens: 100,
    messages: [{
      role: "user", 
      content: `List resources: ${testContent}`
    }]
  };
  
  try {
    const response = await axios.post('http://localhost:8000/analyze-claude', payload, {
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      timeout: 8000
    });
    
    console.log('✅ Response received');
    const claudeContent = response.data.content[0].text;
    console.log(`Claude response:\n${claudeContent}`);
    
    // Check for masking
    const bucketMask = claudeContent.match(/BUCKET_\d{3}/g);
    const rdsMask = claudeContent.match(/RDS_\d{3}/g);
    
    console.log('\n🔍 Masking Analysis:');
    console.log('S3 bucket masks found:', bucketMask || 'None');
    console.log('RDS masks found:', rdsMask || 'None');
    
    // Check if original names appear (should not)
    const hasOriginalBucket = claudeContent.includes('my-app-logs-bucket');
    const hasOriginalDB = claudeContent.includes('production-mysql-db');
    
    console.log('Original bucket name present:', hasOriginalBucket ? '❌ Yes' : '✅ No');
    console.log('Original DB name present:', hasOriginalDB ? '❌ Yes' : '✅ No');
    
    if (bucketMask || rdsMask) {
      console.log(`\n🎯 Successfully masked ${(bucketMask?.length || 0) + (rdsMask?.length || 0)} resources`);
    } else {
      console.log('\n⚠️  No S3/RDS resources were masked');
    }
    
  } catch (error) {
    console.error(`❌ Test failed: ${error.message}`);
    
    if (error.response) {
      console.error(`Status: ${error.response.status}`);
      console.error(`Response: ${JSON.stringify(error.response.data, null, 2)}`);
    }
  }
}

testS3AndRDS().catch(console.error);