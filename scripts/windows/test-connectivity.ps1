# MCP Gateway Connectivity Test Script
# Tests network connectivity and endpoint accessibility
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$LocalPort = "4242",
    [string]$GatewayUrl = "https://gateway.pluginpapi.dev",
    [switch]$TestLocal,
    [switch]$TestExternal,
    [switch]$TestCloudflare,
    [switch]$TestMCPServers,
    [switch]$TestAll,
    [switch]$Continuous,
    [int]$Interval = 30,
    [int]$Timeout = 10,
    [switch]$Verbose,
    [switch]$Silent
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Color functions
function Write-Success { if (-not $Silent) { Write-Host $args -ForegroundColor Green } }
function Write-Info { if (-not $Silent) { Write-Host $args -ForegroundColor Cyan } }
function Write-Warning { if (-not $Silent) { Write-Host $args -ForegroundColor Yellow } }
function Write-Error { if (-not $Silent) { Write-Host $args -ForegroundColor Red } }
function Write-Result {
    param($Test, $Success, $Details = "", $ResponseTime = 0)
    
    if (-not $Silent) {
        $status = if ($Success) { "PASS" } else { "FAIL" }
        $color = if ($Success) { "Green" } else { "Red" }
        
        Write-Host "  $Test`: " -NoNewline
        Write-Host $status -ForegroundColor $color -NoNewline
        
        if ($ResponseTime -gt 0) {
            Write-Host " ($ResponseTime ms)" -NoNewline -ForegroundColor Gray
        }
        
        if ($Details) {
            Write-Host " - $Details" -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }
    }
}

# Banner
if (-not $Silent) {
    Write-Info @"
==============================================================
         MCP Gateway Connectivity Test v1.0              
==============================================================
"@
}

# Test results storage
$Script:TestResults = @{
    Timestamp = Get-Date
    Summary = @{
        Total = 0
        Passed = 0
        Failed = 0
    }
    Tests = @()
}

# Test functions
function Test-PortListening {
    param([int]$Port)
    
    Write-Info "`nTesting Local Port Connectivity..."
    
    $result = @{
        TestName = "Local Port $Port"
        Category = "Local"
        Success = $false
        Details = ""
        ResponseTime = 0
    }
    
    # Check if port is listening
    $listening = netstat -an | Select-String ":$Port\s+.*LISTENING"
    
    if ($listening) {
        $result.Success = $true
        $result.Details = "Port is listening"
        
        # Count connections
        $connections = netstat -an | Select-String ":$Port\s+.*ESTABLISHED"
        if ($connections) {
            $result.Details += " - $($connections.Count) active connections"
        }
    }
    else {
        $result.Details = "Port is not listening - service may not be running"
    }
    
    Write-Result -Test $result.TestName -Success $result.Success -Details $result.Details
    
    # Additional checks if verbose
    if ($Verbose -and $result.Success) {
        Write-Host "    Listening addresses:" -ForegroundColor Gray
        foreach ($line in $listening) {
            Write-Host "      $($line.ToString().Trim())" -ForegroundColor Gray
        }
    }
    
    $Script:TestResults.Tests += $result
    return $result
}

