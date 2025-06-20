# OAuth Implementation Plan for Claude.ai Integration

## Current Status
The auth.js file has already been implemented with the following OAuth endpoints:
- OAuth discovery endpoint: `/.well-known/oauth-authorization-server`
- Authorization endpoint: `/oauth/authorize`
- Token endpoint: `/oauth/token`

## Key Features Already Implemented
1. **OAuth Discovery**: Returns proper metadata for Claude.ai to discover OAuth endpoints
2. **Authorization Flow**: Auto-approves requests (personal use) with proper validation
3. **PKCE Support**: Implements code_challenge and code_verifier for enhanced security
4. **Token Exchange**: Validates authorization codes and returns access tokens
5. **Code Expiration**: 10-minute expiration with automatic cleanup
6. **Security Validations**: Redirect URI matching, grant type validation, parameter checks

## Architecture Decisions
- Using in-memory storage for authorization codes (Map)
- Auto-approval for personal use (no UI needed)
- 1-year token expiry for convenience
- Periodic cleanup of expired codes every minute

## Next Steps
1. Fetch and study Claude.ai OAuth documentation
2. Verify our implementation meets all Claude.ai requirements
3. Create comprehensive test suite
4. Document any Claude.ai specific adaptations