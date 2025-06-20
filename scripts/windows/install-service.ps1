# MCP Gateway Service Installation Script
# Automated installation with all dependencies and configuration
# Author: MCP Gateway Team
# Version: 1.0.0
# Requires: PowerShell 5.0 or higher, Administrator privileges

#Requires -RunAsAdministrator
#Requires -Version 5.0

param(
    [string]$ServiceName = "MCPGateway",
    [string]$ServiceDisplayName = "MCP Gateway Service",
    [string]$ServiceDescription = "MCP Gateway - Unified gateway for Model Context Protocol servers",
    [string]$ProjectPath = $PSScriptRoot,
    [string]$NodePath = "C:\Program Files\nodejs\node.exe",
    [string]$NSSMVersion = "2.24",
    [switch]$Silent,
    [switch]$StartAfterInstall,
    [switch]$SkipDependencyCheck,
    [switch]$SkipFirewall,
    [switch]$ForceReinstall
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Color functions
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }

# Banner
if (-not $Silent) {
    Write-Info @"
==============================================================
             MCP Gateway Service Installer v1.0              
==============================================================
"@
}

# Logging setup
$LogDir = Join-Path $ProjectPath "logs"
$InstallLog = Join-Path $LogDir "install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $InstallLog -Value $LogMessage
    
    if (-not $Silent) {
        switch ($Level) {
            "SUCCESS" { Write-Success $Message }
            "INFO" { Write-Info $Message }
            "WARNING" { Write-Warning $Message }
            "ERROR" { Write-Error $Message }
            default { Write-Host $Message }
        }
    }
}

# Function to test administrator privileges
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to download file with progress
function Download-FileWithProgress {
    param(
        [string]$Url,
        [string]$Destination
    )
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $Destination)
        return $true
    }
    catch {
        Write-Log "Failed to download from $Url : $_" -Level ERROR
        return $false
    }
}

