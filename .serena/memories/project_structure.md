# MCP Gateway Project Structure

## Current Structure
```
mcp-gateway/
├── src/
│   └── server.js          # Main gateway server (placeholder)
├── config/                # Configuration directory (empty)
├── logs/                  # Log files directory (empty)
├── .serena/              # Serena project files
├── package.json          # Node.js project configuration
├── CLAUDE.md            # Claude Code instructions
└── README.md            # Comprehensive setup guide
```

## Planned Structure (from README)
```
mcp-gateway/
├── src/
│   ├── server.js          # Main Express server
│   ├── auth.js            # OAuth 2.0 implementation
│   ├── registry.js        # MCP server registry
│   └── utils/             # Utility functions
├── config/
│   └── servers.json       # MCP server configurations
├── logs/                  # Application logs (gitignored)
├── tests/                 # Test files
├── .env                   # Environment variables (gitignored)
├── .gitignore            # Git ignore rules
├── package.json          # Dependencies and scripts
├── package-lock.json     # Dependency lock file
├── CLAUDE.md            # Claude Code guidance
└── README.md            # Project documentation
```

## Key Directories

### /src
Contains all source code:
- Core server logic
- Authentication handling
- MCP server process management
- Utility functions

### /config
JSON configuration files:
- Server definitions
- Runtime configurations
- Feature flags

### /logs
Generated log files:
- combined.log (all logs)
- error.log (errors only)
- Rotated daily

## File Purposes

- **server.js**: Express server, routing, middleware
- **auth.js**: OAuth flow, token validation
- **registry.js**: Spawn/manage MCP server processes
- **servers.json**: Define available MCP servers
- **.env**: Secrets and environment config
- **.gitignore**: Prevent committing sensitive files