function Test-LocalEndpoint {
    param([string]$BaseUrl = "http://localhost:$LocalPort")
    
    Write-Info "`nTesting Local Endpoints..."
    
    $endpoints = @(
        @{ Path = "/health"; Name = "Health Check" }
        @{ Path = "/servers"; Name = "Server List" }
        @{ Path = "/.well-known/oauth-authorization-server"; Name = "OAuth Discovery" }
    )
    
    foreach ($endpoint in $endpoints) {
        $url = "$BaseUrl$($endpoint.Path)"
        $result = @{
            TestName = "Local: $($endpoint.Name)"
            Category = "Local"
            Url = $url
            Success = $false
            Details = ""
            ResponseTime = 0
        }
        
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec $Timeout -UseBasicParsing
            $stopwatch.Stop()
            
            $result.Success = $true
            $result.ResponseTime = $stopwatch.ElapsedMilliseconds
            $result.StatusCode = $response.StatusCode
            
            # Parse response for additional info
            if ($endpoint.Path -eq "/health") {
                try {
                    $health = $response.Content | ConvertFrom-Json
                    $result.Details = "Status: $($health.status)"
                    if ($health.servers) {
                        $result.Details += ", Servers: $($health.servers.Count)"
                    }
                }
                catch {
                    $result.Details = "Status code: $($response.StatusCode)"
                }
            }
            else {
                $result.Details = "Status code: $($response.StatusCode)"
            }
        }
        catch {
            $result.Details = $_.Exception.Message
            
            # Check if it's a connection error
            if ($_.Exception.Message -match "Unable to connect") {
                $result.Details = "Connection refused - service not running"
            }
            elseif ($_.Exception.Response.StatusCode) {
                $result.StatusCode = $_.Exception.Response.StatusCode.value__
                $result.Details = "HTTP $($result.StatusCode)"
            }
        }
        
        Write-Result -Test $result.TestName -Success $result.Success -Details $result.Details -ResponseTime $result.ResponseTime
        
        if ($Verbose -and $result.Success -and $endpoint.Path -eq "/servers") {
            try {
                $servers = $response.Content | ConvertFrom-Json
                if ($servers.servers) {
                    Write-Host "    Available servers:" -ForegroundColor Gray
                    foreach ($server in $servers.servers) {
                        Write-Host "      - $($server.name): $($server.description)" -ForegroundColor Gray
                    }
                }
            }
            catch {}
        }
        
        $Script:TestResults.Tests += $result
    }
}

