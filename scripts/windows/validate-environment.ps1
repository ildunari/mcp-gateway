# MCP Gateway Environment Validator
# Validates prerequisites and environment setup
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$ProjectPath = "C:\Services\mcp-gateway",
    [switch]$CheckOnly,
    [switch]$InstallMissing,
    [switch]$FixIssues,
    [switch]$Detailed,
    [string]$ReportPath,
    [switch]$Silent
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Color functions
function Write-Success { if (-not $Silent) { Write-Host $args -ForegroundColor Green } }
function Write-Info { if (-not $Silent) { Write-Host $args -ForegroundColor Cyan } }
function Write-Warning { if (-not $Silent) { Write-Host $args -ForegroundColor Yellow } }
function Write-Error { if (-not $Silent) { Write-Host $args -ForegroundColor Red } }
function Write-Check { 
    param($Component, $Status, $Version = "", $Details = "")
    
    if (-not $Silent) {
        Write-Host "  $Component`: " -NoNewline
        
        switch ($Status) {
            "OK" { 
                Write-Host "OK" -ForegroundColor Green -NoNewline
                if ($Version) { Write-Host " (v$Version)" -NoNewline -ForegroundColor Gray }
            }
            "WARNING" { 
                Write-Host "WARNING" -ForegroundColor Yellow -NoNewline 
            }
            "ERROR" { 
                Write-Host "ERROR" -ForegroundColor Red -NoNewline 
            }
            "MISSING" { 
                Write-Host "MISSING" -ForegroundColor Red -NoNewline 
            }
            default { 
                Write-Host $Status -NoNewline 
            }
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
        MCP Gateway Environment Validator v1.0              
==============================================================
"@
}

# Validation results
$Script:ValidationResults = @{
    Timestamp = Get-Date
    Valid = $true
    Components = @{}
    Issues = @()
    Fixes = @()
    Recommendations = @()
}

# Component validators
function Test-OperatingSystem {
    Write-Info "`nValidating Operating System..."
    
    $result = @{
        Name = "Operating System"
        Valid = $true
        Details = @{}
    }
    
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $result.Details.Caption = $os.Caption
    $result.Details.Version = $os.Version
    $result.Details.Architecture = $os.OSArchitecture
    $result.Details.BuildNumber = $os.BuildNumber
    
    # Check Windows version (Windows 10/11 or Server 2016+)
    $majorVersion = [int]$os.Version.Split('.')[0]
    $buildNumber = [int]$os.BuildNumber
    
    if ($majorVersion -ge 10 -or ($majorVersion -eq 6 -and $buildNumber -ge 14393)) {
        Write-Check "Windows Version" "OK" $os.Caption
        $result.Details.VersionCheck = "Supported"
    }
    else {
        Write-Check "Windows Version" "WARNING" $os.Caption "Older version, may have compatibility issues"
        $result.Valid = $false
        $result.Details.VersionCheck = "Unsupported"
        $Script:ValidationResults.Issues += "Windows version is older than recommended (Windows 10/Server 2016)"
    }
    
    # Check architecture
    if ($os.OSArchitecture -eq "64-bit") {
        Write-Check "Architecture" "OK" "64-bit"
    }
    else {
        Write-Check "Architecture" "ERROR" "32-bit" "64-bit OS required"
        $result.Valid = $false
        $Script:ValidationResults.Issues += "32-bit OS detected, 64-bit required"
    }
    
    # Check available memory
    $totalMemoryGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    if ($totalMemoryGB -ge 4) {
        Write-Check "Memory" "OK" "$totalMemoryGB GB"
    }
    elseif ($totalMemoryGB -ge 2) {
        Write-Check "Memory" "WARNING" "$totalMemoryGB GB" "Minimum 4GB recommended"
        $Script:ValidationResults.Recommendations += "Upgrade system memory to at least 4GB for optimal performance"
    }
    else {
        Write-Check "Memory" "ERROR" "$totalMemoryGB GB" "Insufficient memory"
        $result.Valid = $false
        $Script:ValidationResults.Issues += "Insufficient memory (less than 2GB)"
    }
    
    $result.Details.TotalMemoryGB = $totalMemoryGB
    
    $Script:ValidationResults.Components["OperatingSystem"] = $result
    return $result.Valid
}

function Test-PowerShell {
    Write-Info "`nValidating PowerShell..."
    
    $result = @{
        Name = "PowerShell"
        Valid = $true
        Details = @{}
    }
    
    $psVersion = $PSVersionTable.PSVersion
    $result.Details.Version = $psVersion.ToString()
    $result.Details.Edition = $PSVersionTable.PSEdition
    
    # Check PowerShell version (5.0+)
    if ($psVersion.Major -ge 5) {
        Write-Check "PowerShell Version" "OK" $psVersion.ToString()
    }
    else {
        Write-Check "PowerShell Version" "ERROR" $psVersion.ToString() "Version 5.0+ required"
        $result.Valid = $false
        $Script:ValidationResults.Issues += "PowerShell version is too old (5.0+ required)"
        
        if ($FixIssues) {
            $Script:ValidationResults.Recommendations += "Update Windows Management Framework to get PowerShell 5.0+"
        }
    }
    
    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy
    $result.Details.ExecutionPolicy = $executionPolicy.ToString()
    
    if ($executionPolicy -in @("Unrestricted", "RemoteSigned", "Bypass")) {
        Write-Check "Execution Policy" "OK" $executionPolicy
    }
    else {
        Write-Check "Execution Policy" "WARNING" $executionPolicy "May prevent script execution"
        $Script:ValidationResults.Recommendations += "Consider setting execution policy to RemoteSigned: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    }
    
    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $result.Details.RunningAsAdmin = $isAdmin
    
    if ($isAdmin) {
        Write-Check "Administrator Rights" "OK" "Running as Administrator"
    }
    else {
        Write-Check "Administrator Rights" "WARNING" "Not running as Administrator" "Some operations may fail"
        $Script:ValidationResults.Recommendations += "Run PowerShell as Administrator for full functionality"
    }
    
    $Script:ValidationResults.Components["PowerShell"] = $result
    return $result.Valid
}

function Test-NodeJS {
    Write-Info "`nValidating Node.js..."
    
    $result = @{
        Name = "Node.js"
        Valid = $false
        Details = @{}
    }
    
    $node = Get-Command node -ErrorAction SilentlyContinue
    
    if ($node) {
        $result.Details.Installed = $true
        $result.Details.Path = $node.Source
        
        # Get version
        $nodeVersion = & node --version 2>&1
        $result.Details.Version = $nodeVersion
        
        # Parse version
        if ($nodeVersion -match "v(\d+)\.(\d+)\.(\d+)") {
            $majorVersion = [int]$Matches[1]
            $minorVersion = [int]$Matches[2]
            
            # Check version (14.0+)
            if ($majorVersion -ge 14) {
                Write-Check "Node.js" "OK" $nodeVersion.TrimStart('v')
                $result.Valid = $true
                
                # Recommend LTS for older versions
                if ($majorVersion -eq 14 -or $majorVersion -eq 16) {
                    Write-Check "Node.js Version" "WARNING" "" "Consider updating to Node.js 18+ LTS"
                    $Script:ValidationResults.Recommendations += "Update to Node.js 18+ LTS for better performance and security"
                }
            }
            else {
                Write-Check "Node.js" "ERROR" $nodeVersion.TrimStart('v') "Version 14.0+ required"
                $Script:ValidationResults.Issues += "Node.js version is too old (14.0+ required)"
                
                if ($InstallMissing) {
                    $Script:ValidationResults.Recommendations += "Update Node.js from https://nodejs.org/"
                }
            }
        }
        
        # Check npm
        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if ($npm) {
            $npmVersion = & npm --version 2>&1
            $result.Details.NpmVersion = $npmVersion
            Write-Check "npm" "OK" $npmVersion
        }
        else {
            Write-Check "npm" "ERROR" "Not found" "npm is required"
            $result.Valid = $false
            $Script:ValidationResults.Issues += "npm not found in PATH"
        }
    }
    else {
        Write-Check "Node.js" "MISSING" "" "Not installed"
        $result.Details.Installed = $false
        $Script:ValidationResults.Issues += "Node.js is not installed"
        
        if ($InstallMissing) {
            Write-Warning "  Node.js installation required. Download from https://nodejs.org/"
            $Script:ValidationResults.Recommendations += "Install Node.js LTS from https://nodejs.org/"
            
            # Could automate download with:
            # Invoke-WebRequest -Uri "https://nodejs.org/dist/v18.19.0/node-v18.19.0-x64.msi" -OutFile "node-installer.msi"
        }
    }
    
    $Script:ValidationResults.Components["NodeJS"] = $result
    return $result.Valid
}

function Test-ProjectStructure {
    Write-Info "`nValidating Project Structure..."
    
    $result = @{
        Name = "Project Structure"
        Valid = $true
        Details = @{
            MissingDirs = @()
            MissingFiles = @()
        }
    }
    
    # Check if project exists
    if (-not (Test-Path $ProjectPath)) {
        Write-Check "Project Directory" "ERROR" "" "Not found: $ProjectPath"
        $result.Valid = $false
        $Script:ValidationResults.Issues += "Project directory not found"
        
        if ($FixIssues) {
            Write-Info "  Creating project directory..."
            New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
            $Script:ValidationResults.Fixes += "Created project directory"
        }
        
        $Script:ValidationResults.Components["ProjectStructure"] = $result
        return $result.Valid
    }
    
    Write-Check "Project Directory" "OK" $ProjectPath
    
    # Required directories
    $requiredDirs = @("src", "config", "logs", "windows-tools")
    foreach ($dir in $requiredDirs) {
        $dirPath = Join-Path $ProjectPath $dir
        if (-not (Test-Path $dirPath)) {
            $result.Details.MissingDirs += $dir
            $result.Valid = $false
            
            if ($FixIssues) {
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Write-Check "Directory: $dir" "OK" "Created"
                $Script:ValidationResults.Fixes += "Created directory: $dir"
            }
            else {
                Write-Check "Directory: $dir" "MISSING"
            }
        }
        else {
            if ($Detailed) {
                Write-Check "Directory: $dir" "OK"
            }
        }
    }
    
    # Required files
    $requiredFiles = @{
        "package.json" = "Project configuration"
        "src\server.js" = "Main server file"
        "config\servers.json" = "MCP server configuration"
    }
    
    foreach ($file in $requiredFiles.Keys) {
        $filePath = Join-Path $ProjectPath $file
        if (-not (Test-Path $filePath)) {
            $result.Details.MissingFiles += $file
            $result.Valid = $false
            Write-Check "File: $file" "MISSING" "" $requiredFiles[$file]
        }
        else {
            if ($Detailed) {
                Write-Check "File: $file" "OK"
            }
        }
    }
    
    # Check .env file
    $envPath = Join-Path $ProjectPath ".env"
    if (Test-Path $envPath) {
        Write-Check "Environment File" "OK" ".env exists"
        
        # Check for default values
        $envContent = Get-Content $envPath -Raw
        if ($envContent -match "GATEWAY_AUTH_TOKEN=CHANGE_ME") {
            Write-Check "Auth Token" "WARNING" "" "Using default token - security risk!"
            $Script:ValidationResults.Issues += ".env file contains default auth token"
            $Script:ValidationResults.Recommendations += "Generate secure token: [System.Web.Security.Membership]::GeneratePassword(32,8)"
        }
    }
    else {
        Write-Check "Environment File" "WARNING" ".env missing" "Will need configuration"
        $Script:ValidationResults.Recommendations += "Create .env file from .env.example"
    }
    
    # Check node_modules
    $nodeModulesPath = Join-Path $ProjectPath "node_modules"
    if (Test-Path $nodeModulesPath) {
        $moduleCount = (Get-ChildItem $nodeModulesPath -Directory).Count
        Write-Check "Dependencies" "OK" "$moduleCount packages installed"
    }
    else {
        Write-Check "Dependencies" "WARNING" "Not installed" "Run 'npm install'"
        $Script:ValidationResults.Recommendations += "Run 'npm install' to install dependencies"
    }
    
    $Script:ValidationResults.Components["ProjectStructure"] = $result
    return $result.Valid
}

function Test-WindowsService {
    Write-Info "`nValidating Windows Service..."
    
    $result = @{
        Name = "Windows Service"
        Valid = $true
        Details = @{}
    }
    
    # Check NSSM
    $nssmPath = Join-Path $ProjectPath "nssm.exe"
    if (Test-Path $nssmPath) {
        Write-Check "NSSM" "OK" "Service manager available"
        $result.Details.NSSMInstalled = $true
    }
    else {
        Write-Check "NSSM" "WARNING" "Not found" "Required for service management"
        $result.Details.NSSMInstalled = $false
        $Script:ValidationResults.Recommendations += "Download NSSM for service management"
        
        if ($InstallMissing) {
            # Could download NSSM here
            $Script:ValidationResults.Recommendations += "Download NSSM from https://nssm.cc/"
        }
    }
    
    # Check service
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    if ($service) {
        $result.Details.ServiceInstalled = $true
        $result.Details.ServiceStatus = $service.Status.ToString()
        
        Write-Check "Service Installation" "OK" "MCPGateway installed"
        Write-Check "Service Status" $(if ($service.Status -eq "Running") { "OK" } else { "WARNING" }) $service.Status
        
        if ($service.Status -ne "Running") {
            $Script:ValidationResults.Recommendations += "Start service: Start-Service MCPGateway"
        }
    }
    else {
        Write-Check "Service Installation" "WARNING" "Not installed" "Run install-service.ps1"
        $result.Details.ServiceInstalled = $false
        $Script:ValidationResults.Recommendations += "Install service using: .\install-service.ps1"
    }
    
    $Script:ValidationResults.Components["WindowsService"] = $result
    return $result.Valid
}

function Test-Network {
    Write-Info "`nValidating Network Configuration..."
    
    $result = @{
        Name = "Network"
        Valid = $true
        Details = @{}
    }
    
    # Check if port 4242 is available
    $port = 4242
    $tcpListener = $null
    try {
        $tcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
        $tcpListener.Start()
        Write-Check "Port $port" "OK" "Available"
        $result.Details.PortAvailable = $true
    }
    catch {
        # Port is in use
        $listening = netstat -an | Select-String ":$port\s+.*LISTENING"
        if ($listening) {
            # Check if it's our service
            $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq "Running") {
                Write-Check "Port $port" "OK" "In use by MCPGateway"
                $result.Details.PortAvailable = $true
            }
            else {
                Write-Check "Port $port" "ERROR" "In use by another process"
                $result.Valid = $false
                $result.Details.PortAvailable = $false
                $Script:ValidationResults.Issues += "Port $port is in use by another process"
            }
        }
    }
    finally {
        if ($tcpListener) {
            $tcpListener.Stop()
        }
    }
    
    # Check Windows Firewall
    try {
        $firewallRule = Get-NetFirewallRule -DisplayName "*MCP Gateway*" -ErrorAction SilentlyContinue
        if ($firewallRule) {
            Write-Check "Firewall Rule" "OK" "Configured"
            $result.Details.FirewallConfigured = $true
        }
        else {
            Write-Check "Firewall Rule" "WARNING" "Not configured" "May block connections"
            $result.Details.FirewallConfigured = $false
            
            if ($FixIssues) {
                Write-Info "  Creating firewall rule..."
                New-NetFirewallRule -DisplayName "MCP Gateway Inbound" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Private | Out-Null
                $Script:ValidationResults.Fixes += "Created firewall rule for port $port"
            }
            else {
                $Script:ValidationResults.Recommendations += "Create firewall rule: New-NetFirewallRule -DisplayName 'MCP Gateway' -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow"
            }
        }
    }
    catch {
        Write-Check "Firewall" "WARNING" "Could not check" "Requires admin rights"
    }
    
    # Check internet connectivity
    try {
        $ping = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet
        if ($ping) {
            Write-Check "Internet Connectivity" "OK"
            $result.Details.InternetConnected = $true
        }
        else {
            Write-Check "Internet Connectivity" "WARNING" "No connection"
            $result.Details.InternetConnected = $false
        }
    }
    catch {
        Write-Check "Internet Connectivity" "WARNING" "Could not test"
    }
    
    $Script:ValidationResults.Components["Network"] = $result
    return $result.Valid
}

function Test-OptionalComponents {
    Write-Info "`nValidating Optional Components..."
    
    # Git
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitVersion = & git --version 2>&1
        Write-Check "Git" "OK" $gitVersion.Replace("git version ", "")
    }
    else {
        Write-Check "Git" "INFO" "Not installed" "Optional - for version control"
    }
    
    # Cloudflared
    $cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cloudflared) {
        Write-Check "Cloudflared" "OK" "Installed"
        
        # Check tunnel config
        $cfConfig = Join-Path $env:USERPROFILE ".cloudflared\config.yml"
        if (Test-Path $cfConfig) {
            $configContent = Get-Content $cfConfig -Raw
            if ($configContent -match "gateway\.pluginpapi\.dev") {
                Write-Check "Tunnel Config" "OK" "gateway.pluginpapi.dev configured"
            }
            else {
                Write-Check "Tunnel Config" "WARNING" "gateway.pluginpapi.dev not configured"
                $Script:ValidationResults.Recommendations += "Add gateway.pluginpapi.dev to Cloudflare tunnel config"
            }
        }
    }
    else {
        Write-Check "Cloudflared" "INFO" "Not installed" "Required for external access"
        $Script:ValidationResults.Recommendations += "Install cloudflared for external access via Cloudflare tunnel"
    }
    
    # 7-Zip (for encrypted backups)
    $sevenZip = "C:\Program Files\7-Zip\7z.exe"
    if (Test-Path $sevenZip) {
        Write-Check "7-Zip" "OK" "Installed" "Enables encrypted backups"
    }
    else {
        if ($Detailed) {
            Write-Check "7-Zip" "INFO" "Not installed" "Optional - for encrypted backups"
        }
    }
}

