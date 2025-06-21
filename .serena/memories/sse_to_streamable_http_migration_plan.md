# SSE to Streamable HTTP Migration Plan

## Current SSE Architecture Issues

1. **Missing Methods in ServerRegistry**:
   - `getHandler(serverName)` - Not implemented, expected to return request handler
   - `listServers()` - Should be `getAvailableServers()`
   - `getServerStatus(path)` - Not implemented
   - `cleanup()` - Should be `shutdown()`

2. **Current SSE Flow**:
   - POST requests handled by `handlePostRequest()` 
   - SSE connections handled by `handleSSEConnection()` 
   - Sessions store SSE connection info and message queues
   - Manual message routing and response handling

3. **Session Structure**:
   ```javascript
   {
     id: sessionId,
     serverId: server.id,
     serverName: server.name,
     createdAt: Date.now(),
     lastActivity: Date.now(),
     processInfo,
     messageQueue: [],
     responseHandlers: new Map(),
     sseConnection: { res, messageHandler } // SSE specific
   }
   ```

## Target Streamable HTTP Architecture

1. **Single Endpoint**: All requests to `/mcp/:server` (GET, POST, DELETE)
2. **Transport Modes**:
   - POST with JSON response
   - GET/POST with SSE stream (Accept: text/event-stream)
   - DELETE for session termination
3. **Session Management**: Via Mcp-Session-Id headers
4. **SDK Integration**: Use StreamableHTTPServerTransport class

## Implementation Strategy

### Phase 1: Fix Missing Methods
1. Implement `getHandler()` to return unified request handler
2. Rename `cleanup()` to `shutdown()` or add alias
3. Add `listServers()` alias for `getAvailableServers()`
4. Implement `getServerStatus()` for process health

### Phase 2: Create Transport Adapter
1. Import StreamableHTTPServerTransport from SDK
2. Create transport instances per server type
3. Map existing session management to SDK sessions
4. Preserve process management architecture

### Phase 3: Implement Unified Handler
```javascript
getHandler(serverName) {
  return async (req, res) => {
    // Get or create transport for this server
    const transport = this.getOrCreateTransport(serverName);
    
    // Handle via StreamableHTTPServerTransport
    await transport.handleRequest(req, res, req.body);
  };
}
```

### Phase 4: Session Migration
- Replace SSE-specific session fields with transport references
- Let SDK handle message routing and SSE streams
- Keep process management separate from transport

## Key Challenges
1. Preserving sophisticated session/process management
2. Mapping current architecture to SDK patterns
3. Maintaining backward compatibility where possible
4. Testing with existing MCP servers