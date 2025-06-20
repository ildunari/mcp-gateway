import { spawn } from 'child_process';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { EventEmitter } from 'events';
import winston from 'winston';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Session timeout in milliseconds (10 minutes)
const SESSION_TIMEOUT = 10 * 60 * 1000;

// Request timeout in milliseconds (30 seconds)
const REQUEST_TIMEOUT = 30 * 1000;

// Session cleanup interval (1 minute)
const CLEANUP_INTERVAL = 60 * 1000;

/**
 * ServerRegistry manages MCP server processes and sessions
 */
export class ServerRegistry extends EventEmitter {
  constructor(logger = winston.createLogger()) {
    super();
    this.logger = logger;
    this.servers = new Map(); // name -> server config
    this.sessions = new Map(); // sessionId -> session info
    this.processes = new Map(); // serverId -> process info
    this.cleanupInterval = null;
  }

  /**
   * Initialize the registry by loading server configurations
   * @param {string} configPath - Path to servers.json
   */
  async initialize(configPath = join(__dirname, '../config/servers.json')) {
    try {
      const configData = readFileSync(configPath, 'utf8');
      const config = JSON.parse(configData);
      
      if (!config.servers || !Array.isArray(config.servers)) {
        throw new Error('Invalid servers.json format: missing servers array');
      }

      // Load server configurations
      for (const serverConfig of config.servers) {
        if (!serverConfig.enabled) {
          this.logger.info(`Server ${serverConfig.name} is disabled, skipping`);
          continue;
        }

        this.servers.set(serverConfig.name, {
          ...serverConfig,
          id: serverConfig.name,
        });
        
        this.logger.info(`Loaded server configuration: ${serverConfig.name}`);
      }

      // Start session cleanup interval
      this.startCleanupInterval();

      this.logger.info(`ServerRegistry initialized with ${this.servers.size} enabled servers`);
    } catch (error) {
      this.logger.error('Failed to initialize ServerRegistry:', error);
      throw error;
    }
  }

  /**
   * Get available servers
   * @returns {Array} Array of server configurations
   */
  getAvailableServers() {
    return Array.from(this.servers.values()).map(server => ({
      name: server.name,
      path: server.path,
      description: server.description,
      enabled: server.enabled,
    }));
  }

  /**
   * Create a new session for a server
   * @param {string} serverName - Name of the server
   * @param {string} sessionId - Session ID (optional)
   * @returns {Promise<Object>} Session information
   */
  async createSession(serverName, sessionId = null) {
    const server = this.servers.get(serverName);
    if (!server) {
      throw new Error(`Server ${serverName} not found`);
    }

    // Generate session ID if not provided
    if (!sessionId) {
      sessionId = this._generateSessionId();
    }

    // Check if session already exists
    if (this.sessions.has(sessionId)) {
      throw new Error(`Session ${sessionId} already exists`);
    }

    // Get or create process for this server
    let processInfo = this.processes.get(server.id);
    if (!processInfo || processInfo.process.killed) {
      processInfo = await this._spawnServerProcess(server);
      this.processes.set(server.id, processInfo);
    }

    // Create session
    const session = {
      id: sessionId,
      serverId: server.id,
      serverName: server.name,
      createdAt: Date.now(),
      lastActivity: Date.now(),
      processInfo,
      messageQueue: [],
      responseHandlers: new Map(),
    };

    this.sessions.set(sessionId, session);
    
    this.logger.info(`Created session ${sessionId} for server ${serverName}`);
    
    return {
      sessionId: session.id,
      serverName: session.serverName,
      serverId: session.serverId,
    };
  }

