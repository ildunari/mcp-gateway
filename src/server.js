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
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // 100 requests per 15 minutes per IP
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
const server = app.listen(PORT, async () => {
  try {
    // Initialize registry after server starts
    await registry.initialize();
    logger.info(`MCP Gateway running on port ${PORT}`);
    logger.info('Available servers:', registry.listServers().map(s => s.name));
    
    if (process.env.NODE_ENV === 'production') {
      logger.info('Production URL: https://gateway.pluginpapi.dev');
    } else {
      logger.info('Development URL: http://localhost:' + PORT);
    }
  } catch (error) {
    logger.error('Failed to initialize registry:', error);
    process.exit(1);
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