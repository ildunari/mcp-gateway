# MCP Gateway Service Monitor
# Real-time monitoring and alerting for MCP Gateway
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$ServiceName = "MCPGateway",
    [int]$RefreshInterval = 5,
    [int]$HealthCheckInterval = 30,
    [string]$LogPath = "C:\Services\mcp-gateway\logs",
    [switch]$Dashboard,
    [switch]$LogOnly,
    [switch]$AlertsOnly,
    [string]$ExportPath,
    [int]$HistoryMinutes = 60
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Global variables
$Script:Running = $true
$Script:Metrics = @{
    StartTime = Get-Date
    HealthChecks = @()
    ServiceRestarts = 0
    Errors = @()
    Performance = @()
    Connections = @()
}

# Color functions
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Metric { 
    param($Name, $Value, $Unit = "", $Status = "Normal")
    
    $color = switch ($Status) {
        "Good" { "Green" }
        "Warning" { "Yellow" }
        "Critical" { "Red" }
        default { "White" }
    }
    
    Write-Host "$Name`: " -NoNewline
    Write-Host "$Value$Unit" -ForegroundColor $color
}

# Monitoring functions
function Get-ServiceMetrics {
    param([string]$ServiceName)
    
    $metrics = @{
        Timestamp = Get-Date
        ServiceExists = $false
        Status = "Unknown"
        ProcessId = 0
        CPU = 0
        Memory = 0
        Handles = 0
        Threads = 0
        Uptime = [TimeSpan]::Zero
    }
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $metrics.ServiceExists = $true
            $metrics.Status = $service.Status.ToString()
            
            if ($service.Status -eq "Running") {
                # Get process info
                $process = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq $ServiceName }
                if ($process -and $process.ProcessId -gt 0) {
                    $metrics.ProcessId = $process.ProcessId
                    
                    # Get detailed process metrics
                    $proc = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                    if ($proc) {
                        $metrics.CPU = [Math]::Round($proc.CPU, 2)
                        $metrics.Memory = [Math]::Round($proc.WorkingSet64 / 1MB, 2)
                        $metrics.Handles = $proc.HandleCount
                        $metrics.Threads = $proc.Threads.Count
                        $metrics.Uptime = (Get-Date) - $proc.StartTime
                    }
                }
            }
        }
    }
    catch {
        $metrics.Error = $_.Exception.Message
    }
    
    return $metrics
}

function Get-HealthStatus {
    param([string]$Endpoint = "http://localhost:4242/health")
    
    $health = @{
        Timestamp = Get-Date
        Reachable = $false
        ResponseTime = 0
        Status = "Unknown"
        Servers = @()
        Error = $null
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri $Endpoint -Method Get -TimeoutSec 5
        $stopwatch.Stop()
        
        $health.Reachable = $true
        $health.ResponseTime = $stopwatch.ElapsedMilliseconds
        $health.Status = $response.status
        
        if ($response.servers) {
            foreach ($server in $response.servers) {
                $health.Servers += @{
                    Name = $server.name
                    Enabled = $server.enabled
                    Status = if ($server.status.running) { "Running" } else { "Stopped" }
                    Sessions = $server.status.activeSessions
                }
            }
        }
    }
    catch {
        $health.Error = $_.Exception.Message
    }
    
    return $health
}

function Get-NetworkConnections {
    param([int]$Port = 4242)
    
    $connections = @()
    
    try {
        $netstat = netstat -an | Select-String ":$Port\s+"
        foreach ($line in $netstat) {
            if ($line -match "(\S+):$Port\s+(\S+)\s+(\S+)") {
                $connections += @{
                    LocalAddress = $Matches[1]
                    RemoteAddress = $Matches[2]
                    State = $Matches[3]
                }
            }
        }
    }
    catch {}
    
    return $connections
}

