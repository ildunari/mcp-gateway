# MCP Gateway Debug Information Collector
# Collects comprehensive debug information for support
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$ProjectPath = "C:\Services\mcp-gateway",
    [string]$OutputPath,
    [switch]$IncludeLogs,
    [switch]$IncludeConfig,
    [switch]$IncludeSystem,
    [switch]$IncludeNetwork,
    [switch]$IncludeAll,
    [int]$LogDays = 7,
    [switch]$Compress,
    [switch]$Sanitize,
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

# Banner
if (-not $Silent) {
    Write-Info @"
==============================================================
        MCP Gateway Debug Information Collector v1.0              
==============================================================
"@
}

# Create output directory
$DebugId = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $OutputPath) {
    $OutputPath = Join-Path $ProjectPath "debug-info"
}

$DebugPath = Join-Path $OutputPath "debug-$DebugId"
New-Item -ItemType Directory -Path $DebugPath -Force | Out-Null

# Create collector log
$CollectorLog = Join-Path $DebugPath "collector.log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $CollectorLog -Value $LogMessage
    
    if (-not $Silent) {
        switch ($Level) {
            "SUCCESS" { Write-Success $Message }
            "INFO" { Write-Info $Message }
            "WARNING" { Write-Warning $Message }
            "ERROR" { Write-Error $Message }
        }
    }
}

function Sanitize-Content {
    param([string]$Content)
    
    if (-not $Sanitize) { return $Content }
    
    # Patterns to sanitize
    $patterns = @(
        @{ Pattern = 'GATEWAY_AUTH_TOKEN=\S+'; Replacement = 'GATEWAY_AUTH_TOKEN=***REDACTED***' }
        @{ Pattern = 'GITHUB_TOKEN=\S+'; Replacement = 'GITHUB_TOKEN=***REDACTED***' }
        @{ Pattern = 'ghp_\w+'; Replacement = '***GITHUB_TOKEN***' }
        @{ Pattern = 'Bearer\s+[\w\-\.]+'; Replacement = 'Bearer ***TOKEN***' }
        @{ Pattern = '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'; Replacement = '***IP***' }
        @{ Pattern = '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'; Replacement = '***EMAIL***' }
        @{ Pattern = 'password["\s:=]+["\']\S+["\']'; Replacement = 'password=***REDACTED***' }
    )
    
    $sanitized = $Content
    foreach ($pattern in $patterns) {
        $sanitized = $sanitized -replace $pattern.Pattern, $pattern.Replacement
    }
    
    return $sanitized
}

function Collect-SystemInfo {
    Write-Log "Collecting system information..."
    
    $systemPath = Join-Path $DebugPath "system"
    New-Item -ItemType Directory -Path $systemPath -Force | Out-Null
    
    # OS Information
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $computer = Get-WmiObject -Class Win32_ComputerSystem
    
    $osInfo = @{
        ComputerName = $env:COMPUTERNAME
        OSName = $os.Caption
        OSVersion = $os.Version
        OSArchitecture = $os.OSArchitecture
        BuildNumber = $os.BuildNumber
        InstallDate = $os.ConvertToDateTime($os.InstallDate)
        LastBootTime = $os.ConvertToDateTime($os.LastBootUpTime)
        TotalMemoryGB = [Math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        Processors = $computer.NumberOfProcessors
        LogicalProcessors = $computer.NumberOfLogicalProcessors
    }
    
    $osInfo | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $systemPath "os-info.json")
    
    # PowerShell Information
    $psInfo = @{
        Version = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        OS = $PSVersionTable.OS
        Platform = $PSVersionTable.Platform
        CLRVersion = $PSVersionTable.CLRVersion.ToString()
    }
    
    $psInfo | ConvertTo-Json | Set-Content (Join-Path $systemPath "powershell-info.json")
    
    # Environment Variables (filtered)
    $safeEnvVars = @(
        "COMPUTERNAME", "OS", "PROCESSOR_ARCHITECTURE", "PROCESSOR_IDENTIFIER",
        "NUMBER_OF_PROCESSORS", "TEMP", "TMP", "USERPROFILE", "WINDIR",
        "SYSTEMROOT", "PROGRAMFILES", "PROGRAMFILES(X86)", "COMMONPROGRAMFILES",
        "PATH", "PATHEXT", "NODE_ENV", "NODE_PATH"
    )
    
    $envVars = @{}
    foreach ($var in $safeEnvVars) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if ($value) {
            $envVars[$var] = Sanitize-Content $value
        }
    }
    
    $envVars | ConvertTo-Json | Set-Content (Join-Path $systemPath "environment-vars.json")
    
    # Installed software (Node.js, npm, etc.)
    $software = @{
        NodeJS = @{}
        NPM = @{}
        Git = @{}
        Cloudflared = @{}
    }
    
    # Check Node.js
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $software.NodeJS = @{
            Installed = $true
            Path = $node.Source
            Version = & node --version 2>&1
        }
    }
    
    # Check npm
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        $software.NPM = @{
            Installed = $true
            Path = $npm.Source
            Version = & npm --version 2>&1
        }
        
        # Get global packages
        try {
            $globalPackages = & npm list -g --depth=0 --json 2>&1 | ConvertFrom-Json
            $software.NPM.GlobalPackages = $globalPackages.dependencies.PSObject.Properties.Name
        }
        catch {}
    }
    
    # Check Git
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $software.Git = @{
            Installed = $true
            Path = $git.Source
            Version = & git --version 2>&1
        }
    }
    
    # Check Cloudflared
    $cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cloudflared) {
        $software.Cloudflared = @{
            Installed = $true
            Path = $cloudflared.Source
            Version = & cloudflared --version 2>&1
        }
    }
    
    $software | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $systemPath "installed-software.json")
    
    Write-Log "System information collected" -Level SUCCESS
}

