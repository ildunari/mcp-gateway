# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an MCP (Model Context Protocol) Gateway that hosts multiple MCP servers under a unified gateway accessible from Claude.ai. The gateway acts as a proxy, routing requests from Claude.ai to local MCP servers through a secure Cloudflare tunnel.

## Architecture

The request flow is:
```
Claude.ai → Anthropic Backend → gateway.pluginpapi.dev → Cloudflare Tunnel → Local Computer (Port 4242) → MCP Servers
```

Key architectural decisions:
- Express.js server handling OAuth 2.0 authentication and MCP protocol routing
- Child process spawning for individual MCP servers with stdio transport
- Session-based architecture supporting multiple concurrent Claude sessions
- SSE (Server-Sent Events) transport with planned migration to Streamable HTTP

## Common Development Commands

```bash
# Install dependencies
npm install

# Development with auto-reload
npm run dev  # Unix/Mac
npm run dev:windows  # Windows

# Production start
npm start

# Local testing
npm test
```

## Project Structure

The codebase follows this modular structure:
- `src/server.js` - Main Express server with OAuth, CORS, rate limiting
- `src/auth.js` - OAuth 2.0 flow implementation for Claude.ai
- `src/registry.js` - MCP server registry and process management
- `config/servers.json` - MCP server definitions and configurations
- `logs/` - Application logs (Winston logging)

## Key Implementation Details

### Adding New MCP Servers
1. Update `config/servers.json` with server definition
2. Ensure the server supports stdio transport
3. Test locally before deploying

### Environment Configuration
Required `.env` variables:
```
CLIENT_ID=<from MCP settings>
CLIENT_SECRET=<from MCP settings>
REDIRECT_URI=https://gateway.pluginpapi.dev/callback
ACCESS_TOKEN=<generated from setup>
PORT=4242
```

### Testing Approach
1. Start server locally with `npm test`
2. Test health endpoint: `http://localhost:4242/health`
3. Test with MCP Inspector before Claude.ai integration
4. Use Cloudflare tunnel for production testing

### Security Considerations
- OAuth token validation on all requests
- Rate limiting (100 requests per 15 minutes)
- CORS restricted to Claude.ai domains
- Automatic session cleanup after 10 minutes

### Common Debugging
- Check logs in `logs/` directory for detailed error information
- Verify MCP server processes are spawning correctly
- Ensure Cloudflare tunnel is running: `cloudflared tunnel run mcp-gateway`
- Test individual MCP servers with MCP Inspector first

## Important Notes

1. **Transport Protocol**: Currently using SSE, but prepared for Streamable HTTP migration
2. **Process Management**: Each MCP server runs as a child process with proper cleanup
3. **Session Handling**: Sessions are isolated and automatically cleaned up
4. **Error Recovery**: Graceful shutdown and restart capabilities built-in

When implementing features, prioritize:
- Security (token validation, input sanitization)
- Reliability (proper error handling, process cleanup)
- Performance (efficient routing, minimal overhead)
- Logging (comprehensive debug information)