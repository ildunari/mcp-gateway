# MCP Gateway Blueprint - Complete Setup from Scratch

## Overview

A unified gateway to host multiple MCP servers under `gateway.pluginpapi.dev`, accessible from Claude.ai. This is a complete setup guide starting from nothing.

## Architecture

```
Claude.ai → Anthropic Backend → gateway.pluginpapi.dev → Cloudflare Tunnel → Your Computer (Port 4242)
                                         ↓
                                   /mcp/github → GitHub MCP Server
                                   /mcp/desktop → Desktop Commander MCP Server
```

## Part 1: Cloudflare Dashboard Setup (Do This First!)

### 1.1 Login to Cloudflare
1. Go to https://dash.cloudflare.com
2. Login with your account
3. Select your `pluginpapi.dev` domain

### 1.2 Add DNS Record via Dashboard
1. Click on "DNS" in the left sidebar
2. Click "Add record" button
3. Fill in:
   - **Type**: `CNAME`
   - **Name**: `gateway` (this creates gateway.pluginpapi.dev)
   - **Target**: `my-tunnel.cfargotunnel.com` (or whatever your tunnel ID is)
   - **Proxy status**: ✓ Proxied (orange cloud ON)
   - **TTL**: Auto
4. Click "Save"

**Alternative: Add DNS via Terminal (on Windows)**
```bash
cloudflared tunnel route dns my-tunnel gateway.pluginpapi.dev
```

### 1.3 Update Tunnel Configuration on Windows

1. Open File Explorer
2. Navigate to `C:\Users\kosta\.cloudflared\`
3. Find `config.yml` and make a backup copy first (name it `config.yml.backup`)
4. Edit `config.yml` with Notepad++ or VS Code
5. Update it to look like this:

```yaml
tunnel: e2c91768-7c52-4cc4-9aec-12f93e633a93
credentials-file: C:\Users\kosta\.cloudflared\e2c91768-7c52-4cc4-9aec-12f93e633a93.json

ingress:
  # Your existing MCP hub - DO NOT REMOVE THIS
  - hostname: toolhub.pluginpapi.dev
    service: http://localhost:9580
  
  # NEW SECTION - Add this
  - hostname: gateway.pluginpapi.dev
    service: http://localhost:4242
    originRequest:
      noTLSVerify: true
      connectTimeout: 0s
      disableChunkedEncoding: false
  
  # Keep this at the end
  - service: http_status:404
```

6. Save the file

### 1.4 Restart Cloudflare Tunnel

**Option A: If running as Windows Service**
1. Press Win+R, type `services.msc`, press Enter
2. Find "cloudflared" in the list
3. Right-click → Restart

**Option B: If running in terminal**
1. Press Ctrl+C to stop it
2. Run again: `cloudflared tunnel run my-tunnel`

### 1.5 Verify DNS is Working
1. Open browser
2. Go to https://gateway.pluginpapi.dev/health
3. You should see "404 Not Found" - this is GOOD! It means Cloudflare is routing correctly
4. (We haven't built the server yet, so 404 is expected)

## Part 2: Create the Project Structure

### 2.1 Mac Initial Setup (Development)

```bash
# 1. Create project directory
cd /Users/kosta/Documents/ProjectsCode
mkdir mcp-gateway
cd mcp-gateway

# 2. Initialize Node.js project
npm init -y

# 3. Create folder structure
mkdir -p src config logs
touch src/server.js src/auth.js src/registry.js
touch config/servers.json
touch .env .gitignore README.md

# 4. Open in your editor
code .  # or whatever editor you use
```

### 2.2 Project Structure You're Creating

```
mcp-gateway/
├── src/
│   ├── server.js          # Main gateway server
│   ├── auth.js            # Simple OAuth for Claude
│   └── registry.js        # MCP server registry
├── config/
│   └── servers.json       # Server configuration
├── logs/                  # Log files (created automatically)
├── package.json          # Node.js project file
├── .env                  # Environment variables (SECRET!)
├── .gitignore           # Files to ignore in git
└── README.md            # Project documentation
```

## Part 3: Install Dependencies

```bash
# In the mcp-gateway directory
npm install express dotenv @modelcontextprotocol/sdk winston express-rate-limit

# This installs:
# - express: Web server framework
# - dotenv: Environment variable management
# - @modelcontextprotocol/sdk: MCP protocol support
# - winston: Logging
# - express-rate-limit: Protection against too many requests
```

## Part 4: Create All Project Files

### 4.1 Environment Configuration (.env)

Create `.env` file with:

```bash
# Server Configuration
PORT=4242
NODE_ENV=development

