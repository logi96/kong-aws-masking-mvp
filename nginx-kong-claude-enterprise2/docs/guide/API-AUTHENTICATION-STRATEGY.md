# API Authentication Strategy

## Overview
This document outlines the comprehensive API authentication strategy for the Kong AWS Masking MVP, supporting both API Key and JWT authentication methods with rate limiting and management interfaces.

## Architecture Design

### 1. Authentication Flow
```
Client Request → Kong Gateway → Authentication Plugin → Rate Limiting → Backend API
                      ↓                     ↓                ↓
                 API Key/JWT         Validation      Per-Key Limits
```

### 2. Supported Authentication Methods

#### 2.1 API Key Authentication
- **Location**: Header (`X-API-Key`) or Query Parameter (`apikey`)
- **Format**: UUID v4 (e.g., `550e8400-e29b-41d4-a716-446655440000`)
- **Storage**: Kong's built-in Key-Auth plugin with Redis backend
- **Validation**: Real-time validation against Kong's datastore

#### 2.2 JWT Authentication
- **Location**: Authorization header (`Bearer <token>`)
- **Algorithm**: RS256 (recommended) or HS256
- **Claims**: 
  - `sub`: Subject (user/service identifier)
  - `iss`: Issuer (your organization)
  - `exp`: Expiration time
  - `iat`: Issued at
  - `scope`: Permission scopes
- **Validation**: Public key verification for RS256, shared secret for HS256

### 3. Rate Limiting Strategy

#### 3.1 Per-API-Key Limits
- **Default**: 100 requests per minute
- **Premium**: 1000 requests per minute
- **Enterprise**: Custom limits

#### 3.2 Rate Limit Headers
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1609459200
```

### 4. API Key Management Interface

#### 4.1 Endpoints
```
POST   /api/v1/auth/keys          # Create new API key
GET    /api/v1/auth/keys          # List API keys
GET    /api/v1/auth/keys/{id}     # Get specific key details
PUT    /api/v1/auth/keys/{id}     # Update key (e.g., rate limits)
DELETE /api/v1/auth/keys/{id}     # Revoke API key
POST   /api/v1/auth/keys/{id}/rotate  # Rotate API key
```

#### 4.2 Key Metadata
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Production API Key",
  "created_at": "2024-01-01T00:00:00Z",
  "last_used": "2024-01-15T12:30:00Z",
  "rate_limit": {
    "requests_per_minute": 100,
    "tier": "standard"
  },
  "scopes": ["read:aws", "write:masking"],
  "status": "active"
}
```

## Kong Plugin Configuration

### 1. Key-Auth Plugin
```yaml
plugins:
  - name: key-auth
    service: claude-api-service
    config:
      key_names: 
        - X-API-Key
        - apikey
      key_in_body: false
      hide_credentials: true
      anonymous: null
      run_on_preflight: true
```

### 2. JWT Plugin
```yaml
plugins:
  - name: jwt
    service: claude-api-service
    config:
      uri_param_names:
        - jwt
      cookie_names:
        - jwt
      header_names:
        - authorization
      claims_to_verify:
        - exp
      key_claim_name: iss
      secret_is_base64: false
      anonymous: null
      run_on_preflight: true
```

### 3. Rate Limiting Plugin
```yaml
plugins:
  - name: rate-limiting
    service: claude-api-service
    config:
      minute: 100
      hour: 5000
      policy: redis
      redis_host: redis
      redis_port: 6379
      redis_password: "${REDIS_PASSWORD}"
      redis_timeout: 2000
      redis_database: 1
      fault_tolerant: true
      hide_client_headers: false
      limit_by: credential
```

## Backend Implementation

### 1. Authentication Middleware
```javascript
// middlewares/auth.js
const authenticateRequest = async (req, res, next) => {
  // Kong handles primary authentication
  // Backend verifies Kong headers
  const kongConsumer = req.headers['x-consumer-id'];
  const kongCredential = req.headers['x-credential-identifier'];
  
  if (!kongConsumer || !kongCredential) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  // Attach consumer info to request
  req.auth = {
    consumerId: kongConsumer,
    credentialId: kongCredential,
    username: req.headers['x-consumer-username'],
    customId: req.headers['x-consumer-custom-id']
  };
  
  next();
};
```

### 2. API Key Management Service
```javascript
// services/auth/apiKeyService.js
class ApiKeyService {
  async createApiKey(userId, metadata) {
    // Generate new API key
    // Store in Kong via Admin API
    // Return key details
  }
  
  async listApiKeys(userId) {
    // Fetch keys from Kong
    // Return filtered list
  }
  
  async revokeApiKey(keyId) {
    // Delete from Kong
    // Log revocation
  }
  
  async updateRateLimit(keyId, newLimit) {
    // Update Kong consumer rate limit
  }
}
```

## Security Considerations

### 1. API Key Security
- Keys are generated using cryptographically secure random functions
- Keys are hashed before storage (SHA-256)
- Keys are never logged in plaintext
- Keys support automatic rotation

### 2. JWT Security
- Use RS256 for production (asymmetric)
- Rotate signing keys periodically
- Short token expiration (1 hour default)
- Include `jti` claim for revocation support

### 3. Rate Limiting
- Implement distributed rate limiting with Redis
- Graceful degradation if Redis is unavailable
- Clear rate limit feedback to clients
- Different limits per authentication method

### 4. Audit Logging
- Log all authentication attempts
- Track API key usage patterns
- Monitor for suspicious activity
- Alert on repeated failures

## Implementation Phases

### Phase 1: Basic API Key Authentication
1. Enable Kong Key-Auth plugin
2. Create consumer management endpoints
3. Implement basic rate limiting
4. Add authentication middleware to backend

### Phase 2: JWT Support
1. Configure Kong JWT plugin
2. Implement JWT validation
3. Add scope-based authorization
4. Create JWT issuance endpoint

### Phase 3: Advanced Features
1. API key rotation mechanism
2. Advanced rate limiting tiers
3. Usage analytics dashboard
4. Webhook notifications for events

### Phase 4: Management UI
1. Web-based key management interface
2. Usage visualization
3. Self-service key generation
4. Admin oversight capabilities

## Monitoring & Alerts

### 1. Key Metrics
- Authentication success/failure rates
- API key usage by consumer
- Rate limit violations
- Token expiration patterns

### 2. Alerts
- Repeated authentication failures
- Unusual usage patterns
- Rate limit threshold warnings
- Expired credential usage

## Testing Strategy

### 1. Unit Tests
- Key generation logic
- JWT validation
- Rate limit calculations
- Authentication middleware

### 2. Integration Tests
- End-to-end authentication flow
- Kong plugin configuration
- Rate limiting across services
- Key management operations

### 3. Security Tests
- Penetration testing
- Key entropy validation
- JWT signature verification
- Rate limit bypass attempts