function Collect-ServiceInfo {
    Write-Log "Collecting service information..."
    
    $servicePath = Join-Path $DebugPath "service"
    New-Item -ItemType Directory -Path $servicePath -Force | Out-Null
    
    # Windows Service Info
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    
    if ($service) {
        $serviceInfo = @{
            Name = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status.ToString()
            StartType = $service.StartType.ToString()
            ServiceType = $service.ServiceType.ToString()
        }
        
        # Get additional service details
        $wmiService = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq "MCPGateway" }
        if ($wmiService) {
            $serviceInfo.ProcessId = $wmiService.ProcessId
            $serviceInfo.StartMode = $wmiService.StartMode
            $serviceInfo.State = $wmiService.State
            $serviceInfo.PathName = Sanitize-Content $wmiService.PathName
            $serviceInfo.StartName = $wmiService.StartName
            $serviceInfo.Description = $wmiService.Description
        }
        
        $serviceInfo | ConvertTo-Json | Set-Content (Join-Path $servicePath "service-info.json")
        
        # Get process info if running
        if ($service.Status -eq "Running" -and $wmiService.ProcessId) {
            $process = Get-Process -Id $wmiService.ProcessId -ErrorAction SilentlyContinue
            if ($process) {
                $processInfo = @{
                    ProcessName = $process.ProcessName
                    Id = $process.Id
                    StartTime = $process.StartTime
                    CPU = [Math]::Round($process.CPU, 2)
                    WorkingSetMB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
                    VirtualMemoryMB = [Math]::Round($process.VirtualMemorySize64 / 1MB, 2)
                    HandleCount = $process.HandleCount
                    ThreadCount = $process.Threads.Count
                    Modules = @($process.Modules | Select-Object ModuleName, FileName | Select-Object -First 20)
                }
                
                $processInfo | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $servicePath "process-info.json")
            }
        }
        
        # NSSM configuration
        $nssmPath = Join-Path $ProjectPath "nssm.exe"
        if (Test-Path $nssmPath) {
            $nssmConfig = & $nssmPath dump MCPGateway 2>&1
            Sanitize-Content ($nssmConfig -join "`n") | Set-Content (Join-Path $servicePath "nssm-config.txt")
        }
    }
    else {
        "Service not installed" | Set-Content (Join-Path $servicePath "service-not-found.txt")
    }
    
    # Scheduled tasks
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*MCP*" -or $_.TaskName -like "*Gateway*" }
    if ($tasks) {
        $taskInfo = $tasks | Select-Object TaskName, State, LastRunTime, NextRunTime | ConvertTo-Json
        $taskInfo | Set-Content (Join-Path $servicePath "scheduled-tasks.json")
    }
    
    Write-Log "Service information collected" -Level SUCCESS
}

