import crypto from 'crypto';
import express from 'express';

// Store authorization codes temporarily
const authCodes = new Map();
const TOKEN_EXPIRY = 365 * 24 * 60 * 60 * 1000; // 1 year for personal use

export function setupAuth(app, logger) {
  logger.info('Setting up OAuth endpoints for Claude.ai integration');

  // OAuth discovery endpoint - Required for Claude.ai to find our OAuth endpoints
  app.get('/.well-known/oauth-authorization-server', (req, res) => {
    const baseUrl = process.env.NODE_ENV === 'production'
      ? 'https://gateway.pluginpapi.dev'
      : `http://localhost:${process.env.PORT || 4242}`;
    
    logger.debug('OAuth discovery request received');
    
    res.json({
      issuer: baseUrl,
      authorization_endpoint: `${baseUrl}/oauth/authorize`,
      token_endpoint: `${baseUrl}/oauth/token`,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code'],
      code_challenge_methods_supported: ['S256', 'plain'],
      scopes_supported: ['mcp:all']
    });
  });

  // OAuth authorize endpoint - Auto-approves since this is for personal use
  app.get('/oauth/authorize', (req, res) => {
    const { 
      redirect_uri, 
      state, 
      client_id,
      response_type,
      scope,
      code_challenge,
      code_challenge_method
    } = req.query;

    logger.info('OAuth authorize request:', {
      redirect_uri,
      client_id,
      scope,
      has_state: !!state,
      has_challenge: !!code_challenge
    });

    // Validate required parameters
    if (!redirect_uri || !state) {
      logger.warn('Missing required OAuth parameters');
      return res.status(400).json({ 
        error: 'invalid_request',
        error_description: 'Missing required parameters: redirect_uri and state are required' 
      });
    }

    // Validate response_type if provided
    if (response_type && response_type !== 'code') {
      logger.warn(`Unsupported response_type: ${response_type}`);
      return res.status(400).json({ 
        error: 'unsupported_response_type',
        error_description: 'Only "code" response type is supported' 
      });
    }

    // Generate secure authorization code
    const code = crypto.randomUUID();
    
    // Store code with metadata (expires in 10 minutes)
    const codeData = {
      redirect_uri,
      client_id,
      scope: scope || 'mcp:all',
      code_challenge,
      code_challenge_method,
      created_at: Date.now(),
      expires_at: Date.now() + 600000 // 10 minutes
    };
    
    authCodes.set(code, codeData);
    logger.debug(`Stored auth code: ${code.substring(0, 8)}...`);

    // Auto-approve and redirect back to Claude.ai with the authorization code
    const redirectUrl = new URL(redirect_uri);
    redirectUrl.searchParams.set('code', code);
    redirectUrl.searchParams.set('state', state);
    
    logger.info('Auto-approving and redirecting with auth code');
    res.redirect(redirectUrl.toString());
  });

  // OAuth token endpoint - Exchange authorization codes for access tokens
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
      has_code: !!code,
      has_verifier: !!code_verifier
    });

    // Validate grant type
    if (grant_type !== 'authorization_code') {
      logger.warn(`Unsupported grant_type: ${grant_type}`);
      return res.status(400).json({ 
        error: 'unsupported_grant_type',
        error_description: 'Only "authorization_code" grant type is supported'
      });
    }

    // Validate required parameters
    if (!code || !redirect_uri) {
      logger.warn('Missing required token parameters');
      return res.status(400).json({ 
        error: 'invalid_request',
        error_description: 'Missing required parameters: code and redirect_uri are required'
      });
    }

    // Retrieve and validate authorization code
    const authCode = authCodes.get(code);
    if (!authCode) {
      logger.warn('Invalid auth code attempted');
      return res.status(400).json({ 
        error: 'invalid_grant',
        error_description: 'Invalid or expired authorization code'
      });
    }

    // Check if code has expired
    if (authCode.expires_at < Date.now()) {
      authCodes.delete(code);
      logger.warn('Expired auth code attempted');
      return res.status(400).json({ 
        error: 'invalid_grant',
        error_description: 'Authorization code has expired'
      });
    }

    // Validate redirect_uri matches the one used during authorization
    if (authCode.redirect_uri !== redirect_uri) {
      logger.warn('Redirect URI mismatch in token exchange');
      return res.status(400).json({ 
        error: 'invalid_grant',
        error_description: 'Redirect URI does not match the one used during authorization'
      });
    }

    // Validate PKCE if it was used during authorization
    if (authCode.code_challenge) {
      if (!code_verifier) {
        logger.warn('Missing PKCE code_verifier');
        return res.status(400).json({ 
          error: 'invalid_request',
          error_description: 'Code verifier required for PKCE'
        });
      }

      // Verify the code challenge
      const method = authCode.code_challenge_method || 'plain';
      let computedChallenge;
      
      if (method === 'S256') {
        computedChallenge = crypto
          .createHash('sha256')
          .update(code_verifier)
          .digest('base64url');
      } else {
        computedChallenge = code_verifier;
      }

      if (computedChallenge !== authCode.code_challenge) {
        logger.warn('PKCE verification failed');
        return res.status(400).json({ 
          error: 'invalid_grant',
          error_description: 'Code verifier does not match code challenge'
        });
      }
    }

    // Clean up used authorization code
    authCodes.delete(code);
    logger.debug('Auth code consumed and removed');

    // Return the access token from environment
    const accessToken = process.env.GATEWAY_AUTH_TOKEN;
    
    if (!accessToken) {
      logger.error('GATEWAY_AUTH_TOKEN not configured in environment');
      return res.status(500).json({ 
        error: 'server_error',
        error_description: 'Server is not properly configured'
      });
    }
    
    logger.info('Issuing access token for MCP gateway access');
    res.json({
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: Math.floor(TOKEN_EXPIRY / 1000),
      scope: authCode.scope || 'mcp:all'
    });
  });

  // Clean up expired authorization codes periodically
  const cleanupInterval = setInterval(() => {
    const now = Date.now();
    let cleaned = 0;
    
    for (const [code, data] of authCodes.entries()) {
      if (data.expires_at < now) {
        authCodes.delete(code);
        cleaned++;
      }
    }
    
    if (cleaned > 0) {
      logger.debug(`Cleaned up ${cleaned} expired authorization codes`);
    }
  }, 60000); // Run every minute

  // Clean up interval on shutdown
  process.on('SIGTERM', () => {
    clearInterval(cleanupInterval);
  });
  
  process.on('SIGINT', () => {
    clearInterval(cleanupInterval);
  });

  logger.info('OAuth endpoints configured successfully');
}