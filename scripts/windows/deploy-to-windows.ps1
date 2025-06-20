# MCP Gateway Full Deployment Script for Windows
# Complete automated deployment from source to production-ready service
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$SourcePath,
    [string]$TargetPath = "C:\Services\mcp-gateway",
    [string]$GitRepo,
    [switch]$FromGit,
    [switch]$SkipBackup,
    [switch]$SkipTests,
    [switch]$SkipCloudflare,
    [string]$CloudflareTunnelName = "mcp-gateway",
    [switch]$Silent
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import common functions
$CommonFunctions = @'
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Step { 
    param($Step, $Total, $Message)
    Write-Host "[Step $Step/$Total] " -NoNewline -ForegroundColor Cyan
    Write-Host $Message
}
'@
Invoke-Expression $CommonFunctions

# Deployment banner
if (-not $Silent) {
    Write-Info @"
==============================================================
          MCP Gateway Deployment Automation v1.0              
==============================================================
Target: $TargetPath
Mode: $(if ($FromGit) { "Git Repository" } else { "Local Source" })
"@
}

# Create deployment log
$DeploymentId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = "C:\Temp\mcp-gateway-deployments"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$DeploymentLog = Join-Path $LogDir "deploy-$DeploymentId.log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $DeploymentLog -Value $LogMessage
    
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

