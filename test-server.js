#!/usr/bin/env node

import express from 'express';
import dotenv from 'dotenv';
import { setupAuth } from './src/auth.js';
import winston from 'winston';

// Load environment variables
dotenv.config();

const app = express();
app.use(express.json());

// Simple logger for testing
const logger = winston.createLogger({
  level: 'debug',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.colorize(),
    winston.format.simple()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

// Basic middleware to log requests
app.use((req, res, next) => {
  logger.info(`${req.method} ${req.path}`);
  next();
});

// Set up OAuth endpoints
setupAuth(app, logger);

// Simple health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok',
    oauth: 'configured',
    environment: process.env.NODE_ENV || 'development'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Start server
const PORT = process.env.PORT || 4242;
const server = app.listen(PORT, () => {
  logger.info(`OAuth test server running on port ${PORT}`);
  logger.info(`Discovery endpoint: http://localhost:${PORT}/.well-known/oauth-authorization-server`);
  logger.info(`Authorization endpoint: http://localhost:${PORT}/oauth/authorize`);
  logger.info(`Token endpoint: http://localhost:${PORT}/oauth/token`);
  
  if (!process.env.GATEWAY_AUTH_TOKEN) {
    logger.warn('⚠️  GATEWAY_AUTH_TOKEN not set in environment!');
    logger.warn('The token endpoint will fail without this.');
    logger.warn('Create a .env file with: GATEWAY_AUTH_TOKEN=your-secure-token');
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down...');
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down...');
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
});