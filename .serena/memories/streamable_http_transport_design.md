# Streamable HTTP Transport Design

## Key Insights from SDK Example

1. **Transport Instance Per Session**:
   - Create new transport for initialization requests
   - Store transports by session ID in a Map
   - Reuse transport for subsequent requests

2. **Request Handling Flow**:
   ```javascript
   // POST handler
   const sessionId = req.headers['mcp-session-id'];
   if (sessionId && transports[sessionId]) {
     // Use existing transport
     transport = transports[sessionId];
   } else if (!sessionId && isInitializeRequest(req.body)) {
     // Create new transport
     transport = new StreamableHTTPServerTransport({
       sessionIdGenerator: () => randomUUID(),
       onsessioninitialized: (sessionId) => {
         transports[sessionId] = transport;
       }
     });
   }
   await transport.handleRequest(req, res, req.body);
   ```

3. **Three Request Types**:
   - **POST**: JSON-RPC messages (initialization, method calls)
   - **GET**: SSE stream establishment 
   - **DELETE**: Session termination

4. **Transport Options**:
   - `sessionIdGenerator`: Function to generate session IDs
   - `onsessioninitialized`: Callback when session is initialized
   - `eventStore`: Optional for resumability support
   - `enableJsonResponse`: Use JSON responses instead of SSE

## Implementation Plan for ServerRegistry

### 1. Add Missing Methods
```javascript
// Alias for compatibility
listServers() {
  return this.getAvailableServers();
}

// Get server status
getServerStatus(serverPath) {
  const server = Array.from(this.servers.values()).find(s => s.path === serverPath);
  if (!server) return 'unknown';
  
  const processInfo = this.processes.get(server.id);
  if (!processInfo || processInfo.process.killed) return 'stopped';
  return 'running';
}

// Alias for compatibility
cleanup() {
  return this.shutdown();
}
```

### 2. Create getHandler Method
```javascript
getHandler(serverName) {
  const server = this.servers.get(serverName);
  if (!server) return null;
  
  return async (req, res) => {
    try {
      // Get session ID from header
      const sessionId = req.headers['mcp-session-id'];
      
      // Handle based on method
      switch (req.method) {
        case 'POST':
          await this.handlePostRequest(req, res, serverName);
          break;
        case 'GET':
          await this.handleGetRequest(req, res, serverName);
          break;
        case 'DELETE':
          await this.handleDeleteRequest(req, res, serverName);
          break;
        default:
          res.status(405).json({ error: 'Method not allowed' });
      }
    } catch (error) {
      this.logger.error(`Error in ${serverName} handler:`, error);
      if (!res.headersSent) {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  };
}
```

### 3. Replace SSE Implementation
- Remove `handleSSEConnection` method
- Remove SSE-specific session fields
- Add transport management:
  ```javascript
  this.transports = new Map(); // sessionId -> transport
  ```

### 4. Integrate StreamableHTTPServerTransport
```javascript
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';

async handlePostRequest(req, res, serverName) {
  const sessionId = req.headers['mcp-session-id'];
  let transport;
  
  if (sessionId && this.transports.has(sessionId)) {
    transport = this.transports.get(sessionId);
  } else if (!sessionId && isInitializeRequest(req.body)) {
    // Create new transport and session
    transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => this._generateSessionId(),
      onsessioninitialized: (sessionId) => {
        this.transports.set(sessionId, transport);
        // Create session record
        this.createSession(serverName, sessionId);
      }
    });
    
    // Connect to MCP server process
    // ... existing process management logic
  } else {
    res.status(400).json({ error: 'Invalid request' });
    return;
  }
  
  await transport.handleRequest(req, res, req.body);
}
```

### 5. Process Management Integration
- Keep existing process spawning logic
- Connect transport to process via stdio
- Map sessions to processes as before
- Clean up transports on session close

## Benefits of This Approach
1. Minimal changes to existing architecture
2. Preserves sophisticated session/process management
3. Leverages SDK for protocol compliance
4. Supports all Streamable HTTP features
5. Easy to test incrementally