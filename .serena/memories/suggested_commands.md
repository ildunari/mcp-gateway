# Suggested Commands for MCP Gateway Development

## Development Commands

### Running the Server
```bash
# Development mode with auto-reload (Mac/Linux)
npm run dev

# Development mode with auto-reload (Windows)
npm run dev:windows

# Production mode
npm start

# Testing mode
npm test
```

### Package Management
```bash
# Install all dependencies
npm install

# Install a new dependency
npm install <package-name>

# Install a dev dependency
npm install -D <package-name>
```

### Cloudflare Tunnel
```bash
# Run tunnel (if not running as service)
cloudflared tunnel run mcp-gateway

# Check tunnel status
cloudflared tunnel info mcp-gateway

# Update DNS routing
cloudflared tunnel route dns mcp-gateway gateway.pluginpapi.dev
```

### Testing & Debugging
```bash
# Check server health
curl http://localhost:4242/health

# List available servers
curl http://localhost:4242/servers

# View logs
tail -f logs/combined.log
tail -f logs/error.log

# Test with MCP Inspector (before Claude integration)
npx @modelcontextprotocol/inspector http://localhost:4242/mcp/github
```

### Process Management (Windows)
```bash
# Install as Windows service
nssm install mcp-gateway "C:\Program Files\nodejs\node.exe" "C:\path\to\server.js"

# Start/stop service
nssm start mcp-gateway
nssm stop mcp-gateway
nssm restart mcp-gateway

# Check service status
nssm status mcp-gateway
```

### Environment Setup
```bash
# Generate secure token for auth
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# Copy example env (if exists)
cp .env.example .env
```

### Git Commands
```bash
# Initialize git repo
git init

# Add all files
git add .

# Commit changes
git commit -m "Initial commit"

# Check status
git status

# View logs
git log --oneline
```