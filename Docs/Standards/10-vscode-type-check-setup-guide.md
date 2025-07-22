# Kong AWS Masking MVP - VS Code 타입 체크 설정 가이드

## 개요
JavaScript 프로젝트에서 TypeScript의 타입 체크 기능을 활용하는 VS Code 설정 가이드입니다.

## 1. VS Code 설정 파일

### 1.1 프로젝트 설정 (.vscode/settings.json)
```json
{
  // JavaScript 타입 체크 핵심 설정
  "javascript.implicitProjectConfig.checkJs": true,
  "javascript.suggest.autoImports": true,
  "javascript.updateImportsOnFileMove.enabled": "always",
  "javascript.preferences.includePackageJsonAutoImports": "on",
  "javascript.validate.enable": true,
  
  // 코드 품질 도구
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  
  // 에디터 설정
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "editor.rulers": [100],
  
  // 파일 설정
  "files.eol": "\n",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true
}
```

### 1.2 JavaScript 설정 (jsconfig.json)
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "checkJs": true,  // 핵심: JS 파일 타입 체크 활성화
    "lib": ["ES2022"],
    "moduleResolution": "node",
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"],
      "@services/*": ["src/services/*"],
      "@utils/*": ["src/utils/*"]
    }
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["node_modules", "dist", "coverage"]
}
```

## 2. 필수 VS Code 확장 프로그램

### 2.1 설치 권장 확장
```bash
# 명령 팔레트에서 실행 (Cmd/Ctrl + Shift + P)
# "Extensions: Install Recommended Extensions"
```

### 2.2 확장 목록
1. **ESLint** (dbaeumer.vscode-eslint)
   - JavaScript 코드 품질 검사
   - 실시간 오류 표시

2. **Prettier** (esbenp.prettier-vscode)
   - 코드 포맷팅
   - 저장 시 자동 정리

3. **Jest** (orta.vscode-jest)
   - 테스트 실행 및 디버깅
   - 인라인 테스트 결과

4. **Docker** (ms-azuretools.vscode-docker)
   - Docker 파일 지원
   - 컨테이너 관리

5. **REST Client** (humao.rest-client)
   - API 테스트
   - .http 파일 지원

## 3. 타입 체크 활용법

### 3.1 즉시 타입 오류 확인
```javascript
// ❌ 타입 오류가 빨간 밑줄로 표시됨
function processData(data) {
  return data.toLowerCase(); // data가 string이 아닐 수 있음
}

// ✅ JSDoc으로 타입 명시
/**
 * @param {string} data
 */
function processData(data) {
  return data.toLowerCase(); // 안전함
}
```

### 3.2 자동 완성 향상
```javascript
// 타입이 명시되면 자동 완성이 정확해짐
/**
 * @typedef {Object} User
 * @property {string} id
 * @property {string} name
 * @property {string} email
 */

/** @type {User} */
const user = {
  // 여기서 Ctrl+Space를 누르면 id, name, email이 제안됨
};
```

### 3.3 임포트 자동 관리
```javascript
// @/ 경로 별칭 사용 시 자동 임포트
import { MaskingService } from '@/services/maskingService';

// 파일 이동 시 자동으로 임포트 경로 업데이트
```

## 4. 문제 해결 단축키

### 4.1 주요 단축키
| 기능 | Mac | Windows/Linux |
|------|-----|---------------|
| 빠른 수정 | `Cmd + .` | `Ctrl + .` |
| 정의로 이동 | `Cmd + Click` | `Ctrl + Click` |
| 모든 참조 찾기 | `Shift + F12` | `Shift + F12` |
| 심볼 이름 바꾸기 | `F2` | `F2` |
| 타입 정보 보기 | `Cmd + K, I` | `Ctrl + K, I` |

### 4.2 타입 관련 명령
```bash
# 명령 팔레트 (Cmd/Ctrl + Shift + P)
- "TypeScript: Restart TS Server" - 타입 서버 재시작
- "TypeScript: Go to Type Definition" - 타입 정의로 이동
- "TypeScript: Find All References" - 모든 참조 찾기
```

## 5. ESLint 통합 설정

### 5.1 .eslintrc.json
```json
{
  "env": {
    "node": true,
    "es2022": true,
    "jest": true
  },
  "extends": ["eslint:recommended"],
  "parserOptions": {
    "ecmaVersion": 2022,
    "sourceType": "module"
  },
  "rules": {
    "no-unused-vars": ["error", { 
      "argsIgnorePattern": "^_",
      "varsIgnorePattern": "^_"
    }],
    "no-console": ["warn", { 
      "allow": ["warn", "error"] 
    }],
    "prefer-const": "error",
    "no-var": "error"
  },
  "overrides": [
    {
      "files": ["*.test.js", "*.spec.js"],
      "env": {
        "jest": true
      }
    }
  ]
}
```

### 5.2 타입 체크와 ESLint 연동
```javascript
// package.json
{
  "scripts": {
    "lint": "eslint . --ext .js",
    "lint:fix": "eslint . --ext .js --fix",
    "type-check": "tsc --noEmit --allowJs --checkJs",
    "validate": "npm run lint && npm run type-check"
  }
}
```

## 6. 디버깅 설정

### 6.1 launch.json
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Debug Current File",
      "program": "${file}",
      "skipFiles": [
        "<node_internals>/**"
      ]
    },
    {
      "type": "node",
      "request": "launch",
      "name": "Debug Express App",
      "program": "${workspaceFolder}/src/app.js",
      "envFile": "${workspaceFolder}/.env",
      "skipFiles": [
        "<node_internals>/**"
      ]
    },
    {
      "type": "node",
      "request": "launch",
      "name": "Jest Debug Current File",
      "program": "${workspaceFolder}/node_modules/.bin/jest",
      "args": ["${fileBasenameNoExtension}", "--coverage=false"],
      "console": "integratedTerminal",
      "internalConsoleOptions": "neverOpen"
    }
  ]
}
```