function Collect-ProjectInfo {
    Write-Log "Collecting project information..."
    
    $projectInfoPath = Join-Path $DebugPath "project"
    New-Item -ItemType Directory -Path $projectInfoPath -Force | Out-Null
    
    # Project structure
    $structure = Get-ChildItem -Path $ProjectPath -Recurse -File | 
                 Where-Object { $_.FullName -notmatch "node_modules|\.git|logs" } |
                 Select-Object @{
                     Name = "RelativePath"
                     Expression = { $_.FullName.Replace($ProjectPath, "").TrimStart("\") }
                 }, Length, LastWriteTime |
                 Sort-Object RelativePath
    
    $structure | ConvertTo-Json | Set-Content (Join-Path $projectInfoPath "file-structure.json")
    
    # Package.json
    $packagePath = Join-Path $ProjectPath "package.json"
    if (Test-Path $packagePath) {
        Copy-Item $packagePath (Join-Path $projectInfoPath "package.json")
    }
    
    # Package-lock.json (just metadata)
    $lockPath = Join-Path $ProjectPath "package-lock.json"
    if (Test-Path $lockPath) {
        $lockInfo = Get-Item $lockPath | Select-Object Name, Length, LastWriteTime
        $lockInfo | ConvertTo-Json | Set-Content (Join-Path $projectInfoPath "package-lock-info.json")
    }
    
    # Git info (if available)
    if (Test-Path (Join-Path $ProjectPath ".git")) {
        Push-Location $ProjectPath
        try {
            $gitInfo = @{
                Branch = & git branch --show-current 2>&1
                LastCommit = & git log -1 --pretty=format:"%h - %an, %ar : %s" 2>&1
                Status = & git status --short 2>&1
                Remotes = & git remote -v 2>&1
            }
            $gitInfo | ConvertTo-Json | Set-Content (Join-Path $projectInfoPath "git-info.json")
        }
        catch {}
        finally {
            Pop-Location
        }
    }
    
    Write-Log "Project information collected" -Level SUCCESS
}

function Collect-ConfigInfo {
    if (-not $IncludeConfig -and -not $IncludeAll) { return }
    
    Write-Log "Collecting configuration information..."
    
    $configPath = Join-Path $DebugPath "config"
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    
    # .env file (sanitized)
    $envFile = Join-Path $ProjectPath ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile -Raw
        $sanitizedEnv = Sanitize-Content $envContent
        $sanitizedEnv | Set-Content (Join-Path $configPath "env-sanitized.txt")
        
        # Extract configuration keys only
        $envKeys = @()
        foreach ($line in $envContent -split "`n") {
            if ($line -match "^([A-Z_]+)=") {
                $envKeys += $Matches[1]
            }
        }
        $envKeys | ConvertTo-Json | Set-Content (Join-Path $configPath "env-keys.json")
    }
    
    # servers.json
    $serversPath = Join-Path $ProjectPath "config\servers.json"
    if (Test-Path $serversPath) {
        $servers = Get-Content $serversPath | ConvertFrom-Json
        
        # Sanitize server config
        foreach ($server in $servers.servers) {
            if ($server.env) {
                $server.env.PSObject.Properties | ForEach-Object {
                    if ($_.Name -match "TOKEN|KEY|SECRET|PASSWORD") {
                        $_.Value = "***REDACTED***"
                    }
                }
            }
        }
        
        $servers | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $configPath "servers-sanitized.json")
    }
    
    # Cloudflare tunnel config (if exists)
    $cfConfig = Join-Path $env:USERPROFILE ".cloudflared\config.yml"
    if (Test-Path $cfConfig) {
        $cfContent = Get-Content $cfConfig -Raw
        $sanitizedCf = Sanitize-Content $cfContent
        $sanitizedCf | Set-Content (Join-Path $configPath "cloudflared-config-sanitized.yml")
    }
    
    Write-Log "Configuration information collected" -Level SUCCESS
}

