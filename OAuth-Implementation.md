# OAuth 2.0 Implementation for Claude.ai MCP Integration

This directory contains the OAuth 2.0 implementation required for Claude.ai to authenticate with your MCP Gateway.

## Overview

The implementation provides a complete OAuth 2.0 authorization code flow with:
- Auto-approval for personal use (no user interaction required)
- PKCE (Proof Key for Code Exchange) support for enhanced security
- Proper error handling and validation
- Authorization code cleanup mechanism
- Full compliance with Claude.ai's OAuth expectations

## Files Created

### `src/auth.js`
The main OAuth implementation with three key endpoints:

1. **Discovery Endpoint** (`/.well-known/oauth-authorization-server`)
   - Allows Claude.ai to discover OAuth endpoints
   - Returns metadata about supported flows and methods

2. **Authorization Endpoint** (`/oauth/authorize`)
   - Handles authorization requests from Claude.ai
   - Auto-approves and redirects with authorization code
   - Supports PKCE for enhanced security

3. **Token Endpoint** (`/oauth/token`)
   - Exchanges authorization codes for access tokens
   - Validates all parameters including PKCE verification
   - Returns the GATEWAY_AUTH_TOKEN from environment

### `test-server.js`
A minimal Express server for testing the OAuth implementation independently.

### `test-oauth.js`
Comprehensive test suite that verifies:
- Discovery endpoint functionality
- Authorization flow with PKCE
- Token exchange process
- Error handling for invalid requests

## Security Features

1. **Secure Code Generation**: Uses `crypto.randomUUID()` for unpredictable codes
2. **Code Expiration**: Authorization codes expire after 10 minutes
3. **PKCE Support**: Validates code challenges for enhanced security
4. **Redirect URI Validation**: Ensures token requests match authorization
5. **Automatic Cleanup**: Expired codes are cleaned up every minute

## Testing

1. Create a `.env` file:
```bash
GATEWAY_AUTH_TOKEN=your-secure-token-here
PORT=4242
```

2. Install dependencies:
```bash
npm install express dotenv winston
```

3. Run the test server:
```bash
node test-server.js
```

4. In another terminal, run the tests:
```bash
node test-oauth.js
```

## Integration with Main Server

To integrate this OAuth implementation into your main server:

1. Import the setupAuth function:
```javascript
import { setupAuth } from './auth.js';
```

2. Call it with your Express app and logger:
```javascript
setupAuth(app, logger);
```

3. Ensure you have the required middleware:
```javascript
app.use(express.json());
app.use(express.urlencoded({ extended: true })); // For token endpoint
```

## Claude.ai Integration

When adding this gateway to Claude.ai:

1. Go to https://claude.ai/settings/integrations
2. Click "Add Integration" → "Add from URL"
3. Enter your gateway URL (e.g., `https://gateway.pluginpapi.dev/mcp/github`)
4. Claude will:
   - Fetch the discovery endpoint
   - Redirect you to the authorization endpoint
   - Exchange the code for a token automatically

## Environment Variables

Required:
- `GATEWAY_AUTH_TOKEN`: The access token that will be returned to Claude.ai

Optional:
- `NODE_ENV`: Set to 'production' for production URLs
- `PORT`: Server port (default: 4242)

## Notes

- This implementation auto-approves all authorization requests since it's for personal use
- The access token is set to expire after 1 year (can be adjusted)
- All OAuth errors follow the OAuth 2.0 specification for proper error responses
- The implementation is stateless except for temporary authorization codes