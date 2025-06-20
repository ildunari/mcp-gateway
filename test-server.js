import http from 'http';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Test configuration
const TEST_PORT = process.env.TEST_PORT || 4242;
const TEST_HOST = 'http://localhost:' + TEST_PORT;
const STARTUP_TIMEOUT = 5000;
const REQUEST_TIMEOUT = 3000;

// Test results
const results = {
  passed: 0,
  failed: 0,
  tests: []
};

// Helper function to make HTTP requests
async function makeRequest(method, path, options = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, TEST_HOST);
    const reqOptions = {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...options.headers
      },
      timeout: REQUEST_TIMEOUT
    };

    const req = http.request(url, reqOptions, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = data ? JSON.parse(data) : null;
          resolve({ status: res.statusCode, headers: res.headers, body: json });
        } catch (e) {
          resolve({ status: res.statusCode, headers: res.headers, body: data });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    if (options.body) {
      req.write(JSON.stringify(options.body));
    }
    req.end();
  });
}

// Test runner
async function runTest(name, testFn) {
  console.log(`\nRunning: ${name}`);
  try {
    await testFn();
    results.passed++;
    results.tests.push({ name, status: 'PASSED' });
    console.log(`✓ PASSED`);
  } catch (error) {
    results.failed++;
    results.tests.push({ name, status: 'FAILED', error: error.message });
    console.log(`✗ FAILED: ${error.message}`);
  }
}

// Assert helper
function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

