/**
 * @fileoverview /quick-mask-test 엔드포인트 - 마스킹만 빠르게 테스트
 * @description Claude API 호출 없이 Kong 마스킹 기능만 테스트
 */

'use strict';

const express = require('express');
const router = express.Router();

/**
 * 빠른 마스킹 테스트 - 단순히 텍스트를 반환하여 Kong이 마스킹하는지 확인
 * @param {express.Request} req - Express request
 * @param {express.Response} res - Express response
 */
function handleQuickMaskTest(req, res) {
  const { testText } = req.body;
  
  if (!testText) {
    return res.status(400).json({
      success: false,
      error: 'testText is required'
    });
  }
  
  // 단순히 입력 텍스트를 에코백 - Kong이 마스킹 처리
  const response = {
    success: true,
    data: {
      originalInput: testText,
      message: "This response will be masked by Kong Gateway",
      testPatterns: [
        testText,
        `Additional test: ${testText}`,
        `JSON context: {"instanceId": "${testText}", "status": "active"}`
      ]
    },
    timestamp: new Date().toISOString()
  };
  
  // 즉시 응답 - Claude API 호출 없음
  res.status(200).json(response);
}

// Route definition
router.post('/', handleQuickMaskTest);

module.exports = { 
  router,
  handleQuickMaskTest
};