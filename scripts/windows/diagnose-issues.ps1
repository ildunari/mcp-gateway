# MCP Gateway Diagnostic Tool
# Comprehensive issue diagnosis and troubleshooting
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$ProjectPath = "C:\Services\mcp-gateway",
    [switch]$Quick,
    [switch]$Deep,
    [switch]$ServiceOnly,
    [switch]$NetworkOnly,
    [switch]$ConfigOnly,
    [switch]$AutoFix,
    [string]$OutputPath,
    [switch]$Silent
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"  # Continue on errors for diagnostics

# Color functions
function Write-Success { if (-not $Silent) { Write-Host $args -ForegroundColor Green } }
function Write-Info { if (-not $Silent) { Write-Host $args -ForegroundColor Cyan } }
function Write-Warning { if (-not $Silent) { Write-Host $args -ForegroundColor Yellow } }
function Write-Error { if (-not $Silent) { Write-Host $args -ForegroundColor Red } }
function Write-Check { 
    param($Name, $Status, $Details = "")
    if (-not $Silent) {
        Write-Host "  $Name`: " -NoNewline
        switch ($Status) {
            "PASS" { Write-Host "PASS" -ForegroundColor Green -NoNewline }
            "FAIL" { Write-Host "FAIL" -ForegroundColor Red -NoNewline }
            "WARN" { Write-Host "WARN" -ForegroundColor Yellow -NoNewline }
            "INFO" { Write-Host "INFO" -ForegroundColor Cyan -NoNewline }
            default { Write-Host $Status -NoNewline }
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
           MCP Gateway Diagnostic Tool v1.0              
==============================================================
"@
}

# Diagnostic results storage
$Script:Diagnostics = @{
    Timestamp = Get-Date
    System = @{}
    Service = @{}
    Network = @{}
    Configuration = @{}
    Dependencies = @{}
    Logs = @{}
    Issues = @()
    Recommendations = @()
}

# Create diagnostic log
$DiagnosticId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogPath = if ($OutputPath) { $OutputPath } else { Join-Path $ProjectPath "diagnostics" }

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$DiagnosticLog = Join-Path $LogPath "diagnostic-$DiagnosticId.log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $DiagnosticLog -Value $LogMessage
}

# Diagnostic functions
function Test-SystemRequirements {
    Write-Info "Checking System Requirements..."
    
    $results = @{
        OS = @{}
        PowerShell = @{}
        Memory = @{}
        Disk = @{}
        Permissions = @{}
    }
    
    # OS Version
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $results.OS = @{
        Version = $os.Caption
        Build = $os.BuildNumber
        Architecture = $os.OSArchitecture
        Status = "PASS"
    }
    Write-Check "OS Version" "PASS" "$($os.Caption) ($($os.OSArchitecture))"
    
    # PowerShell Version
    $psVersion = $PSVersionTable.PSVersion
    $results.PowerShell = @{
        Version = $psVersion.ToString()
        Status = if ($psVersion.Major -ge 5) { "PASS" } else { "FAIL" }
    }
    Write-Check "PowerShell" $results.PowerShell.Status "v$($psVersion.ToString())"
    
    # Memory
    $totalMemoryGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $memoryUsagePercent = [Math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 2)
    
    $results.Memory = @{
        TotalGB = $totalMemoryGB
        FreeGB = $freeMemoryGB
        UsagePercent = $memoryUsagePercent
        Status = if ($freeMemoryGB -gt 1) { "PASS" } elseif ($freeMemoryGB -gt 0.5) { "WARN" } else { "FAIL" }
    }
    Write-Check "Memory" $results.Memory.Status "$freeMemoryGB GB free of $totalMemoryGB GB"
    
    # Disk Space
    $drive = Get-PSDrive -Name (Split-Path $ProjectPath -Qualifier).TrimEnd(':')
    $freeSpaceGB = [Math]::Round($drive.Free / 1GB, 2)
    
    $results.Disk = @{
        Drive = $drive.Name
        FreeGB = $freeSpaceGB
        Status = if ($freeSpaceGB -gt 5) { "PASS" } elseif ($freeSpaceGB -gt 1) { "WARN" } else { "FAIL" }
    }
    Write-Check "Disk Space" $results.Disk.Status "$freeSpaceGB GB free on $($drive.Name):"
    
    # Administrator Permissions
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $results.Permissions = @{
        IsAdmin = $isAdmin
        Status = if ($isAdmin) { "PASS" } else { "WARN" }
    }
    Write-Check "Admin Rights" $results.Permissions.Status $(if ($isAdmin) { "Running as Administrator" } else { "Not running as Administrator" })
    
    $Script:Diagnostics.System = $results
    return $results
}

function Test-Dependencies {
    Write-Info "`nChecking Dependencies..."
    
    $results = @{
        NodeJS = @{}
        NPM = @{}
        Git = @{}
        Cloudflared = @{}
        NSSM = @{}
    }
    
    # Node.js
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $nodeVersion = & node --version 2>&1
        $results.NodeJS = @{
            Installed = $true
            Version = $nodeVersion
            Path = $node.Source
            Status = "PASS"
        }
        Write-Check "Node.js" "PASS" $nodeVersion
    }
    else {
        $results.NodeJS = @{
            Installed = $false
            Status = "FAIL"
        }
        Write-Check "Node.js" "FAIL" "Not installed"
        $Script:Diagnostics.Issues += "Node.js is not installed"
    }
    
    # NPM
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        $npmVersion = & npm --version 2>&1
        $results.NPM = @{
            Installed = $true
            Version = "v$npmVersion"
            Path = $npm.Source
            Status = "PASS"
        }
        Write-Check "NPM" "PASS" "v$npmVersion"
    }
    else {
        $results.NPM = @{
            Installed = $false
            Status = "FAIL"
        }
        Write-Check "NPM" "FAIL" "Not installed"
        $Script:Diagnostics.Issues += "NPM is not installed"
    }
    
    # Git (optional)
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitVersion = & git --version 2>&1
        $results.Git = @{
            Installed = $true
            Version = $gitVersion
            Path = $git.Source
            Status = "PASS"
        }
        Write-Check "Git" "PASS" $gitVersion
    }
    else {
        $results.Git = @{
            Installed = $false
            Status = "INFO"
        }
        Write-Check "Git" "INFO" "Not installed (optional)"
    }
    
    # Cloudflared (optional)
    $cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cloudflared) {
        $cfVersion = & cloudflared --version 2>&1
        $results.Cloudflared = @{
            Installed = $true
            Version = $cfVersion
            Path = $cloudflared.Source
            Status = "PASS"
        }
        Write-Check "Cloudflared" "PASS" "Installed"
    }
    else {
        $results.Cloudflared = @{
            Installed = $false
            Status = "INFO"
        }
        Write-Check "Cloudflared" "INFO" "Not installed (needed for tunnel)"
    }
    
    # NSSM
    $nssmPath = Join-Path $ProjectPath "nssm.exe"
    if (Test-Path $nssmPath) {
        $results.NSSM = @{
            Installed = $true
            Path = $nssmPath
            Status = "PASS"
        }
        Write-Check "NSSM" "PASS" "Found at project path"
    }
    else {
        $results.NSSM = @{
            Installed = $false
            Status = "WARN"
        }
        Write-Check "NSSM" "WARN" "Not found (needed for service management)"
    }
    
    $Script:Diagnostics.Dependencies = $results
    return $results
}

