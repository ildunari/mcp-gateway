# @ildunari/mcp-gateway

A unified gateway server for hosting multiple MCP (Model Context Protocol) servers, making them accessible from Claude.ai through a single endpoint.

## Overview

The MCP Gateway acts as a proxy server that routes requests from Claude.ai to various MCP servers running on your local machine. This allows you to use multiple MCP tools within Claude without having to manage multiple endpoints.

## Features

- 🔄 **Unified Endpoint**: Access all your MCP servers through a single gateway
- 🔒 **Secure Authentication**: OAuth 2.0 integration with Claude.ai
- 🚀 **Easy Server Management**: Simple configuration to add/remove MCP servers
- 📊 **Comprehensive Logging**: Built-in Winston logging for debugging
- ⚡ **Session Management**: Isolated sessions with automatic cleanup
- 🛡️ **Rate Limiting**: Protection against excessive requests
- 🔧 **Extensible**: Easy to add new MCP servers

## Architecture

```
Claude.ai → MCP Gateway → Individual MCP Servers
                ↓
          ┌─────────────┐
          │   GitHub    │
          │   Server    │
          └─────────────┘
          ┌─────────────┐
          │  Desktop    │
          │ Commander   │
          └─────────────┘
          ┌─────────────┐
          │   Custom    │
          │   Server    │
          └─────────────┘
```

## Installation

```bash
npm install @ildunari/mcp-gateway
```

Or clone from GitHub:

```bash
git clone https://github.com/ildunari/mcp-gateway.git
cd mcp-gateway
npm install
```

## Quick Start

1. **Configure Environment Variables**

Create a `.env` file:

```bash
PORT=4242
GATEWAY_AUTH_TOKEN=your-secure-token-here
NODE_ENV=production
```

2. **Configure MCP Servers**

Edit `config/servers.json`:

```json
{
  "servers": [
    {
      "name": "github",
      "path": "github",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "your-github-token"
      },
      "enabled": true
    }
  ]
}
```

3. **Start the Gateway**

```bash
npm start
```

The gateway will be available at `http://localhost:4242`

## Usage with Claude.ai

1. Set up a tunnel to expose your local gateway (e.g., using Cloudflare Tunnel)
2. Configure Claude.ai to use your gateway endpoint
3. Your MCP servers will be available at:
   - `/mcp/github` - GitHub MCP Server
   - `/mcp/desktop` - Desktop Commander
   - `/mcp/[server-name]` - Any custom server

## Configuration

### Adding New MCP Servers

1. Update `config/servers.json` with your server configuration
2. Ensure the server supports stdio transport
3. Restart the gateway

### Server Configuration Options

```json
{
  "name": "server-name",
  "path": "url-path",
  "command": "command-to-run",
  "args": ["array", "of", "arguments"],
  "env": {
    "ENV_VAR": "value"
  },
  "enabled": true,
  "description": "Server description"
}
```

## API Endpoints

- `GET /health` - Health check and server status
- `GET /servers` - List available MCP servers
- `POST /mcp/:server` - MCP server endpoint
- `GET /oauth/authorize` - OAuth authorization
- `GET /callback` - OAuth callback

## Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Run tests
npm test
```

## Security

- OAuth 2.0 authentication required for all MCP endpoints
- Rate limiting enabled (100 requests per minute)
- CORS configured for Claude.ai domains only
- Automatic session timeout after 10 minutes of inactivity

## Logging

Logs are stored in the `logs/` directory:
- `combined.log` - All application logs
- `error.log` - Error logs only

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Links

- [GitHub Repository](https://github.com/ildunari/mcp-gateway)
- [npm Package](https://www.npmjs.com/package/@ildunari/mcp-gateway)
- [MCP Documentation](https://modelcontextprotocol.org)

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/ildunari/mcp-gateway/issues) page.