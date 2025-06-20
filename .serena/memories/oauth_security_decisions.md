# OAuth Security Decisions and Rationale

## Key Security Implementations

### 1. Authorization Code Handling
- **10-minute expiration**: Maximum recommended by OAuth 2.0 RFC
- **Single-use enforcement**: Codes deleted immediately after use
- **Cryptographic generation**: Using crypto.randomUUID() for unpredictability

### 2. PKCE Implementation
- **Full support**: Both plain and S256 methods
- **Proper SHA256**: Using crypto.createHash() with base64url encoding
- **Mandatory verification**: If challenge present, verifier required

### 3. State Parameter
- **Required parameter**: Prevents CSRF attacks
- **Preserved through flow**: Returned unchanged in redirect
- **Validation**: Must be present in authorization request

### 4. Redirect URI Validation
- **Exact match required**: Between authorization and token requests
- **Stored with code**: Prevents code substitution attacks
- **No wildcards**: Strict validation for security

## Claude.ai Specific Considerations

### 1. Dynamic Client Registration
- **Not implemented**: Personal gateway doesn't need it
- **Impact**: Users add integration by URL in Claude settings
- **Future**: Can add if Claude.ai makes it mandatory

### 2. Authentication Spec
- **Following 3/26 spec**: As referenced in Claude.ai docs
- **OAuth 2.0 compliant**: Standard authorization code flow
- **Ready for updates**: Monitoring for new spec requirements

### 3. No Refresh Tokens
- **Design choice**: 1-year access tokens for simplicity
- **Personal use**: No need for token rotation
- **Can add later**: If Claude.ai requires shorter-lived tokens

## Error Handling Philosophy

### 1. OAuth Compliant Errors
- Using standard error codes (invalid_request, invalid_grant, etc.)
- Descriptive error_description for debugging
- Proper HTTP status codes (400 for client errors)

### 2. No Information Leakage
- Generic errors for invalid codes
- No timing attacks (consistent response times)
- No hints about valid vs invalid parameters

### 3. Logging Strategy
- Log enough for debugging (with prefixes like "OAuth authorize request:")
- Never log sensitive data (tokens, full codes)
- Use log levels appropriately (info, warn, error)