/**
 * @fileoverview /test-masking 엔드포인트 - Kong 마스킹 플로우 테스트용
 * @description AWS 리소스 마스킹/언마스킹 전체 플로우 테스트
 */

'use strict';

const express = require('express');
const claudeService = require('../../services/claude/claudeService');
const logger = require('../../../utils/logger');

const router = express.Router();

/**
 * 마스킹 테스트 요청 처리
 * @param {express.Request} req - Express request
 * @param {express.Response} res - Express response
 */
async function handleMaskingTest(req, res) {
  const startTime = Date.now();
  
  try {
    const { testText, systemPrompt } = req.body;
    
    if (!testText) {
      return res.status(400).json({
        success: false,
        error: 'testText is required'
      });
    }
    
    console.log('\n=== 마스킹 플로우 테스트 시작 ===');
    console.log('1. Backend API 수신:', testText);
    
    // Claude API 호출 (Kong을 통해)
    console.log('2. Kong Gateway로 전송 중...');
    
    const response = await claudeService.analyzeAwsData(
      { testData: testText }, // 더미 데이터로 전달
      {
        systemPrompt: systemPrompt || 'Echo exactly what I send: ' + testText,
        maxTokens: 200,
        analysisType: 'test_masking'
      }
    );
    
    console.log('3. Backend API 응답 수신 완료');
    
    const duration = Date.now() - startTime;
    
    // 응답에서 텍스트 추출
    const responseText = response.content?.[0]?.text || '';
    
    // 플로우 요약
    const flowSummary = {
      step1_backend_received: testText,
      step2_kong_will_mask: '(Kong이 AWS 패턴을 마스킹)',
      step3_claude_receives: '(마스킹된 텍스트)',
      step4_claude_responds: '(마스킹된 응답)',
      step5_kong_will_unmask: '(Kong이 응답을 언마스킹)',
      step6_backend_receives: responseText
    };
    
    res.json({
      success: true,
      flow: flowSummary,
      originalText: testText,
      finalResponse: responseText,
      duration: duration + 'ms',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('마스킹 테스트 실패:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
}

/**
 * 50개 패턴 일괄 테스트
 */
async function handleBatchTest(req, res) {
  const patterns = req.body.patterns || [];
  
  if (!patterns.length) {
    return res.status(400).json({
      success: false,
      error: 'patterns array is required'
    });
  }
  
  const results = [];
  
  for (const pattern of patterns) {
    try {
      const response = await claudeService.analyzeAwsData(
        { testData: pattern.original },
        {
          systemPrompt: `Return exactly: ${pattern.original}`,
          maxTokens: 100
        }
      );
      
      const responseText = response.content?.[0]?.text || '';
      
      results.push({
        type: pattern.type,
        original: pattern.original,
        expected_mask: pattern.masked,
        response: responseText,
        success: responseText.includes(pattern.original)
      });
      
    } catch (error) {
      results.push({
        type: pattern.type,
        original: pattern.original,
        error: error.message,
        success: false
      });
    }
  }
  
  res.json({
    success: true,
    totalPatterns: patterns.length,
    successCount: results.filter(r => r.success).length,
    results: results
  });
}

// 라우트 정의
router.post('/', handleMaskingTest);
router.post('/batch', handleBatchTest);

module.exports = router;