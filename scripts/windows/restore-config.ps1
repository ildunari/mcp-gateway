# MCP Gateway Configuration Restore Script
# Restores configuration from backup archives
# Author: MCP Gateway Team  
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$BackupFile,
    [string]$RestorePath = "C:\Services\mcp-gateway",
    [string]$Password,
    [switch]$ListBackups,
    [string]$BackupPath,
    [switch]$ValidateOnly,
    [switch]$ConfigOnly,
    [switch]$KeepExisting,
    [switch]$Force,
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

# Banner
if (-not $Silent -and -not $ListBackups) {
    Write-Info @"
==============================================================
        MCP Gateway Configuration Restore v1.0              
==============================================================
"@
}

# Create restore log
$RestoreId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = "C:\Temp\mcp-gateway-restore"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$RestoreLog = Join-Path $LogDir "restore-$RestoreId.log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    Add-Content -Path $RestoreLog -Value $LogMessage -ErrorAction SilentlyContinue
    
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
    
    if (-not $Path) {
        # Try common locations
        $possiblePaths = @(
            (Join-Path $RestorePath "backups"),
            "C:\Backups\mcp-gateway",
            (Join-Path $env:USERPROFILE "Documents\MCP-Gateway-Backups")
        )
        
        foreach ($p in $possiblePaths) {
            if (Test-Path $p) {
                $Path = $p
                break
            }
        }
    }
    
    if (-not $Path -or -not (Test-Path $Path)) {
        return @()
    }
    
    $backups = @()
    
    # Find backup files
    $backupFiles = Get-ChildItem -Path $Path -Filter "*.zip" -File
    $backupFiles += Get-ChildItem -Path $Path -Filter "*.7z" -File
    
    foreach ($file in $backupFiles | Sort-Object CreationTime -Descending) {
        $backup = @{
            Name = $file.Name
            Path = $file.FullName
            Size = [Math]::Round($file.Length / 1MB, 2)
            Created = $file.CreationTime
            Type = $file.Extension.TrimStart(".")
            Info = $null
        }
        
        # Look for info file
        $infoFile = $file.FullName.Replace($file.Extension, ".json")
        if (Test-Path $infoFile) {
            try {
                $backup.Info = Get-Content $infoFile | ConvertFrom-Json
            }
            catch {}
        }
        
        $backups += $backup
    }
    
    return $backups
}

function Show-Backups {
    param($Backups)
    
    if ($Backups.Count -eq 0) {
        Write-Warning "No backups found"
        return
    }
    
    Write-Info "Available Backups"
    Write-Info "================"
    Write-Host ""
    
    $index = 1
    foreach ($backup in $Backups) {
        Write-Host "[$index] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($backup.Name)" -ForegroundColor Cyan
        Write-Host "     Created: $($backup.Created)"
        Write-Host "     Size: $($backup.Size) MB"
        Write-Host "     Type: $($backup.Type.ToUpper())"
        
        if ($backup.Info) {
            Write-Host "     Encrypted: $($backup.Info.Encrypted)"
            if ($backup.Info.Manifest) {
                Write-Host "     Files: $($backup.Info.Manifest.Statistics.TotalFiles)"
                Write-Host "     Version: $($backup.Info.Manifest.ServiceInfo.Version)"
            }
        }
        
        Write-Host ""
        $index++
    }
}