function Test-ExternalEndpoint {
    param([string]$BaseUrl = $GatewayUrl)
    
    Write-Info "`nTesting External Gateway Endpoints..."
    
    $endpoints = @(
        @{ Path = "/health"; Name = "Health Check"; RequiresAuth = $false }
        @{ Path = "/servers"; Name = "Server List"; RequiresAuth = $false }
        @{ Path = "/mcp/github"; Name = "GitHub MCP"; RequiresAuth = $true }
        @{ Path = "/mcp/desktop"; Name = "Desktop MCP"; RequiresAuth = $true }
    )
    
    foreach ($endpoint in $endpoints) {
        $url = "$BaseUrl$($endpoint.Path)"
        $result = @{
            TestName = "External: $($endpoint.Name)"
            Category = "External"
            Url = $url
            Success = $false
            Details = ""
            ResponseTime = 0
        }
        
        try {
            $headers = @{}
            if ($endpoint.RequiresAuth) {
                # For auth endpoints, we expect 401 without token
                $headers["Accept"] = "application/json"
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -TimeoutSec $Timeout -UseBasicParsing
            $stopwatch.Stop()
            
            $result.ResponseTime = $stopwatch.ElapsedMilliseconds
            $result.StatusCode = $response.StatusCode
            
            if ($endpoint.RequiresAuth) {
                # Should not get 200 without auth
                $result.Success = $false
                $result.Details = "Unexpected success without auth"
            }
            else {
                $result.Success = $true
                $result.Details = "Accessible"
            }
        }
        catch {
            if ($endpoint.RequiresAuth -and $_.Exception.Response.StatusCode.value__ -eq 401) {
                # Expected 401 for auth endpoints
                $result.Success = $true
                $result.Details = "Protected endpoint (401 expected)"
                $result.ResponseTime = $stopwatch.ElapsedMilliseconds
            }
            elseif ($_.Exception.Message -match "Could not resolve") {
                $result.Details = "DNS resolution failed"
            }
            elseif ($_.Exception.Message -match "timed out") {
                $result.Details = "Connection timeout"
            }
            else {
                $result.Details = $_.Exception.Message
            }
        }
        
        Write-Result -Test $result.TestName -Success $result.Success -Details $result.Details -ResponseTime $result.ResponseTime
        $Script:TestResults.Tests += $result
    }
}

function Test-CloudflareInfrastructure {
    Write-Info "`nTesting Cloudflare Infrastructure..."
    
    # Test Cloudflare tunnel process
    $tunnelResult = @{
        TestName = "Cloudflare Tunnel Process"
        Category = "Cloudflare"
        Success = $false
        Details = ""
    }
    
    $tunnelProcess = Get-Process cloudflared -ErrorAction SilentlyContinue
    if ($tunnelProcess) {
        $tunnelResult.Success = $true
        $tunnelResult.Details = "Running ($($tunnelProcess.Count) process(es))"
        
        if ($Verbose) {
            foreach ($proc in $tunnelProcess) {
                $tunnelResult.Details += " - PID: $($proc.Id), Memory: $([Math]::Round($proc.WorkingSet64/1MB, 2))MB"
            }
        }
    }
    else {
        $tunnelResult.Details = "Not running"
    }
    
    Write-Result -Test $tunnelResult.TestName -Success $tunnelResult.Success -Details $tunnelResult.Details
    $Script:TestResults.Tests += $tunnelResult
    
    # Test Cloudflare DNS resolution
    $dnsResult = @{
        TestName = "DNS Resolution (gateway.pluginpapi.dev)"
        Category = "Cloudflare"
        Success = $false
        Details = ""
    }
    
    try {
        $dns = Resolve-DnsName "gateway.pluginpapi.dev" -Type A -ErrorAction Stop
        if ($dns) {
            $dnsResult.Success = $true
            $ips = ($dns | Where-Object { $_.Type -eq "A" } | Select-Object -ExpandProperty IPAddress) -join ", "
            $dnsResult.Details = "Resolved to: $ips"
            
            # Check if it's Cloudflare IP
            if ($ips -match "104\.|172\.6[4-9]\.|172\.7[0-1]\.") {
                $dnsResult.Details += " (Cloudflare)"
            }
        }
    }
    catch {
        $dnsResult.Details = "DNS resolution failed: $($_.Exception.Message)"
    }
    
    Write-Result -Test $dnsResult.TestName -Success $dnsResult.Success -Details $dnsResult.Details
    $Script:TestResults.Tests += $dnsResult
    
    # Test Cloudflare tunnel config
    $configResult = @{
        TestName = "Cloudflare Tunnel Configuration"
        Category = "Cloudflare"
        Success = $false
        Details = ""
    }
    
    $cfConfig = Join-Path $env:USERPROFILE ".cloudflared\config.yml"
    if (Test-Path $cfConfig) {
        $configResult.Success = $true
        $configResult.Details = "Config file exists"
        
        # Check if gateway is configured
        $configContent = Get-Content $cfConfig -Raw
        if ($configContent -match "gateway\.pluginpapi\.dev") {
            $configResult.Details += " - gateway.pluginpapi.dev configured"
        }
        else {
            $configResult.Success = $false
            $configResult.Details += " - gateway.pluginpapi.dev NOT configured"
        }
    }
    else {
        $configResult.Details = "Config file not found"
    }
    
    Write-Result -Test $configResult.TestName -Success $configResult.Success -Details $configResult.Details
    $Script:TestResults.Tests += $configResult
}

function Test-MCPServerEndpoints {
    Write-Info "`nTesting MCP Server Endpoints..."
    
    # First get the list of available servers
    $serversUrl = "http://localhost:$LocalPort/servers"
    $availableServers = @()
    
    try {
        $response = Invoke-RestMethod -Uri $serversUrl -Method Get -TimeoutSec 5
        if ($response.servers) {
            $availableServers = $response.servers
        }
    }
    catch {
        Write-Warning "  Could not retrieve server list"
        return
    }
    
    if ($availableServers.Count -eq 0) {
        Write-Warning "  No MCP servers configured"
        return
    }
    
    # Test each server endpoint
    foreach ($server in $availableServers) {
        $result = @{
            TestName = "MCP Server: $($server.name)"
            Category = "MCP"
            Success = $false
            Details = ""
            ResponseTime = 0
        }
        
        # Extract server path from endpoint
        if ($server.endpoint -match "/mcp/(.+)$") {
            $serverPath = $Matches[1]
            $testUrl = "http://localhost:$LocalPort/mcp/$serverPath"
            
            try {
                # MCP servers typically require specific headers
                $headers = @{
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer test-token"
                }
                
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $response = Invoke-WebRequest -Uri $testUrl -Method POST -Headers $headers `
                    -Body '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{}}' `
                    -TimeoutSec $Timeout -UseBasicParsing
                $stopwatch.Stop()
                
                $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                
                # MCP servers should return 401 without valid auth
                if ($response.StatusCode -eq 200) {
                    $result.Success = $false
                    $result.Details = "Unexpected success - security issue?"
                }
                else {
                    $result.Success = $true
                    $result.Details = "Endpoint responding"
                }
            }
            catch {
                if ($_.Exception.Response.StatusCode.value__ -eq 401) {
                    $result.Success = $true
                    $result.Details = "Protected (401 - auth required)"
                    $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                }
                else {
                    $result.Details = "Error: $($_.Exception.Message)"
                }
            }
        }
        else {
            $result.Details = "Invalid endpoint format"
        }
        
        Write-Result -Test $result.TestName -Success $result.Success -Details $result.Details -ResponseTime $result.ResponseTime
        $Script:TestResults.Tests += $result
    }
}

function Test-GeneralConnectivity {
    Write-Info "`nTesting General Internet Connectivity..."
    
    $endpoints = @(
        @{ Name = "Claude.ai"; Url = "https://claude.ai"; Critical = $true }
        @{ Name = "GitHub API"; Url = "https://api.github.com"; Critical = $false }
        @{ Name = "Cloudflare"; Url = "https://cloudflare.com"; Critical = $false }
        @{ Name = "Google DNS"; Url = "https://dns.google"; Critical = $false }
    )
    
    foreach ($endpoint in $endpoints) {
        $result = @{
            TestName = "Internet: $($endpoint.Name)"
            Category = "Internet"
            Url = $endpoint.Url
            Success = $false
            Details = ""
            ResponseTime = 0
        }
        
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $endpoint.Url -Method Head -TimeoutSec $Timeout -UseBasicParsing
            $stopwatch.Stop()
            
            $result.Success = $true
            $result.ResponseTime = $stopwatch.ElapsedMilliseconds
            $result.StatusCode = $response.StatusCode
            $result.Details = "Reachable"
        }
        catch {
            if ($_.Exception.Message -match "Could not resolve") {
                $result.Details = "DNS resolution failed"
            }
            elseif ($_.Exception.Message -match "timed out") {
                $result.Details = "Connection timeout"
            }
            else {
                $result.Details = "Unreachable"
            }
        }
        
        Write-Result -Test $result.TestName -Success $result.Success -Details $result.Details -ResponseTime $result.ResponseTime
        $Script:TestResults.Tests += $result
    }
}