function Test-ServiceStatus {
    if ($NetworkOnly -or $ConfigOnly) { return }
    
    Write-Info "`nChecking Service Status..."
    
    $results = @{
        ServiceExists = $false
        Status = "Not Installed"
        ProcessInfo = @{}
        Configuration = @{}
    }
    
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    
    if ($service) {
        $results.ServiceExists = $true
        $results.Status = $service.Status.ToString()
        
        Write-Check "Service Installed" "PASS" "MCPGateway service found"
        Write-Check "Service Status" $(if ($service.Status -eq "Running") { "PASS" } else { "WARN" }) $service.Status
        
        if ($service.Status -eq "Running") {
            # Get process information
            $process = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq "MCPGateway" }
            if ($process -and $process.ProcessId -gt 0) {
                $proc = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                if ($proc) {
                    $results.ProcessInfo = @{
                        PID = $proc.Id
                        CPU = [Math]::Round($proc.CPU, 2)
                        MemoryMB = [Math]::Round($proc.WorkingSet64 / 1MB, 2)
                        Handles = $proc.HandleCount
                        Threads = $proc.Threads.Count
                        StartTime = $proc.StartTime
                        Uptime = (Get-Date) - $proc.StartTime
                    }
                    
                    Write-Check "Process ID" "INFO" $proc.Id
                    Write-Check "Memory Usage" $(if ($results.ProcessInfo.MemoryMB -lt 500) { "PASS" } else { "WARN" }) "$($results.ProcessInfo.MemoryMB) MB"
                    Write-Check "Uptime" "INFO" "$([int]$results.ProcessInfo.Uptime.TotalHours)h $($results.ProcessInfo.Uptime.Minutes)m"
                }
            }
        }
        else {
            $Script:Diagnostics.Issues += "Service is not running"
        }
        
        # Get service configuration using NSSM
        $nssmPath = Join-Path $ProjectPath "nssm.exe"
        if (Test-Path $nssmPath) {
            $appDir = & $nssmPath get MCPGateway AppDirectory 2>&1
            $startType = & $nssmPath get MCPGateway Start 2>&1
            
            $results.Configuration = @{
                AppDirectory = if ($appDir -notmatch "error") { $appDir } else { "Unknown" }
                StartType = if ($startType -notmatch "error") { $startType } else { "Unknown" }
            }
        }
    }
    else {
        Write-Check "Service Installed" "FAIL" "MCPGateway service not found"
        $Script:Diagnostics.Issues += "MCPGateway service is not installed"
    }
    
    $Script:Diagnostics.Service = $results
    return $results
}

