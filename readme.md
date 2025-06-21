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
- 🔄 **Process Management**: Automatic restart of crashed MCP servers
- 📡 **SSE Support**: Real-time communication with Server-Sent Events

## Architecture

```
Claude.ai → Cloudflare Tunnel → MCP Gateway (Port 4242) → MCP Servers
                                      ↓
                              ┌─────────────┐
                              │   GitHub    │
                              │   Server    │
                              └─────────────┘
                              ┌─────────────┐
                              │ Filesystem  │
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

### From npm

```bash
npm install -g @ildunari/mcp-gateway
```

### From Source

```bash
git clone https://github.com/ildunari/mcp-gateway.git
cd mcp-gateway
npm install
```

## Quick Start

### 1. Configure Environment Variables

Create a `.env` file in the project root:

```bash
# Generate a secure token with:
# node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
GATEWAY_AUTH_TOKEN=your-secure-random-token-here

# Server Configuration
PORT=4242
NODE_ENV=development

# For production deployment:
# NODE_ENV=production

# Optional: GitHub Token for GitHub MCP Server
# Get from: https://github.com/settings/tokens
GITHUB_TOKEN=ghp_your_github_token_here

# Optional: Brave Search API Key
BRAVE_API_KEY=your_brave_api_key_here
```

### 2. Configure MCP Servers

The gateway comes with pre-configured servers in `config/servers.json`:

```json
{
  "servers": [
    {
      "name": "github",
      "path": "github",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      },
      "enabled": true,
      "description": "GitHub MCP Server - Access repositories, files, issues, and PRs"
    },
    {
      "name": "filesystem",
      "path": "filesystem", 
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "--allowed-directories", "${HOME}/Documents,${HOME}/Desktop"],
      "env": {},
      "enabled": true,
      "description": "Filesystem MCP Server - Read and write local files"
    },
    {
      "name": "desktop-commander",
      "path": "desktop",
      "command": "npx",
      "args": ["-y", "@wonderwhy-er/desktop-commander@latest"],
      "env": {},
      "enabled": false,
      "description": "Desktop Commander - Control desktop applications"
    }
  ]
}
```

### 3. Start the Gateway

```bash
# Development mode with auto-reload
npm run dev

# Production mode
npm start

# Windows development
npm run dev:windows
```

The gateway will start on `http://localhost:4242`

## MCP Server Configurations

### GitHub Server
- **Purpose**: Access GitHub repositories, files, issues, and pull requests
- **Requirements**: `GITHUB_TOKEN` environment variable
- **Permissions**: Based on your GitHub token scopes

### Filesystem Server
- **Purpose**: Read and write files in specified directories
- **Default Access**: `~/Documents` and `~/Desktop`
- **Configuration**: Modify `--allowed-directories` in the args to change accessible paths

### Desktop Commander
- **Purpose**: Full desktop control including file operations, command execution, and application control
- **⚠️ Security Warning**: When enabled, Desktop Commander has **unrestricted access to your entire file system and can execute any command**. Only enable if you understand the security implications.
- **Enable**: Set `"enabled": true` in the configuration
- **No Path Restrictions**: Unlike the Filesystem server, Desktop Commander is not limited to specific directories

### Adding Custom Servers

To add a new MCP server:

1. Edit `config/servers.json`
2. Add your server configuration:

```json
{
  "name": "my-server",
  "path": "my-server",
  "command": "npx",
  "args": ["-y", "@my-org/my-mcp-server"],
  "env": {
    "MY_API_KEY": "${MY_API_KEY}"
  },
  "enabled": true,
  "description": "My custom MCP server"
}
```

3. Restart the gateway

## Production Deployment

### Using Cloudflare Tunnel

1. **Install Cloudflare Tunnel**:
```bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Windows
winget install --id Cloudflare.cloudflared
```

2. **Create and Configure Tunnel**:
```bash
cloudflared tunnel create mcp-gateway
cloudflared tunnel route dns mcp-gateway gateway.yourdomain.com
```

3. **Update Tunnel Configuration** (`~/.cloudflared/config.yml`):
```yaml
tunnel: your-tunnel-id
credentials-file: /path/to/credentials.json

ingress:
  - hostname: gateway.yourdomain.com
    service: http://localhost:4242
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

4. **Run Tunnel**:
```bash
cloudflared tunnel run mcp-gateway
```

### Windows Service Installation

Use the provided PowerShell scripts in `scripts/windows/`:

```powershell
# Install as Windows service
.\scripts\windows\install-service.ps1

