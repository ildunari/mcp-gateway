import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
import crypto from 'crypto';

// Load environment variables
const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '.env') });

const BASE_URL = process.env.NODE_ENV === 'production' 
  ? 'https://gateway.pluginpapi.dev'
  : 'http://localhost:4242';

class OAuthTester {
  constructor() {
    this.results = [];
    this.testCount = 0;
    this.passCount = 0;
  }

  async runAllTests() {
    console.log('🔍 Starting OAuth Flow Tests...\n');
    
    // Test OAuth Discovery
    await this.testOAuthDiscovery();
    
    // Test Authorization Endpoint
    await this.testAuthorizationEndpoint();
    
    // Test Token Endpoint
    await this.testTokenEndpoint();
    
    // Test Complete OAuth Flow
    await this.testCompleteOAuthFlow();
    
    // Test Error Cases
    await this.testErrorCases();
    
    // Test PKCE Flow
    await this.testPKCEFlow();
    
    // Display Results
    this.displayResults();
  }

  async testOAuthDiscovery() {
    console.log('📋 Testing OAuth Discovery Endpoint...');
    
    try {
      const response = await fetch(`${BASE_URL}/.well-known/oauth-authorization-server`);
      const data = await response.json();
      
      this.assert(response.status === 200, 'Discovery endpoint returns 200');
      this.assert(data.issuer === BASE_URL, 'Issuer matches base URL');
      this.assert(data.authorization_endpoint === `${BASE_URL}/oauth/authorize`, 'Authorization endpoint correct');
      this.assert(data.token_endpoint === `${BASE_URL}/oauth/token`, 'Token endpoint correct');
      this.assert(data.response_types_supported.includes('code'), 'Supports authorization code flow');
      this.assert(data.grant_types_supported.includes('authorization_code'), 'Supports authorization_code grant');
      this.assert(data.code_challenge_methods_supported.includes('S256'), 'Supports PKCE S256');
      
      console.log('✅ OAuth Discovery tests passed\n');
    } catch (error) {
      this.fail(`Discovery endpoint error: ${error.message}`);
    }
  }

  async testAuthorizationEndpoint() {
    console.log('🔑 Testing Authorization Endpoint...');
    
    // Test valid authorization request
    const state = crypto.randomUUID();
    const clientId = 'test-client';
    const redirectUri = 'https://claude.ai/callback';
    
    try {
      const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
      authUrl.searchParams.set('response_type', 'code');
      authUrl.searchParams.set('client_id', clientId);
      authUrl.searchParams.set('redirect_uri', redirectUri);
      authUrl.searchParams.set('state', state);
      authUrl.searchParams.set('scope', 'mcp:all');
      
      const response = await fetch(authUrl, { redirect: 'manual' });
      
      this.assert(response.status === 302, 'Authorization returns redirect');
      
      const location = response.headers.get('location');
      this.assert(location, 'Has redirect location');
      
      const redirectUrl = new URL(location);
      this.assert(redirectUrl.searchParams.get('state') === state, 'State parameter preserved');
      this.assert(redirectUrl.searchParams.get('code'), 'Authorization code present');
      
      console.log('✅ Authorization endpoint tests passed\n');
    } catch (error) {
      this.fail(`Authorization endpoint error: ${error.message}`);
    }
  }

