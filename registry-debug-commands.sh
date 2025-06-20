#!/bin/bash

# Registry Debug Commands
# Collection of useful commands for troubleshooting MCP Gateway Registry issues

echo "=== MCP Gateway Registry Debug Tool ==="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Function to print errors
print_error() {
    echo -e "${RED}Error: $1${NC}"
}

# Check if running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MAC=true
else
    IS_MAC=false
fi

# 1. Check MCP server processes
print_section "MCP Server Processes"
if $IS_MAC; then
    ps aux | grep -E "(mock-mcp-server|mcp-server|npx.*modelcontextprotocol)" | grep -v grep
else
    ps aux | grep -E "(mock-mcp-server|mcp-server|npx.*modelcontextprotocol)" | grep -v grep
fi
echo

# 2. Check Node.js processes
print_section "Node.js Processes"
if $IS_MAC; then
    ps aux | grep "node" | grep -v grep | head -10
else
    ps aux | grep "node" | grep -v grep | head -10
fi
echo

# 3. Check port usage
print_section "Port Usage (4242)"
if $IS_MAC; then
    lsof -i :4242 2>/dev/null || echo "Port 4242 is not in use"
else
    netstat -tulpn 2>/dev/null | grep :4242 || echo "Port 4242 is not in use"
fi
echo

# 4. Check memory usage of Node processes
print_section "Memory Usage (Top Node Processes)"
if $IS_MAC; then
    ps aux | grep node | grep -v grep | sort -nrk 4 | head -5 | awk '{printf "%-10s %-6s %-6s %s\n", $1, $3"%", $4"%", $11}'
else
    ps aux | grep node | grep -v grep | sort -nrk 4 | head -5 | awk '{printf "%-10s %-6s %-6s %s\n", $1, $3"%", $4"%", $11}'
fi
echo

# 5. Check for zombie processes
print_section "Zombie Processes"
if $IS_MAC; then
    ps aux | grep "<defunct>" | grep -v grep || echo "No zombie processes found"
else
    ps aux | grep "<defunct>" | grep -v grep || echo "No zombie processes found"
fi
echo

# 6. Test mock MCP server
print_section "Testing Mock MCP Server"
if [ -f "mock-mcp-server.js" ]; then
    echo "Sending test message to mock server..."
    echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' | timeout 2 node mock-mcp-server.js 2>&1 | head -5
else
    print_warning "mock-mcp-server.js not found in current directory"
fi
echo

# 7. Check log files
print_section "Recent Log Entries"
if [ -d "logs" ]; then
    echo "Last 10 lines from combined.log:"
    tail -10 logs/combined.log 2>/dev/null || echo "No combined.log found"
    echo
    echo "Last 5 error entries:"
    tail -50 logs/error.log 2>/dev/null | grep -i error | tail -5 || echo "No errors found"
else
    print_warning "logs directory not found"
fi
echo

# 8. Check server configuration
print_section "Server Configuration"
if [ -f "config/servers.json" ]; then
    echo "Configured servers:"
    cat config/servers.json | grep -E '"name"|"enabled"' | sed 'N;s/\n/ /'
else
    print_error "config/servers.json not found"
fi
echo

# 9. Environment variables
print_section "MCP-related Environment Variables"
env | grep -E "(MCP|GITHUB_TOKEN|API_KEY|NODE_ENV)" | grep -v "SECRET" || echo "No MCP-related environment variables found"
echo

# 10. Network connections
print_section "Active Network Connections (Node)"
if $IS_MAC; then
    lsof -i -n | grep node | head -10 || echo "No active Node.js network connections"
else
    ss -tulpn 2>/dev/null | grep node || netstat -tulpn 2>/dev/null | grep node || echo "No active Node.js network connections"
fi
echo

# 11. File descriptors
print_section "Open File Descriptors"
if $IS_MAC; then
    NODE_PIDS=$(ps aux | grep "node.*mcp" | grep -v grep | awk '{print $2}')
    for pid in $NODE_PIDS; do
        echo "Process $pid: $(lsof -p $pid 2>/dev/null | wc -l) open files"
    done
else
    NODE_PIDS=$(ps aux | grep "node.*mcp" | grep -v grep | awk '{print $2}')
    for pid in $NODE_PIDS; do
        echo "Process $pid: $(ls /proc/$pid/fd 2>/dev/null | wc -l) open files"
    done
fi
echo

# 12. Quick health check
print_section "Quick Health Check"
if command -v curl &> /dev/null; then
    echo "Testing local gateway health endpoint..."
    curl -s http://localhost:4242/health || print_error "Gateway not responding on port 4242"
else
    print_warning "curl not installed, skipping health check"
fi
echo

# Interactive debugging menu
print_section "Interactive Debug Options"
echo "1) Kill all MCP server processes"
echo "2) Test server spawn with mock server"
echo "3) Monitor logs in real-time"
echo "4) Check for port conflicts"
echo "5) Generate debug report"
echo "6) Exit"
echo
read -p "Select option (1-6): " option

case $option in
    1)
        print_section "Killing MCP Processes"
        pkill -f "mock-mcp-server" 2>/dev/null
        pkill -f "modelcontextprotocol" 2>/dev/null
        echo "MCP processes terminated"
        ;;
    2)
        print_section "Testing Server Spawn"
        echo "Starting mock server for 5 seconds..."
        timeout 5 node mock-mcp-server.js > test-spawn.log 2>&1 &
        PID=$!
        sleep 1
        if ps -p $PID > /dev/null; then
            echo "✓ Server spawned successfully (PID: $PID)"
            echo "Sending test message..."
            echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' > /proc/$PID/fd/0 2>/dev/null || echo "Failed to send message"
            sleep 1
            cat test-spawn.log
        else
            print_error "Failed to spawn server"
        fi
        kill $PID 2>/dev/null
        rm -f test-spawn.log
        ;;
    3)
        print_section "Real-time Log Monitoring"
        echo "Press Ctrl+C to stop monitoring"
        tail -f logs/combined.log 2>/dev/null || print_error "Log file not found"
        ;;
    4)
        print_section "Port Conflict Check"
        for port in 4242 3000 8080 8081; do
            if $IS_MAC; then
                lsof -i :$port > /dev/null 2>&1 && echo "Port $port is in use" || echo "Port $port is free"
            else
                netstat -tulpn 2>/dev/null | grep :$port > /dev/null && echo "Port $port is in use" || echo "Port $port is free"
            fi
        done
        ;;
    5)
        print_section "Generating Debug Report"
        REPORT_FILE="mcp-debug-report-$(date +%Y%m%d-%H%M%S).txt"
        {
            echo "MCP Gateway Debug Report"
            echo "Generated: $(date)"
            echo "========================"
            echo
            echo "System Info:"
            uname -a
            echo
            echo "Node Version:"
            node --version
            echo
            echo "NPM Version:"
            npm --version
            echo
            echo "Process List:"
            ps aux | grep -E "(node|mcp)" | grep -v grep
            echo
            echo "Memory Info:"
            if $IS_MAC; then
                vm_stat
            else
                free -h
            fi
            echo
            echo "Recent Errors:"
            tail -50 logs/error.log 2>/dev/null | grep -i error | tail -20
        } > "$REPORT_FILE"
        echo "Debug report saved to: $REPORT_FILE"
        ;;
    6)
        echo "Exiting debug tool"
        exit 0
        ;;
    *)
        print_error "Invalid option"
        ;;
esac

echo
echo "Debug session complete"