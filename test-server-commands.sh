#!/bin/bash

# MCP Gateway Server Test Commands
# This script contains all the test commands for validating the server

echo "🧪 MCP Gateway Server Test Commands"
echo "=================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PORT=${PORT:-4242}
HOST="http://localhost:$PORT"
AUTH_TOKEN=${GATEWAY_AUTH_TOKEN:-test-token}

# Helper function to print section headers
print_section() {
    echo ""
    echo -e "${YELLOW}### $1 ###${NC}"
    echo ""
}

# Helper function to run a command and show the result
run_test() {
    local description="$1"
    local command="$2"
    
    echo -e "${GREEN}Test:${NC} $description"
    echo -e "${GREEN}Command:${NC} $command"
    echo ""
    eval "$command"
    echo ""
    echo "---"
}

# Start of tests
print_section "1. Basic Server Tests"

run_test "Check server health" \
    "curl -X GET $HOST/health | jq ."

run_test "List available servers" \
    "curl -X GET $HOST/servers | jq ."

run_test "Check OAuth discovery endpoint" \
    "curl -X GET $HOST/.well-known/oauth-authorization-server | jq ."

print_section "2. CORS Tests"

run_test "Test CORS with Claude.ai origin" \
    "curl -X OPTIONS $HOST/health \
        -H 'Origin: https://claude.ai' \
        -H 'Access-Control-Request-Method: GET' \
        -H 'Access-Control-Request-Headers: Content-Type' \
        -v 2>&1 | grep -i 'access-control'"

run_test "Test CORS with unauthorized origin (should not have CORS headers)" \
    "curl -X OPTIONS $HOST/health \
        -H 'Origin: https://evil.com' \
        -H 'Access-Control-Request-Method: GET' \
        -v 2>&1 | grep -i 'access-control' || echo 'No CORS headers (expected)'"

print_section "3. Authentication Tests"

run_test "MCP endpoint without auth (should fail)" \
    "curl -X POST $HOST/mcp/test \
        -H 'Content-Type: application/json' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"test\",\"id\":1}' | jq ."

run_test "MCP endpoint with valid auth" \
    "curl -X POST $HOST/mcp/test \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Bearer $AUTH_TOKEN' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"test\",\"id\":1}' | jq ."

print_section "4. Error Handling Tests"

run_test "404 for non-existent endpoint" \
    "curl -X GET $HOST/nonexistent | jq ."

run_test "Invalid JSON body" \
    "curl -X POST $HOST/health \
        -H 'Content-Type: application/json' \
        -d '{ invalid json' -v 2>&1 | grep -E 'HTTP|{'"

run_test "Large request body (5MB)" \
    "dd if=/dev/zero bs=1024 count=5120 2>/dev/null | \
        curl -X POST $HOST/mcp/test \
        -H 'Content-Type: application/octet-stream' \
        -H 'Authorization: Bearer $AUTH_TOKEN' \
        --data-binary @- \
        -v 2>&1 | grep -E 'HTTP|413|200'"

print_section "5. Rate Limiting Test"

run_test "Make multiple requests to test rate limiting" \
    "for i in {1..10}; do \
        curl -s -o /dev/null -w '%{http_code} ' $HOST/mcp/test; \
    done && echo ''"

print_section "6. Session Header Test"

run_test "MCP request with session header" \
    "curl -X POST $HOST/mcp/test \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Bearer $AUTH_TOKEN' \
        -H 'Mcp-Session-Id: test-session-123' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"test\",\"id\":1}' \
        -v 2>&1 | grep -E 'Mcp-Session-Id|{'"

print_section "7. Method Tests"

run_test "GET request to MCP endpoint" \
    "curl -X GET $HOST/mcp/test \
        -H 'Authorization: Bearer $AUTH_TOKEN' \
        -v 2>&1 | grep -E 'HTTP|{'"

run_test "POST request to MCP endpoint" \
    "curl -X POST $HOST/mcp/test \
        -H 'Authorization: Bearer $AUTH_TOKEN' \
        -H 'Content-Type: application/json' \
        -d '{}' \
        -v 2>&1 | grep -E 'HTTP|{'"

print_section "8. Performance Tests"

run_test "Response time for health endpoint" \
    "curl -o /dev/null -s -w 'Response time: %{time_total}s\n' $HOST/health"

run_test "Concurrent requests handling" \
    "for i in {1..5}; do \
        curl -s $HOST/health > /dev/null & \
    done && \
    wait && \
    echo 'All concurrent requests completed'"

print_section "9. Log Verification"

run_test "Check if logs directory exists" \
    "ls -la logs/ 2>/dev/null || echo 'Logs directory not found'"

run_test "Check log files" \
    "ls -la logs/*.log 2>/dev/null || echo 'No log files found yet'"

print_section "10. Full Test Suite"

run_test "Run the complete test suite" \
    "node test-server.js"

echo ""
echo -e "${GREEN}✅ Test commands completed!${NC}"
echo ""
echo "To run individual tests, you can copy and run any of the curl commands above."
echo "Make sure the server is running first with: npm run dev"