function Validate-Backup {
    param(
        [string]$BackupPath,
        [string]$TempPath
    )
    
    $validation = @{
        Valid = $true
        Errors = @()
        Warnings = @()
        Manifest = $null
    }
    
    # Check for manifest
    $manifestPath = Join-Path $TempPath "backup-manifest.json"
    if (-not (Test-Path $manifestPath)) {
        $validation.Errors += "No backup manifest found"
        $validation.Valid = $false
        return $validation
    }
    
    try {
        $manifest = Get-Content $manifestPath | ConvertFrom-Json
        $validation.Manifest = $manifest
    }
    catch {
        $validation.Errors += "Invalid backup manifest: $_"
        $validation.Valid = $false
        return $validation
    }
    
    # Validate required files
    $requiredFiles = @(
        "package.json",
        "src\server.js"
    )
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $TempPath $file
        if (-not (Test-Path $filePath)) {
            $validation.Errors += "Required file missing: $file"
            $validation.Valid = $false
        }
    }
    
    # Validate package.json
    $packagePath = Join-Path $TempPath "package.json"
    if (Test-Path $packagePath) {
        try {
            $package = Get-Content $packagePath | ConvertFrom-Json
            if ($package.name -ne "mcp-gateway") {
                $validation.Warnings += "Package name mismatch: $($package.name)"
            }
        }
        catch {
            $validation.Errors += "Invalid package.json: $_"
            $validation.Valid = $false
        }
    }
    
    # Check file integrity if hashes are available
    if ($manifest.IncludedFiles) {
        $hashMismatches = 0
        
        foreach ($fileInfo in $manifest.IncludedFiles | Where-Object { $_.Hash }) {
            $filePath = Join-Path $TempPath $fileInfo.Path
            if (Test-Path $filePath) {
                $currentHash = (Get-FileHash -Path $filePath -Algorithm MD5).Hash
                if ($currentHash -ne $fileInfo.Hash) {
                    $hashMismatches++
                }
            }
        }
        
        if ($hashMismatches -gt 0) {
            $validation.Warnings += "$hashMismatches file(s) have different hashes than backup"
        }
    }
    
    return $validation
}

function Extract-Backup {
    param(
        [string]$BackupPath,
        [string]$DestinationPath,
        [string]$Password
    )
    
    try {
        $extension = [System.IO.Path]::GetExtension($BackupPath).ToLower()
        
        if ($extension -eq ".zip") {
            # Extract ZIP
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupPath, $DestinationPath)
            return $true
        }
        elseif ($extension -eq ".7z") {
            # Extract 7z (requires 7-Zip)
            $sevenZip = "C:\Program Files\7-Zip\7z.exe"
            if (-not (Test-Path $sevenZip)) {
                throw "7-Zip is required to extract encrypted backups"
            }
            
            if ($Password) {
                & $sevenZip x "-p$Password" -y "-o$DestinationPath" "$BackupPath" | Out-Null
            }
            else {
                & $sevenZip x -y "-o$DestinationPath" "$BackupPath" | Out-Null
            }
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to extract backup (wrong password?)"
            }
            
            return $true
        }
        else {
            throw "Unsupported backup format: $extension"
        }
    }
    catch {
        throw "Failed to extract backup: $_"
    }
}

function Restore-Files {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [bool]$ConfigOnly,
        [bool]$KeepExisting
    )
    
    $restored = @{
        Files = 0
        Skipped = 0
        Errors = 0
    }
    
    # Get all files to restore
    $files = Get-ChildItem -Path $SourcePath -Recurse -File
    
    foreach ($file in $files) {
        $relativePath = $file.FullName.Replace($SourcePath, "").TrimStart("\")
        
        # Skip non-config files if ConfigOnly
        if ($ConfigOnly) {
            $configExtensions = @(".json", ".env", ".yml", ".yaml", ".xml")
            if ($file.Extension -notin $configExtensions) {
                $restored.Skipped++
                continue
            }
        }
        
        $destFile = Join-Path $DestinationPath $relativePath
        $destDir = Split-Path $destFile -Parent
        
        # Create directory if needed
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        # Check if file exists
        if ((Test-Path $destFile) -and $KeepExisting) {
            Write-Log "Keeping existing file: $relativePath"
            $restored.Skipped++
            continue
        }
        
        try {
            Copy-Item -Path $file.FullName -Destination $destFile -Force
            $restored.Files++
        }
        catch {
            Write-Log "Failed to restore $relativePath`: $_" -Level ERROR
            $restored.Errors++
        }
    }
    
    return $restored
}