function Show-Summary {
    Write-Info "`n" + "="*60
    Write-Info "Connectivity Test Summary"
    Write-Info "="*60
    
    # Calculate statistics
    $Script:TestResults.Summary.Total = $Script:TestResults.Tests.Count
    $Script:TestResults.Summary.Passed = ($Script:TestResults.Tests | Where-Object { $_.Success }).Count
    $Script:TestResults.Summary.Failed = $Script:TestResults.Summary.Total - $Script:TestResults.Summary.Passed
    
    $successRate = if ($Script:TestResults.Summary.Total -gt 0) {
        [Math]::Round(($Script:TestResults.Summary.Passed / $Script:TestResults.Summary.Total) * 100, 2)
    } else { 0 }
    
    Write-Host "`nTotal Tests: $($Script:TestResults.Summary.Total)"
    Write-Success "Passed: $($Script:TestResults.Summary.Passed)"
    if ($Script:TestResults.Summary.Failed -gt 0) {
        Write-Error "Failed: $($Script:TestResults.Summary.Failed)"
    }
    Write-Host "Success Rate: $successRate%"
    
    # Show failures
    $failures = $Script:TestResults.Tests | Where-Object { -not $_.Success }
    if ($failures) {
        Write-Warning "`nFailed Tests:"
        foreach ($failure in $failures) {
            Write-Host "  - $($failure.TestName): $($failure.Details)" -ForegroundColor Red
        }
    }
    
    # Show warnings
    $warnings = @()
    
    # Check if local is working but external isn't
    $localHealth = $Script:TestResults.Tests | Where-Object { $_.TestName -eq "Local: Health Check" -and $_.Success }
    $externalHealth = $Script:TestResults.Tests | Where-Object { $_.TestName -eq "External: Health Check" -and $_.Success }
    
    if ($localHealth -and -not $externalHealth) {
        $warnings += "Service is running locally but not accessible externally. Check Cloudflare tunnel."
    }
    
    # Check if tunnel is running but external still fails
    $tunnelRunning = $Script:TestResults.Tests | Where-Object { $_.TestName -eq "Cloudflare Tunnel Process" -and $_.Success }
    if ($tunnelRunning -and -not $externalHealth) {
        $warnings += "Cloudflare tunnel is running but gateway is not accessible. Check tunnel configuration."
    }
    
    if ($warnings) {
        Write-Warning "`nWarnings:"
        foreach ($warning in $warnings) {
            Write-Host "  ! $warning" -ForegroundColor Yellow
        }
    }
    
    # Recommendations
    Write-Info "`nRecommendations:"
    
    $localPort = $Script:TestResults.Tests | Where-Object { $_.TestName -like "Local Port*" }
    if ($localPort -and -not $localPort.Success) {
        Write-Host "  1. Start the MCP Gateway service" -ForegroundColor Yellow
        Write-Host "     Run: Start-Service MCPGateway" -ForegroundColor Gray
    }
    
    if (-not $tunnelRunning) {
        Write-Host "  2. Start Cloudflare tunnel for external access" -ForegroundColor Yellow
        Write-Host "     Run: cloudflared tunnel run my-tunnel" -ForegroundColor Gray
    }
    
    $dnsIssue = $Script:TestResults.Tests | Where-Object { $_.TestName -match "DNS Resolution" -and -not $_.Success }
    if ($dnsIssue) {
        Write-Host "  3. Check DNS configuration for gateway.pluginpapi.dev" -ForegroundColor Yellow
        Write-Host "     Ensure CNAME record points to your tunnel" -ForegroundColor Gray
    }
}