  /**
   * Get session by ID
   * @param {string} sessionId - Session ID
   * @returns {Object|null} Session object or null
   */
  getSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (session) {
      // Update last activity
      session.lastActivity = Date.now();
    }
    return session;
  }

  /**
   * Send a message to a session
   * @param {string} sessionId - Session ID
   * @param {Object} message - JSON-RPC message
   * @param {Function} responseHandler - Handler for response (optional)
   * @returns {Promise<void>}
   */
  async sendMessage(sessionId, message, responseHandler = null) {
    const session = this.getSession(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    // Add response handler if provided
    if (responseHandler && message.id) {
      session.responseHandlers.set(message.id, {
        handler: responseHandler,
        timestamp: Date.now(),
      });
    }

    // Send message to process
    try {
      const messageStr = JSON.stringify(message) + '\n';
      session.processInfo.process.stdin.write(messageStr);
      
      this.logger.debug(`Sent message to session ${sessionId}:`, message);
    } catch (error) {
      this.logger.error(`Failed to send message to session ${sessionId}:`, error);
      throw error;
    }
  }

  /**
   * Handle SSE connection for a session
   * @param {string} sessionId - Session ID
   * @param {Object} res - Express response object
   * @returns {Promise<void>}
   */
  async handleSSEConnection(sessionId, res) {
    const session = this.getSession(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    // Set SSE headers
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no', // Disable Nginx buffering
    });

    // Send initial connection event
    res.write(`event: connection\ndata: {"sessionId":"${sessionId}"}\n\n`);

    // Set up message handler for this connection
    const messageHandler = (message) => {
      try {
        res.write(`event: message\ndata: ${JSON.stringify(message)}\n\n`);
      } catch (error) {
        this.logger.error(`Failed to send SSE message:`, error);
      }
    };

    // Store SSE connection in session
    session.sseConnection = {
      res,
      messageHandler,
    };

    // Send any queued messages
    while (session.messageQueue.length > 0) {
      const queuedMessage = session.messageQueue.shift();
      messageHandler(queuedMessage);
    }

    // Handle connection close
    res.on('close', () => {
      this.logger.info(`SSE connection closed for session ${sessionId}`);
      if (session.sseConnection) {
        delete session.sseConnection;
      }
    });

    // Keep connection alive with periodic pings
    const pingInterval = setInterval(() => {
      try {
        res.write(':ping\n\n');
      } catch (error) {
        clearInterval(pingInterval);
      }
    }, 30000); // 30 seconds

    res.on('close', () => clearInterval(pingInterval));
  }

  /**
   * Handle POST request for a session
   * @param {string} sessionId - Session ID
   * @param {Object} message - JSON-RPC message
   * @returns {Promise<Object>} Response message
   */
  async handlePostRequest(sessionId, message) {
    const session = this.getSession(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        session.responseHandlers.delete(message.id);
        reject(new Error('Request timeout'));
      }, REQUEST_TIMEOUT);

      // Send message with response handler
      this.sendMessage(sessionId, message, (response) => {
        clearTimeout(timeout);
        resolve(response);
      }).catch((error) => {
        clearTimeout(timeout);
        reject(error);
      });
    });
  }

  /**
   * Close a session
   * @param {string} sessionId - Session ID
   */
  closeSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return;
    }

    // Close SSE connection if exists
    if (session.sseConnection) {
      try {
        session.sseConnection.res.end();
      } catch (error) {
        // Connection might already be closed
      }
    }

    // Clear response handlers
    session.responseHandlers.clear();

    // Remove session
    this.sessions.delete(sessionId);
    
    this.logger.info(`Closed session ${sessionId}`);

    // Check if we need to stop the process
    this._checkProcessUsage(session.serverId);
  }

  /**
   * Spawn a server process
   * @private
   * @param {Object} server - Server configuration
   * @returns {Promise<Object>} Process information
   */
  async _spawnServerProcess(server) {
    this.logger.info(`Spawning process for server ${server.name}`);

    // Prepare environment variables
    const env = {
      ...process.env,
      ...this._expandEnvironmentVariables(server.env || {}),
    };

    // Spawn process
    const args = server.args || [];
    const childProcess = spawn(server.command, args, {
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });

    // Create process info
    const processInfo = {
      process: childProcess,
      serverId: server.id,
      serverName: server.name,
      startedAt: Date.now(),
      restartCount: 0,
      buffer: '', // Buffer for incomplete messages
    };

    // Handle stdout (messages from server)
    childProcess.stdout.on('data', (chunk) => {
      processInfo.buffer += chunk.toString();
      this._processStdoutBuffer(processInfo);
    });

    // Handle stderr (logging)
    childProcess.stderr.on('data', (chunk) => {
      const message = chunk.toString().trim();
      if (message) {
        this.logger.info(`[${server.name}] ${message}`);
      }
    });

    // Handle process exit
    childProcess.on('exit', (code, signal) => {
      this.logger.error(`Process for ${server.name} exited with code ${code}, signal ${signal}`);
      
      // Check if we need to restart
      const shouldRestart = this._shouldRestartProcess(processInfo);
      if (shouldRestart) {
        this.logger.info(`Restarting process for ${server.name}`);
        processInfo.restartCount++;
        setTimeout(() => {
          this._spawnServerProcess(server).then((newProcessInfo) => {
            this.processes.set(server.id, newProcessInfo);
            this._transferSessionsToNewProcess(server.id, newProcessInfo);
          }).catch((error) => {
            this.logger.error(`Failed to restart process for ${server.name}:`, error);
          });
        }, 1000); // Wait 1 second before restart
      }
    });

    // Handle process errors
    childProcess.on('error', (error) => {
      this.logger.error(`Process error for ${server.name}:`, error);
    });

    return processInfo;
  }

  /**
   * Process stdout buffer for complete messages
   * @private
   * @param {Object} processInfo - Process information
   */
  _processStdoutBuffer(processInfo) {
    const lines = processInfo.buffer.split('\n');
    processInfo.buffer = lines.pop() || ''; // Keep incomplete line in buffer

    for (const line of lines) {
      if (!line.trim()) continue;

      try {
        const message = JSON.parse(line);
        this._handleServerMessage(processInfo.serverId, message);
      } catch (error) {
        this.logger.error(`Failed to parse message from ${processInfo.serverName}: ${line}`);
      }
    }
  }

  /**
   * Handle message from server
   * @private
   * @param {string} serverId - Server ID
   * @param {Object} message - JSON-RPC message
   */
  _handleServerMessage(serverId, message) {
    // Find sessions for this server
    const sessions = Array.from(this.sessions.values()).filter(
      session => session.serverId === serverId
    );

    // Route message to appropriate sessions
    for (const session of sessions) {
      // Check if this is a response to a request
      if (message.id && session.responseHandlers.has(message.id)) {
        const { handler } = session.responseHandlers.get(message.id);
        session.responseHandlers.delete(message.id);
        handler(message);
      } else {
        // Send to SSE connection or queue
        if (session.sseConnection) {
          session.sseConnection.messageHandler(message);
        } else {
          session.messageQueue.push(message);
        }
      }
    }
  }

  /**
   * Check if process should be kept alive
   * @private
   * @param {string} serverId - Server ID
   */
  _checkProcessUsage(serverId) {
    const sessions = Array.from(this.sessions.values()).filter(
      session => session.serverId === serverId
    );

    if (sessions.length === 0) {
      // No active sessions, can stop process
      const processInfo = this.processes.get(serverId);
      if (processInfo) {
        this.logger.info(`Stopping unused process for server ${serverId}`);
        processInfo.process.kill();
        this.processes.delete(serverId);
      }
    }
  }

  /**
   * Check if process should be restarted
   * @private
   * @param {Object} processInfo - Process information
   * @returns {boolean} Whether to restart
   */
  _shouldRestartProcess(processInfo) {
    // Don't restart if too many restarts
    if (processInfo.restartCount >= 5) {
      this.logger.error(`Process ${processInfo.serverName} has restarted too many times`);
      return false;
    }

    // Check if there are active sessions
    const sessions = Array.from(this.sessions.values()).filter(
      session => session.serverId === processInfo.serverId
    );

    return sessions.length > 0;
  }

  /**
   * Transfer sessions to new process
   * @private
   * @param {string} serverId - Server ID
   * @param {Object} newProcessInfo - New process information
   */
  _transferSessionsToNewProcess(serverId, newProcessInfo) {
    const sessions = Array.from(this.sessions.values()).filter(
      session => session.serverId === serverId
    );

    for (const session of sessions) {
      session.processInfo = newProcessInfo;
      this.logger.info(`Transferred session ${session.id} to new process`);
    }
  }

  /**
   * Start cleanup interval
   * @private
   */
  startCleanupInterval() {
    this.cleanupInterval = setInterval(() => {
      this._cleanupSessions();
    }, CLEANUP_INTERVAL);
  }

  /**
   * Clean up inactive sessions
   * @private
   */
  _cleanupSessions() {
    const now = Date.now();
    const sessionsToRemove = [];

    for (const [sessionId, session] of this.sessions) {
      if (now - session.lastActivity > SESSION_TIMEOUT) {
        sessionsToRemove.push(sessionId);
      }
    }

    for (const sessionId of sessionsToRemove) {
      this.logger.info(`Cleaning up inactive session ${sessionId}`);
      this.closeSession(sessionId);
    }
  }

  /**
   * Generate unique session ID
   * @private
   * @returns {string} Session ID
   */
  _generateSessionId() {
    return `mcp-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Expand environment variables in configuration
   * @private
   * @param {Object} env - Environment variables configuration
   * @returns {Object} Expanded environment variables
   */
  _expandEnvironmentVariables(env) {
    const expanded = {};
    
    for (const [key, value] of Object.entries(env)) {
      if (typeof value === 'string' && value.startsWith('${') && value.endsWith('}')) {
        const envVar = value.slice(2, -1);
        expanded[key] = process.env[envVar] || '';
      } else {
        expanded[key] = value;
      }
    }
    
    return expanded;
  }

  /**
   * Shutdown the registry
   */
  async shutdown() {
    this.logger.info('Shutting down ServerRegistry');

    // Stop cleanup interval
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }

    // Close all sessions
    const sessionIds = Array.from(this.sessions.keys());
    for (const sessionId of sessionIds) {
      this.closeSession(sessionId);
    }

    // Kill all processes
    for (const [serverId, processInfo] of this.processes) {
      try {
        processInfo.process.kill();
        this.logger.info(`Killed process for server ${serverId}`);
      } catch (error) {
        this.logger.error(`Failed to kill process for server ${serverId}:`, error);
      }
    }

    this.processes.clear();
    this.servers.clear();
  }
}