function Collect-NetworkInfo {
    if (-not $IncludeNetwork -and -not $IncludeAll) { return }
    
    Write-Log "Collecting network information..."
    
    $networkPath = Join-Path $DebugPath "network"
    New-Item -ItemType Directory -Path $networkPath -Force | Out-Null
    
    # Network adapters
    $adapters = Get-NetAdapter | Select-Object Name, Status, MacAddress, LinkSpeed, InterfaceDescription
    $adapters | ConvertTo-Json | Set-Content (Join-Path $networkPath "network-adapters.json")
    
    # IP Configuration
    $ipconfig = ipconfig /all
    Sanitize-Content ($ipconfig -join "`n") | Set-Content (Join-Path $networkPath "ipconfig.txt")
    
    # Listening ports
    $netstat = netstat -an | Select-String "LISTENING"
    $netstat | Out-String | Set-Content (Join-Path $networkPath "listening-ports.txt")
    
    # Port 4242 specific
    $port4242 = netstat -an | Select-String ":4242"
    $port4242 | Out-String | Set-Content (Join-Path $networkPath "port-4242-connections.txt")
    
    # Firewall rules
    try {
        $firewallRules = Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*MCP*" -or $_.DisplayName -like "*4242*" }
        if ($firewallRules) {
            $firewallInfo = $firewallRules | Select-Object DisplayName, Enabled, Direction, Action, Protocol
            $firewallInfo | ConvertTo-Json | Set-Content (Join-Path $networkPath "firewall-rules.json")
        }
    }
    catch {}
    
    # DNS configuration
    $dnsServers = Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses } | 
                  Select-Object InterfaceAlias, AddressFamily, ServerAddresses
    $dnsServers | ConvertTo-Json | Set-Content (Join-Path $networkPath "dns-servers.json")
    
    # Test connectivity to common endpoints
    $connectivityTests = @(
        @{ Name = "Localhost"; Uri = "http://localhost:4242/health" }
        @{ Name = "Gateway"; Uri = "https://gateway.pluginpapi.dev/health" }
        @{ Name = "Claude"; Uri = "https://claude.ai" }
        @{ Name = "GitHub"; Uri = "https://github.com" }
    )
    
    $testResults = @()
    foreach ($test in $connectivityTests) {
        try {
            $response = Invoke-WebRequest -Uri $test.Uri -Method Head -TimeoutSec 5 -UseBasicParsing
            $testResults += @{
                Name = $test.Name
                Uri = $test.Uri
                Success = $true
                StatusCode = $response.StatusCode
            }
        }
        catch {
            $testResults += @{
                Name = $test.Name
                Uri = $test.Uri
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    $testResults | ConvertTo-Json | Set-Content (Join-Path $networkPath "connectivity-tests.json")
    
    Write-Log "Network information collected" -Level SUCCESS
}

function Collect-Logs {
    if (-not $IncludeLogs -and -not $IncludeAll) { return }
    
    Write-Log "Collecting logs..."
    
    $logsPath = Join-Path $DebugPath "logs"
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    
    $logDir = Join-Path $ProjectPath "logs"
    if (Test-Path $logDir) {
        # Get logs from last N days
        $cutoffDate = (Get-Date).AddDays(-$LogDays)
        
        $logFiles = Get-ChildItem $logDir -Filter "*.log" | 
                    Where-Object { $_.LastWriteTime -gt $cutoffDate }
        
        foreach ($logFile in $logFiles) {
            # Copy recent portions of large logs
            if ($logFile.Length -gt 10MB) {
                $tailLines = 10000
                $content = Get-Content $logFile.FullName -Tail $tailLines
                $sanitized = Sanitize-Content ($content -join "`n")
                
                $newName = "$($logFile.BaseName)-tail$($logFile.Extension)"
                $sanitized | Set-Content (Join-Path $logsPath $newName)
                
                Write-Log "Collected tail of $($logFile.Name) (last $tailLines lines)"
            }
            else {
                $content = Get-Content $logFile.FullName -Raw
                $sanitized = Sanitize-Content $content
                $sanitized | Set-Content (Join-Path $logsPath $logFile.Name)
                
                Write-Log "Collected $($logFile.Name)"
            }
        }
        
        # Create log summary
        $logSummary = @{
            TotalLogs = $logFiles.Count
            DateRange = @{
                From = ($logFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
                To = ($logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            }
            LogFiles = $logFiles | Select-Object Name, Length, LastWriteTime
        }
        
        $logSummary | ConvertTo-Json | Set-Content (Join-Path $logsPath "log-summary.json")
    }
    else {
        "No logs directory found" | Set-Content (Join-Path $logsPath "no-logs.txt")
    }
    
    # Windows Event Logs (Application)
    try {
        $events = Get-EventLog -LogName Application -Source "*MCP*", "*Gateway*" -Newest 100 -ErrorAction SilentlyContinue
        if ($events) {
            $eventInfo = $events | Select-Object TimeGenerated, EntryType, Source, Message |
                         ConvertTo-Json
            $eventInfo | Set-Content (Join-Path $logsPath "event-log-application.json")
        }
    }
    catch {}
    
    Write-Log "Logs collected" -Level SUCCESS
}

function Create-Summary {
    Write-Log "Creating debug summary..."
    
    $summary = @{
        CollectionId = $DebugId
        CollectionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        MachineName = $env:COMPUTERNAME
        ProjectPath = $ProjectPath
        IncludedSections = @()
        FileCount = 0
        TotalSizeMB = 0
    }
    
    # Determine what was included
    if ($IncludeAll) {
        $summary.IncludedSections = @("System", "Service", "Project", "Config", "Network", "Logs")
    }
    else {
        $summary.IncludedSections += "System", "Service", "Project"  # Always included
        if ($IncludeConfig) { $summary.IncludedSections += "Config" }
        if ($IncludeNetwork) { $summary.IncludedSections += "Network" }
        if ($IncludeLogs) { $summary.IncludedSections += "Logs" }
    }
    
    # Count files and size
    $allFiles = Get-ChildItem $DebugPath -Recurse -File
    $summary.FileCount = $allFiles.Count
    $summary.TotalSizeMB = [Math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    
    # Add key findings
    $summary.KeyInfo = @{}
    
    # Check service status
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    $summary.KeyInfo.ServiceStatus = if ($service) { $service.Status.ToString() } else { "Not Installed" }
    
    # Check Node.js
    $node = Get-Command node -ErrorAction SilentlyContinue
    $summary.KeyInfo.NodeJSInstalled = $node -ne $null
    
    # Check if project exists
    $summary.KeyInfo.ProjectExists = Test-Path $ProjectPath
    
    # Save summary
    $summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $DebugPath "debug-summary.json")
    
    # Create README
    $readme = @"
MCP Gateway Debug Information
=============================
Collection ID: $DebugId
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Machine: $env:COMPUTERNAME

This debug package contains diagnostic information for MCP Gateway.
Sensitive information has been automatically redacted.

Contents:
- /system     - System and environment information
- /service    - Windows service configuration and status
- /project    - Project structure and dependencies
$(if ($IncludeConfig -or $IncludeAll) { "- /config     - Configuration files (sanitized)`n" })$(if ($IncludeNetwork -or $IncludeAll) { "- /network    - Network configuration and connectivity`n" })$(if ($IncludeLogs -or $IncludeAll) { "- /logs       - Recent log files (sanitized)`n" })
Files: $($summary.FileCount)
Size: $($summary.TotalSizeMB) MB

To share this information:
1. Review the contents to ensure no sensitive data remains
2. Compress the folder if needed
3. Share the resulting file with support

For questions, refer to the MCP Gateway documentation.
"@
    
    $readme | Set-Content (Join-Path $DebugPath "README.txt")
    
    Write-Log "Debug summary created" -Level SUCCESS
}

# Main collection process
try {
    Write-Log "Starting debug information collection"
    Write-Log "Output path: $DebugPath"
    
    if ($IncludeAll) {
        Write-Log "Collecting all information (--IncludeAll specified)"
        $IncludeConfig = $true
        $IncludeNetwork = $true
        $IncludeLogs = $true
        $IncludeSystem = $true
    }
    
    # Always collect these
    Collect-SystemInfo
    Collect-ServiceInfo
    Collect-ProjectInfo
    
    # Optional collections
    Collect-ConfigInfo
    Collect-NetworkInfo
    Collect-Logs
    
    # Create summary
    Create-Summary
    
    # Compress if requested
    if ($Compress) {
        Write-Log "Compressing debug information..."
        
        $zipPath = Join-Path $OutputPath "mcp-debug-$DebugId.zip"
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($DebugPath, $zipPath)
        
        # Remove uncompressed folder
        Remove-Item $DebugPath -Recurse -Force
        
        Write-Log "Debug information compressed to: $zipPath" -Level SUCCESS
        $finalPath = $zipPath
    }
    else {
        $finalPath = $DebugPath
    }
    
    # Final summary
    Write-Log "="*60
    Write-Log "Debug information collection completed!" -Level SUCCESS
    Write-Log "="*60
    
    if (-not $Silent) {
        Write-Success "`nDebug information collected successfully!"
        Write-Host ""
        Write-Info "Location: $finalPath"
        
        if ($Sanitize) {
            Write-Info "Sensitive information has been redacted"
        }
        else {
            Write-Warning "Warning: Debug information may contain sensitive data"
            Write-Warning "Review contents before sharing"
        }
        
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "1. Review the collected information"
        Write-Host "2. Remove any remaining sensitive data"
        Write-Host "3. Share with support if needed"
    }
    
}
catch {
    Write-Log "Collection failed: $_" -Level ERROR
    Write-Error "Failed to collect debug information: $_"
    exit 1
}