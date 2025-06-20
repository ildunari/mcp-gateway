# Server.js Implementation Plan

## Overview
Implement the main Express server for MCP Gateway following Part 4.3 of gateway.md blueprint, incorporating best practices from MCP documentation research.

## Implementation Structure

### 1. Import and Setup Phase
- Import all required modules (Express, dotenv, Winston, etc.)
- Load environment variables with dotenv
- Create Express app instance
- Set up __dirname for ES modules

### 2. Middleware Stack (Order Matters!)
1. **Body Parser** - JSON with 10mb limit for large MCP requests
2. **Request Logging** - Log all incoming requests with metadata
3. **CORS Middleware** - Restrict to Claude.ai domains only (production)
4. **Rate Limiting** - Apply to /mcp/* endpoints (100 req/15 min)
5. **Error Handling** - Global error handler at the end

### 3. Logging Configuration
- Winston logger with multiple transports:
  - File transport for errors (error.log)
  - File transport for combined logs (combined.log)
  - Console transport with colors for development
- Ensure logs directory exists before starting
- Log rotation configuration

### 4. Endpoint Implementation
- **GET /health** - Server status with environment info and server list
- **GET /servers** - List available MCP servers with metadata
- **ALL /mcp/:server** - Main MCP handler (routing only, not implementation)
- **404 Handler** - Catch all undefined routes
- **Error Handler** - Express error middleware

### 5. Server Lifecycle
- Start server on configured port
- Log startup information
- Implement graceful shutdown for SIGTERM/SIGINT
- Handle uncaught exceptions and unhandled rejections
- Cleanup resources on shutdown

### 6. Security Considerations
- Token validation in MCP endpoint (basic check)
- CORS headers properly configured
- Rate limiting to prevent abuse
- Input sanitization (handled by body parser)
- Secure error messages (no stack traces in production)

### 7. Integration Points
- Import setupAuth from auth.js
- Import ServerRegistry from registry.js
- Pass logger instance to both modules
- Registry handles actual MCP server communication

## Key Implementation Details

### CORS Configuration
```javascript
const allowedOrigins = ['https://claude.ai'];
if (process.env.NODE_ENV === 'development') {
  allowedOrigins.push('http://localhost:3000', 'http://localhost:4242');
}
```

### Rate Limiter Config
```javascript
windowMs: 15 * 60 * 1000, // 15 minutes
max: 100, // 100 requests per window
standardHeaders: true,
legacyHeaders: false
```

### Logger Format
- Timestamp, error stack traces, JSON format for files
- Colorized simple format for console
- Structured logging for better debugging

### Error Handling Strategy
- Log all errors with full context
- Return user-friendly error messages
- Different error levels (warn, error, info)
- Graceful degradation on failures

## Testing Requirements
- Server starts successfully
- All middleware loads correctly
- Endpoints return expected responses
- CORS headers are correct
- Rate limiting works
- Graceful shutdown functions
- Error handling catches all cases
- Logs are created in correct location