// Start server and wait for it to be ready
async function startServer() {
  return new Promise((resolve, reject) => {
    console.log('Starting server...');
    
    // Create minimal .env if it doesn't exist
    const envPath = path.join(__dirname, '.env');
    if (!fs.existsSync(envPath)) {
      fs.writeFileSync(envPath, `
PORT=${TEST_PORT}
NODE_ENV=test
GATEWAY_AUTH_TOKEN=test-token-12345
LOG_LEVEL=error
`.trim());
    }

    // Create empty config if doesn't exist
    const configDir = path.join(__dirname, 'config');
    if (!fs.existsSync(configDir)) {
      fs.mkdirSync(configDir, { recursive: true });
    }
    
    const configPath = path.join(configDir, 'servers.json');
    if (!fs.existsSync(configPath)) {
      fs.writeFileSync(configPath, JSON.stringify({
        servers: [
          {
            name: "Test Server",
            description: "Test MCP server",
            path: "test",
            enabled: true,
            type: "stdio",
            command: "echo",
            args: ["test"],
            env: {}
          }
        ]
      }, null, 2));
    }

    const serverProcess = spawn('node', ['src/server.js'], {
      env: { ...process.env, NODE_ENV: 'test', PORT: TEST_PORT },
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let started = false;
    const timeout = setTimeout(() => {
      if (!started) {
        serverProcess.kill();
        reject(new Error('Server startup timeout'));
      }
    }, STARTUP_TIMEOUT);

    serverProcess.stdout.on('data', (data) => {
      const output = data.toString();
      if (output.includes('MCP Gateway running on port') && !started) {
        started = true;
        clearTimeout(timeout);
        console.log('Server started successfully');
        resolve(serverProcess);
      }
    });

    serverProcess.stderr.on('data', (data) => {
      console.error('Server error:', data.toString());
    });

    serverProcess.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

// Test suite
async function runTests() {
  let serverProcess;
  
  try {
    // Start server
    serverProcess = await startServer();
    
    // Wait a bit for server to fully initialize
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Test 1: Health endpoint
    await runTest('Health endpoint returns correct status', async () => {
      const res = await makeRequest('GET', '/health');
      assert(res.status === 200, `Expected status 200, got ${res.status}`);
      assert(res.body.status === 'ok', 'Expected status to be ok');
      assert(res.body.timestamp, 'Expected timestamp to be present');
      assert(res.body.environment === 'test', 'Expected environment to be test');
      assert(Array.isArray(res.body.servers), 'Expected servers to be an array');
    });

    // Test 2: Servers endpoint
    await runTest('Servers endpoint lists available servers', async () => {
      const res = await makeRequest('GET', '/servers');
      assert(res.status === 200, `Expected status 200, got ${res.status}`);
      assert(res.body.servers, 'Expected servers property');
      assert(Array.isArray(res.body.servers), 'Expected servers to be an array');
      const server = res.body.servers[0];
      if (server) {
        assert(server.name, 'Expected server to have name');
        assert(server.description, 'Expected server to have description');
        assert(server.endpoint, 'Expected server to have endpoint');
      }
    });

    // Test 3: CORS headers
    await runTest('CORS headers are properly set', async () => {
      const res = await makeRequest('OPTIONS', '/health', {
        headers: { 'Origin': 'https://claude.ai' }
      });
      assert(res.status === 200, `Expected status 200, got ${res.status}`);
      assert(res.headers['access-control-allow-origin'] === 'https://claude.ai', 
        'Expected CORS origin to be claude.ai');
      assert(res.headers['access-control-allow-methods'], 
        'Expected CORS methods header');
      assert(res.headers['access-control-allow-headers'], 
        'Expected CORS headers header');
    });

    // Test 4: CORS blocks unauthorized origins
    await runTest('CORS blocks unauthorized origins', async () => {
      const res = await makeRequest('GET', '/health', {
        headers: { 'Origin': 'https://evil.com' }
      });
      assert(!res.headers['access-control-allow-origin'], 
        'Should not have CORS headers for unauthorized origin');
    });

    // Test 5: 404 handler
    await runTest('404 handler works correctly', async () => {
      const res = await makeRequest('GET', '/nonexistent');
      assert(res.status === 404, `Expected status 404, got ${res.status}`);
      assert(res.body.error === 'Not found', 'Expected not found error');
    });

    // Test 6: MCP endpoint requires authentication
    await runTest('MCP endpoint requires authentication', async () => {
      const res = await makeRequest('POST', '/mcp/test');
      assert(res.status === 401, `Expected status 401, got ${res.status}`);
      assert(res.body.error === 'Unauthorized', 'Expected unauthorized error');
    });

    // Test 7: MCP endpoint with valid auth
    await runTest('MCP endpoint accepts valid authentication', async () => {
      const res = await makeRequest('POST', '/mcp/test', {
        headers: { 'Authorization': 'Bearer test-token-12345' }
      });
      // Should either succeed or return 404 for non-existent handler
      assert(res.status === 404 || res.status === 200 || res.status === 500, 
        `Expected status 404/200/500, got ${res.status}`);
    });

    // Test 8: Rate limiting
    await runTest('Rate limiting works', async () => {
      // Make many requests quickly
      const promises = [];
      for (let i = 0; i < 105; i++) {
        promises.push(makeRequest('GET', '/mcp/test').catch(e => ({ error: e })));
      }
      const responses = await Promise.all(promises);
      
      // Check that some requests were rate limited
      const rateLimited = responses.filter(r => r.status === 429);
      assert(rateLimited.length > 0, 'Expected some requests to be rate limited');
    });

    // Test 9: Large request body
    await runTest('Server handles large request bodies', async () => {
      const largeBody = { data: 'x'.repeat(5 * 1024 * 1024) }; // 5MB
      const res = await makeRequest('POST', '/mcp/test', {
        headers: { 'Authorization': 'Bearer test-token-12345' },
        body: largeBody
      });
      assert(res.status !== 413, 'Should accept large bodies up to 10MB');
    });

    // Test 10: Invalid JSON body
    await runTest('Server handles invalid JSON gracefully', async () => {
      // This test requires a custom request since our helper uses JSON.stringify
      const url = new URL('/health', TEST_HOST);
      const promise = new Promise((resolve, reject) => {
        const req = http.request(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' }
        }, (res) => {
          resolve({ status: res.statusCode });
        });
        req.on('error', reject);
        req.write('{ invalid json');
        req.end();
      });
      
      const res = await promise;
      assert(res.status === 400 || res.status === 200, 
        'Should handle invalid JSON without crashing');
    });

    // Test 11: OAuth discovery endpoint
    await runTest('OAuth discovery endpoint exists', async () => {
      const res = await makeRequest('GET', '/.well-known/oauth-authorization-server');
      // This endpoint is handled by auth.js, so we just check it doesn't 404
      assert(res.status !== 404, 'OAuth discovery endpoint should exist');
    });

    // Test 12: Environment variables
    await runTest('Server respects environment variables', async () => {
      const res = await makeRequest('GET', '/health');
      assert(res.body.environment === 'test', 'Should use NODE_ENV from environment');
    });

    // Test 13: Logging directory
    await runTest('Logs directory is created', async () => {
      const logsDir = path.join(__dirname, 'logs');
      assert(fs.existsSync(logsDir), 'Logs directory should exist');
    });

    // Test 14: Server info in health check
    await runTest('Health check includes server information', async () => {
      const res = await makeRequest('GET', '/health');
      assert(res.body.servers, 'Should include servers array');
      const server = res.body.servers[0];
      if (server) {
        assert(server.name, 'Server should have name');
        assert(server.path, 'Server should have path');
        assert(typeof server.enabled === 'boolean', 'Server should have enabled flag');
        assert(server.status, 'Server should have status');
      }
    });

    // Test 15: Content-Type handling
    await runTest('Server handles different content types', async () => {
      const res = await makeRequest('POST', '/health', {
        headers: { 'Content-Type': 'text/plain' },
        body: 'plain text'
      });
      // Should not crash, regardless of response
      assert(res.status, 'Should return a status code');
    });

  } finally {
    // Cleanup
    if (serverProcess) {
      console.log('\nShutting down server...');
      serverProcess.kill('SIGTERM');
      
      // Wait for graceful shutdown
      await new Promise(resolve => {
        serverProcess.on('exit', resolve);
        setTimeout(resolve, 3000); // Max wait 3 seconds
      });
    }
  }
}

// Test edge cases in separate process
async function testEdgeCases() {
  console.log('\n=== Testing Edge Cases ===');

  // Test 1: Port already in use
  await runTest('Server handles port already in use', async () => {
    // Start a dummy server on the test port
    const dummyServer = http.createServer().listen(TEST_PORT);
    
    try {
      // Try to start our server
      const serverProcess = spawn('node', ['src/server.js'], {
        env: { ...process.env, NODE_ENV: 'test', PORT: TEST_PORT },
        stdio: ['ignore', 'pipe', 'pipe']
      });

      let errorDetected = false;
      await new Promise((resolve) => {
        serverProcess.stderr.on('data', (data) => {
          if (data.toString().includes('EADDRINUSE')) {
            errorDetected = true;
          }
        });
        
        serverProcess.on('exit', (code) => {
          resolve();
        });

        setTimeout(() => {
          serverProcess.kill();
          resolve();
        }, 2000);
      });

      assert(errorDetected || serverProcess.exitCode !== 0, 
        'Should detect port in use');
    } finally {
      dummyServer.close();
    }
  });

  // Test 2: Missing environment variables
  await runTest('Server starts without .env file', async () => {
    // Temporarily rename .env
    const envPath = path.join(__dirname, '.env');
    const backupPath = path.join(__dirname, '.env.backup');
    
    if (fs.existsSync(envPath)) {
      fs.renameSync(envPath, backupPath);
    }

    try {
      const serverProcess = spawn('node', ['src/server.js'], {
        env: { ...process.env, NODE_ENV: 'test' },
        stdio: ['ignore', 'pipe', 'pipe']
      });

      let started = false;
      await new Promise((resolve) => {
        serverProcess.stdout.on('data', (data) => {
          if (data.toString().includes('MCP Gateway running')) {
            started = true;
            serverProcess.kill();
            resolve();
          }
        });

        setTimeout(() => {
          serverProcess.kill();
          resolve();
        }, 3000);
      });

      assert(started, 'Server should start without .env file');
    } finally {
      if (fs.existsSync(backupPath)) {
        fs.renameSync(backupPath, envPath);
      }
    }
  });

  // Test 3: Graceful shutdown
  await runTest('Server shuts down gracefully on SIGTERM', async () => {
    const serverProcess = spawn('node', ['src/server.js'], {
      env: { ...process.env, NODE_ENV: 'test', PORT: TEST_PORT },
      stdio: ['ignore', 'pipe', 'pipe']
    });

    // Wait for startup
    await new Promise((resolve) => {
      serverProcess.stdout.on('data', (data) => {
        if (data.toString().includes('MCP Gateway running')) {
          resolve();
        }
      });
    });

    // Send SIGTERM
    serverProcess.kill('SIGTERM');

    // Wait for shutdown
    let gracefulShutdown = false;
    await new Promise((resolve) => {
      serverProcess.stdout.on('data', (data) => {
        if (data.toString().includes('Shutting down gracefully')) {
          gracefulShutdown = true;
        }
      });

      serverProcess.on('exit', () => {
        resolve();
      });
    });

    assert(gracefulShutdown, 'Should log graceful shutdown');
  });
}

// Main test runner
async function main() {
  console.log('🧪 MCP Gateway Server Test Suite\n');
  console.log('================================\n');

  try {
    // Run main tests
    await runTests();
    
    // Run edge case tests
    await testEdgeCases();

    // Print summary
    console.log('\n================================');
    console.log('📊 Test Summary\n');
    console.log(`Total Tests: ${results.passed + results.failed}`);
    console.log(`✅ Passed: ${results.passed}`);
    console.log(`❌ Failed: ${results.failed}`);
    
    if (results.failed > 0) {
      console.log('\n❌ Failed Tests:');
      results.tests
        .filter(t => t.status === 'FAILED')
        .forEach(t => console.log(`  - ${t.name}: ${t.error}`));
    }

    // Exit code based on test results
    process.exit(results.failed > 0 ? 1 : 0);
  } catch (error) {
    console.error('\n💥 Test suite failed:', error.message);
    process.exit(1);
  }
}

// Run tests
main();
