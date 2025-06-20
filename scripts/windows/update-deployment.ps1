# MCP Gateway Update Deployment Script
# Updates existing deployment with minimal downtime
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$SourcePath,
    [string]$TargetPath = "C:\Services\mcp-gateway",
    [string]$GitRepo,
    [switch]$FromGit,
    [switch]$SkipBackup,
    [switch]$SkipDependencies,
    [switch]$ForceUpdate,
    [switch]$ConfigOnly,
    [switch]$CodeOnly,
    [int]$GracefulStopTimeout = 30,
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

# Update banner
if (-not $Silent) {
    Write-Info @"
==============================================================
          MCP Gateway Update Deployment v1.0              
==============================================================
Target: $TargetPath
Update Mode: $(if ($ConfigOnly) { "Configuration Only" } elseif ($CodeOnly) { "Code Only" } else { "Full Update" })
"@
}

# Create update log
$UpdateId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = "C:\Temp\mcp-gateway-deployments"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$UpdateLog = Join-Path $LogDir "update-$UpdateId.log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $UpdateLog -Value $LogMessage
    
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

function Get-ServiceConnections {
    param([int]$Port = 4242)
    
    $connections = @()
    $netstat = netstat -an | Select-String ":$Port\s+.*ESTABLISHED"
    foreach ($line in $netstat) {
        $connections += $line.ToString().Trim()
    }
    return $connections
}

function Wait-ForServiceStop {
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $service -or $service.Status -eq "Stopped") {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    
    return $false
}