# Main installation process
try {
    Write-Log "Starting MCP Gateway installation process"
    Write-Log "Project Path: $ProjectPath"
    Write-Log "Node Path: $NodePath"
    
    # Step 1: Verify administrator privileges
    if (-not (Test-Administrator)) {
        throw "This script requires administrator privileges. Please run as Administrator."
    }
    Write-Log "Administrator privileges verified" -Level SUCCESS
    
    # Step 2: Check Node.js installation
    if (-not $SkipDependencyCheck) {
        Write-Log "Checking Node.js installation..."
        
        if (-not (Test-Path $NodePath)) {
            # Try to find Node.js in PATH
            $nodeInPath = Get-Command node -ErrorAction SilentlyContinue
            if ($nodeInPath) {
                $NodePath = $nodeInPath.Source
                Write-Log "Found Node.js in PATH: $NodePath" -Level SUCCESS
            }
            else {
                throw "Node.js not found. Please install Node.js from https://nodejs.org"
            }
        }
        
        # Check Node.js version
        $nodeVersion = & $NodePath --version
        Write-Log "Node.js version: $nodeVersion" -Level SUCCESS
        
        # Check npm
        $npmPath = Join-Path (Split-Path $NodePath -Parent) "npm.cmd"
        if (-not (Test-Path $npmPath)) {
            $npmPath = Get-Command npm -ErrorAction SilentlyContinue
            if (-not $npmPath) {
                throw "npm not found. Please ensure Node.js is properly installed."
            }
        }
        Write-Log "npm found" -Level SUCCESS
    }
    
    # Step 3: Download and install NSSM
    Write-Log "Checking NSSM installation..."
    
    $NSSMPath = Join-Path $ProjectPath "nssm.exe"
    
    if (-not (Test-Path $NSSMPath)) {
        Write-Log "NSSM not found. Downloading..."
        
        $NSSMUrl = "https://nssm.cc/release/nssm-$NSSMVersion.zip"
        $TempZip = Join-Path $env:TEMP "nssm.zip"
        $TempDir = Join-Path $env:TEMP "nssm_extract"
        
        # Download NSSM
        if (Download-FileWithProgress -Url $NSSMUrl -Destination $TempZip) {
            Write-Log "NSSM downloaded successfully"
            
            # Extract NSSM
            if (Test-Path $TempDir) {
                Remove-Item $TempDir -Recurse -Force
            }
            
            Expand-Archive -Path $TempZip -DestinationPath $TempDir -Force
            
            # Find appropriate version (64-bit or 32-bit)
            $NSSM64 = Join-Path $TempDir "nssm-$NSSMVersion\win64\nssm.exe"
            $NSSM32 = Join-Path $TempDir "nssm-$NSSMVersion\win32\nssm.exe"
            
            if (Test-Path $NSSM64) {
                Copy-Item $NSSM64 -Destination $NSSMPath -Force
                Write-Log "Installed 64-bit NSSM" -Level SUCCESS
            }
            elseif (Test-Path $NSSM32) {
                Copy-Item $NSSM32 -Destination $NSSMPath -Force
                Write-Log "Installed 32-bit NSSM" -Level SUCCESS
            }
            else {
                throw "Could not find NSSM executable in downloaded archive"
            }
            
            # Cleanup
            Remove-Item $TempZip -Force -ErrorAction SilentlyContinue
            Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            throw "Failed to download NSSM"
        }
    }
    else {
        Write-Log "NSSM already installed" -Level SUCCESS
    }
    
    # Step 4: Check if service already exists
    $existingService = & $NSSMPath status $ServiceName 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($ForceReinstall) {
            Write-Log "Service exists. Force reinstall requested. Removing existing service..." -Level WARNING
            & $NSSMPath stop $ServiceName 2>&1 | Out-Null
            & $NSSMPath remove $ServiceName confirm 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        }
        else {
            throw "Service '$ServiceName' already exists. Use -ForceReinstall to replace it."
        }
    }
    
    # Step 5: Validate project structure
    Write-Log "Validating project structure..."
    
    $RequiredFiles = @(
        "src\server.js",
        "package.json",
        "config\servers.json"
    )
    
    foreach ($file in $RequiredFiles) {
        $filePath = Join-Path $ProjectPath $file
        if (-not (Test-Path $filePath)) {
            throw "Required file not found: $file"
        }
    }
    Write-Log "Project structure validated" -Level SUCCESS
    
    # Step 6: Check/Create .env file
    $EnvFile = Join-Path $ProjectPath ".env"
    if (-not (Test-Path $EnvFile)) {
        Write-Log ".env file not found. Creating from template..." -Level WARNING
        
        $EnvExample = Join-Path $ProjectPath ".env.example"
        if (Test-Path $EnvExample) {
            Copy-Item $EnvExample -Destination $EnvFile
            Write-Log "Created .env from .env.example" -Level SUCCESS
            Write-Warning "Please edit .env file and configure your tokens!"
        }
        else {
            # Create basic .env file
            $envContent = @"
# Server Configuration
PORT=4242
NODE_ENV=production

# Authentication - CHANGE THIS!
GATEWAY_AUTH_TOKEN=CHANGE_ME_TO_RANDOM_TOKEN_$(Get-Random -Maximum 999999)

# GitHub Personal Access Token
# Get one from: https://github.com/settings/tokens
GITHUB_TOKEN=your_github_token_here

# Desktop Commander Allowed Paths
DESKTOP_ALLOWED_PATHS=C:\Users\$env:USERNAME\Documents,C:\Users\$env:USERNAME\Desktop

# Logging
LOG_LEVEL=info
"@
            Set-Content -Path $EnvFile -Value $envContent
            Write-Log "Created default .env file" -Level SUCCESS
            Write-Warning "IMPORTANT: Edit .env file and configure your tokens!"
        }
    }
    
    # Step 7: Install npm dependencies
    if (-not $SkipDependencyCheck) {
        Write-Log "Installing npm dependencies..."
        
        $nodeModules = Join-Path $ProjectPath "node_modules"
        if (-not (Test-Path $nodeModules)) {
            Push-Location $ProjectPath
            try {
                & npm install
                if ($LASTEXITCODE -ne 0) {
                    throw "npm install failed"
                }
                Write-Log "npm dependencies installed" -Level SUCCESS
            }
            finally {
                Pop-Location
            }
        }
        else {
            Write-Log "npm dependencies already installed" -Level SUCCESS
        }
    }
    
    # Step 8: Install the service
    Write-Log "Installing Windows service..."
    
    $ScriptPath = Join-Path $ProjectPath "src\server.js"
    
    # Install service
    & $NSSMPath install $ServiceName $NodePath $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install service"
    }
    
    # Configure service
    & $NSSMPath set $ServiceName DisplayName $ServiceDisplayName | Out-Null
    & $NSSMPath set $ServiceName Description $ServiceDescription | Out-Null
    & $NSSMPath set $ServiceName AppDirectory $ProjectPath | Out-Null
    & $NSSMPath set $ServiceName AppEnvironmentExtra "NODE_ENV=production" | Out-Null
    
    # Configure logging
    $LogPath = Join-Path $LogDir "service.log"
    $ErrorLogPath = Join-Path $LogDir "service-error.log"
    
    & $NSSMPath set $ServiceName AppStdout $LogPath | Out-Null
    & $NSSMPath set $ServiceName AppStderr $ErrorLogPath | Out-Null
    & $NSSMPath set $ServiceName AppRotateFiles 1 | Out-Null
    & $NSSMPath set $ServiceName AppRotateBytes 10485760 | Out-Null
    & $NSSMPath set $ServiceName AppRotateOnline 1 | Out-Null
    
    # Set startup type to automatic
    & $NSSMPath set $ServiceName Start SERVICE_AUTO_START | Out-Null
    
    # Configure recovery options
    & $NSSMPath set $ServiceName AppRestartDelay 5000 | Out-Null
    & $NSSMPath set $ServiceName AppThrottle 30000 | Out-Null
    
    Write-Log "Windows service installed successfully" -Level SUCCESS
    
    # Step 9: Configure Windows Firewall
    if (-not $SkipFirewall) {
        Write-Log "Configuring Windows Firewall..."
        
        $FirewallRuleName = "MCP Gateway Inbound"
        
        # Remove existing rule if present
        Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
        
        # Add new firewall rule
        New-NetFirewallRule `
            -DisplayName $FirewallRuleName `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 4242 `
            -Action Allow `
            -Profile Private `
            -Description "Allow inbound traffic for MCP Gateway service" | Out-Null
            
        Write-Log "Firewall rule created" -Level SUCCESS
    }
    
    # Step 10: Create scheduled task for auto-start
    Write-Log "Creating scheduled task for service monitoring..."
    
    $TaskName = "MCP Gateway Monitor"
    $TaskDescription = "Monitors and ensures MCP Gateway service is running"
    
    # Create monitor script
    $MonitorScript = @'
$ServiceName = "MCPGateway"
$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($Service -and $Service.Status -ne "Running") {
    Start-Service -Name $ServiceName
    Add-EventLog -LogName Application -Source "MCP Gateway" -EntryType Information -EventId 1000 -Message "MCP Gateway service was restarted by monitor task"
}
'@
    
    $MonitorScriptPath = Join-Path $ProjectPath "monitor-service.ps1"
    Set-Content -Path $MonitorScriptPath -Value $MonitorScript
    
    # Create scheduled task
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$MonitorScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description $TaskDescription `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null
        
    Write-Log "Scheduled task created" -Level SUCCESS
    
    # Step 11: Create desktop shortcut
    Write-Log "Creating desktop shortcut..."
    
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $DesktopPath "MCP Gateway Manager.lnk"
    
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = "cmd.exe"
    $Shortcut.Arguments = "/k cd /d `"$ProjectPath`" && manage-service.bat"
    $Shortcut.WorkingDirectory = $ProjectPath
    $Shortcut.IconLocation = "shell32.dll,13"
    $Shortcut.Description = "MCP Gateway Service Manager"
    $Shortcut.Save()
    
    Write-Log "Desktop shortcut created" -Level SUCCESS
    
    # Step 12: Perform post-installation verification
    Write-Log "Performing post-installation verification..."
    
    # Verify service installation
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $Service) {
        throw "Service verification failed - service not found"
    }
    Write-Log "Service installation verified" -Level SUCCESS
    
    # Create validation report
    $ValidationReport = @"
MCP Gateway Installation Summary
================================
Service Name: $ServiceName
Status: $($Service.Status)
Startup Type: $($Service.StartType)
Project Path: $ProjectPath
Node.js Path: $NodePath
Log Directory: $LogDir

Configuration Files:
- .env: $(if (Test-Path $EnvFile) { "✓ Present" } else { "✗ Missing" })
- servers.json: $(if (Test-Path (Join-Path $ProjectPath "config\servers.json")) { "✓ Present" } else { "✗ Missing" })

Next Steps:
1. Edit the .env file to configure your tokens
2. Start the service using the desktop shortcut or manage-service.bat
3. Set up Cloudflare tunnel to expose the service
"@
    
    $ReportPath = Join-Path $ProjectPath "installation-report.txt"
    Set-Content -Path $ReportPath -Value $ValidationReport
    
    Write-Log "Installation report created: $ReportPath" -Level SUCCESS
    
    # Step 13: Start service if requested
    if ($StartAfterInstall) {
        Write-Log "Starting service..."
        Start-Service -Name $ServiceName
        Start-Sleep -Seconds 3
        
        $Service = Get-Service -Name $ServiceName
        if ($Service.Status -eq "Running") {
            Write-Log "Service started successfully" -Level SUCCESS
            
            # Test health endpoint
            try {
                $healthCheck = Invoke-WebRequest -Uri "http://localhost:4242/health" -UseBasicParsing -TimeoutSec 5
                if ($healthCheck.StatusCode -eq 200) {
                    Write-Log "Health check passed" -Level SUCCESS
                }
            }
            catch {
                Write-Log "Health check failed (service may still be starting)" -Level WARNING
            }
        }
        else {
            Write-Log "Service failed to start. Check logs for details." -Level ERROR
        }
    }
    
    # Final success message
    Write-Log "="*60
    Write-Log "MCP Gateway installation completed successfully!" -Level SUCCESS
    Write-Log "="*60
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Installation completed successfully!"
        Write-Host ""
        Write-Info "Next steps:"
        Write-Host "1. Edit the .env file to configure your tokens"
        Write-Host "2. Use 'manage-service.bat' or the desktop shortcut to manage the service"
        Write-Host "3. Set up Cloudflare tunnel for external access"
        Write-Host ""
        Write-Host "Installation log: $InstallLog"
        Write-Host "Installation report: $ReportPath"
    }
    
    # Open installation report
    if (-not $Silent) {
        $openReport = Read-Host "Would you like to open the installation report? (Y/N)"
        if ($openReport -eq "Y") {
            notepad $ReportPath
        }
    }
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Installation failed: $_" -Level ERROR
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Installation failed: $_"
        Write-Host ""
        Write-Host "Please check the installation log for details:"
        Write-Host $InstallLog
    }
    
    exit 1
}

# Create EventLog source if it doesn't exist
if (-not [System.Diagnostics.EventLog]::SourceExists("MCP Gateway")) {
    New-EventLog -LogName Application -Source "MCP Gateway" -ErrorAction SilentlyContinue
}

# Log successful installation to Event Log
Write-EventLog -LogName Application -Source "MCP Gateway" -EntryType Information -EventId 1 -Message "MCP Gateway service installed successfully"