function Create-ValidationReport {
    $report = @{
        ValidationResults = $Script:ValidationResults
        Summary = @{
            Valid = $Script:ValidationResults.Valid
            ComponentCount = $Script:ValidationResults.Components.Count
            IssueCount = $Script:ValidationResults.Issues.Count
            FixCount = $Script:ValidationResults.Fixes.Count
            RecommendationCount = $Script:ValidationResults.Recommendations.Count
        }
        Environment = @{
            MachineName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            ProjectPath = $ProjectPath
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    
    if ($ReportPath) {
        $reportDir = Split-Path $ReportPath -Parent
        if ($reportDir -and -not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
        
        $report | ConvertTo-Json -Depth 10 | Set-Content $ReportPath -Encoding UTF8
        Write-Info "`nValidation report saved to: $ReportPath"
    }
    
    return $report
}

# Main validation process
try {
    Write-Info "Validating environment for MCP Gateway..."
    Write-Info "Project Path: $ProjectPath"
    
    # Run validators
    $osValid = Test-OperatingSystem
    $psValid = Test-PowerShell
    $nodeValid = Test-NodeJS
    $projectValid = Test-ProjectStructure
    $serviceValid = Test-WindowsService
    $networkValid = Test-Network
    Test-OptionalComponents
    
    # Determine overall validity
    $Script:ValidationResults.Valid = $osValid -and $psValid -and $nodeValid -and $projectValid -and $networkValid
    
    # Create report
    $report = Create-ValidationReport
    
    # Display summary
    Write-Info "`n" + "="*60
    Write-Info "Validation Summary"
    Write-Info "="*60
    
    if ($Script:ValidationResults.Valid) {
        Write-Success "`nEnvironment is VALID ✓"
        Write-Success "All critical components are properly configured."
    }
    else {
        Write-Error "`nEnvironment is INVALID ✗"
        Write-Error "Critical issues must be resolved before deployment."
    }
    
    # Show issues
    if ($Script:ValidationResults.Issues.Count -gt 0) {
        Write-Warning "`nIssues Found ($($Script:ValidationResults.Issues.Count)):"
        foreach ($issue in $Script:ValidationResults.Issues) {
            Write-Host "  ✗ $issue" -ForegroundColor Red
        }
    }
    
    # Show fixes applied
    if ($Script:ValidationResults.Fixes.Count -gt 0) {
        Write-Success "`nFixes Applied ($($Script:ValidationResults.Fixes.Count)):"
        foreach ($fix in $Script:ValidationResults.Fixes) {
            Write-Host "  ✓ $fix" -ForegroundColor Green
        }
    }
    
    # Show recommendations
    if ($Script:ValidationResults.Recommendations.Count -gt 0) {
        Write-Info "`nRecommendations ($($Script:ValidationResults.Recommendations.Count)):"
        foreach ($rec in $Script:ValidationResults.Recommendations | Select-Object -Unique) {
            Write-Host "  • $rec" -ForegroundColor Yellow
        }
    }
    
    # Next steps
    if (-not $Script:ValidationResults.Valid) {
        Write-Info "`nNext Steps:"
        Write-Host "1. Address the critical issues listed above"
        Write-Host "2. Run this script again with -FixIssues to auto-fix some problems"
        Write-Host "3. Use -InstallMissing to get download links for missing components"
        
        if (-not $CheckOnly) {
            Write-Host ""
            Write-Warning "Deployment cannot proceed until environment is valid."
        }
    }
    else {
        Write-Info "`nNext Steps:"
        Write-Host "1. Review and address any recommendations"
        Write-Host "2. Run deployment script: .\deploy-to-windows.ps1"
        Write-Host "3. Configure .env file with proper tokens"
    }
    
    # Exit code
    if ($Script:ValidationResults.Valid) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-Error "Validation failed: $_"
    exit 2
}