function Compare-Versions {
    param(
        [string]$CurrentPath,
        [string]$NewPath
    )
    
    $changes = @{
        CodeChanged = $false
        ConfigChanged = $false
        DependenciesChanged = $false
        Files = @()
    }
    
    # Compare package.json
    $currentPackage = Join-Path $CurrentPath "package.json"
    $newPackage = Join-Path $NewPath "package.json"
    
    if ((Test-Path $currentPackage) -and (Test-Path $newPackage)) {
        $currentJson = Get-Content $currentPackage | ConvertFrom-Json
        $newJson = Get-Content $newPackage | ConvertFrom-Json
        
        if ($currentJson.version -ne $newJson.version) {
            $changes.CodeChanged = $true
            Write-Log "Version change detected: $($currentJson.version) -> $($newJson.version)"
        }
        
        # Check dependencies
        $currentDeps = $currentJson.dependencies | ConvertTo-Json
        $newDeps = $newJson.dependencies | ConvertTo-Json
        if ($currentDeps -ne $newDeps) {
            $changes.DependenciesChanged = $true
            Write-Log "Dependencies changed"
        }
    }
    
    # Compare source files
    $sourceFiles = @("src\*.js", "config\*.json")
    foreach ($pattern in $sourceFiles) {
        $currentFiles = Get-ChildItem -Path (Join-Path $CurrentPath $pattern) -ErrorAction SilentlyContinue
        $newFiles = Get-ChildItem -Path (Join-Path $NewPath $pattern) -ErrorAction SilentlyContinue
        
        foreach ($newFile in $newFiles) {
            $relativePath = $newFile.FullName.Replace($NewPath, "").TrimStart("\")
            $currentFile = Join-Path $CurrentPath $relativePath
            
            if (Test-Path $currentFile) {
                $currentHash = Get-FileHash $currentFile -Algorithm MD5
                $newHash = Get-FileHash $newFile.FullName -Algorithm MD5
                
                if ($currentHash.Hash -ne $newHash.Hash) {
                    $changes.Files += $relativePath
                    if ($relativePath -like "*.json") {
                        $changes.ConfigChanged = $true
                    }
                    else {
                        $changes.CodeChanged = $true
                    }
                }
            }
            else {
                $changes.Files += "+ $relativePath"
                $changes.CodeChanged = $true
            }
        }
    }
    
    return $changes
}

# Main update process
try {
    $TotalSteps = 10
    $CurrentStep = 0
    
    Write-Log "Starting MCP Gateway update - ID: $UpdateId"
    
    # Step 1: Validate target deployment
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Validating existing deployment"
    
    if (-not (Test-Path $TargetPath)) {
        throw "Target deployment not found at: $TargetPath"
    }
    
    # Check if service exists
    $ServiceName = "MCPGateway"
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        throw "MCP Gateway service not found. Please run full deployment first."
    }
    
    Write-Log "Current service status: $($service.Status)"
    
    # Step 2: Prepare source code
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Preparing update source"
    
    $TempSource = Join-Path $env:TEMP "mcp-gateway-update-$UpdateId"
    
    if ($FromGit) {
        if (-not $GitRepo) {
            # Try to get repo from existing deployment
            $gitDir = Join-Path $TargetPath ".git"
            if (Test-Path $gitDir) {
                Push-Location $TargetPath
                $GitRepo = git config --get remote.origin.url
                Pop-Location
                Write-Log "Using Git repo from existing deployment: $GitRepo"
            }
            else {
                $GitRepo = Read-Host "Enter Git repository URL"
            }
        }
        
        Write-Log "Pulling latest from repository: $GitRepo"
        git clone $GitRepo $TempSource
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone repository"
        }
        
        # Get latest tag/version
        Push-Location $TempSource
        $latestTag = git describe --tags --abbrev=0 2>$null
        if ($latestTag) {
            Write-Log "Latest version: $latestTag"
        }
        Pop-Location
        
        $SourcePath = $TempSource
    }
    elseif ($SourcePath) {
        if (-not (Test-Path $SourcePath)) {
            throw "Source path not found: $SourcePath"
        }
        Write-Log "Using local source: $SourcePath"
    }
    else {
        throw "No source specified. Use -SourcePath or -FromGit"
    }
    
    # Step 3: Compare versions
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Analyzing changes"
    
    $changes = Compare-Versions -CurrentPath $TargetPath -NewPath $SourcePath
    
    if ($changes.Files.Count -eq 0 -and -not $ForceUpdate) {
        Write-Log "No changes detected. Use -ForceUpdate to update anyway." -Level WARNING
        exit 0
    }
    
    Write-Log "Changes detected:"
    Write-Log "  Code changed: $($changes.CodeChanged)"
    Write-Log "  Config changed: $($changes.ConfigChanged)"
    Write-Log "  Dependencies changed: $($changes.DependenciesChanged)"
    Write-Log "  Files changed: $($changes.Files.Count)"
    
    foreach ($file in $changes.Files) {
        Write-Log "    $file"
    }
    
    # Step 4: Check active connections
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Checking active connections"
    
    $connections = Get-ServiceConnections
    if ($connections.Count -gt 0) {
        Write-Log "Active connections detected: $($connections.Count)" -Level WARNING
        foreach ($conn in $connections) {
            Write-Log "  $conn"
        }
        
        if (-not $ForceUpdate) {
            $continue = Read-Host "Active connections found. Continue with update? (Y/N)"
            if ($continue -ne "Y") {
                Write-Log "Update cancelled by user" -Level WARNING
                exit 0
            }
        }
    }
    
    # Step 5: Create backup
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Creating backup"
    
    if (-not $SkipBackup) {
        $BackupDir = Join-Path $TargetPath "backups"
        if (-not (Test-Path $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }
        
        $BackupPath = Join-Path $BackupDir "pre-update-$UpdateId"
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        
        # Backup critical files
        $BackupItems = @(
            "src",
            "config",
            "package.json",
            "package-lock.json",
            ".env"
        )
        
        foreach ($item in $BackupItems) {
            $sourcePath = Join-Path $TargetPath $item
            if (Test-Path $sourcePath) {
                $destPath = Join-Path $BackupPath $item
                if (Test-Path $sourcePath -PathType Container) {
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                }
                else {
                    Copy-Item -Path $sourcePath -Destination $destPath -Force
                }
            }
        }
        
        Write-Log "Backup created at: $BackupPath" -Level SUCCESS
    }
    
    # Step 6: Stop service gracefully
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Stopping service gracefully"
    
    if ($service.Status -eq "Running") {
        Write-Log "Sending stop signal to service"
        
        # Create shutdown signal file
        $shutdownSignal = Join-Path $TargetPath "shutdown.signal"
        "graceful" | Set-Content -Path $shutdownSignal
        
        # Stop service
        Stop-Service -Name $ServiceName -Force
        
        # Wait for graceful stop
        if (Wait-ForServiceStop -ServiceName $ServiceName -TimeoutSeconds $GracefulStopTimeout) {
            Write-Log "Service stopped gracefully" -Level SUCCESS
        }
        else {
            Write-Log "Service stop timeout, forcing stop" -Level WARNING
            Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue
        }
        
        # Remove shutdown signal
        Remove-Item -Path $shutdownSignal -Force -ErrorAction SilentlyContinue
    }
    
    # Step 7: Update files
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Updating files"
    
    if (-not $ConfigOnly) {
        # Update code files
        $CodeItems = @("src", "package.json", "package-lock.json")
        
        foreach ($item in $CodeItems) {
            $sourcePath = Join-Path $SourcePath $item
            if (Test-Path $sourcePath) {
                $destPath = Join-Path $TargetPath $item
                
                # Remove old version
                if (Test-Path $destPath) {
                    Remove-Item -Path $destPath -Recurse -Force
                }
                
                # Copy new version
                if (Test-Path $sourcePath -PathType Container) {
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                }
                else {
                    Copy-Item -Path $sourcePath -Destination $destPath -Force
                }
                
                Write-Log "Updated: $item"
            }
        }
    }
    
    if (-not $CodeOnly) {
        # Update config files (with merge)
        $configDir = Join-Path $TargetPath "config"
        $newConfigDir = Join-Path $SourcePath "config"
        
        if (Test-Path $newConfigDir) {
            $configFiles = Get-ChildItem -Path $newConfigDir -Filter "*.json"
            
            foreach ($configFile in $configFiles) {
                $currentConfig = Join-Path $configDir $configFile.Name
                $newConfig = $configFile.FullName
                
                if (Test-Path $currentConfig) {
                    # Backup current config
                    $configBackup = "$currentConfig.backup.$UpdateId"
                    Copy-Item -Path $currentConfig -Destination $configBackup
                    Write-Log "Backed up config: $($configFile.Name)"
                }
                
                # Copy new config
                Copy-Item -Path $newConfig -Destination $currentConfig -Force
                Write-Log "Updated config: $($configFile.Name)"
            }
        }
    }
    
    # Update scripts
    $Scripts = @(
        "manage-service.bat",
        "install-service.ps1",
        "update-deployment.ps1",
        "rollback-deployment.ps1"
    )
    
    foreach ($script in $Scripts) {
        $sourcePath = Join-Path $SourcePath $script
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination (Join-Path $TargetPath $script) -Force
            Write-Log "Updated script: $script"
        }
    }
    
    # Step 8: Update dependencies
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Updating dependencies"
    
    if (-not $SkipDependencies -and $changes.DependenciesChanged) {
        Push-Location $TargetPath
        try {
            Write-Log "Installing updated dependencies"
            
            # Clean install
            if (Test-Path "node_modules") {
                Remove-Item -Path "node_modules" -Recurse -Force
            }
            
            npm ci --production
            if ($LASTEXITCODE -ne 0) {
                npm install --production
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install dependencies"
                }
            }
            
            Write-Log "Dependencies updated successfully" -Level SUCCESS
        }
        finally {
            Pop-Location
        }
    }
    elseif ($changes.DependenciesChanged) {
        Write-Log "Dependencies changed but update skipped (-SkipDependencies)" -Level WARNING
    }
    
    # Step 9: Run post-update validation
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Running validation"
    
    # Validate configuration
    $envFile = Join-Path $TargetPath ".env"
    if (-not (Test-Path $envFile)) {
        Write-Log ".env file missing!" -Level ERROR
        throw "Configuration file missing"
    }
    
    # Validate main script
    $mainScript = Join-Path $TargetPath "src\server.js"
    if (-not (Test-Path $mainScript)) {
        Write-Log "Main script missing!" -Level ERROR
        throw "Main script missing"
    }
    
    # Test Node.js syntax
    Push-Location $TargetPath
    $syntaxCheck = node -c $mainScript 2>&1
    Pop-Location
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Syntax check failed: $syntaxCheck" -Level ERROR
        throw "Code validation failed"
    }
    
    Write-Log "Validation passed" -Level SUCCESS
    
    # Step 10: Start service
    $CurrentStep++
    Write-Step -Step $CurrentStep -Total $TotalSteps -Message "Starting service"
    
    Write-Log "Starting service"
    Start-Service -Name $ServiceName
    
    # Wait for service to start
    $startTimeout = 30
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $startTimeout) {
        $service = Get-Service -Name $ServiceName
        if ($service.Status -eq "Running") {
            Write-Log "Service started successfully" -Level SUCCESS
            break
        }
        Start-Sleep -Milliseconds 500
    }
    
    if ($service.Status -ne "Running") {
        Write-Log "Service failed to start within timeout" -Level ERROR
        
        # Check logs for errors
        $errorLog = Join-Path $TargetPath "logs\service-error.log"
        if (Test-Path $errorLog) {
            $recentErrors = Get-Content $errorLog -Tail 20
            Write-Log "Recent errors:"
            foreach ($error in $recentErrors) {
                Write-Log "  $error"
            }
        }
        
        throw "Service failed to start"
    }
    
    # Test health endpoint
    Start-Sleep -Seconds 2
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:4242/health" -Method Get -TimeoutSec 10
        Write-Log "Health check passed - Status: $($health.status)" -Level SUCCESS
        
        # Log server information
        if ($health.servers) {
            Write-Log "Active servers: $($health.servers.Count)"
            foreach ($server in $health.servers) {
                Write-Log "  - $($server.name): $($server.status)"
            }
        }
    }
    catch {
        Write-Log "Health check failed: $_" -Level WARNING
    }
    
    # Cleanup
    if ($TempSource -and (Test-Path $TempSource)) {
        Remove-Item -Path $TempSource -Recurse -Force
        Write-Log "Cleaned up temporary files"
    }
    
    # Create update record
    $updateRecord = @{
        UpdateId = $UpdateId
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SourcePath = $SourcePath
        TargetPath = $TargetPath
        Changes = $changes
        BackupPath = if ($BackupPath) { $BackupPath } else { "None" }
        Success = $true
    }
    
    $recordPath = Join-Path $TargetPath "deployments"
    if (-not (Test-Path $recordPath)) {
        New-Item -ItemType Directory -Path $recordPath -Force | Out-Null
    }
    
    $recordFile = Join-Path $recordPath "update-$UpdateId.json"
    $updateRecord | ConvertTo-Json -Depth 10 | Set-Content -Path $recordFile -Encoding UTF8
    
    # Update current deployment link
    $currentLink = Join-Path $recordPath "current.json"
    Copy-Item -Path $recordFile -Destination $currentLink -Force
    
    # Final summary
    Write-Log "="*60
    Write-Log "Update completed successfully!" -Level SUCCESS
    Write-Log "="*60
    Write-Log "Update ID: $UpdateId"
    Write-Log "Files updated: $($changes.Files.Count)"
    Write-Log "Service Status: Running"
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Update completed successfully!"
        Write-Host ""
        if ($changes.ConfigChanged) {
            Write-Warning "Configuration files were updated. Please review the changes."
        }
        if ($changes.DependenciesChanged -and $SkipDependencies) {
            Write-Warning "Dependencies changed but were not updated. Run 'npm install' manually if needed."
        }
        Write-Host ""
        Write-Host "Update log: $UpdateLog"
    }
    
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Update failed: $_" -Level ERROR
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Update failed: $_"
        Write-Host ""
        Write-Host "Check the update log for details:"
        Write-Host $UpdateLog
    }
    
    # Attempt rollback
    if ($BackupPath -and (Test-Path $BackupPath)) {
        Write-Warning "Attempting to rollback to backup..."
        
        $rollbackScript = Join-Path $TargetPath "windows-tools\rollback-deployment.ps1"
        if (Test-Path $rollbackScript) {
            & $rollbackScript -BackupPath $BackupPath -TargetPath $TargetPath -Silent
        }
        else {
            Write-Error "Rollback script not found. Manual intervention required."
            Write-Host "Backup location: $BackupPath"
        }
    }
    
    exit 1
}