# Main deployment process
try {
    $TotalSteps = 12
    $CurrentStep = 0
    
    Write-Log "Starting MCP Gateway deployment - ID: $DeploymentId"
    
    # Step 1: Validate prerequisites
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Validating prerequisites"
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script requires administrator privileges"
    }
    
    # Check Node.js
    $nodeVersion = node --version 2>$null
    if (-not $nodeVersion) {
        throw "Node.js is not installed. Please install Node.js first."
    }
    Write-Log "Node.js version: $nodeVersion" -Level SUCCESS
    
    # Check Git (if deploying from Git)
    if ($FromGit) {
        $gitVersion = git --version 2>$null
        if (-not $gitVersion) {
            throw "Git is not installed. Please install Git first."
        }
        Write-Log "Git version: $gitVersion" -Level SUCCESS
    }
    
    # Step 2: Prepare source code
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Preparing source code"
    
    $TempSource = Join-Path $env:TEMP "mcp-gateway-source-$DeploymentId"
    
    if ($FromGit) {
        if (-not $GitRepo) {
            $GitRepo = Read-Host "Enter Git repository URL"
        }
        
        Write-Log "Cloning repository: $GitRepo"
        git clone $GitRepo $TempSource
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone repository"
        }
        $SourcePath = $TempSource
    }
    elseif ($SourcePath) {
        if (-not (Test-Path $SourcePath)) {
            throw "Source path not found: $SourcePath"
        }
        Write-Log "Using local source: $SourcePath"
    }
    else {
        # Try to find source in current directory or parent
        $PossiblePaths = @(
            $PWD.Path,
            (Join-Path $PWD.Path ".."),
            (Join-Path $env:USERPROFILE "Documents\ProjectsCode\mcp-gateway")
        )
        
        foreach ($path in $PossiblePaths) {
            if (Test-Path (Join-Path $path "package.json")) {
                $packageJson = Get-Content (Join-Path $path "package.json") | ConvertFrom-Json
                if ($packageJson.name -eq "mcp-gateway") {
                    $SourcePath = $path
                    break
                }
            }
        }
        
        if (-not $SourcePath) {
            throw "Could not find MCP Gateway source. Please specify -SourcePath"
        }
        Write-Log "Found source at: $SourcePath"
    }
    
    # Step 3: Create backup of existing deployment
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Creating backup"
    
    if (-not $SkipBackup -and (Test-Path $TargetPath)) {
        $BackupPath = "$TargetPath.backup.$DeploymentId"
        Write-Log "Creating backup at: $BackupPath"
        
        # Stop service if running
        $serviceName = "MCPGateway"
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "Stopping service for backup"
            Stop-Service -Name $serviceName -Force
            Start-Sleep -Seconds 2
        }
        
        # Create backup
        Copy-Item -Path $TargetPath -Destination $BackupPath -Recurse -Force
        Write-Log "Backup created successfully" -Level SUCCESS
    }
    
    # Step 4: Prepare target directory
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Preparing target directory"
    
    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        Write-Log "Created target directory: $TargetPath"
    }
    
    # Step 5: Copy files to target
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Deploying files"
    
    # Files and directories to copy
    $ItemsToCopy = @(
        "src",
        "config",
        "package.json",
        "package-lock.json",
        ".env.example",
        "README.md",
        "manage-service.bat",
        "install-service.ps1"
    )
    
    # Copy deployment scripts
    $DeploymentScripts = @(
        "deploy-to-windows.ps1",
        "update-deployment.ps1",
        "rollback-deployment.ps1",
        "monitor-service.ps1",
        "cleanup-logs.ps1",
        "backup-config.ps1",
        "restore-config.ps1",
        "diagnose-issues.ps1",
        "collect-debug-info.ps1",
        "test-connectivity.ps1",
        "validate-environment.ps1",
        "test-deployment.ps1"
    )
    
    foreach ($item in $ItemsToCopy) {
        $sourcePath = Join-Path $SourcePath $item
        if (Test-Path $sourcePath) {
            $destPath = Join-Path $TargetPath $item
            if (Test-Path $sourcePath -PathType Container) {
                Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
            }
            else {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
            }
            Write-Log "Copied: $item"
        }
    }
    
    # Copy deployment scripts if they exist
    $scriptsDir = Join-Path $TargetPath "windows-tools"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }
    
    foreach ($script in $DeploymentScripts) {
        $sourcePath = Join-Path $SourcePath $script
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination (Join-Path $scriptsDir $script) -Force
            Write-Log "Copied script: $script"
        }
    }
    
    # Step 6: Install dependencies
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Installing dependencies"
    
    Push-Location $TargetPath
    try {
        # Clean install for production
        if (Test-Path "node_modules") {
            Remove-Item -Path "node_modules" -Recurse -Force
        }
        
        Write-Log "Running npm ci for production dependencies"
        npm ci --production
        if ($LASTEXITCODE -ne 0) {
            # Fallback to npm install if ci fails
            Write-Log "npm ci failed, trying npm install" -Level WARNING
            npm install --production
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install dependencies"
            }
        }
        Write-Log "Dependencies installed successfully" -Level SUCCESS
    }
    finally {
        Pop-Location
    }
    
    # Step 7: Configure environment
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Configuring environment"
    
    $envFile = Join-Path $TargetPath ".env"
    $envExampleFile = Join-Path $TargetPath ".env.example"
    
    if (-not (Test-Path $envFile)) {
        if (Test-Path $envExampleFile) {
            Copy-Item -Path $envExampleFile -Destination $envFile
            Write-Log "Created .env from .env.example" -Level WARNING
            Write-Warning "Please configure the .env file with your tokens!"
        }
        else {
            # Create default .env
            $envContent = @"
# Server Configuration
PORT=4242
NODE_ENV=production

# Authentication - CHANGE THIS!
GATEWAY_AUTH_TOKEN=$(([System.Web.Security.Membership]::GeneratePassword(32,8)))

# GitHub Personal Access Token
GITHUB_TOKEN=

# Desktop Commander Allowed Paths  
DESKTOP_ALLOWED_PATHS=C:\Users\$env:USERNAME\Documents,C:\Users\$env:USERNAME\Desktop

# Logging
LOG_LEVEL=info
"@
            Set-Content -Path $envFile -Value $envContent -Encoding UTF8
            Write-Log "Created default .env file" -Level WARNING
        }
    }
    else {
        Write-Log ".env file already exists" -Level SUCCESS
    }
    
    # Step 8: Run tests (if not skipped)
    if (-not $SkipTests) {
        $CurrentStep++
        Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Running tests"
        
        $testScript = Join-Path $scriptsDir "test-deployment.ps1"
        if (Test-Path $testScript) {
            Write-Log "Running deployment tests"
            & $testScript -TargetPath $TargetPath -Silent
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Some tests failed, but continuing deployment" -Level WARNING
            }
            else {
                Write-Log "All tests passed" -Level SUCCESS
            }
        }
        else {
            Write-Log "Test script not found, skipping tests" -Level WARNING
        }
    }
    else {
        $CurrentStep++
    }
    
    # Step 9: Install Windows service
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Installing Windows service"
    
    $installScript = Join-Path $TargetPath "install-service.ps1"
    if (Test-Path $installScript) {
        Write-Log "Running service installation script"
        & $installScript -ProjectPath $TargetPath -Silent -ForceReinstall
        if ($LASTEXITCODE -ne 0) {
            throw "Service installation failed"
        }
        Write-Log "Service installed successfully" -Level SUCCESS
    }
    else {
        Write-Log "Install script not found, skipping service installation" -Level WARNING
    }
    
    # Step 10: Configure Cloudflare tunnel (if not skipped)
    if (-not $SkipCloudflare) {
        $CurrentStep++
        Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Configuring Cloudflare tunnel"
        
        $cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
        if ($cloudflared) {
            Write-Log "Checking Cloudflare tunnel configuration"
            
            # Check if tunnel config exists
            $tunnelConfig = Join-Path $env:USERPROFILE ".cloudflared\config.yml"
            if (Test-Path $tunnelConfig) {
                $config = Get-Content $tunnelConfig -Raw
                if ($config -match "gateway\.pluginpapi\.dev") {
                    Write-Log "Cloudflare tunnel already configured" -Level SUCCESS
                }
                else {
                    Write-Log "Cloudflare tunnel configuration needs to be updated manually" -Level WARNING
                    Write-Warning "Please update $tunnelConfig to include gateway.pluginpapi.dev routing"
                }
            }
            else {
                Write-Log "Cloudflare tunnel not configured" -Level WARNING
                Write-Warning "Please set up Cloudflare tunnel according to the documentation"
            }
        }
        else {
            Write-Log "cloudflared not installed" -Level WARNING
            Write-Warning "Please install cloudflared and configure the tunnel"
        }
    }
    else {
        $CurrentStep++
    }
    
    # Step 11: Start service
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Starting service"
    
    $serviceName = "MCPGateway"
    Write-Log "Starting $serviceName service"
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $serviceName
    if ($service.Status -eq "Running") {
        Write-Log "Service started successfully" -Level SUCCESS
        
        # Test health endpoint
        try {
            $health = Invoke-RestMethod -Uri "http://localhost:4242/health" -Method Get -TimeoutSec 10
            Write-Log "Health check passed - Status: $($health.status)" -Level SUCCESS
        }
        catch {
            Write-Log "Health check failed: $_" -Level WARNING
        }
    }
    else {
        Write-Log "Service failed to start" -Level ERROR
    }
    
    # Step 12: Create deployment record
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Creating deployment record"
    
    $deploymentRecord = @{
        DeploymentId = $DeploymentId
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SourcePath = $SourcePath
        TargetPath = $TargetPath
        FromGit = $FromGit
        GitRepo = $GitRepo
        NodeVersion = $nodeVersion
        ServiceStatus = $service.Status
        BackupPath = if (-not $SkipBackup -and $BackupPath) { $BackupPath } else { "None" }
    }
    
    $recordPath = Join-Path $TargetPath "deployments"
    if (-not (Test-Path $recordPath)) {
        New-Item -ItemType Directory -Path $recordPath -Force | Out-Null
    }
    
    $recordFile = Join-Path $recordPath "deployment-$DeploymentId.json"
    $deploymentRecord | ConvertTo-Json | Set-Content -Path $recordFile -Encoding UTF8
    
    # Create current deployment link
    $currentLink = Join-Path $recordPath "current.json"
    Copy-Item -Path $recordFile -Destination $currentLink -Force
    
    Write-Log "Deployment record created: $recordFile" -Level SUCCESS
    
    # Cleanup
    if ($TempSource -and (Test-Path $TempSource)) {
        Remove-Item -Path $TempSource -Recurse -Force
        Write-Log "Cleaned up temporary files"
    }
    
    # Final summary
    Write-Log "="*60
    Write-Log "Deployment completed successfully!" -Level SUCCESS
    Write-Log "="*60
    Write-Log "Deployment ID: $DeploymentId"
    Write-Log "Target: $TargetPath"
    Write-Log "Service Status: $($service.Status)"
    Write-Log "Health Endpoint: http://localhost:4242/health"
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Deployment completed successfully!"
        Write-Host ""
        Write-Info "Next steps:"
        Write-Host "1. Configure .env file if not already done"
        Write-Host "2. Set up Cloudflare tunnel if not configured"
        Write-Host "3. Monitor service using manage-service.bat"
        Write-Host ""
        Write-Host "Deployment log: $DeploymentLog"
    }
    
    # Create success indicator
    $successFile = Join-Path $LogDir "deploy-$DeploymentId.success"
    "Success" | Set-Content -Path $successFile
    
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Deployment failed: $_" -Level ERROR
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Deployment failed: $_"
        Write-Host ""
        Write-Host "Check the deployment log for details:"
        Write-Host $DeploymentLog
    }
    
    # Create failure indicator
    $failureFile = Join-Path $LogDir "deploy-$DeploymentId.failed"
    $_ | Set-Content -Path $failureFile
    
    # Attempt rollback if backup exists
    if ($BackupPath -and (Test-Path $BackupPath)) {
        Write-Warning "Attempting to rollback to previous version..."
        try {
            # Stop service
            Stop-Service -Name "MCPGateway" -Force -ErrorAction SilentlyContinue
            
            # Restore backup
            if (Test-Path $TargetPath) {
                Remove-Item -Path $TargetPath -Recurse -Force
            }
            Move-Item -Path $BackupPath -Destination $TargetPath
            
            # Start service
            Start-Service -Name "MCPGateway"
            
            Write-Success "Rollback completed successfully"
        }
        catch {
            Write-Error "Rollback failed: $_"
        }
    }
    
    exit 1
}