function Test-NetworkConnectivity {
    if ($ServiceOnly -or $ConfigOnly) { return }
    
    Write-Info "`nChecking Network Connectivity..."
    
    $results = @{
        LocalPort = @{}
        HealthEndpoint = @{}
        ActiveConnections = @()
        CloudflareTunnel = @{}
        ExternalAccess = @{}
    }
    
    # Check if port 4242 is listening
    $listening = netstat -an | Select-String ":4242\s+.*LISTENING"
    $results.LocalPort = @{
        IsListening = $listening -ne $null
        Status = if ($listening) { "PASS" } else { "FAIL" }
    }
    Write-Check "Port 4242" $results.LocalPort.Status $(if ($listening) { "Listening" } else { "Not listening" })
    
    if (-not $listening) {
        $Script:Diagnostics.Issues += "Port 4242 is not listening"
    }
    
    # Test health endpoint
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:4242/health" -Method Get -TimeoutSec 5
        $results.HealthEndpoint = @{
            Reachable = $true
            Status = $health.status
            Timestamp = $health.timestamp
            Servers = $health.servers
            ResponseStatus = "PASS"
        }
        Write-Check "Health Endpoint" "PASS" "Reachable - Status: $($health.status)"
        
        if ($health.servers) {
            foreach ($server in $health.servers) {
                Write-Check "  MCP Server: $($server.name)" $(if ($server.enabled) { "INFO" } else { "WARN" }) $(if ($server.enabled) { "Enabled" } else { "Disabled" })
            }
        }
    }
    catch {
        $results.HealthEndpoint = @{
            Reachable = $false
            Error = $_.Exception.Message
            ResponseStatus = "FAIL"
        }
        Write-Check "Health Endpoint" "FAIL" "Not reachable"
        $Script:Diagnostics.Issues += "Health endpoint not reachable: $($_.Exception.Message)"
    }
    
    # Check active connections
    $connections = netstat -an | Select-String ":4242\s+.*ESTABLISHED"
    $results.ActiveConnections = @($connections | ForEach-Object { $_.ToString().Trim() })
    Write-Check "Active Connections" "INFO" $results.ActiveConnections.Count
    
    # Check Cloudflare tunnel (if configured)
    $tunnelProcess = Get-Process cloudflared -ErrorAction SilentlyContinue
    if ($tunnelProcess) {
        $results.CloudflareTunnel = @{
            Running = $true
            ProcessCount = $tunnelProcess.Count
            Status = "PASS"
        }
        Write-Check "Cloudflare Tunnel" "PASS" "Running ($($tunnelProcess.Count) process(es))"
    }
    else {
        $results.CloudflareTunnel = @{
            Running = $false
            Status = "INFO"
        }
        Write-Check "Cloudflare Tunnel" "INFO" "Not running"
    }
    
    # Test external access (if tunnel is configured)
    if ($Deep -and $results.CloudflareTunnel.Running) {
        try {
            $external = Invoke-WebRequest -Uri "https://gateway.pluginpapi.dev/health" -Method Get -TimeoutSec 10 -UseBasicParsing
            $results.ExternalAccess = @{
                Reachable = $true
                StatusCode = $external.StatusCode
                Status = "PASS"
            }
            Write-Check "External Access" "PASS" "gateway.pluginpapi.dev reachable"
        }
        catch {
            $results.ExternalAccess = @{
                Reachable = $false
                Error = $_.Exception.Message
                Status = "WARN"
            }
            Write-Check "External Access" "WARN" "gateway.pluginpapi.dev not reachable"
        }
    }
    
    $Script:Diagnostics.Network = $results
    return $results
}

