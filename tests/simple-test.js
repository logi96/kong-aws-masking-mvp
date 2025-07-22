const axios = require('axios');

const BACKEND_URL = 'http://localhost:3000';
const KONG_URL = 'http://localhost:8000';

async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function testHealthCheck() {
    console.log('Testing health check...');
    try {
        const response = await axios.get(`${BACKEND_URL}/health`);
        console.log('✓ Health check passed:', response.data);
    } catch (error) {
        console.error('✗ Health check failed:', error.message);
    }
}

async function testMaskingFunctionality() {
    console.log('\nTesting masking functionality...');
    try {
        // Sample AWS data that should be masked
        const testData = {
            instances: [
                { id: 'i-1234567890abcdef0', ip: '10.0.1.100' },
                { id: 'i-0987654321fedcba0', ip: '10.0.2.200' }
            ],
            buckets: ['my-test-bucket', 'another-bucket'],
            databases: ['production-db', 'staging-db']
        };
        
        const response = await axios.post(`${KONG_URL}/analyze`, {
            aws_data: testData
        });
        
        console.log('✓ Masking test response:', JSON.stringify(response.data, null, 2));
        
        // Check if data was masked
        const responseStr = JSON.stringify(response.data);
        if (responseStr.includes('i-1234567890abcdef0') || responseStr.includes('10.0.1.100')) {
            console.error('✗ Warning: Sensitive data may not be properly masked!');
        } else {
            console.log('✓ Sensitive data appears to be masked');
        }
        
    } catch (error) {
        console.error('✗ Masking test failed:', error.message);
    }
}

async function testKongStatus() {
    console.log('\nTesting Kong status...');
    try {
        const response = await axios.get('http://localhost:8001/status');
        console.log('✓ Kong status:', response.data);
    } catch (error) {
        console.error('✗ Kong status check failed:', error.message);
    }
}

async function runTests() {
    console.log('Starting MVP test suite...\n');
    
    // Wait for services to be ready
    console.log('Waiting for services to start...');
    await sleep(5000);
    
    await testHealthCheck();
    await testKongStatus();
    await testMaskingFunctionality();
    
    console.log('\nTest suite completed!');
}

// Run tests
runTests().catch(console.error);