## 7. 작업 자동화

### 7.1 tasks.json
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Run Tests",
      "type": "npm",
      "script": "test",
      "group": {
        "kind": "test",
        "isDefault": true
      },
      "problemMatcher": []
    },
    {
      "label": "Type Check",
      "type": "npm",
      "script": "type-check",
      "problemMatcher": "$tsc",
      "group": "build"
    },
    {
      "label": "Docker Compose Up",
      "type": "shell",
      "command": "docker-compose up -d",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    }
  ]
}
```

## 8. 코드 스니펫

### 8.1 JavaScript 스니펫 (.vscode/javascript.code-snippets)
```json
{
  "JSDoc Function": {
    "prefix": "jsdoc",
    "body": [
      "/**",
      " * ${1:Description}",
      " * @param {${2:type}} ${3:name} - ${4:description}",
      " * @returns {${5:type}} ${6:description}",
      " */",
      "function ${7:functionName}(${3:name}) {",
      "  $0",
      "}"
    ]
  },
  "JSDoc Type": {
    "prefix": "typedef",
    "body": [
      "/**",
      " * @typedef {Object} ${1:TypeName}",
      " * @property {${2:type}} ${3:property} - ${4:description}",
      " */"
    ]
  },
  "Express Handler": {
    "prefix": "handler",
    "body": [
      "/**",
      " * ${1:Description}",
      " * @param {import('express').Request} req",
      " * @param {import('express').Response} res",
      " * @param {import('express').NextFunction} next",
      " */",
      "async function ${2:handlerName}(req, res, next) {",
      "  try {",
      "    $0",
      "  } catch (error) {",
      "    next(error);",
      "  }",
      "}"
    ]
  }
}
```

## 9. 팀 설정 공유

### 9.1 .vscode/extensions.json
```json
{
  "recommendations": [
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "orta.vscode-jest",
    "humao.rest-client",
    "ms-azuretools.vscode-docker",
    "streetsidesoftware.code-spell-checker"
  ],
  "unwantedRecommendations": []
}
```

### 9.2 팀원 온보딩
```bash
# 1. 프로젝트 클론
git clone <repository>
cd kong-aws-masking-mvp

# 2. VS Code로 열기
code .

# 3. 추천 확장 설치
# VS Code가 자동으로 확장 설치를 제안함

# 4. 의존성 설치
npm install

# 5. 타입 체크 확인
npm run type-check
```

## 10. 고급 팁

### 10.1 조건부 타입 체크
```javascript
// @ts-check
// 파일 상단에 추가하면 해당 파일만 타입 체크

// @ts-ignore
// 다음 줄의 타입 오류 무시

// @ts-expect-error
// 의도적인 타입 오류 (테스트용)
```

### 10.2 타입 정의 다운로드
```bash
# 타입 정의가 없는 패키지용
npm install --save-dev @types/package-name

# 자동 타입 획득 (jsconfig.json)
"typeAcquisition": {
  "enable": true,
  "include": ["jest", "node"]
}
```

### 10.3 성능 최적화
```json
// 큰 프로젝트에서 성능 향상
{
  "typescript.tsserver.maxTsServerMemory": 4096,
  "typescript.tsserver.useSingleInferredProject": true,
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/.git/subtree-cache/**": true,
    "**/node_modules/**": true,
    "**/dist/**": true
  }
}
```

## 11. 문제 해결

### 11.1 타입 체크가 작동하지 않을 때
1. TypeScript 서버 재시작: `Cmd/Ctrl + Shift + P` → "Restart TS Server"
2. VS Code 재시작
3. `node_modules` 삭제 후 재설치
4. jsconfig.json 확인

### 11.2 느린 성능
1. 제외 패턴 추가 (exclude in jsconfig.json)
2. 메모리 할당 증가
3. 불필요한 타입 체크 비활성화

## 12. 결론

VS Code의 타입 체크 설정으로:
- **즉시 피드백**: 코드 작성 중 오류 감지
- **향상된 IntelliSense**: 정확한 자동 완성
- **안전한 리팩토링**: 타입 기반 코드 변경
- **팀 일관성**: 공유된 설정으로 동일한 개발 경험

이 설정은 TypeScript 전환 없이도 대부분의 타입 안정성 이점을 제공합니다.