# Authentication - CHANGE THIS!
GATEWAY_AUTH_TOKEN=CHANGE_ME_TO_RANDOM_TOKEN

# GitHub Personal Access Token
# Get one from: https://github.com/settings/tokens
# Needs repo, read:user scopes
GITHUB_TOKEN=your_github_token_here

# Desktop Commander Allowed Paths
# Mac paths:
DESKTOP_ALLOWED_PATHS=/Users/kosta/Documents,/Users/kosta/Desktop
# Windows paths (uncomment for Windows):
# DESKTOP_ALLOWED_PATHS=C:\Users\kosta\Documents,C:\Users\kosta\Desktop

# Logging
LOG_LEVEL=info
```

**Generate a secure token:**
```bash
# Run this in terminal to generate a random token
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Copy the output and replace `CHANGE_ME_TO_RANDOM_TOKEN` with it.

### 4.2 Git Ignore File (.gitignore)

```
# IMPORTANT: Never commit secrets!
.env
.env.local
.env.*.local

# Dependencies
node_modules/

# Logs
logs/
*.log

# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# Test files
*.test.js
coverage/
```

### 4.3 Main Server (src/server.js)

```javascript
import express from 'express';
import dotenv from 'dotenv';
import { setupAuth } from './auth.js';
import { ServerRegistry } from './registry.js';
import winston from 'winston';
import rateLimit from 'express-rate-limit';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';

// Load environment variables
dotenv.config();

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(express.json({ limit: '10mb' })); // Handle larger MCP requests

// Ensure logs directory exists
const logsDir = join(__dirname, '..', 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir, { recursive: true });
}

// Logging setup
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ 
      filename: join(logsDir, 'error.log'), 
      level: 'error' 
    }),
    new winston.transports.File({ 
      filename: join(logsDir, 'combined.log') 
    }),
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

// Log startup
logger.info('Starting MCP Gateway...');
logger.info(`Environment: ${process.env.NODE_ENV}`);
logger.info(`Port: ${process.env.PORT || 4242}`);

// Request logging middleware
app.use((req, res, next) => {
  logger.info({
    type: 'request',
    method: req.method,
    path: req.path,
    ip: req.ip,
    headers: {
      origin: req.headers.origin,
      'user-agent': req.headers['user-agent']
    }
  });
  next();
});

// CORS for Claude.ai - IMPORTANT!
app.use((req, res, next) => {
  const origin = req.headers.origin;
  
  // Only allow Claude.ai and local development
  const allowedOrigins = ['https://claude.ai'];
  if (process.env.NODE_ENV === 'development') {
    allowedOrigins.push('http://localhost:3000', 'http://localhost:4242');
  }
  
  if (allowedOrigins.includes(origin)) {
    res.header('Access-Control-Allow-Origin', origin);
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Mcp-Session-Id');
    res.header('Access-Control-Allow-Credentials', 'true');
  }
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// Rate limiting - prevent abuse
const limiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 100, // 100 requests per minute per IP
  message: 'Too many requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

// Apply rate limiting to MCP endpoints
app.use('/mcp/', limiter);

// Initialize server registry
const registry = new ServerRegistry(logger);

// Setup OAuth endpoints (required for Claude.ai)
setupAuth(app, logger);

// Health check endpoint
app.get('/health', (req, res) => {
  const servers = registry.listServers();
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV,
    servers: servers.map(s => ({ 
      name: s.name, 
      path: s.path, 
      enabled: s.enabled,
      status: registry.getServerStatus(s.path)
    }))
  });
});

// List available servers (useful for debugging)
app.get('/servers', (req, res) => {
  const servers = registry.listServers();
  res.json({
    servers: servers.filter(s => s.enabled).map(s => ({
      name: s.name,
      description: s.description,
      endpoint: process.env.NODE_ENV === 'production' 
        ? `https://gateway.pluginpapi.dev/mcp/${s.path}`
        : `http://localhost:4242/mcp/${s.path}`
    }))
  });
});