function Test-Configuration {
    if ($ServiceOnly -or $NetworkOnly) { return }
    
    Write-Info "`nChecking Configuration..."
    
    $results = @{
        ProjectStructure = @{}
        EnvFile = @{}
        ServersJson = @{}
        PackageJson = @{}
        NodeModules = @{}
    }
    
    # Check project structure
    $requiredDirs = @("src", "config", "logs")
    $requiredFiles = @("src\server.js", "package.json", "config\servers.json")
    
    $missingDirs = @()
    $missingFiles = @()
    
    foreach ($dir in $requiredDirs) {
        $path = Join-Path $ProjectPath $dir
        if (-not (Test-Path $path)) {
            $missingDirs += $dir
        }
    }
    
    foreach ($file in $requiredFiles) {
        $path = Join-Path $ProjectPath $file
        if (-not (Test-Path $path)) {
            $missingFiles += $file
        }
    }
    
    $results.ProjectStructure = @{
        MissingDirs = $missingDirs
        MissingFiles = $missingFiles
        Status = if ($missingDirs.Count -eq 0 -and $missingFiles.Count -eq 0) { "PASS" } else { "FAIL" }
    }
    
    Write-Check "Project Structure" $results.ProjectStructure.Status $(if ($results.ProjectStructure.Status -eq "PASS") { "All required files present" } else { "$($missingDirs.Count) dirs, $($missingFiles.Count) files missing" })
    
    if ($missingFiles.Count -gt 0) {
        $Script:Diagnostics.Issues += "Missing files: $($missingFiles -join ', ')"
    }
    
    # Check .env file
    $envPath = Join-Path $ProjectPath ".env"
    if (Test-Path $envPath) {
        $envContent = Get-Content $envPath -Raw
        $hasPort = $envContent -match "PORT="
        $hasToken = $envContent -match "GATEWAY_AUTH_TOKEN="
        $hasDefaultToken = $envContent -match "GATEWAY_AUTH_TOKEN=CHANGE_ME"
        
        $results.EnvFile = @{
            Exists = $true
            HasPort = $hasPort
            HasToken = $hasToken
            HasDefaultToken = $hasDefaultToken
            Status = if ($hasPort -and $hasToken -and -not $hasDefaultToken) { "PASS" } elseif ($hasDefaultToken) { "WARN" } else { "FAIL" }
        }
        
        Write-Check ".env File" $results.EnvFile.Status $(if ($hasDefaultToken) { "Has default token - needs configuration" } elseif (-not $hasToken) { "Missing auth token" } else { "Configured" })
        
        if ($hasDefaultToken) {
            $Script:Diagnostics.Issues += ".env file has default auth token"
            $Script:Diagnostics.Recommendations += "Generate a secure token for GATEWAY_AUTH_TOKEN"
        }
    }
    else {
        $results.EnvFile = @{
            Exists = $false
            Status = "FAIL"
        }
        Write-Check ".env File" "FAIL" "Not found"
        $Script:Diagnostics.Issues += ".env file not found"
    }
    
    # Check servers.json
    $serversPath = Join-Path $ProjectPath "config\servers.json"
    if (Test-Path $serversPath) {
        try {
            $servers = Get-Content $serversPath | ConvertFrom-Json
            $enabledCount = ($servers.servers | Where-Object { $_.enabled }).Count
            
            $results.ServersJson = @{
                Exists = $true
                Valid = $true
                TotalServers = $servers.servers.Count
                EnabledServers = $enabledCount
                Status = if ($enabledCount -gt 0) { "PASS" } else { "WARN" }
            }
            
            Write-Check "servers.json" $results.ServersJson.Status "$enabledCount of $($servers.servers.Count) servers enabled"
        }
        catch {
            $results.ServersJson = @{
                Exists = $true
                Valid = $false
                Error = $_.Exception.Message
                Status = "FAIL"
            }
            Write-Check "servers.json" "FAIL" "Invalid JSON"
            $Script:Diagnostics.Issues += "servers.json is invalid: $($_.Exception.Message)"
        }
    }
    else {
        $results.ServersJson = @{
            Exists = $false
            Status = "FAIL"
        }
        Write-Check "servers.json" "FAIL" "Not found"
        $Script:Diagnostics.Issues += "servers.json not found"
    }
    
    # Check package.json
    $packagePath = Join-Path $ProjectPath "package.json"
    if (Test-Path $packagePath) {
        try {
            $package = Get-Content $packagePath | ConvertFrom-Json
            $results.PackageJson = @{
                Exists = $true
                Valid = $true
                Name = $package.name
                Version = $package.version
                Status = "PASS"
            }
            Write-Check "package.json" "PASS" "v$($package.version)"
        }
        catch {
            $results.PackageJson = @{
                Exists = $true
                Valid = $false
                Status = "FAIL"
            }
            Write-Check "package.json" "FAIL" "Invalid JSON"
        }
    }
    
    # Check node_modules
    $nodeModulesPath = Join-Path $ProjectPath "node_modules"
    if (Test-Path $nodeModulesPath) {
        $moduleCount = (Get-ChildItem $nodeModulesPath -Directory).Count
        $results.NodeModules = @{
            Exists = $true
            ModuleCount = $moduleCount
            Status = if ($moduleCount -gt 0) { "PASS" } else { "WARN" }
        }
        Write-Check "node_modules" $results.NodeModules.Status "$moduleCount packages installed"
    }
    else {
        $results.NodeModules = @{
            Exists = $false
            Status = "FAIL"
        }
        Write-Check "node_modules" "FAIL" "Not found - run 'npm install'"
        $Script:Diagnostics.Issues += "Dependencies not installed"
        $Script:Diagnostics.Recommendations += "Run 'npm install' in project directory"
    }
    
    $Script:Diagnostics.Configuration = $results
    return $results
}

