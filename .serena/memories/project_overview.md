# MCP Gateway Project Overview

## Purpose
The MCP Gateway is a unified gateway server that hosts multiple MCP (Model Context Protocol) servers under a single domain (`gateway.pluginpapi.dev`), making them accessible from Claude.ai. It acts as a proxy/router that forwards requests from Claude.ai to local MCP servers through a secure Cloudflare tunnel.

## Architecture
- **Request Flow**: Claude.ai → Anthropic Backend → gateway.pluginpapi.dev → Cloudflare Tunnel → Local Computer (Port 4242) → Individual MCP Servers
- **Transport**: Currently using SSE (Server-Sent Events) with planned migration to Streamable HTTP
- **Session Management**: Supports multiple concurrent Claude sessions with 10-minute timeout for inactive sessions
- **Process Model**: Each MCP server runs as a child process with stdio transport

## Tech Stack
- **Runtime**: Node.js
- **Framework**: Express.js
- **Protocol**: Model Context Protocol (MCP) SDK
- **Authentication**: OAuth 2.0
- **Logging**: Winston
- **Security**: express-rate-limit, CORS
- **Infrastructure**: Cloudflare Tunnel for secure exposure
- **Process Management**: NSSM for Windows Service

## Key Features
- Modular server registry for easy addition of new MCP servers
- Comprehensive logging and error handling
- Rate limiting (100 requests per 15 minutes)
- CORS restricted to Claude.ai domains
- Health check endpoints for monitoring
- Graceful shutdown and process cleanup