  async testTokenEndpoint() {
    console.log('🎫 Testing Token Endpoint...');
    
    // First get an authorization code
    const code = await this.getAuthorizationCode();
    
    try {
      // Test valid token exchange
      const response = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: 'https://claude.ai/callback',
          client_id: 'test-client'
        })
      });
      
      const data = await response.json();
      
      this.assert(response.status === 200, 'Token endpoint returns 200');
      this.assert(data.access_token, 'Access token present');
      this.assert(data.token_type === 'Bearer', 'Token type is Bearer');
      this.assert(typeof data.expires_in === 'number', 'Expires_in is a number');
      this.assert(data.scope, 'Scope is present');
      
      console.log('✅ Token endpoint tests passed\n');
    } catch (error) {
      this.fail(`Token endpoint error: ${error.message}`);
    }
  }

  async testCompleteOAuthFlow() {
    console.log('🔄 Testing Complete OAuth Flow...');
    
    try {
      // Step 1: Get authorization code
      const state = crypto.randomUUID();
      const clientId = 'claude-ai-client';
      const redirectUri = 'https://claude.ai/oauth/callback';
      
      const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
      authUrl.searchParams.set('response_type', 'code');
      authUrl.searchParams.set('client_id', clientId);
      authUrl.searchParams.set('redirect_uri', redirectUri);
      authUrl.searchParams.set('state', state);
      
      const authResponse = await fetch(authUrl, { redirect: 'manual' });
      const location = authResponse.headers.get('location');
      const redirectUrl = new URL(location);
      const code = redirectUrl.searchParams.get('code');
      
      this.assert(code, 'Authorization code received');
      
      // Step 2: Exchange code for token
      const tokenResponse = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirectUri,
          client_id: clientId
        })
      });
      
      const tokenData = await tokenResponse.json();
      
      this.assert(tokenData.access_token === process.env.GATEWAY_AUTH_TOKEN, 'Correct access token returned');
      
      // Step 3: Use token to access protected resource
      const testResponse = await fetch(`${BASE_URL}/health`, {
        headers: {
          'Authorization': `Bearer ${tokenData.access_token}`
        }
      });
      
      this.assert(testResponse.status === 200, 'Can access protected endpoint with token');
      
      console.log('✅ Complete OAuth flow tests passed\n');
    } catch (error) {
      this.fail(`Complete flow error: ${error.message}`);
    }
  }

  async testErrorCases() {
    console.log('❌ Testing Error Cases...');
    
    try {
      // Test missing required parameters
      const missingStateResponse = await fetch(`${BASE_URL}/oauth/authorize?redirect_uri=test`, { 
        redirect: 'manual' 
      });
      const missingStateData = await missingStateResponse.json();
      this.assert(missingStateResponse.status === 400, 'Missing state returns 400');
      this.assert(missingStateData.error === 'invalid_request', 'Correct error for missing state');
      
      // Test invalid grant type
      const invalidGrantResponse = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'password',
          code: 'test',
          redirect_uri: 'test'
        })
      });
      const invalidGrantData = await invalidGrantResponse.json();
      this.assert(invalidGrantResponse.status === 400, 'Invalid grant type returns 400');
      this.assert(invalidGrantData.error === 'unsupported_grant_type', 'Correct error for invalid grant');
      
      // Test invalid authorization code
      const invalidCodeResponse = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: 'invalid-code-12345',
          redirect_uri: 'https://claude.ai/callback'
        })
      });
      const invalidCodeData = await invalidCodeResponse.json();
      this.assert(invalidCodeResponse.status === 400, 'Invalid code returns 400');
      this.assert(invalidCodeData.error === 'invalid_grant', 'Correct error for invalid code');
      
      // Test redirect URI mismatch
      const code = await this.getAuthorizationCode();
      const mismatchResponse = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: 'https://wrong-uri.com/callback'
        })
      });
      const mismatchData = await mismatchResponse.json();
      this.assert(mismatchResponse.status === 400, 'Redirect URI mismatch returns 400');
      this.assert(mismatchData.error === 'invalid_grant', 'Correct error for URI mismatch');
      
      console.log('✅ Error case tests passed\n');
    } catch (error) {
      this.fail(`Error case testing failed: ${error.message}`);
    }
  }

  async testPKCEFlow() {
    console.log('🔐 Testing PKCE Flow...');
    
    try {
      // Generate PKCE values
      const codeVerifier = this.generateCodeVerifier();
      const codeChallenge = this.generateCodeChallenge(codeVerifier);
      
      // Step 1: Authorization with PKCE
      const state = crypto.randomUUID();
      const clientId = 'pkce-test-client';
      const redirectUri = 'https://claude.ai/callback';
      
      const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
      authUrl.searchParams.set('response_type', 'code');
      authUrl.searchParams.set('client_id', clientId);
      authUrl.searchParams.set('redirect_uri', redirectUri);
      authUrl.searchParams.set('state', state);
      authUrl.searchParams.set('code_challenge', codeChallenge);
      authUrl.searchParams.set('code_challenge_method', 'S256');
      
      const authResponse = await fetch(authUrl, { redirect: 'manual' });
      const location = authResponse.headers.get('location');
      const redirectUrl = new URL(location);
      const code = redirectUrl.searchParams.get('code');
      
      this.assert(code, 'PKCE authorization code received');
      
      // Step 2: Token exchange with code verifier
      const tokenResponse = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirectUri,
          client_id: clientId,
          code_verifier: codeVerifier
        })
      });
      
      const tokenData = await tokenResponse.json();
      this.assert(tokenResponse.status === 200, 'PKCE token exchange successful');
      this.assert(tokenData.access_token, 'PKCE flow returns access token');
      
      // Test invalid code verifier
      const newCode = await this.getAuthorizationCode(codeChallenge, 'S256');
      const invalidVerifierResponse = await fetch(`${BASE_URL}/oauth/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: newCode,
          redirect_uri: 'https://claude.ai/callback',
          client_id: 'test-client',
          code_verifier: 'wrong-verifier'
        })
      });
      
      const invalidVerifierData = await invalidVerifierResponse.json();
      this.assert(invalidVerifierResponse.status === 400, 'Invalid verifier returns 400');
      this.assert(invalidVerifierData.error === 'invalid_grant', 'Correct error for invalid verifier');
      
      console.log('✅ PKCE flow tests passed\n');
    } catch (error) {
      this.fail(`PKCE flow error: ${error.message}`);
    }
  }

  async testCodeExpiration() {
    console.log('⏰ Testing Authorization Code Expiration...');
    
    try {
      // Get a code but wait before using it
      const code = await this.getAuthorizationCode();
      
      console.log('  Waiting 11 minutes for code to expire...');
      console.log('  (In production, codes expire after 10 minutes)');
      
      // Note: This test would take 11 minutes to run properly
      // For now, we'll just document that this should be tested manually
      
      console.log('  ⚠️  Skipping expiration test (would take 11 minutes)');
      console.log('  ℹ️  Manual test: Wait 11 minutes after getting a code, then try to use it\n');
      
    } catch (error) {
      this.fail(`Expiration test error: ${error.message}`);
    }
  }

  // Helper methods
  async getAuthorizationCode(codeChallenge = null, codeChallengeMethod = null) {
    const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('client_id', 'test-client');
    authUrl.searchParams.set('redirect_uri', 'https://claude.ai/callback');
    authUrl.searchParams.set('state', crypto.randomUUID());
    
    if (codeChallenge) {
      authUrl.searchParams.set('code_challenge', codeChallenge);
      authUrl.searchParams.set('code_challenge_method', codeChallengeMethod);
    }
    
    const response = await fetch(authUrl, { redirect: 'manual' });
    const location = response.headers.get('location');
    const redirectUrl = new URL(location);
    return redirectUrl.searchParams.get('code');
  }

  generateCodeVerifier() {
    return crypto.randomBytes(32).toString('base64url');
  }

  generateCodeChallenge(verifier) {
    return crypto
      .createHash('sha256')
      .update(verifier)
      .digest('base64url');
  }

  assert(condition, message) {
    this.testCount++;
    if (condition) {
      this.passCount++;
      console.log(`  ✅ ${message}`);
    } else {
      this.fail(message);
    }
  }

  fail(message) {
    console.log(`  ❌ ${message}`);
    this.results.push({ success: false, message });
  }

  displayResults() {
    console.log('\n' + '='.repeat(50));
    console.log('📊 Test Results Summary');
    console.log('='.repeat(50));
    console.log(`Total Tests: ${this.testCount}`);
    console.log(`Passed: ${this.passCount}`);
    console.log(`Failed: ${this.testCount - this.passCount}`);
    console.log(`Success Rate: ${((this.passCount / this.testCount) * 100).toFixed(1)}%`);
    
    if (this.results.length > 0) {
      console.log('\n❌ Failed Tests:');
      this.results.forEach(result => {
        if (!result.success) {
          console.log(`  - ${result.message}`);
        }
      });
    }
    
    console.log('\n' + '='.repeat(50));
  }
}

// Check if server is running
async function checkServerRunning() {
  try {
    const response = await fetch(`${BASE_URL}/health`);
    return response.ok;
  } catch (error) {
    return false;
  }
}

// Main execution
async function main() {
  console.log('🚀 OAuth Implementation Test Suite');
  console.log('=' .repeat(50));
  console.log(`Testing against: ${BASE_URL}`);
  console.log('=' .repeat(50) + '\n');

  // Check if server is running
  const serverRunning = await checkServerRunning();
  if (!serverRunning) {
    console.error('❌ Server is not running!');
    console.error(`Please start the server at ${BASE_URL} before running tests.`);
    console.error('\nRun: npm run dev');
    process.exit(1);
  }

  const tester = new OAuthTester();
  await tester.runAllTests();
}

// Run tests
main().catch(console.error);