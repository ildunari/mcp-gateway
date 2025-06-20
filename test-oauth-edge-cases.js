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

console.log('🔍 OAuth Edge Case Tests\n');

// Test 1: Authorization code reuse
async function testCodeReuse() {
  console.log('📋 Test: Authorization Code Reuse Prevention');
  
  try {
    // Get an authorization code
    const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('client_id', 'test-client');
    authUrl.searchParams.set('redirect_uri', 'https://claude.ai/callback');
    authUrl.searchParams.set('state', crypto.randomUUID());
    
    const authResponse = await fetch(authUrl, { redirect: 'manual' });
    const location = authResponse.headers.get('location');
    const code = new URL(location).searchParams.get('code');
    
    console.log(`  Got code: ${code.substring(0, 8)}...`);
    
    // First use - should succeed
    const firstUse = await fetch(`${BASE_URL}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: 'https://claude.ai/callback',
        client_id: 'test-client'
      })
    });
    
    const firstResponse = await firstUse.json();
    console.log(`  First use: ${firstUse.status} - ${firstResponse.access_token ? '✅ Got token' : '❌ No token'}`);
    
    // Second use - should fail
    const secondUse = await fetch(`${BASE_URL}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: 'https://claude.ai/callback',
        client_id: 'test-client'
      })
    });
    
    const secondResponse = await secondUse.json();
    console.log(`  Second use: ${secondUse.status} - ${secondResponse.error === 'invalid_grant' ? '✅ Correctly rejected' : '❌ Should have failed'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 2: Special characters in parameters
async function testSpecialCharacters() {
  console.log('📋 Test: Special Characters in Parameters');
  
  try {
    const specialState = 'test-!@#$%^&*()_+-=[]{}|;:,.<>?';
    const encodedState = encodeURIComponent(specialState);
    
    const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('client_id', 'test-client-特殊文字');
    authUrl.searchParams.set('redirect_uri', 'https://claude.ai/callback');
    authUrl.searchParams.set('state', specialState);
    
    const response = await fetch(authUrl, { redirect: 'manual' });
    const location = response.headers.get('location');
    const returnedState = new URL(location).searchParams.get('state');
    
    console.log(`  Original state: ${specialState}`);
    console.log(`  Returned state: ${returnedState}`);
    console.log(`  State preserved: ${returnedState === specialState ? '✅ Yes' : '❌ No'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 3: Missing Content-Type header
async function testMissingContentType() {
  console.log('📋 Test: Token Request Without Content-Type');
  
  try {
    const response = await fetch(`${BASE_URL}/oauth/token`, {
      method: 'POST',
      body: 'grant_type=authorization_code&code=test&redirect_uri=test'
    });
    
    console.log(`  Status: ${response.status}`);
    console.log(`  Expected: Should handle missing Content-Type gracefully`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 4: Concurrent authorization requests
async function testConcurrentRequests() {
  console.log('📋 Test: Concurrent Authorization Requests');
  
  try {
    const requests = [];
    
    // Create 5 concurrent authorization requests
    for (let i = 0; i < 5; i++) {
      const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
      authUrl.searchParams.set('response_type', 'code');
      authUrl.searchParams.set('client_id', `client-${i}`);
      authUrl.searchParams.set('redirect_uri', 'https://claude.ai/callback');
      authUrl.searchParams.set('state', `state-${i}`);
      
      requests.push(fetch(authUrl, { redirect: 'manual' }));
    }
    
    const responses = await Promise.all(requests);
    const codes = [];
    
    for (const response of responses) {
      const location = response.headers.get('location');
      const code = new URL(location).searchParams.get('code');
      codes.push(code);
    }
    
    // Check all codes are unique
    const uniqueCodes = new Set(codes);
    console.log(`  Generated ${codes.length} codes`);
    console.log(`  Unique codes: ${uniqueCodes.size}`);
    console.log(`  All unique: ${codes.length === uniqueCodes.size ? '✅ Yes' : '❌ No'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 5: Very long redirect URI
async function testLongRedirectUri() {
  console.log('📋 Test: Very Long Redirect URI');
  
  try {
    const longPath = 'a'.repeat(1000);
    const longRedirectUri = `https://claude.ai/callback/${longPath}`;
    
    const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('client_id', 'test-client');
    authUrl.searchParams.set('redirect_uri', longRedirectUri);
    authUrl.searchParams.set('state', 'test');
    
    const response = await fetch(authUrl, { redirect: 'manual' });
    console.log(`  Status: ${response.status}`);
    console.log(`  Long URI handled: ${response.status === 302 ? '✅ Yes' : '❌ No'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 6: Invalid JSON in token request
async function testInvalidTokenRequest() {
  console.log('📋 Test: Invalid Token Request Body');
  
  try {
    const response = await fetch(`${BASE_URL}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"invalid": "json"'
    });
    
    console.log(`  Status: ${response.status}`);
    console.log(`  Handled gracefully: ${response.status >= 400 ? '✅ Yes' : '❌ No'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 7: PKCE with wrong challenge method
async function testInvalidPKCEMethod() {
  console.log('📋 Test: PKCE with Unsupported Challenge Method');
  
  try {
    const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('client_id', 'test-client');
    authUrl.searchParams.set('redirect_uri', 'https://claude.ai/callback');
    authUrl.searchParams.set('state', 'test');
    authUrl.searchParams.set('code_challenge', 'test-challenge');
    authUrl.searchParams.set('code_challenge_method', 'unsupported-method');
    
    const response = await fetch(authUrl, { redirect: 'manual' });
    console.log(`  Status: ${response.status}`);
    console.log(`  Handled unsupported method: ${response.status === 302 ? '✅ Accepted (stored as-is)' : '❌ Rejected'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Test 8: Empty parameter values
async function testEmptyParameters() {
  console.log('📋 Test: Empty Parameter Values');
  
  try {
    const authUrl = new URL(`${BASE_URL}/oauth/authorize`);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('client_id', '');  // Empty client_id
    authUrl.searchParams.set('redirect_uri', 'https://claude.ai/callback');
    authUrl.searchParams.set('state', 'test');
    
    const response = await fetch(authUrl, { redirect: 'manual' });
    console.log(`  Status: ${response.status}`);
    console.log(`  Empty client_id: ${response.status === 302 ? '✅ Accepted' : '❌ Rejected'}`);
    
  } catch (error) {
    console.error(`  ❌ Error: ${error.message}`);
  }
  console.log();
}

// Main execution
async function runEdgeCaseTests() {
  console.log(`Testing against: ${BASE_URL}\n`);
  
  // Check server is running
  try {
    const health = await fetch(`${BASE_URL}/health`);
    if (!health.ok) throw new Error('Server not healthy');
  } catch (error) {
    console.error('❌ Server is not running!');
    console.error('Please start the server with: npm run dev');
    process.exit(1);
  }
  
  await testCodeReuse();
  await testSpecialCharacters();
  await testMissingContentType();
  await testConcurrentRequests();
  await testLongRedirectUri();
  await testInvalidTokenRequest();
  await testInvalidPKCEMethod();
  await testEmptyParameters();
  
  console.log('✅ Edge case tests complete!\n');
}

runEdgeCaseTests().catch(console.error);