function Get-LogErrors {
    param(
        [string]$LogPath,
        [int]$MinutesBack = 5
    )
    
    $errors = @()
    $since = (Get-Date).AddMinutes(-$MinutesBack)
    
    $errorLog = Join-Path $LogPath "service-error.log"
    $combinedLog = Join-Path $LogPath "combined.log"
    
    foreach ($logFile in @($errorLog, $combinedLog)) {
        if (Test-Path $logFile) {
            try {
                $content = Get-Content $logFile -Tail 100 | Where-Object { $_ -match "ERROR|Error|error" }
                foreach ($line in $content) {
                    # Try to parse timestamp
                    if ($line -match "^\[?(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})") {
                        $timestamp = [DateTime]::Parse($Matches[1])
                        if ($timestamp -gt $since) {
                            $errors += @{
                                Timestamp = $timestamp
                                Message = $line
                                Source = (Split-Path $logFile -Leaf)
                            }
                        }
                    }
                }
            }
            catch {}
        }
    }
    
    return $errors | Sort-Object Timestamp -Descending
}

function Show-Dashboard {
    param($Metrics, $Health, $Connections, $RecentErrors)
    
    Clear-Host
    
    # Header
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "         MCP Gateway Service Monitor Dashboard" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host ""
    
    # Service Status
    Write-Host "SERVICE STATUS" -ForegroundColor Yellow
    Write-Host "--------------"
    
    $statusColor = switch ($Metrics.Status) {
        "Running" { "Green" }
        "Stopped" { "Red" }
        default { "Yellow" }
    }
    
    Write-Metric "Status" $Metrics.Status -Status $(if ($Metrics.Status -eq "Running") { "Good" } else { "Critical" })
    
    if ($Metrics.Status -eq "Running") {
        Write-Metric "PID" $Metrics.ProcessId
        Write-Metric "Uptime" "$([int]$Metrics.Uptime.TotalHours)h $($Metrics.Uptime.Minutes)m"
        Write-Host ""
        
        # Performance Metrics
        Write-Host "PERFORMANCE" -ForegroundColor Yellow
        Write-Host "-----------"
        Write-Metric "CPU" $Metrics.CPU " %"
        Write-Metric "Memory" $Metrics.Memory " MB" -Status $(if ($Metrics.Memory -gt 1000) { "Warning" } else { "Good" })
        Write-Metric "Handles" $Metrics.Handles -Status $(if ($Metrics.Handles -gt 1000) { "Warning" } else { "Good" })
        Write-Metric "Threads" $Metrics.Threads
    }
    
    Write-Host ""
    
    # Health Check
    Write-Host "HEALTH CHECK" -ForegroundColor Yellow
    Write-Host "------------"
    
    if ($Health.Reachable) {
        Write-Metric "Status" $Health.Status -Status "Good"
        Write-Metric "Response Time" $Health.ResponseTime " ms" -Status $(if ($Health.ResponseTime -gt 1000) { "Warning" } else { "Good" })
        
        if ($Health.Servers.Count -gt 0) {
            Write-Host ""
            Write-Host "MCP Servers:" -ForegroundColor White
            foreach ($server in $Health.Servers) {
                $status = if ($server.Status -eq "Running") { "Good" } else { "Warning" }
                Write-Host "  - $($server.Name): " -NoNewline
                Write-Host "$($server.Status)" -ForegroundColor $(if ($status -eq "Good") { "Green" } else { "Yellow" })
                if ($server.Sessions -gt 0) {
                    Write-Host "    Active Sessions: $($server.Sessions)" -ForegroundColor Gray
                }
            }
        }
    }
    else {
        Write-Metric "Status" "Unreachable" -Status "Critical"
        if ($Health.Error) {
            Write-Host "  Error: $($Health.Error)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    
    # Network Connections
    Write-Host "NETWORK" -ForegroundColor Yellow
    Write-Host "-------"
    Write-Metric "Active Connections" $Connections.Count
    
    if ($Connections.Count -gt 0) {
        $established = ($Connections | Where-Object { $_.State -eq "ESTABLISHED" }).Count
        $listening = ($Connections | Where-Object { $_.State -eq "LISTENING" }).Count
        
        Write-Host "  Established: $established"
        Write-Host "  Listening: $listening"
    }
    
    Write-Host ""
    
    # Recent Errors
    if ($RecentErrors.Count -gt 0) {
        Write-Host "RECENT ERRORS (Last 5 min)" -ForegroundColor Yellow
        Write-Host "-------------------------"
        
        $displayErrors = $RecentErrors | Select-Object -First 3
        foreach ($error in $displayErrors) {
            Write-Host "[$($error.Timestamp.ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Gray
            $message = $error.Message
            if ($message.Length -gt 60) {
                $message = $message.Substring(0, 57) + "..."
            }
            Write-Host $message -ForegroundColor Red
        }
        
        if ($RecentErrors.Count -gt 3) {
            Write-Host "  ... and $($RecentErrors.Count - 3) more" -ForegroundColor Gray
        }
        
        Write-Host ""
    }
    
    # Footer
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "Last Update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to exit" -ForegroundColor Gray
}

function Export-Metrics {
    param(
        [string]$Path,
        $Metrics
    )
    
    $export = @{
        ExportTime = Get-Date
        MonitoringDuration = (Get-Date) - $Script:Metrics.StartTime
        ServiceRestarts = $Script:Metrics.ServiceRestarts
        TotalHealthChecks = $Script:Metrics.HealthChecks.Count
        HealthCheckSuccess = ($Script:Metrics.HealthChecks | Where-Object { $_.Reachable }).Count
        RecentMetrics = $Metrics
        PerformanceHistory = $Script:Metrics.Performance | Select-Object -Last 100
        ErrorCount = $Script:Metrics.Errors.Count
        RecentErrors = $Script:Metrics.Errors | Select-Object -Last 50
    }
    
    $export | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
    Write-Success "Metrics exported to: $Path"
}

function Start-Monitoring {
    Write-Info "Starting MCP Gateway monitoring..."
    Write-Info "Service: $ServiceName"
    Write-Info "Refresh: Every $RefreshInterval seconds"
    Write-Info "Health Check: Every $HealthCheckInterval seconds"
    Write-Host ""
    
    if ($Dashboard) {
        Write-Info "Dashboard mode enabled"
    }
    if ($LogOnly) {
        Write-Info "Log monitoring mode"
    }
    if ($AlertsOnly) {
        Write-Info "Alerts only mode"
    }
    
    Write-Host ""
    Write-Host "Press Ctrl+C to stop monitoring"
    Write-Host ""
    
    $lastHealthCheck = [DateTime]::MinValue
    $lastServiceStatus = ""
    
    # Set up Ctrl+C handler
    [Console]::TreatControlCAsInput = $false
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        $Script:Running = $false
    }
    
    try {
        while ($Script:Running) {
            # Get current metrics
            $metrics = Get-ServiceMetrics -ServiceName $ServiceName
            $Script:Metrics.Performance += $metrics
            
            # Check for service status change
            if ($metrics.Status -ne $lastServiceStatus) {
                if ($lastServiceStatus -ne "" -and $metrics.Status -eq "Running") {
                    $Script:Metrics.ServiceRestarts++
                    if (-not $Dashboard) {
                        Write-Warning "Service restarted"
                    }
                }
                $lastServiceStatus = $metrics.Status
            }
            
            # Perform health check if needed
            $health = $null
            if ((Get-Date) -gt $lastHealthCheck.AddSeconds($HealthCheckInterval)) {
                $health = Get-HealthStatus
                $Script:Metrics.HealthChecks += $health
                $lastHealthCheck = Get-Date
            }
            elseif ($Script:Metrics.HealthChecks.Count -gt 0) {
                $health = $Script:Metrics.HealthChecks[-1]
            }
            
            # Get network connections
            $connections = Get-NetworkConnections
            $Script:Metrics.Connections += @{
                Timestamp = Get-Date
                Count = $connections.Count
                Details = $connections
            }
            
            # Get recent errors
            $recentErrors = Get-LogErrors -LogPath $LogPath -MinutesBack 5
            foreach ($error in $recentErrors) {
                if (-not ($Script:Metrics.Errors | Where-Object { 
                    $_.Timestamp -eq $error.Timestamp -and 
                    $_.Message -eq $error.Message 
                })) {
                    $Script:Metrics.Errors += $error
                    
                    if ($AlertsOnly -or (-not $Dashboard -and -not $LogOnly)) {
                        Write-Error "[$($error.Timestamp)] $($error.Message)"
                    }
                }
            }
            
            # Display based on mode
            if ($Dashboard) {
                Show-Dashboard -Metrics $metrics -Health $health -Connections $connections -RecentErrors $recentErrors
            }
            elseif ($LogOnly) {
                if ($recentErrors.Count -gt 0) {
                    foreach ($error in $recentErrors) {
                        Write-Host "[$($error.Timestamp)] " -NoNewline -ForegroundColor Gray
                        Write-Host $error.Message -ForegroundColor Red
                    }
                }
            }
            elseif (-not $AlertsOnly) {
                # Simple status line
                Write-Host "`r[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline
                Write-Host "Status: " -NoNewline
                
                $statusColor = if ($metrics.Status -eq "Running") { "Green" } else { "Red" }
                Write-Host $metrics.Status -ForegroundColor $statusColor -NoNewline
                
                if ($metrics.Status -eq "Running") {
                    Write-Host " | CPU: $($metrics.CPU)% | Mem: $($metrics.Memory)MB | Connections: $($connections.Count)" -NoNewline
                }
                
                Write-Host "          " -NoNewline
            }
            
            # Check for critical conditions
            if ($metrics.Status -eq "Running") {
                # High memory usage
                if ($metrics.Memory -gt 2000) {
                    if (-not $LogOnly) {
                        Write-Warning "High memory usage: $($metrics.Memory) MB"
                    }
                }
                
                # High handle count
                if ($metrics.Handles -gt 5000) {
                    if (-not $LogOnly) {
                        Write-Warning "High handle count: $($metrics.Handles)"
                    }
                }
                
                # Health check failures
                if ($health -and -not $health.Reachable) {
                    if (-not $LogOnly) {
                        Write-Error "Health check failed: Service not responding"
                    }
                }
            }
            
            # Sleep
            Start-Sleep -Seconds $RefreshInterval
        }
    }
    finally {
        # Export metrics if requested
        if ($ExportPath) {
            Export-Metrics -Path $ExportPath -Metrics $metrics
        }
        
        Write-Host ""
        Write-Info "Monitoring stopped"
        
        # Summary
        $duration = (Get-Date) - $Script:Metrics.StartTime
        Write-Host ""
        Write-Info "Monitoring Summary:"
        Write-Host "  Duration: $([int]$duration.TotalMinutes) minutes"
        Write-Host "  Service Restarts: $($Script:Metrics.ServiceRestarts)"
        Write-Host "  Health Checks: $($Script:Metrics.HealthChecks.Count)"
        Write-Host "  Errors Detected: $($Script:Metrics.Errors.Count)"
    }
}

# Main execution
if ($PSCmdlet.MyInvocation.BoundParameters.Count -eq 0) {
    # Show help
    Write-Info "MCP Gateway Service Monitor"
    Write-Info "=========================="
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\monitor-service.ps1 [-Dashboard] [-RefreshInterval <seconds>]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Dashboard         Show real-time dashboard"
    Write-Host "  -LogOnly          Monitor logs only"
    Write-Host "  -AlertsOnly       Show alerts only"
    Write-Host "  -RefreshInterval   Update interval in seconds (default: 5)"
    Write-Host "  -HealthCheckInterval  Health check interval in seconds (default: 30)"
    Write-Host "  -ExportPath       Export metrics to JSON file on exit"
    Write-Host "  -HistoryMinutes   How many minutes of history to keep (default: 60)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\monitor-service.ps1 -Dashboard"
    Write-Host "  .\monitor-service.ps1 -LogOnly"
    Write-Host "  .\monitor-service.ps1 -AlertsOnly -RefreshInterval 10"
    Write-Host "  .\monitor-service.ps1 -Dashboard -ExportPath metrics.json"
}
else {
    Start-Monitoring
}