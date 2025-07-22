#!/usr/bin/env node
/**
 * Multiple AWS Resources Masking Test
 * Tests Kong Gateway masking with various AWS resource identifiers
 */

require('dotenv').config();
const axios = require('axios');

const testCases = [
  {
    name: "EC2 and Private IP",
    content: "EC2 instance i-1234567890abcdef0 has private IP 10.0.1.100 in subnet subnet-abc123"
  },
  {
    name: "Multiple EC2 Instances",
    content: "Instances: i-0a1b2c3d4e5f67890, i-abcdef123456789ab, and i-98765432109876543"
  },
  {
    name: "S3 and RDS Resources", 
    content: "S3 bucket: my-app-logs-bucket-2024, RDS: production-mysql-db"
  },
  {
    name: "Private IPs Range",
    content: "Network: 10.0.1.100, 10.255.255.255, 10.1.2.3 in VPC vpc-abc123"
  },
  {
    name: "Mixed AWS Resources",
    content: "Deploy i-abcd1234ef567890 to 10.0.1.50, store logs in my-logs-bucket, connect to prod-db-cluster"
  }
];

async function testMultipleResources() {
  console.log('🧪 Testing Kong AWS Masking with Multiple Resource Types');
  console.log('====================================================');
  
  for (const testCase of testCases) {
    console.log(`\n🔍 Test: ${testCase.name}`);
    console.log(`Original: ${testCase.content}`);
    
    const payload = {
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 150,
      messages: [{
        role: "user", 
        content: `Please list all AWS resources mentioned: ${testCase.content}`
      }]
    };
    
    try {
      const response = await axios.post('http://localhost:8000/analyze-claude', payload, {
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': process.env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01'
        },
        timeout: 10000
      });
      
      console.log('✅ Response received');
      const claudeContent = response.data.content[0].text;
      console.log(`Claude saw: ${claudeContent.substring(0, 200)}...`);
      
      // Check for masked identifiers in Claude's response
      const maskingIndicators = [
        /EC2_\d{3}/g,
        /PRIVATE_IP_\d{3}/g,
        /BUCKET_\d{3}/g,
        /RDS_\d{3}/g
      ];
      
      let maskedCount = 0;
      maskingIndicators.forEach((pattern, index) => {
        const matches = claudeContent.match(pattern);
        if (matches) {
          maskedCount += matches.length;
          console.log(`  📊 Found ${matches.length} masked ${['EC2', 'IP', 'S3', 'RDS'][index]} resources: ${matches.join(', ')}`);
        }
      });
      
      if (maskedCount > 0) {
        console.log(`🎯 Successfully masked ${maskedCount} resources`);
      } else {
        console.log('⚠️  No masked resources detected in response');
      }
      
    } catch (error) {
      console.error(`❌ Test failed: ${error.message}`);
      
      if (error.response) {
        console.error(`Status: ${error.response.status}`);
        if (error.response.status !== 200) {
          console.error(`Response: ${JSON.stringify(error.response.data, null, 2)}`);
        }
      }
    }
    
    // Small delay between tests
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  
  console.log('\n🎉 Multiple resource masking tests completed');
}

// Run comprehensive test
testMultipleResources()
  .catch(error => {
    console.error('💥 Test suite failed:', error);
    process.exit(1);
  });