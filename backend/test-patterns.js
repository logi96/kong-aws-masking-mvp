#!/usr/bin/env node
/**
 * Pattern Validation Test for Kong AWS Masker
 * Tests specific AWS resource patterns without full API call
 */

const testPatterns = [
  {
    name: "EC2 Instance ID",
    pattern: /i-[0-9a-f]{8,17}/g,
    testCases: [
      "i-1234567890abcdef0",
      "i-abcdef123",
      "i-0123456789012345a"
    ],
    shouldMatch: true
  },
  {
    name: "Private IP",
    pattern: /10\.\d+\.\d+\.\d+/g,
    testCases: [
      "10.0.1.100",
      "10.255.255.255",
      "10.1.2.3"
    ],
    shouldMatch: true
  },
  {
    name: "Non-matching cases",
    pattern: /i-[0-9a-f]{8,17}/g,
    testCases: [
      "i-123",  // too short
      "i-xyz123", // invalid characters
      "instance-123"
    ],
    shouldMatch: false
  }
];

console.log('🧪 Testing AWS Resource Pattern Matching');
console.log('=====================================');

for (const test of testPatterns) {
  console.log(`\n📋 Testing: ${test.name}`);
  console.log(`Pattern: ${test.pattern}`);
  
  for (const testCase of test.testCases) {
    const matches = testCase.match(test.pattern);
    const hasMatch = matches && matches.length > 0;
    
    const expected = test.shouldMatch;
    const result = hasMatch === expected ? '✅' : '❌';
    
    console.log(`${result} "${testCase}" -> ${hasMatch ? `matched: ${matches[0]}` : 'no match'}`);
    
    if (hasMatch !== expected) {
      console.log(`   ⚠️  Expected: ${expected ? 'match' : 'no match'}, Got: ${hasMatch ? 'match' : 'no match'}`);
    }
  }
}

console.log('\n🔍 Testing Full Content Sample');
const sampleContent = "Please analyze this AWS resource: Instance ID is i-1234567890abcdef0 with private IP 10.0.1.100";

console.log('Original content:', sampleContent);

// Test EC2 pattern
const ec2Pattern = /i-[0-9a-f]{8,17}/g;
const ec2Matches = sampleContent.match(ec2Pattern);
console.log('EC2 matches:', ec2Matches);

// Test IP pattern  
const ipPattern = /10\.\d+\.\d+\.\d+/g;
const ipMatches = sampleContent.match(ipPattern);
console.log('IP matches:', ipMatches);

// Simulate masking
let maskedContent = sampleContent;
if (ec2Matches) {
  ec2Matches.forEach((match, index) => {
    maskedContent = maskedContent.replace(match, `EC2_${String(index + 1).padStart(3, '0')}`);
  });
}
if (ipMatches) {
  ipMatches.forEach((match, index) => {
    maskedContent = maskedContent.replace(match, `PRIVATE_IP_${String(index + 1).padStart(3, '0')}`);
  });
}

console.log('Masked content:', maskedContent);

const maskedCount = (ec2Matches ? ec2Matches.length : 0) + (ipMatches ? ipMatches.length : 0);
console.log(`Total resources masked: ${maskedCount}`);

console.log('\n✅ Pattern testing completed');