# Main restore process
try {
    # Handle list backups request
    if ($ListBackups) {
        if (-not $BackupPath) {
            $BackupPath = Join-Path $RestorePath "backups"
        }
        
        $backups = Get-AvailableBackups -Path $BackupPath
        Show-Backups -Backups $backups
        exit 0
    }
    
    Write-Log "Starting MCP Gateway restore"
    Write-Log "Restore Path: $RestorePath"
    
    # Find backup file
    if (-not $BackupFile) {
        # Interactive selection
        if (-not $BackupPath) {
            $BackupPath = Join-Path $RestorePath "backups"
        }
        
        $backups = Get-AvailableBackups -Path $BackupPath
        
        if ($backups.Count -eq 0) {
            throw "No backups found in $BackupPath"
        }
        
        if (-not $Silent) {
            Show-Backups -Backups $backups
            
            $selection = Read-Host "Select backup to restore (1-$($backups.Count))"
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $backups.Count) {
                $BackupFile = $backups[[int]$selection - 1].Path
            }
            else {
                throw "Invalid selection"
            }
        }
        else {
            # Use most recent backup
            $BackupFile = $backups[0].Path
        }
    }
    
    if (-not (Test-Path $BackupFile)) {
        throw "Backup file not found: $BackupFile"
    }
    
    Write-Log "Selected backup: $BackupFile"
    
    # Check if encrypted
    $isEncrypted = $BackupFile.EndsWith(".7z")
    if ($isEncrypted -and -not $Password) {
        if (-not $Silent) {
            $securePassword = Read-Host "Enter password for encrypted backup" -AsSecureString
            $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            )
        }
        else {
            throw "Encrypted backup requires password"
        }
    }
    
    # Extract to temporary location
    Write-Log "Extracting backup"
    $tempPath = Join-Path $env:TEMP "mcp-restore-$RestoreId"
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    
    $extracted = Extract-Backup -BackupPath $BackupFile -DestinationPath $tempPath -Password $Password
    if (-not $extracted) {
        throw "Failed to extract backup"
    }
    
    # Validate backup
    Write-Log "Validating backup"
    $validation = Validate-Backup -BackupPath $BackupFile -TempPath $tempPath
    
    if (-not $validation.Valid) {
        Write-Log "Backup validation failed:" -Level ERROR
        foreach ($error in $validation.Errors) {
            Write-Log "  - $error" -Level ERROR
        }
        throw "Invalid backup file"
    }
    
    foreach ($warning in $validation.Warnings) {
        Write-Log "  - $warning" -Level WARNING
    }
    
    if ($ValidateOnly) {
        Write-Log "Validation completed successfully" -Level SUCCESS
        Write-Log "Backup is valid and can be restored"
        
        if ($validation.Manifest) {
            Write-Log "Backup Information:"
            Write-Log "  Created: $($validation.Manifest.Timestamp)"
            Write-Log "  Machine: $($validation.Manifest.MachineName)"
            Write-Log "  Files: $($validation.Manifest.Statistics.TotalFiles)"
            Write-Log "  Size: $($validation.Manifest.Statistics.TotalSizeMB) MB"
        }
        
        # Cleanup
        Remove-Item -Path $tempPath -Recurse -Force
        exit 0
    }
    
    # Confirmation
    if (-not $Force -and -not $Silent) {
        Write-Warning "This will restore files to: $RestorePath"
        
        if (-not $KeepExisting) {
            Write-Warning "Existing files will be overwritten!"
        }
        
        $confirm = Read-Host "Continue with restore? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "Restore cancelled by user" -Level WARNING
            Remove-Item -Path $tempPath -Recurse -Force
            exit 0
        }
    }
    
    # Stop service if running
    Write-Log "Checking service status"
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    $serviceStopped = $false
    
    if ($service -and $service.Status -eq "Running") {
        Write-Log "Stopping service"
        Stop-Service -Name "MCPGateway" -Force
        $serviceStopped = $true
        Start-Sleep -Seconds 2
    }
    
    # Create restore path if needed
    if (-not (Test-Path $RestorePath)) {
        Write-Log "Creating restore directory: $RestorePath"
        New-Item -ItemType Directory -Path $RestorePath -Force | Out-Null
    }
    
    # Backup current configuration if exists
    if ((Test-Path $RestorePath) -and -not $KeepExisting) {
        $currentBackup = Join-Path $RestorePath "pre-restore-backup-$RestoreId"
        Write-Log "Backing up current configuration to: $currentBackup"
        
        $itemsToBackup = @(".env", "config", "src")
        New-Item -ItemType Directory -Path $currentBackup -Force | Out-Null
        
        foreach ($item in $itemsToBackup) {
            $itemPath = Join-Path $RestorePath $item
            if (Test-Path $itemPath) {
                $destPath = Join-Path $currentBackup $item
                if (Test-Path $itemPath -PathType Container) {
                    Copy-Item -Path $itemPath -Destination $destPath -Recurse -Force
                }
                else {
                    Copy-Item -Path $itemPath -Destination $destPath -Force
                }
            }
        }
    }
    
    # Restore files
    Write-Log "Restoring files"
    $result = Restore-Files `
        -SourcePath $tempPath `
        -DestinationPath $RestorePath `
        -ConfigOnly $ConfigOnly `
        -KeepExisting $KeepExisting
    
    Write-Log "Restored $($result.Files) files"
    if ($result.Skipped -gt 0) {
        Write-Log "Skipped $($result.Skipped) files"
    }
    if ($result.Errors -gt 0) {
        Write-Log "Failed to restore $($result.Errors) files" -Level WARNING
    }
    
    # Restore service configuration if available
    $serviceConfigPath = Join-Path $tempPath "service-config.txt"
    if ((Test-Path $serviceConfigPath) -and $service) {
        Write-Log "Restoring service configuration"
        
        # Note: This would require parsing and applying NSSM configuration
        # For now, just notify the user
        Write-Log "Service configuration backup found. Manual reconfiguration may be needed." -Level WARNING
    }
    
    # Post-restore tasks
    if (-not $ConfigOnly) {
        # Check if npm install is needed
        $nodeModulesPath = Join-Path $RestorePath "node_modules"
        if (-not (Test-Path $nodeModulesPath)) {
            Write-Log "Running npm install" -Level WARNING
            
            Push-Location $RestorePath
            try {
                npm install
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Dependencies installed successfully" -Level SUCCESS
                }
                else {
                    Write-Log "Failed to install dependencies" -Level ERROR
                }
            }
            finally {
                Pop-Location
            }
        }
    }
    
    # Restart service if it was running
    if ($serviceStopped) {
        Write-Log "Starting service"
        Start-Service -Name "MCPGateway"
        
        Start-Sleep -Seconds 3
        $service = Get-Service -Name "MCPGateway"
        
        if ($service.Status -eq "Running") {
            Write-Log "Service started successfully" -Level SUCCESS
        }
        else {
            Write-Log "Service failed to start" -Level ERROR
        }
    }
    
    # Cleanup
    Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    
    # Final summary
    Write-Log "="*60
    Write-Log "Restore completed successfully!" -Level SUCCESS
    Write-Log "="*60
    Write-Log "Backup File: $(Split-Path $BackupFile -Leaf)"
    Write-Log "Restored To: $RestorePath"
    Write-Log "Files Restored: $($result.Files)"
    
    if ($validation.Manifest) {
        Write-Log "Original Backup Info:"
        Write-Log "  Created: $($validation.Manifest.Timestamp)"
        Write-Log "  Machine: $($validation.Manifest.MachineName)"
        Write-Log "  Version: $($validation.Manifest.ServiceInfo.Version)"
    }
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Restore completed successfully!"
        Write-Host ""
        
        if ($currentBackup) {
            Write-Info "Previous configuration backed up to:"
            Write-Host $currentBackup
        }
        
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "1. Verify the restored configuration"
        Write-Host "2. Update .env file if needed"
        Write-Host "3. Test the service functionality"
    }
    
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Restore failed: $_" -Level ERROR
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Restore failed: $_"
        Write-Host ""
        Write-Host "Check the restore log for details:"
        Write-Host $RestoreLog
    }
    
    # Cleanup on failure
    if ($tempPath -and (Test-Path $tempPath)) {
        Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}