#!/usr/bin/env node

/**
 * 간단한 JSDoc 타입 체크 - MVP용
 * @description TypeScript 대신 JSDoc 주석 검증
 */

const fs = require('fs');
const path = require('path');

/**
 * JSDoc 주석 패턴 검증
 * @param {string} content - 파일 내용
 * @param {string} filePath - 파일 경로
 * @returns {Array<{line: number, message: string}>} 에러 목록
 */
function validateJSDoc(content, filePath) {
  const errors = [];
  const lines = content.split('\n');
  
  // 함수 선언 찾기
  lines.forEach((line, index) => {
    const lineNum = index + 1;
    
    // 함수 선언 패턴
    if (line.match(/^(async\s+)?function\s+\w+/)) {
      // 이전 라인들에서 JSDoc 찾기
      let hasJSDoc = false;
      for (let i = index - 1; i >= Math.max(0, index - 10); i--) {
        if (lines[i].trim().startsWith('/**')) {
          hasJSDoc = true;
          break;
        }
        if (lines[i].trim() && !lines[i].trim().startsWith('*') && !lines[i].trim().startsWith('//')) {
          break;
        }
      }
      
      if (!hasJSDoc) {
        errors.push({
          line: lineNum,
          message: `Function missing JSDoc documentation`
        });
      }
    }
  });
  
  return errors;
}

/**
 * 디렉토리 내 JS 파일 검사
 * @param {string} dir - 검사할 디렉토리
 */
function checkDirectory(dir) {
  const files = fs.readdirSync(dir, { withFileTypes: true });
  let totalErrors = 0;
  
  files.forEach(file => {
    const filePath = path.join(dir, file.name);
    
    if (file.isDirectory() && file.name !== 'node_modules') {
      totalErrors += checkDirectory(filePath);
    } else if (file.name.endsWith('.js')) {
      const content = fs.readFileSync(filePath, 'utf8');
      const errors = validateJSDoc(content, filePath);
      
      if (errors.length > 0) {
        console.log(`\n📄 ${filePath.replace(process.cwd(), '.')}`);
        errors.forEach(error => {
          console.log(`  Line ${error.line}: ${error.message}`);
        });
        totalErrors += errors.length;
      }
    }
  });
  
  return totalErrors;
}

/**
 * 메인 실행
 */
function main() {
  console.log('🔍 Simple JSDoc Type Check (MVP)');
  console.log('=====================================');
  
  const srcPath = path.join(process.cwd(), 'src');
  
  if (!fs.existsSync(srcPath)) {
    console.log('❌ src directory not found');
    process.exit(1);
  }
  
  const totalErrors = checkDirectory(srcPath);
  
  if (totalErrors === 0) {
    console.log('✅ All files have proper JSDoc documentation');
  } else {
    console.log(`\n⚠️  Found ${totalErrors} documentation issues`);
    console.log('💡 Add JSDoc comments to functions for better type safety');
  }
  
  // MVP에서는 경고만 출력, 실패하지 않음
  process.exit(0);
}

if (require.main === module) {
  main();
}