function Run-ContinuousTests {
    Write-Info "Starting continuous connectivity monitoring..."
    Write-Info "Press Ctrl+C to stop"
    Write-Host ""
    
    $iteration = 1
    
    while ($true) {
        Write-Info "`n[$(Get-Date -Format 'HH:mm:ss')] Test iteration #$iteration"
        
        # Reset results for this iteration
        $Script:TestResults.Tests = @()
        
        # Run selected tests
        if ($TestAll -or $TestLocal) {
            Test-PortListening -Port $LocalPort
            Test-LocalEndpoint
        }
        
        if ($TestAll -or $TestExternal) {
            Test-ExternalEndpoint
        }
        
        # Quick summary
        $passed = ($Script:TestResults.Tests | Where-Object { $_.Success }).Count
        $total = $Script:TestResults.Tests.Count
        
        if ($passed -eq $total) {
            Write-Success "`nAll tests passed ($passed/$total)"
        }
        else {
            Write-Warning "`nSome tests failed ($passed/$total passed)"
        }
        
        Write-Host "`nNext test in $Interval seconds..."
        Start-Sleep -Seconds $Interval
        $iteration++
    }
}

# Main execution
try {
    # Determine what to test
    if ($TestAll) {
        $TestLocal = $true
        $TestExternal = $true
        $TestCloudflare = $true
        $TestMCPServers = $true
    }
    elseif (-not $TestLocal -and -not $TestExternal -and -not $TestCloudflare -and -not $TestMCPServers) {
        # Default: test local and external
        $TestLocal = $true
        $TestExternal = $true
    }
    
    if ($Continuous) {
        Run-ContinuousTests
    }
    else {
        # Run tests once
        if ($TestLocal) {
            Test-PortListening -Port $LocalPort
            Test-LocalEndpoint
        }
        
        if ($TestExternal) {
            Test-ExternalEndpoint
        }
        
        if ($TestCloudflare) {
            Test-CloudflareInfrastructure
        }
        
        if ($TestMCPServers) {
            Test-MCPServerEndpoints
        }
        
        # Always test general connectivity
        Test-GeneralConnectivity
        
        # Show summary
        Show-Summary
        
        # Save results
        $resultsPath = Join-Path (Split-Path $PSCommandPath -Parent) "connectivity-test-results.json"
        $Script:TestResults | ConvertTo-Json -Depth 5 | Set-Content $resultsPath -Encoding UTF8
        
        if ($Verbose) {
            Write-Info "`nDetailed results saved to: $resultsPath"
        }
        
        # Exit code based on failures
        if ($Script:TestResults.Summary.Failed -gt 0) {
            exit 1
        }
    }
}
catch {
    Write-Error "Test failed: $_"
    exit 2
}