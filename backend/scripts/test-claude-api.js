#!/usr/bin/env node

/**
 * @fileoverview Claude API 연결성 테스트 스크립트
 * @description 실제 Claude API 키가 올바르게 작동하는지 검증
 */

require('dotenv').config();

/**
 * Claude API 테스트 실행
 * @returns {Promise<void>}
 */
async function testClaudeAPI() {
  console.log('🔑 Claude API 연결성 테스트 시작...');
  console.log('=====================================');
  
  // 환경 변수 확인
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error('❌ ANTHROPIC_API_KEY 환경 변수가 설정되지 않았습니다.');
    process.exit(1);
  }

  if (!apiKey.startsWith('sk-ant-api03-')) {
    console.error('❌ Claude API 키 형식이 올바르지 않습니다.');
    process.exit(1);
  }

  console.log(`✅ API 키 형식 검증 완료: ${apiKey.substring(0, 20)}...`);
  console.log(`🌏 AWS 리전: ${process.env.AWS_REGION}`);
  console.log(`🚀 Kong 프록시 URL: ${process.env.KONG_PROXY_URL}`);

  try {
    // Claude Service 로드 및 테스트
    const claudeService = require('../src/services/claude/claudeService');
    
    console.log('📡 Claude API 연결성 테스트 실행 중...');
    const result = await claudeService.testConnection();

    if (result.success) {
      console.log('✅ Claude API 연결 성공!');
      console.log(`📊 응답 시간: ${result.duration}ms`);
      console.log(`🤖 모델: ${result.model}`);
      console.log(`🔢 토큰 사용량:`, result.usage);
    } else {
      console.error('❌ Claude API 연결 실패:', result.error);
      process.exit(1);
    }

  } catch (error) {
    console.error('💥 Claude API 테스트 중 오류 발생:', error.message);
    
    if (error.message.includes('Connection refused')) {
      console.log('💡 Kong Gateway가 실행되지 않은 것으로 보입니다.');
      console.log('   다음 명령으로 Kong을 시작하세요: docker-compose up kong');
    }
    
    process.exit(1);
  }

  console.log('=====================================');
  console.log('🎉 모든 연결성 테스트가 완료되었습니다.');
}

// 메인 실행
if (require.main === module) {
  testClaudeAPI();
}

module.exports = { testClaudeAPI };