import fetch from 'node-fetch';

const TEST_HOST = 'http://localhost:4242';
const AUTH_TOKEN = process.env.GATEWAY_AUTH_TOKEN || 'test-token-12345';

async function runTest() {
  console.log('Testing Streamable HTTP Transport...\n');

  try {
    // Test 1: Health check
    console.log('1. Testing health endpoint...');
    const healthRes = await fetch(`${TEST_HOST}/health`);
    const health = await healthRes.json();
    console.log('Health check:', health.status === 'ok' ? '✓' : '✗');

    // Test 2: Initialize session
    console.log('\n2. Testing session initialization...');
    const initRes = await fetch(`${TEST_HOST}/mcp/filesystem`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AUTH_TOKEN}`
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'initialize',
        params: {
          protocolVersion: '2024-11-05',
          clientInfo: {
            name: 'test-client',
            version: '1.0.0'
          }
        },
        id: 1
      })
    });

    if (!initRes.ok) {
      throw new Error(`Initialize failed: ${initRes.status} ${await initRes.text()}`);
    }

    const sessionId = initRes.headers.get('mcp-session-id');
    console.log('Session ID:', sessionId);

    const initData = await initRes.json();
    console.log('Initialize response:', initData);

    // Test 3: Send a tools/list request
    console.log('\n3. Testing tools/list with session...');
    const toolsRes = await fetch(`${TEST_HOST}/mcp/filesystem`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${AUTH_TOKEN}`,
        'Mcp-Session-Id': sessionId
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'tools/list',
        params: {},
        id: 2
      })
    });

    if (!toolsRes.ok) {
      throw new Error(`Tools list failed: ${toolsRes.status} ${await toolsRes.text()}`);
    }

    const toolsData = await toolsRes.json();
    console.log('Tools:', toolsData.result?.tools?.length || 0);

    // Test 4: Try GET request for SSE
    console.log('\n4. Testing SSE stream endpoint...');
    const sseRes = await fetch(`${TEST_HOST}/mcp/filesystem`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${AUTH_TOKEN}`,
        'Mcp-Session-Id': sessionId,
        'Accept': 'text/event-stream'
      }
    });

    console.log('SSE Response:', sseRes.status, sseRes.headers.get('content-type'));

    // Test 5: Session termination
    console.log('\n5. Testing session termination...');
    const deleteRes = await fetch(`${TEST_HOST}/mcp/filesystem`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${AUTH_TOKEN}`,
        'Mcp-Session-Id': sessionId
      }
    });

    console.log('DELETE Response:', deleteRes.status);

    console.log('\n✓ All tests passed!');
  } catch (error) {
    console.error('\n✗ Test failed:', error.message);
    process.exit(1);
  }
}

// Run the test
runTest();