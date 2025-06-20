# MCP Gateway Rollback Deployment Script
# Emergency rollback to previous deployment version
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$TargetPath = "C:\Services\mcp-gateway",
    [string]$BackupPath,
    [string]$BackupId,
    [switch]$ListBackups,
    [switch]$Force,
    [switch]$KeepCurrentAsBackup,
    [switch]$Silent,
    [int]$KeepBackups = 10
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

# Rollback banner
if (-not $Silent -and -not $ListBackups) {
    Write-Warning @"
==============================================================
        MCP Gateway Emergency Rollback v1.0              
==============================================================
WARNING: This will restore a previous version of the deployment
Target: $TargetPath
"@
}

# Create rollback log
$RollbackId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = "C:\Temp\mcp-gateway-deployments"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$RollbackLog = Join-Path $LogDir "rollback-$RollbackId.log"

function Write-Log {
    param($Message, $Level = "INFO")
    
    if ($ListBackups) { return }
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $RollbackLog -Value $LogMessage
    
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

function Get-AvailableBackups {
    param([string]$Path)
    
    $backups = @()
    
    # Check deployment backups
    $deploymentBackups = Join-Path $Path "backups"
    if (Test-Path $deploymentBackups) {
        $dirs = Get-ChildItem -Path $deploymentBackups -Directory | Sort-Object CreationTime -Descending
        foreach ($dir in $dirs) {
            $info = @{
                Type = "Deployment"
                Path = $dir.FullName
                Name = $dir.Name
                Created = $dir.CreationTime
                Size = (Get-ChildItem $dir.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
            }
            
            # Check if it's a valid backup
            if ((Test-Path (Join-Path $dir.FullName "package.json")) -and 
                (Test-Path (Join-Path $dir.FullName "src"))) {
                $backups += $info
            }
        }
    }
    
    # Check system backups (created by deployment/update scripts)
    $systemBackups = Get-ChildItem -Path (Split-Path $Path -Parent) -Directory -Filter "$((Split-Path $Path -Leaf)).backup.*" -ErrorAction SilentlyContinue
    foreach ($dir in $systemBackups | Sort-Object CreationTime -Descending) {
        $info = @{
            Type = "System"
            Path = $dir.FullName
            Name = $dir.Name
            Created = $dir.CreationTime
            Size = (Get-ChildItem $dir.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
        }
        
        if ((Test-Path (Join-Path $dir.FullName "package.json")) -and 
            (Test-Path (Join-Path $dir.FullName "src"))) {
            $backups += $info
        }
    }
    
    return $backups
}

function Test-BackupValidity {
    param([string]$BackupPath)
    
    $required = @(
        "src\server.js",
        "package.json",
        "config"
    )
    
    foreach ($item in $required) {
        $itemPath = Join-Path $BackupPath $item
        if (-not (Test-Path $itemPath)) {
            return $false
        }
    }
    
    # Test package.json validity
    try {
        $package = Get-Content (Join-Path $BackupPath "package.json") | ConvertFrom-Json
        if (-not $package.name -or $package.name -ne "mcp-gateway") {
            return $false
        }
    }
    catch {
        return $false
    }
    
    return $true
}

function Get-DeploymentInfo {
    param([string]$Path)
    
    $info = @{
        Version = "Unknown"
        LastModified = (Get-Item $Path).LastWriteTime
        HasEnv = Test-Path (Join-Path $Path ".env")
        ServiceRunning = $false
    }
    
    # Get version from package.json
    $packagePath = Join-Path $Path "package.json"
    if (Test-Path $packagePath) {
        try {
            $package = Get-Content $packagePath | ConvertFrom-Json
            $info.Version = $package.version
        }
        catch {}
    }
    
    # Check service status
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    if ($service) {
        $info.ServiceRunning = $service.Status -eq "Running"
    }
    
    return $info
}

# Main rollback process
try {
    # Handle list backups request
    if ($ListBackups) {
        Write-Info "Available Backups for $TargetPath"
        Write-Info ("="*60)
        
        $backups = Get-AvailableBackups -Path $TargetPath
        
        if ($backups.Count -eq 0) {
            Write-Warning "No backups found"
            exit 0
        }
        
        $index = 1
        foreach ($backup in $backups) {
            Write-Host ""
            Write-Host "[$index] " -NoNewline -ForegroundColor Yellow
            Write-Host "$($backup.Name)" -ForegroundColor Cyan
            Write-Host "    Type: $($backup.Type)"
            Write-Host "    Created: $($backup.Created)"
            Write-Host "    Size: $([math]::Round($backup.Size, 2)) MB"
            Write-Host "    Path: $($backup.Path)"
            $index++
        }
        
        Write-Host ""
        Write-Info "Current Deployment Info:"
        $currentInfo = Get-DeploymentInfo -Path $TargetPath
        Write-Host "  Version: $($currentInfo.Version)"
        Write-Host "  Last Modified: $($currentInfo.LastModified)"
        Write-Host "  Has .env: $($currentInfo.HasEnv)"
        Write-Host "  Service Running: $($currentInfo.ServiceRunning)"
        
        exit 0
    }
    
    $TotalSteps = 8
    $CurrentStep = 0
    
    Write-Log "Starting MCP Gateway rollback - ID: $RollbackId"
    
    # Step 1: Validate target
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Validating target deployment"
    
    if (-not (Test-Path $TargetPath)) {
        throw "Target deployment not found at: $TargetPath"
    }
    
    $currentInfo = Get-DeploymentInfo -Path $TargetPath
    Write-Log "Current version: $($currentInfo.Version)"
    Write-Log "Service running: $($currentInfo.ServiceRunning)"
    
    # Step 2: Find backup to restore
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Locating backup"
    
    if (-not $BackupPath) {
        # Find backup by ID or use latest
        $backups = Get-AvailableBackups -Path $TargetPath
        
        if ($backups.Count -eq 0) {
            throw "No backups available for rollback"
        }
        
        if ($BackupId) {
            $backup = $backups | Where-Object { $_.Name -like "*$BackupId*" } | Select-Object -First 1
            if (-not $backup) {
                throw "Backup with ID '$BackupId' not found"
            }
            $BackupPath = $backup.Path
        }
        else {
            # Interactive selection
            if (-not $Force -and -not $Silent) {
                Write-Host ""
                Write-Warning "Available backups:"
                $index = 1
                foreach ($backup in $backups | Select-Object -First 5) {
                    Write-Host "[$index] $($backup.Name) (Created: $($backup.Created))" -ForegroundColor Yellow
                    $index++
                }
                
                $selection = Read-Host "Select backup to restore (1-$($index-1))"
                if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -lt $index) {
                    $BackupPath = $backups[[int]$selection - 1].Path
                }
                else {
                    throw "Invalid selection"
                }
            }
            else {
                # Use most recent backup
                $BackupPath = $backups[0].Path
                Write-Log "Using most recent backup: $($backups[0].Name)"
            }
        }
    }
    
    if (-not (Test-Path $BackupPath)) {
        throw "Backup path not found: $BackupPath"
    }
    
    Write-Log "Selected backup: $BackupPath"
    
    # Step 3: Validate backup
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Validating backup"
    
    if (-not (Test-BackupValidity -BackupPath $BackupPath)) {
        throw "Backup validation failed - missing required files"
    }
    
    $backupInfo = Get-DeploymentInfo -Path $BackupPath
    Write-Log "Backup version: $($backupInfo.Version)"
    
    # Confirmation
    if (-not $Force -and -not $Silent) {
        Write-Host ""
        Write-Warning "This will replace the current deployment!"
        Write-Host "Current version: $($currentInfo.Version)"
        Write-Host "Restore version: $($backupInfo.Version)"
        Write-Host ""
        $confirm = Read-Host "Continue with rollback? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "Rollback cancelled by user" -Level WARNING
            exit 0
        }
    }
    
    # Step 4: Create safety backup
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Creating safety backup"
    
    if ($KeepCurrentAsBackup) {
        $safetyBackup = "$TargetPath.rollback-safety.$RollbackId"
        Write-Log "Creating safety backup at: $safetyBackup"
        
        # Stop service first
        $ServiceName = "MCPGateway"
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force
            Start-Sleep -Seconds 2
        }
        
        # Create backup
        Copy-Item -Path $TargetPath -Destination $safetyBackup -Recurse -Force
        Write-Log "Safety backup created" -Level SUCCESS
    }
    
    # Step 5: Stop service
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Stopping service"
    
    $ServiceName = "MCPGateway"
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Log "Stopping service"
            Stop-Service -Name $ServiceName -Force
            
            # Wait for stop
            $timeout = 30
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($stopwatch.Elapsed.TotalSeconds -lt $timeout) {
                $service = Get-Service -Name $ServiceName
                if ($service.Status -eq "Stopped") {
                    break
                }
                Start-Sleep -Milliseconds 500
            }
            
            if ($service.Status -ne "Stopped") {
                Write-Log "Force killing service process" -Level WARNING
                Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Log "Service stopped" -Level SUCCESS
    }
    
    # Step 6: Preserve configuration
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Preserving configuration"
    
    $preserveFiles = @()
    
    # Preserve .env file
    $currentEnv = Join-Path $TargetPath ".env"
    $backupEnv = Join-Path $BackupPath ".env"
    
    if ((Test-Path $currentEnv) -and -not (Test-Path $backupEnv)) {
        $tempEnv = Join-Path $env:TEMP "env-$RollbackId"
        Copy-Item -Path $currentEnv -Destination $tempEnv
        $preserveFiles += @{Source = $tempEnv; Dest = ".env"}
        Write-Log "Preserving current .env file"
    }
    
    # Preserve logs directory
    $currentLogs = Join-Path $TargetPath "logs"
    if (Test-Path $currentLogs) {
        $tempLogs = Join-Path $env:TEMP "logs-$RollbackId"
        Copy-Item -Path $currentLogs -Destination $tempLogs -Recurse
        $preserveFiles += @{Source = $tempLogs; Dest = "logs"}
        Write-Log "Preserving logs directory"
    }
    
    # Step 7: Perform rollback
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Performing rollback"
    
    Write-Log "Removing current deployment"
    
    # Remove current deployment
    $itemsToRemove = @("src", "config", "node_modules", "package.json", "package-lock.json")
    foreach ($item in $itemsToRemove) {
        $itemPath = Join-Path $TargetPath $item
        if (Test-Path $itemPath) {
            Remove-Item -Path $itemPath -Recurse -Force
            Write-Log "Removed: $item"
        }
    }
    
    # Copy backup to target
    Write-Log "Restoring from backup"
    
    $itemsToRestore = Get-ChildItem -Path $BackupPath
    foreach ($item in $itemsToRestore) {
        $destPath = Join-Path $TargetPath $item.Name
        
        if ($item.PSIsContainer) {
            Copy-Item -Path $item.FullName -Destination $destPath -Recurse -Force
        }
        else {
            Copy-Item -Path $item.FullName -Destination $destPath -Force
        }
        Write-Log "Restored: $($item.Name)"
    }
    
    # Restore preserved files
    foreach ($file in $preserveFiles) {
        $destPath = Join-Path $TargetPath $file.Dest
        if (Test-Path $file.Source) {
            if (Test-Path $file.Source -PathType Container) {
                if (-not (Test-Path $destPath)) {
                    Copy-Item -Path $file.Source -Destination $destPath -Recurse -Force
                }
            }
            else {
                Copy-Item -Path $file.Source -Destination $destPath -Force
            }
            Write-Log "Restored preserved: $($file.Dest)"
            
            # Cleanup temp file
            Remove-Item -Path $file.Source -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Step 8: Start service
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Starting service"
    
    if ($service) {
        Write-Log "Starting service"
        Start-Service -Name $ServiceName
        
        # Wait for start
        $timeout = 30
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($stopwatch.Elapsed.TotalSeconds -lt $timeout) {
            $service = Get-Service -Name $ServiceName
            if ($service.Status -eq "Running") {
                Write-Log "Service started successfully" -Level SUCCESS
                break
            }
            Start-Sleep -Milliseconds 500
        }
        
        if ($service.Status -ne "Running") {
            Write-Log "Service failed to start" -Level ERROR
            
            # Check logs
            $errorLog = Join-Path $TargetPath "logs\service-error.log"
            if (Test-Path $errorLog) {
                $errors = Get-Content $errorLog -Tail 20
                Write-Log "Recent errors:"
                foreach ($error in $errors) {
                    Write-Log "  $error"
                }
            }
            
            throw "Service failed to start after rollback"
        }
        
        # Test health
        Start-Sleep -Seconds 2
        try {
            $health = Invoke-RestMethod -Uri "http://localhost:4242/health" -Method Get -TimeoutSec 10
            Write-Log "Health check passed" -Level SUCCESS
        }
        catch {
            Write-Log "Health check failed: $_" -Level WARNING
        }
    }
    
    # Clean up old backups
    Write-Log "Cleaning up old backups"
    
    $backups = Get-AvailableBackups -Path $TargetPath
    if ($backups.Count -gt $KeepBackups) {
        $toDelete = $backups | Select-Object -Skip $KeepBackups
        foreach ($backup in $toDelete) {
            try {
                Remove-Item -Path $backup.Path -Recurse -Force
                Write-Log "Removed old backup: $($backup.Name)"
            }
            catch {
                Write-Log "Failed to remove old backup: $($backup.Name)" -Level WARNING
            }
        }
    }
    
    # Create rollback record
    $rollbackRecord = @{
        RollbackId = $RollbackId
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        FromVersion = $currentInfo.Version
        ToVersion = $backupInfo.Version
        BackupPath = $BackupPath
        Success = $true
    }
    
    $recordPath = Join-Path $TargetPath "deployments"
    if (-not (Test-Path $recordPath)) {
        New-Item -ItemType Directory -Path $recordPath -Force | Out-Null
    }
    
    $recordFile = Join-Path $recordPath "rollback-$RollbackId.json"
    $rollbackRecord | ConvertTo-Json | Set-Content -Path $recordFile -Encoding UTF8
    
    # Final summary
    Write-Log "="*60
    Write-Log "Rollback completed successfully!" -Level SUCCESS
    Write-Log "="*60
    Write-Log "Rollback ID: $RollbackId"
    Write-Log "Restored version: $($backupInfo.Version)"
    Write-Log "Service Status: $($service.Status)"
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Rollback completed successfully!"
        Write-Host ""
        Write-Info "Restored to version: $($backupInfo.Version)"
        if ($safetyBackup) {
            Write-Info "Previous version backed up to: $safetyBackup"
        }
        Write-Host ""
        Write-Host "Rollback log: $RollbackLog"
    }
    
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Rollback failed: $_" -Level ERROR  
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Rollback failed: $_"
        Write-Host ""
        Write-Host "Check the rollback log for details:"
        Write-Host $RollbackLog
        
        if ($safetyBackup -and (Test-Path $safetyBackup)) {
            Write-Host ""
            Write-Warning "A safety backup was created at: $safetyBackup"
            Write-Warning "You may need to manually restore from this backup"
        }
    }
    
    exit 1
}