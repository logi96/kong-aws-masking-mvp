# Technology Stack - AIDA Phase 2

## Runtime Environment
```json
{
  "node": ">=20.11.0",
  "typescript": "^5.5.3"
}
```

## Core Dependencies
```json
{
  "@a2a-js/sdk": "^0.2.2",
  "vitest": "^2.0.3",
  "tsx": "^4.16.2",
  "esbuild": "^0.23.0"
}
```

## Quality Tools
```json
{
  "eslint": "^9.6.0",
  "prettier": "^3.3.3",
  "husky": "^9.1.0",
  "lint-staged": "^15.2.7"
}
```

## Data Layer
```json
{
  "pg": "^8.12.0",
  "@clickhouse/client": "^1.0.0",
  "redis": "^4.6.0"
}
```

## Version Requirements
- All versions consistent across Phase 0, 1, and 2
- Node.js 20+ for native ESM support
- TypeScript 5.5+ for latest type features