// Main MCP endpoint - handles all MCP server requests
app.all('/mcp/:server', async (req, res) => {
  const serverName = req.params.server;
  
  logger.info({
    type: 'mcp-request',
    server: serverName,
    method: req.method,
    sessionId: req.headers['mcp-session-id']
  });
  
  try {
    // Check authentication
    const authHeader = req.headers.authorization;
    const expectedToken = process.env.GATEWAY_AUTH_TOKEN;
    
    if (!authHeader || !authHeader.includes(expectedToken)) {
      logger.warn(`Unauthorized access attempt for ${serverName}`);
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Get server handler
    const handler = registry.getHandler(serverName);
    if (!handler) {
      logger.warn(`Server not found: ${serverName}`);
      return res.status(404).json({ error: `Server '${serverName}' not found` });
    }

    // Handle the MCP request
    await handler(req, res);
    
  } catch (error) {
    logger.error(`Error in ${serverName}:`, error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// 404 handler
app.use((req, res) => {
  logger.warn(`404: ${req.method} ${req.path}`);
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
const PORT = process.env.PORT || 4242;
const server = app.listen(PORT, () => {
  logger.info(`MCP Gateway running on port ${PORT}`);
  logger.info('Available servers:', registry.listServers().map(s => s.name));
  
  if (process.env.NODE_ENV === 'production') {
    logger.info('Production URL: https://gateway.pluginpapi.dev');
  } else {
    logger.info('Development URL: http://localhost:' + PORT);
  }
});

// Graceful shutdown
const shutdown = () => {
  logger.info('Shutting down gracefully...');
  server.close(() => {
    registry.cleanup();
    logger.info('Server closed');
    process.exit(0);
  });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// Handle uncaught errors
process.on('uncaughtException', (error) => {
  logger.error('Uncaught exception:', error);
  shutdown();
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled rejection at:', promise, 'reason:', reason);
  shutdown();
});
```

### 4.4 OAuth Implementation (src/auth.js)

```javascript
import crypto from 'crypto';

const authCodes = new Map();
const TOKEN_EXPIRY = 365 * 24 * 60 * 60 * 1000; // 1 year

export function setupAuth(app, logger) {
  logger.info('Setting up OAuth endpoints');

  // OAuth discovery endpoint
  app.get('/.well-known/oauth-authorization-server', (req, res) => {
    const baseUrl = process.env.NODE_ENV === 'production'
      ? 'https://gateway.pluginpapi.dev'
      : `http://localhost:${process.env.PORT || 4242}`;
    
    res.json({
      issuer: baseUrl,
      authorization_endpoint: `${baseUrl}/oauth/authorize`,
      token_endpoint: `${baseUrl}/oauth/token`,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code'],
      code_challenge_methods_supported: ['S256', 'plain']
    });
  });

  // OAuth authorize endpoint - auto-approves since this is personal use
  app.get('/oauth/authorize', (req, res) => {
    const { 
      redirect_uri, 
      state, 
      client_id,
      response_type,
      scope
    } = req.query;

    logger.info('OAuth authorize request:', {
      redirect_uri,
      client_id,
      scope
    });

    // Validate required parameters
    if (!redirect_uri || !state) {
      return res.status(400).json({ 
        error: 'invalid_request',
        error_description: 'Missing required parameters' 
      });
    }

    // Generate authorization code
    const code = crypto.randomUUID();
    
    // Store code with metadata (expires in 10 minutes)
    authCodes.set(code, {
      redirect_uri,
      client_id,
      scope,
      expires: Date.now() + 600000
    });

    // Auto-approve and redirect back
    const redirectUrl = new URL(redirect_uri);
    redirectUrl.searchParams.set('code', code);
    redirectUrl.searchParams.set('state', state);
    
    logger.info('Redirecting with auth code');
    res.redirect(redirectUrl.toString());
  });

  // OAuth token endpoint
  app.post('/oauth/token', express.urlencoded({ extended: true }), (req, res) => {
    const { 
      grant_type,
      code,
      redirect_uri,
      client_id,
      code_verifier 
    } = req.body;

    logger.info('OAuth token request:', {
      grant_type,
      client_id,
      has_code: !!code
    });

    // Validate grant type
    if (grant_type !== 'authorization_code') {
      return res.status(400).json({ 
        error: 'unsupported_grant_type' 
      });
    }

    // Validate code
    const authCode = authCodes.get(code);
    if (!authCode) {
      logger.warn('Invalid auth code attempted');
      return res.status(400).json({ 
        error: 'invalid_grant',
        error_description: 'Invalid authorization code'
      });
    }

    // Check if code expired
    if (authCode.expires < Date.now()) {
      authCodes.delete(code);
      logger.warn('Expired auth code attempted');
      return res.status(400).json({ 
        error: 'invalid_grant',
        error_description: 'Authorization code expired'
      });
    }

    // Validate redirect_uri matches
    if (authCode.redirect_uri !== redirect_uri) {
      logger.warn('Redirect URI mismatch');
      return res.status(400).json({ 
        error: 'invalid_grant',
        error_description: 'Redirect URI mismatch'
      });
    }

    // Clean up used code
    authCodes.delete(code);

    // Return the configured token
    const accessToken = process.env.GATEWAY_AUTH_TOKEN;
    
    logger.info('Issuing access token');
    res.json({
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: Math.floor(TOKEN_EXPIRY / 1000),
      scope: authCode.scope || 'mcp:all'
    });
  });

  // Clean up expired codes periodically
  setInterval(() => {
    const now = Date.now();
    for (const [code, data] of authCodes.entries()) {
      if (data.expires < now) {
        authCodes.delete(code);
      }
    }
  }, 60000); // Every minute
}
```

### 4.5 Server Registry (src/registry.js)

```javascript
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import crypto from 'crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export class ServerRegistry {
  constructor(logger) {
    this.servers = new Map();
    this.sessions = new Map();
    this.logger = logger;
    this.sessionCleanupInterval = null;
    this.loadServers();
    this.startSessionCleanup();
  }

  loadServers() {
    const configPath = path.join(__dirname, '..', 'config', 'servers.json');
    
    try {
      const configData = fs.readFileSync(configPath, 'utf-8');
      const config = JSON.parse(configData);

      for (const serverConfig of config.servers) {
        if (serverConfig.enabled) {
          this.registerServer(serverConfig);
        }
      }
    } catch (error) {
      this.logger.error('Failed to load server configuration:', error);
      throw error;
    }
  }

  registerServer(config) {
    const handler = this.createStdioHandler(config);
    this.servers.set(config.path, {
      ...config,
      handler
    });
    this.logger.info(`Registered server: ${config.name} at /mcp/${config.path}`);
  }

  createStdioHandler(config) {
    return async (req, res) => {
      const sessionId = req.headers['mcp-session-id'] || crypto.randomUUID();
      const processKey = `${config.path}:${sessionId}`;
      
      let session = this.sessions.get(processKey);
      
      // Create new process if needed
      if (!session || session.process.killed) {
        try {
          const { process: childProcess, cleanup } = await this.spawnProcess(config, sessionId);
          session = {
            process: childProcess,
            cleanup,
            lastActivity: Date.now(),
            config
          };
          this.sessions.set(processKey, session);
        } catch (error) {
          this.logger.error(`Failed to spawn ${config.name}:`, error);
          return res.status(500).json({ 
            error: 'Failed to start MCP server',
            details: error.message 
          });
        }
      }

      // Update last activity
      session.lastActivity = Date.now();

      // Handle different request types
      if (req.method === 'GET') {
        // SSE connection
        this.handleSSEConnection(req, res, session, sessionId, config);
      } else if (req.method === 'POST') {
        // Regular request/response
        this.handlePostRequest(req, res, session, sessionId, config);
      } else {
        res.status(405).json({ error: 'Method not allowed' });
      }
    };
  }

  async spawnProcess(config, sessionId) {
    const command = config.command;
    const args = [...config.args];
    
    // Build environment
    const env = { ...process.env };
    if (config.env) {
      for (const [key, value] of Object.entries(config.env)) {
        // Handle environment variable references
        if (typeof value === 'string' && value.startsWith('$')) {
          const envVarName = value.substring(1);
          env[key] = process.env[envVarName] || '';
        } else {
          env[key] = value;
        }
      }
    }

    this.logger.info(`Spawning ${config.name} for session ${sessionId}`);
    this.logger.debug(`Command: ${command} ${args.join(' ')}`);

    const child = spawn(command, args, {
      env,
      shell: process.platform === 'win32' // Use shell on Windows
    });

    // Set up error handling
    child.on('error', (error) => {
      this.logger.error(`${config.name} process error:`, error);
    });

    child.on('exit', (code, signal) => {
      this.logger.info(`${config.name} exited: code=${code}, signal=${signal}`);
    });

    // Capture stderr for debugging
    child.stderr.on('data', (data) => {
      const message = data.toString().trim();
      if (message) {
        this.logger.debug(`${config.name} stderr: ${message}`);
      }
    });

    // Create cleanup function
    const cleanup = () => {
      if (!child.killed) {
        this.logger.info(`Cleaning up ${config.name} process`);
        child.kill('SIGTERM');
        setTimeout(() => {
          if (!child.killed) {
            child.kill('SIGKILL');
          }
        }, 5000);
      }
    };

    return { process: child, cleanup };
  }

  handleSSEConnection(req, res, session, sessionId, config) {
    this.logger.info(`SSE connection established for ${config.name} (session: ${sessionId})`);

    // Set SSE headers
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no', // Disable Nginx buffering
      'Mcp-Session-Id': sessionId
    });

    // Send initial connection event
    res.write(':ok\n\n');

    // Set up data handler
    const dataHandler = (data) => {
      const lines = data.toString().split('\n');
      for (const line of lines) {
        if (line.trim()) {
          try {
            const parsed = JSON.parse(line);
            res.write(`data: ${JSON.stringify(parsed)}\n\n`);
          } catch (e) {
            // Not JSON, skip
            this.logger.debug(`Non-JSON output from ${config.name}: ${line}`);
          }
        }
      }
    };

    session.process.stdout.on('data', dataHandler);

    // Clean up on disconnect
    req.on('close', () => {
      this.logger.info(`SSE connection closed for ${config.name} (session: ${sessionId})`);
      session.process.stdout.removeListener('data', dataHandler);
    });

    // Send keepalive every 30 seconds
    const keepalive = setInterval(() => {
      res.write(':keepalive\n\n');
    }, 30000);

    req.on('close', () => {
      clearInterval(keepalive);
    });
  }

  handlePostRequest(req, res, session, sessionId, config) {
    this.logger.debug(`POST request to ${config.name}: ${JSON.stringify(req.body)}`);

    // Send request to stdio
    session.process.stdin.write(JSON.stringify(req.body) + '\n');

    // Set up one-time response handler
    const chunks = [];
    let timeout;

    const dataHandler = (data) => {
      const lines = data.toString().split('\n');
      for (const line of lines) {
        if (line.trim()) {
          try {
            const parsed = JSON.parse(line);
            chunks.push(parsed);
            
            // Clear existing timeout
            if (timeout) clearTimeout(timeout);
            
            // Wait a bit for more chunks
            timeout = setTimeout(() => {
              session.process.stdout.removeListener('data', dataHandler);
              
              // Send response
              if (chunks.length === 1) {
                res.json(chunks[0]);
              } else {
                res.json(chunks);
              }
            }, 100);
          } catch (e) {
            this.logger.debug(`Non-JSON output: ${line}`);
          }
        }
      }
    };

    session.process.stdout.on('data', dataHandler);

    // Timeout after 30 seconds
    setTimeout(() => {
      session.process.stdout.removeListener('data', dataHandler);
      if (!res.headersSent) {
        res.status(504).json({ error: 'Request timeout' });
      }
    }, 30000);
  }

  startSessionCleanup() {
    // Clean up inactive sessions every 5 minutes
    this.sessionCleanupInterval = setInterval(() => {
      const now = Date.now();
      const timeout = 10 * 60 * 1000; // 10 minutes

      for (const [key, session] of this.sessions.entries()) {
        if (now - session.lastActivity > timeout) {
          this.logger.info(`Cleaning up inactive session: ${key}`);
          session.cleanup();
          this.sessions.delete(key);
        }
      }
    }, 5 * 60 * 1000);
  }

  getHandler(serverPath) {
    const server = this.servers.get(serverPath);
    return server?.handler;
  }

  listServers() {
    return Array.from(this.servers.values());
  }

  getServerStatus(serverPath) {
    const sessions = Array.from(this.sessions.keys())
      .filter(key => key.startsWith(`${serverPath}:`));
    return {
      activeSessions: sessions.length,
      running: sessions.length > 0
    };
  }

  cleanup() {
    // Stop cleanup interval
    if (this.sessionCleanupInterval) {
      clearInterval(this.sessionCleanupInterval);
    }

    // Clean up all sessions
    for (const [key, session] of this.sessions.entries()) {
      this.logger.info(`Cleaning up session: ${key}`);
      session.cleanup();
    }
    this.sessions.clear();
  }
}
```

### 4.6 Server Configuration (config/servers.json)

```json
{
  "servers": [
    {
      "name": "GitHub",
      "description": "GitHub repository operations and code management",
      "path": "github",
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-github@latest"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "$GITHUB_TOKEN"
      }
    },
    {
      "name": "Desktop Commander",
      "description": "Full computer control - files, commands, and system operations",
      "path": "desktop",
      "enabled": true,
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@wonderwhy-er/desktop-commander-mcp@latest"
      ],
      "env": {}
    }
  ]
}
```

### 4.7 Package.json Updates

After running `npm init -y`, update your `package.json`:

```json
{
  "name": "mcp-gateway",
  "version": "1.0.0",
  "description": "Personal MCP Gateway for Claude.ai Integration",
  "type": "module",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "NODE_ENV=development node --watch src/server.js",
    "dev:windows": "set NODE_ENV=development && node --watch src/server.js",
    "test": "NODE_ENV=development node src/server.js"
  },
  "keywords": ["mcp", "claude", "ai", "gateway"],
  "author": "kosta",
  "license": "MIT",
  "dependencies": {
    "express": "^4.19.2",
    "dotenv": "^16.4.5",
    "@modelcontextprotocol/sdk": "^1.0.4",
    "winston": "^3.13.0",
    "express-rate-limit": "^7.4.0"
  }
}
```

### 4.8 README.md

```markdown
# MCP Gateway

Personal MCP (Model Context Protocol) gateway for Claude.ai integration.

## Features

- GitHub integration for repository management
- Desktop Commander for full computer control
- Simple OAuth flow for Claude.ai
- Session management for multiple connections
- Comprehensive logging
- Rate limiting for security

## Setup

1. Copy `.env.example` to `.env` and fill in your tokens
2. Run `npm install`
3. Run `npm run dev` for development
4. Run `npm start` for production

## Available Endpoints

- `GET /health` - Health check
- `GET /servers` - List available MCP servers
- `GET /oauth/authorize` - OAuth authorization
- `POST /oauth/token` - OAuth token exchange
- `ALL /mcp/:server` - MCP server endpoints

## Security

- Never commit `.env` file
- Keep your `GATEWAY_AUTH_TOKEN` secret
- Only accessible via Cloudflare tunnel
```

## Part 5: Setting Up GitHub Token

### 5.1 Create GitHub Personal Access Token

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Name it: "MCP Gateway"
4. Select scopes:
   - ✓ `repo` (Full control of private repositories)
   - ✓ `read:user` (Read user profile data)
5. Click "Generate token"
6. **COPY THE TOKEN NOW** (you won't see it again!)
7. Add it to your `.env` file as `GITHUB_TOKEN=ghp_xxxxx`

## Part 6: Testing Your Setup

### 6.1 Start Development Server (Mac)

```bash
# In your mcp-gateway directory
npm run dev

# You should see:
# MCP Gateway running on port 4242
# Available servers: GitHub, Desktop Commander
# Development URL: http://localhost:4242
```

### 6.2 Test Local Endpoints

```bash
# Test health
curl http://localhost:4242/health

# Test server list
curl http://localhost:4242/servers

# Test OAuth discovery
curl http://localhost:4242/.well-known/oauth-authorization-server
```

### 6.3 Test Desktop Commander

First, let's see what Desktop Commander can do:

```bash
# Get config to see what's allowed
curl -X POST http://localhost:4242/mcp/desktop \
  -H "Authorization: Bearer YOUR_TOKEN_FROM_ENV" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"config/get","id":1}'
```

## Part 7: Deploy to Production (Windows)

### 7.1 Copy Project to Windows

**Option A: Using Git (Recommended)**
```bash
# On Mac, initialize git
cd /Users/kosta/Documents/ProjectsCode/mcp-gateway
git init
git add .
git commit -m "Initial MCP Gateway setup"

# Create a GitHub repo and push
# Then on Windows:
cd C:\Users\kosta\Projects
git clone YOUR_GITHUB_REPO_URL mcp-gateway
```

**Option B: Manual Copy**
1. Zip the entire `mcp-gateway` folder on Mac
2. Transfer to Windows (via cloud, USB, etc.)
3. Extract to `C:\Users\kosta\Projects\mcp-gateway`

### 7.2 Windows Setup

```powershell
# Open PowerShell as Administrator
cd C:\Users\kosta\Projects\mcp-gateway

# Install dependencies
npm install

# Update .env file for Windows paths
# Edit DESKTOP_ALLOWED_PATHS to:
# DESKTOP_ALLOWED_PATHS=C:\Users\kosta\Documents,C:\Users\kosta\Desktop

# Test the server
npm start
```

### 7.3 Create Windows Service

1. Download NSSM from https://nssm.cc/download
2. Extract `nssm.exe` to your project directory
3. Run as Administrator:

```powershell
# Create service
.\nssm.exe install MCPGateway "C:\Program Files\nodejs\node.exe"
.\nssm.exe set MCPGateway AppDirectory "C:\Users\kosta\Projects\mcp-gateway"
.\nssm.exe set MCPGateway AppParameters "src\server.js"
.\nssm.exe set MCPGateway AppEnvironmentExtra "NODE_ENV=production"

# Set up logging
.\nssm.exe set MCPGateway AppStdout "C:\Users\kosta\Projects\mcp-gateway\logs\service.log"
.\nssm.exe set MCPGateway AppStderr "C:\Users\kosta\Projects\mcp-gateway\logs\service-error.log"
.\nssm.exe set MCPGateway AppRotateFiles 1
.\nssm.exe set MCPGateway AppRotateBytes 10485760

# Start service
.\nssm.exe start MCPGateway
```

### 7.4 Verify Production Setup

```bash
# Check if service is running
curl https://gateway.pluginpapi.dev/health

# Check logs
Get-Content C:\Users\kosta\Projects\mcp-gateway\logs\combined.log -Tail 50
```

## Part 8: Add to Claude.ai

### 8.1 Add GitHub Integration

1. Go to https://claude.ai/settings/integrations
2. Click "Add Integration" → "Add from URL"
3. Enter details:
   - **Name**: "GitHub Tools"
   - **URL**: `https://gateway.pluginpapi.dev/mcp/github`
4. Click "Connect"
5. You'll be redirected to authorize (auto-approves)
6. Back in Claude, the integration is active!

### 8.2 Add Desktop Commander Integration

1. Still in Claude settings
2. Click "Add Integration" → "Add from URL"
3. Enter details:
   - **Name**: "Computer Control"
   - **URL**: `https://gateway.pluginpapi.dev/mcp/desktop`
4. Click "Connect"
5. Authorize and it's ready!

### 8.3 Test in Claude

Try these commands:
- "List my GitHub repositories"
- "Create a test.txt file on my desktop with 'Hello from Claude!'"
- "What files are in my Documents folder?"

## Part 9: Troubleshooting

### Common Issues and Solutions

**"502 Bad Gateway" from Cloudflare**
- Your server isn't running
- Check Windows service: `.\nssm.exe status MCPGateway`
- Check tunnel: `cloudflared tunnel info my-tunnel`

**"401 Unauthorized" errors**
- Check your `GATEWAY_AUTH_TOKEN` in `.env`
- Make sure it matches what Claude stored during OAuth

**MCP server not starting**
- Check logs: `logs/combined.log`
- Test command directly: `npx -y @modelcontextprotocol/server-github`
- Verify npm/npx works: `npx --version`

**Desktop Commander not working**
- Install it first: `npm install -g @wonderwhy-er/desktop-commander-mcp`
- Check paths in `.env` are correct
- Try with test config first

### View Logs

**Windows PowerShell:**
```powershell
# Real-time logs
Get-Content logs\combined.log -Wait -Tail 50

# Error logs only
Get-Content logs\error.log -Tail 20
```

**Mac Terminal:**
```bash
# Real-time logs
tail -f logs/combined.log

# Last 50 lines
tail -50 logs/combined.log
```

## Part 10: Maintenance

### Update MCP Servers

```bash
# Update the SDK
npm update @modelcontextprotocol/sdk

# Servers update automatically via npx
```

### Add New MCP Server

1. Edit `config/servers.json`
2. Add new server entry
3. Restart gateway
4. Add to Claude.ai

### Backup

Important files to backup:
- `.env` (your tokens!)
- `config/servers.json`
- `logs/` (if you want history)

## Security Notes

1. **Never expose port 4242 directly** - Always use Cloudflare tunnel
2. **Keep your tokens secret** - Don't share `.env` file
3. **Monitor logs** for unusual activity
4. **Update regularly** for security patches

## Future: Streamable HTTP

When MCP SDK adds Streamable HTTP support:
1. Update `@modelcontextprotocol/sdk`
2. Modify `registry.js` to use new transport
3. Everything else stays the same!

---

That's it! You now have a working MCP Gateway that Claude.ai can use to control your computer and access GitHub! 🎉

## Part 11: Essential Documentation & Resources

### Official MCP Documentation

1. **Model Context Protocol Specification**
   - https://modelcontextprotocol.io/
   - The official MCP website with core documentation
   - Includes protocol specification, architecture overview, and getting started guides

2. **MCP GitHub Repository**
   - https://github.com/modelcontextprotocol/specification
   - Official specification repository with detailed protocol information
   - Check issues for latest updates on Streamable HTTP transport

3. **MCP TypeScript SDK**
   - https://github.com/modelcontextprotocol/typescript-sdk
   - Official SDK we're using in this project
   - Check releases for Streamable HTTP server support updates

### Anthropic Official Resources

4. **Anthropic MCP Announcement**
   - https://www.anthropic.com/news/model-context-protocol
   - Original announcement explaining MCP's purpose and vision
   - Good for understanding the "why" behind MCP

5. **Claude.ai MCP Integration Guide**
   - https://support.anthropic.com/en/articles/11175166-about-custom-integrations-using-remote-mcp
   - Official guide for custom integrations on Claude.ai
   - Critical for understanding OAuth requirements and security

6. **Building Custom Integrations**
   - https://support.anthropic.com/en/articles/11503834-building-custom-integrations-via-remote-mcp-servers
   - Detailed guide on building remote MCP servers
   - Includes testing with MCP Inspector

7. **Pre-built Integrations Examples**
   - https://support.anthropic.com/en/articles/11176164-pre-built-integrations-using-remote-mcp
   - Examples of existing integrations (Asana, Atlassian, etc.)
   - Good reference for how integrations should work

8. **Anthropic MCP Documentation**
   - https://docs.anthropic.com/en/docs/build-with-claude/mcp
   - Developer documentation for MCP
   - Includes Messages API MCP connector info

### Transport Protocol Documentation

9. **MCP Transports Specification**
   - https://modelcontextprotocol.io/specification/2025-03-26/basic/transports
   - Official spec for different transport types
   - Critical section on Streamable HTTP vs SSE

10. **Streamable HTTP Implementation (Cloudflare)**
    - https://blog.cloudflare.com/streamable-http-mcp-servers-python/
    - Cloudflare's implementation of Streamable HTTP
    - Good reference for understanding the new protocol

### Community Tools & Resources

11. **Supergateway Repository**
    - https://github.com/supercorp-ai/supergateway
    - Tool for bridging MCP transports
    - Issue #38 discusses Streamable HTTP support needs

12. **MCP Inspector**
    - https://github.com/modelcontextprotocol/inspector
    - Essential tool for testing MCP servers
    - Supports both SSE and Streamable HTTP

13. **Desktop Commander MCP**
    - https://github.com/wonderwhy-er/DesktopCommanderMCP
    - The Desktop Commander server we're using
    - Check for configuration options and updates

### Implementation References

14. **Cloudflare MCP Demo Day**
    - https://blog.cloudflare.com/mcp-demo-day/
    - Shows how major companies implemented MCP
    - Good architectural patterns and ideas

15. **Building Remote MCP Servers on Cloudflare**
    - https://blog.cloudflare.com/remote-model-context-protocol-servers-mcp/
    - Detailed guide on MCP server architecture
    - Includes OAuth implementation details

### Technical Deep Dives

16. **SSE vs Streamable HTTP Comparison**
    - https://brightdata.com/blog/ai/sse-vs-streamable-http
    - Explains why MCP is moving to Streamable HTTP
    - Technical comparison of both protocols

17. **MCP Protocol Flow Analysis**
    - https://blog.christianposta.com/ai/understanding-mcp-recent-change-around-http-sse/
    - Deep dive into how MCP protocol works
    - Good for understanding request/response patterns

### Additional Learning Resources

18. **How to MCP - Complete Guide**
    - https://simplescraper.io/blog/how-to-mcp
    - Comprehensive guide with common pitfalls
    - Includes both SSE and Streamable HTTP examples

19. **MCP with AWS Lambda**
    - https://dev.to/aws-builders/mcp-server-with-aws-lambda-and-http-api-gateway-1j49
    - Example of serverless MCP implementation
    - Shows Streamable HTTP in production

20. **Example MCP Clients**
    - https://modelcontextprotocol.io/clients
    - List of applications that support MCP
    - Good for understanding client implementations

### Key Specifications to Monitor

21. **MCP Specification Pull Requests**
    - https://github.com/modelcontextprotocol/specification/pulls
    - Watch for updates on Streamable HTTP
    - PR #206 introduced the new transport

22. **Anthropic Help Center**
    - https://support.anthropic.com/
    - Check for new articles on MCP integrations
    - Often has the most up-to-date integration guides

### Tools for Development

23. **MCP Server Examples**
    - https://github.com/modelcontextprotocol/servers
    - Official example servers
    - Good reference for implementation patterns

24. **Claude Desktop MCP Setup**
    - https://support.anthropic.com/en/articles/10949351-getting-started-with-model-context-protocol-mcp-on-claude-for-desktop
    - While we're using web, this shows MCP patterns
    - Useful for understanding configuration

### Security & Best Practices

25. **MCP Security Considerations**
    - Check the security sections in articles 5 & 6 above
    - Important for understanding OAuth requirements
    - Covers prompt injection risks

**Pro tip**: Bookmark these resources and check them periodically. The MCP ecosystem is evolving rapidly, especially around Streamable HTTP support. The official MCP GitHub repos and Anthropic's help center will have the most current information.