function Test-Logs {
    if ($Quick -or $ServiceOnly -or $NetworkOnly -or $ConfigOnly) { return }
    
    Write-Info "`nChecking Logs..."
    
    $results = @{
        LogDirectory = @{}
        RecentErrors = @()
        LogFiles = @()
    }
    
    $logPath = Join-Path $ProjectPath "logs"
    
    if (Test-Path $logPath) {
        $logFiles = Get-ChildItem $logPath -Filter "*.log" -File
        $results.LogDirectory.Exists = $true
        $results.LogDirectory.FileCount = $logFiles.Count
        
        Write-Check "Log Directory" "PASS" "$($logFiles.Count) log files"
        
        # Check for recent errors
        $recentErrors = @()
        $errorPatterns = @("ERROR", "Error", "error", "FAIL", "Failed", "Exception")
        
        foreach ($logFile in $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 3) {
            $content = Get-Content $logFile.FullName -Tail 100 -ErrorAction SilentlyContinue
            
            foreach ($line in $content) {
                foreach ($pattern in $errorPatterns) {
                    if ($line -match $pattern) {
                        $recentErrors += @{
                            File = $logFile.Name
                            Line = $line
                            Pattern = $pattern
                        }
                        break
                    }
                }
            }
            
            $results.LogFiles += @{
                Name = $logFile.Name
                SizeMB = [Math]::Round($logFile.Length / 1MB, 2)
                LastModified = $logFile.LastWriteTime
            }
        }
        
        $results.RecentErrors = $recentErrors | Select-Object -First 10
        
        if ($recentErrors.Count -gt 0) {
            Write-Check "Recent Errors" "WARN" "$($recentErrors.Count) errors found in logs"
            
            if ($Deep) {
                Write-Info "`n  Recent Error Samples:"
                $recentErrors | Select-Object -First 3 | ForEach-Object {
                    Write-Host "    [$($_.File)] $($_.Line.Substring(0, [Math]::Min($_.Line.Length, 80)))..." -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Check "Recent Errors" "PASS" "No recent errors found"
        }
        
        # Check log size
        $totalLogSize = ($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB
        if ($totalLogSize -gt 1000) {
            Write-Check "Log Size" "WARN" "$([Math]::Round($totalLogSize, 2)) MB - consider cleanup"
            $Script:Diagnostics.Recommendations += "Run cleanup-logs.ps1 to manage log size"
        }
    }
    else {
        $results.LogDirectory.Exists = $false
        Write-Check "Log Directory" "WARN" "Not found"
    }
    
    $Script:Diagnostics.Logs = $results
    return $results
}

function Get-Recommendations {
    # Add context-specific recommendations
    
    # Service recommendations
    if ($Script:Diagnostics.Service.ServiceExists -and $Script:Diagnostics.Service.Status -ne "Running") {
        $Script:Diagnostics.Recommendations += "Start the service using: Start-Service MCPGateway"
    }
    
    if (-not $Script:Diagnostics.Service.ServiceExists) {
        $Script:Diagnostics.Recommendations += "Install the service using: .\install-service.ps1"
    }
    
    # Memory recommendations
    if ($Script:Diagnostics.System.Memory.FreeGB -lt 1) {
        $Script:Diagnostics.Recommendations += "Low memory available. Consider closing other applications."
    }
    
    # Disk space recommendations
    if ($Script:Diagnostics.System.Disk.FreeGB -lt 1) {
        $Script:Diagnostics.Recommendations += "Low disk space. Clean up unnecessary files."
    }
    
    # Network recommendations
    if ($Script:Diagnostics.Network.LocalPort.IsListening -and -not $Script:Diagnostics.Network.CloudflareTunnel.Running) {
        $Script:Diagnostics.Recommendations += "Service is running but Cloudflare tunnel is not. External access won't work."
    }
    
    # Remove duplicates
    $Script:Diagnostics.Recommendations = @($Script:Diagnostics.Recommendations | Select-Object -Unique)
}

function Invoke-AutoFix {
    if (-not $AutoFix) { return }
    
    Write-Info "`nAttempting Auto-Fix..."
    
    $fixed = @()
    
    # Fix: Install dependencies
    if (-not $Script:Diagnostics.Configuration.NodeModules.Exists) {
        Write-Info "Installing npm dependencies..."
        Push-Location $ProjectPath
        try {
            npm install
            if ($LASTEXITCODE -eq 0) {
                $fixed += "Installed npm dependencies"
            }
        }
        catch {}
        finally {
            Pop-Location
        }
    }
    
    # Fix: Create missing directories
    foreach ($dir in $Script:Diagnostics.Configuration.ProjectStructure.MissingDirs) {
        $path = Join-Path $ProjectPath $dir
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $fixed += "Created directory: $dir"
    }
    
    # Fix: Create .env from example
    if (-not $Script:Diagnostics.Configuration.EnvFile.Exists) {
        $envExample = Join-Path $ProjectPath ".env.example"
        $envFile = Join-Path $ProjectPath ".env"
        
        if (Test-Path $envExample) {
            Copy-Item $envExample $envFile
            $fixed += "Created .env from .env.example"
        }
    }
    
    # Fix: Start service if installed but not running
    if ($Script:Diagnostics.Service.ServiceExists -and $Script:Diagnostics.Service.Status -ne "Running") {
        try {
            Start-Service MCPGateway
            Start-Sleep -Seconds 3
            $service = Get-Service MCPGateway
            if ($service.Status -eq "Running") {
                $fixed += "Started MCPGateway service"
            }
        }
        catch {}
    }
    
    if ($fixed.Count -gt 0) {
        Write-Success "`nAuto-Fix Results:"
        foreach ($fix in $fixed) {
            Write-Success "  ✓ $fix"
        }
    }
    else {
        Write-Info "No automatic fixes available"
    }
}

function Export-DiagnosticReport {
    $report = @{
        Diagnostics = $Script:Diagnostics
        Summary = @{
            TotalIssues = $Script:Diagnostics.Issues.Count
            CriticalIssues = 0
            Warnings = 0
            Status = "Unknown"
        }
    }
    
    # Calculate summary
    foreach ($issue in $Script:Diagnostics.Issues) {
        if ($issue -match "not installed|not found|FAIL") {
            $report.Summary.CriticalIssues++
        }
        else {
            $report.Summary.Warnings++
        }
    }
    
    if ($report.Summary.CriticalIssues -gt 0) {
        $report.Summary.Status = "Critical"
    }
    elseif ($report.Summary.Warnings -gt 0) {
        $report.Summary.Status = "Warning"
    }
    else {
        $report.Summary.Status = "Healthy"
    }
    
    # Save detailed report
    $reportPath = Join-Path (Split-Path $DiagnosticLog -Parent) "diagnostic-report-$DiagnosticId.json"
    $report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8
    
    # Create summary report
    $summaryPath = Join-Path (Split-Path $DiagnosticLog -Parent) "diagnostic-summary-$DiagnosticId.txt"
    $summary = @"
MCP Gateway Diagnostic Summary
==============================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Status: $($report.Summary.Status)

Issues Found: $($report.Summary.TotalIssues)
- Critical: $($report.Summary.CriticalIssues)
- Warnings: $($report.Summary.Warnings)

Key Findings:
$($Script:Diagnostics.Issues | ForEach-Object { "- $_" } | Out-String)

Recommendations:
$($Script:Diagnostics.Recommendations | ForEach-Object { "- $_" } | Out-String)

Full report: $reportPath
"@
    
    Set-Content $summaryPath -Value $summary -Encoding UTF8
    
    return @{
        Report = $reportPath
        Summary = $summaryPath
    }
}

# Main diagnostic process
try {
    Write-Log "Starting MCP Gateway diagnostics"
    Write-Log "Mode: $(if ($Quick) { 'Quick' } elseif ($Deep) { 'Deep' } else { 'Standard' })"
    
    # Run diagnostics based on mode
    if (-not $ServiceOnly -and -not $NetworkOnly -and -not $ConfigOnly) {
        # Full diagnostics
        Test-SystemRequirements
        Test-Dependencies
        Test-ServiceStatus
        Test-NetworkConnectivity
        Test-Configuration
        
        if (-not $Quick) {
            Test-Logs
        }
    }
    else {
        # Partial diagnostics
        if (-not $NetworkOnly -and -not $ConfigOnly) {
            Test-SystemRequirements
            Test-Dependencies
        }
        
        if ($ServiceOnly) {
            Test-ServiceStatus
        }
        
        if ($NetworkOnly) {
            Test-NetworkConnectivity
        }
        
        if ($ConfigOnly) {
            Test-Configuration
        }
    }
    
    # Generate recommendations
    Get-Recommendations
    
    # Attempt auto-fix if requested
    Invoke-AutoFix
    
    # Export reports
    $reports = Export-DiagnosticReport
    
    # Display summary
    if (-not $Silent) {
        Write-Info "`n" + "="*60
        Write-Info "Diagnostic Summary"
        Write-Info "="*60
        
        if ($Script:Diagnostics.Issues.Count -eq 0) {
            Write-Success "`nNo issues found! System appears healthy."
        }
        else {
            Write-Warning "`nIssues Found: $($Script:Diagnostics.Issues.Count)"
            foreach ($issue in $Script:Diagnostics.Issues) {
                Write-Host "  - $issue" -ForegroundColor Red
            }
        }
        
        if ($Script:Diagnostics.Recommendations.Count -gt 0) {
            Write-Info "`nRecommendations:"
            foreach ($rec in $Script:Diagnostics.Recommendations) {
                Write-Host "  • $rec" -ForegroundColor Yellow
            }
        }
        
        Write-Info "`nDiagnostic Reports:"
        Write-Host "  Summary: $($reports.Summary)"
        Write-Host "  Full Report: $($reports.Report)"
    }
    
    # Exit code based on issues
    if ($Script:Diagnostics.Issues.Count -gt 0) {
        exit 1
    }
    else {
        exit 0
    }
}
catch {
    Write-Log "Diagnostic failed: $_" -Level ERROR
    Write-Error "Diagnostic failed: $_"
    exit 2
}