# Manage service
.\scripts\windows\manage-service.bat start
.\scripts\windows\manage-service.bat stop
.\scripts\windows\manage-service.bat restart
```

## Claude.ai Integration

1. Go to https://claude.ai/settings/integrations
2. Click "Add Integration" → "Add from URL"
3. Enter your gateway URL for each server:
   - GitHub: `https://gateway.yourdomain.com/mcp/github`
   - Filesystem: `https://gateway.yourdomain.com/mcp/filesystem`
   - Desktop Commander: `https://gateway.yourdomain.com/mcp/desktop` (if enabled)
4. Complete the OAuth flow (auto-approves)
5. Your MCP servers are now available in Claude!

## API Endpoints

- `GET /health` - Health check with server status
- `GET /servers` - List enabled MCP servers
- `GET /.well-known/oauth-authorization-server` - OAuth discovery
- `GET /oauth/authorize` - OAuth authorization endpoint
- `POST /oauth/token` - OAuth token exchange
- `ALL /mcp/:server` - MCP server endpoints (authenticated)

## Security Considerations

### Authentication
- All MCP endpoints require OAuth 2.0 authentication
- Bearer token must match `GATEWAY_AUTH_TOKEN` from environment
- OAuth flow auto-approves for personal use

### Access Control
- **Filesystem Server**: Limited to directories specified in configuration
- **Desktop Commander**: ⚠️ **UNRESTRICTED ACCESS** - can read/write any file and execute any command
- **GitHub Server**: Limited by GitHub token permissions

### Network Security
- CORS restricted to Claude.ai domains
- Rate limiting: 100 requests per 15 minutes per IP
- Automatic session cleanup after 10 minutes of inactivity
- All production traffic should go through HTTPS (Cloudflare Tunnel)

### Best Practices
1. Use a strong, randomly generated `GATEWAY_AUTH_TOKEN`
2. Only enable Desktop Commander if you fully trust the environment
3. Regularly review logs for suspicious activity
4. Keep the gateway and MCP servers updated
5. Use Cloudflare Tunnel for production deployments

## Troubleshooting

### Common Issues

**"502 Bad Gateway" from Cloudflare**
- Check if the gateway is running: `curl http://localhost:4242/health`
- Verify Cloudflare tunnel is running
- Check logs in `logs/combined.log`

**"401 Unauthorized" errors**
- Verify `GATEWAY_AUTH_TOKEN` is set correctly
- Ensure Claude.ai has completed OAuth flow
- Check that the token matches in both `.env` and Claude's stored token

**MCP server not starting**
- Check server logs in `logs/combined.log`
- Verify required environment variables are set
- Test the command directly: `npx -y @modelcontextprotocol/server-name`

**Desktop Commander not working**
- Ensure it's enabled in `config/servers.json`
- Check if npx can download and run it
- Review security implications before enabling

### Debug Mode

Enable debug logging:
```bash
LOG_LEVEL=debug npm run dev
```

### Windows-Specific Issues

Use the diagnostic script:
```powershell
.\scripts\windows\diagnose-issues.ps1
```

## Development

### Project Structure
```
mcp-gateway/
├── src/
│   ├── server.js        # Main Express server
│   ├── auth.js          # OAuth implementation
│   └── registry.js      # MCP server process management
├── config/
│   └── servers.json     # MCP server configurations
├── scripts/
│   └── windows/         # Windows deployment scripts
├── logs/                # Application logs
└── .env                 # Environment configuration
```

### Running Tests
```bash
# Run all tests
npm test

# OAuth flow testing
node test-oauth.js

# Server functionality
node test-server.js

# Registry stress test
node test-registry-stress.js
```

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see LICENSE file for details

## Links

- [GitHub Repository](https://github.com/ildunari/mcp-gateway)
- [npm Package](https://www.npmjs.com/package/@ildunari/mcp-gateway)
- [Model Context Protocol](https://modelcontextprotocol.io)
- [MCP Servers List](https://github.com/modelcontextprotocol/servers)

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/ildunari/mcp-gateway/issues) page.

## Changelog

### v0.1.1
- Enhanced session-based architecture
- Improved process management with auto-restart
- Added SSE support for real-time communication
- Windows service installation scripts
- Published to npm registry

### v0.1.0
- Initial release
- OAuth 2.0 integration
- Support for multiple MCP servers
- Basic process management