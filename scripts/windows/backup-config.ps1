# MCP Gateway Configuration Backup Script
# Creates comprehensive backups of configuration and state
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$ProjectPath = "C:\Services\mcp-gateway",
    [string]$BackupPath,
    [string]$BackupName,
    [switch]$IncludeLogs,
    [switch]$IncludeNodeModules,
    [switch]$Encrypt,
    [string]$Password,
    [switch]$Upload,
    [string]$UploadPath,
    [switch]$Schedule,
    [string]$ScheduleTime = "02:00",
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
if (-not $Silent) {
    Write-Info @"
==============================================================
         MCP Gateway Configuration Backup v1.0              
==============================================================
"@
}

# Create backup ID
$BackupId = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $BackupName) {
    $BackupName = "mcp-gateway-backup-$BackupId"
}

# Default backup path
if (-not $BackupPath) {
    $BackupPath = Join-Path $ProjectPath "backups"
}

# Create backup log
$BackupLog = Join-Path $BackupPath "backup-$BackupId.log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Ensure backup directory exists
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }
    
    Add-Content -Path $BackupLog -Value $LogMessage -ErrorAction SilentlyContinue
    
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

function Get-ServiceInfo {
    $info = @{
        ServiceInstalled = $false
        ServiceStatus = "Not Installed"
        Version = "Unknown"
        LastModified = $null
    }
    
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    if ($service) {
        $info.ServiceInstalled = $true
        $info.ServiceStatus = $service.Status.ToString()
    }
    
    $packagePath = Join-Path $ProjectPath "package.json"
    if (Test-Path $packagePath) {
        try {
            $package = Get-Content $packagePath | ConvertFrom-Json
            $info.Version = $package.version
        }
        catch {}
        
        $info.LastModified = (Get-Item $packagePath).LastWriteTime
    }
    
    return $info
}

function Get-BackupManifest {
    param(
        [string]$ProjectPath,
        [array]$IncludedFiles,
        [array]$ExcludedFiles
    )
    
    $manifest = @{
        BackupId = $BackupId
        BackupName = $BackupName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        MachineName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        ProjectPath = $ProjectPath
        ServiceInfo = Get-ServiceInfo
        IncludedFiles = @()
        ExcludedFiles = $ExcludedFiles
        Statistics = @{
            TotalFiles = 0
            TotalSizeMB = 0
            ConfigFiles = 0
            SourceFiles = 0
            LogFiles = 0
        }
    }
    
    foreach ($file in $IncludedFiles) {
        $relativePath = $file.FullName.Replace($ProjectPath, "").TrimStart("\")
        $fileInfo = @{
            Path = $relativePath
            Size = $file.Length
            Modified = $file.LastWriteTime
            Hash = ""
        }
        
        # Calculate hash for important files
        if ($file.Extension -in @(".json", ".js", ".env", ".yml", ".yaml")) {
            try {
                $fileInfo.Hash = (Get-FileHash -Path $file.FullName -Algorithm MD5).Hash
            }
            catch {}
        }
        
        $manifest.IncludedFiles += $fileInfo
        $manifest.Statistics.TotalFiles++
        $manifest.Statistics.TotalSizeMB += ($file.Length / 1MB)
        
        # Categorize files
        switch ($file.Extension) {
            ".json" { $manifest.Statistics.ConfigFiles++ }
            ".js" { $manifest.Statistics.SourceFiles++ }
            ".log" { $manifest.Statistics.LogFiles++ }
        }
    }
    
    $manifest.Statistics.TotalSizeMB = [Math]::Round($manifest.Statistics.TotalSizeMB, 2)
    
    return $manifest
}

function Compress-Backup {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [bool]$Encrypt,
        [string]$Password
    )
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Create zip file
        if (Test-Path $DestinationPath) {
            Remove-Item $DestinationPath -Force
        }
        
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $DestinationPath)
        
        # Encrypt if requested
        if ($Encrypt -and $Password) {
            # Note: Native .NET doesn't support password-protected zips
            # This would require a third-party library like DotNetZip
            Write-Log "Note: Encryption requires 7-Zip to be installed" -Level WARNING
            
            $sevenZip = "C:\Program Files\7-Zip\7z.exe"
            if (Test-Path $sevenZip) {
                $encryptedPath = $DestinationPath.Replace(".zip", ".7z")
                
                & $sevenZip a -p"$Password" -mhe=on "$encryptedPath" "$SourcePath\*" | Out-Null
                
                if (Test-Path $encryptedPath) {
                    Remove-Item $DestinationPath -Force
                    return $encryptedPath
                }
            }
        }
        
        return $DestinationPath
    }
    catch {
        throw "Failed to compress backup: $_"
    }
}

function Upload-Backup {
    param(
        [string]$FilePath,
        [string]$UploadPath
    )
    
    # This is a placeholder for upload functionality
    # In practice, this could upload to:
    # - Network share
    # - FTP/SFTP
    # - Cloud storage (Azure, AWS, etc.)
    
    if ($UploadPath.StartsWith("\\")) {
        # Network share
        try {
            $fileName = Split-Path $FilePath -Leaf
            $destination = Join-Path $UploadPath $fileName
            Copy-Item -Path $FilePath -Destination $destination -Force
            Write-Log "Uploaded to network share: $destination" -Level SUCCESS
            return $true
        }
        catch {
            Write-Log "Failed to upload to network share: $_" -Level ERROR
            return $false
        }
    }
    else {
        Write-Log "Upload path type not supported: $UploadPath" -Level WARNING
        return $false
    }
}

function Create-ScheduledBackup {
    param(
        [string]$Time,
        [string]$ScriptPath,
        [hashtable]$Parameters
    )
    
    $taskName = "MCP Gateway Daily Backup"
    
    # Build argument string
    $arguments = "-NoProfile -WindowStyle Hidden -File `"$ScriptPath`""
    foreach ($key in $Parameters.Keys) {
        if ($Parameters[$key] -is [switch]) {
            if ($Parameters[$key]) {
                $arguments += " -$key"
            }
        }
        else {
            $arguments += " -$key `"$($Parameters[$key])`""
        }
    }
    
    # Create scheduled task
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -Daily -At $Time
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
    Register-ScheduledTask `
        -TaskName $taskName `
        -Description "Daily backup of MCP Gateway configuration" `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null
        
    Write-Log "Scheduled task created: $taskName at $Time daily" -Level SUCCESS
}

# Main backup process
try {
    Write-Log "Starting MCP Gateway backup"
    Write-Log "Project Path: $ProjectPath"
    Write-Log "Backup Name: $BackupName"
    
    # Validate project path
    if (-not (Test-Path $ProjectPath)) {
        throw "Project path not found: $ProjectPath"
    }
    
    # Create temporary backup directory
    $tempBackupPath = Join-Path $env:TEMP "mcp-backup-$BackupId"
    New-Item -ItemType Directory -Path $tempBackupPath -Force | Out-Null
    
    Write-Log "Collecting files for backup"
    
    # Define what to backup
    $includePatterns = @(
        "src\*",
        "config\*",
        "windows-tools\*",
        "*.json",
        "*.js",
        "*.ps1",
        "*.bat",
        "*.md",
        ".env*"
    )
    
    $excludePatterns = @(
        "node_modules",
        "*.log",
        "temp",
        "*.tmp",
        ".git"
    )
    
    # Add patterns based on parameters
    if ($IncludeLogs) {
        $includePatterns += "logs\*.log"
        Write-Log "Including log files in backup"
    }
    
    if ($IncludeNodeModules) {
        $excludePatterns = $excludePatterns | Where-Object { $_ -ne "node_modules" }
        Write-Log "Including node_modules in backup (this may take time)"
    }
    
    # Collect files
    $filesToBackup = @()
    $excludedFiles = @()
    
    foreach ($pattern in $includePatterns) {
        $path = Join-Path $ProjectPath $pattern
        $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
        
        foreach ($file in $files) {
            $excluded = $false
            
            # Check exclusions
            foreach ($exclude in $excludePatterns) {
                if ($file.FullName -like "*$exclude*") {
                    $excluded = $true
                    $excludedFiles += $file.FullName
                    break
                }
            }
            
            if (-not $excluded) {
                $filesToBackup += $file
            }
        }
    }
    
    Write-Log "Files to backup: $($filesToBackup.Count)"
    
    # Copy files to temp directory
    foreach ($file in $filesToBackup) {
        $relativePath = $file.FullName.Replace($ProjectPath, "").TrimStart("\")
        $destPath = Join-Path $tempBackupPath $relativePath
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        Copy-Item -Path $file.FullName -Destination $destPath -Force
    }
    
    # Create manifest
    Write-Log "Creating backup manifest"
    $manifest = Get-BackupManifest -ProjectPath $ProjectPath -IncludedFiles $filesToBackup -ExcludedFiles $excludedFiles
    $manifestPath = Join-Path $tempBackupPath "backup-manifest.json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8
    
    # Backup service configuration if installed
    $service = Get-Service -Name "MCPGateway" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "Backing up service configuration"
        $serviceConfigPath = Join-Path $tempBackupPath "service-config.txt"
        
        # Export service configuration using nssm
        $nssmPath = Join-Path $ProjectPath "nssm.exe"
        if (Test-Path $nssmPath) {
            & $nssmPath dump MCPGateway > $serviceConfigPath 2>$null
        }
    }
    
    # Compress backup
    Write-Log "Compressing backup"
    $backupFileName = "$BackupName.zip"
    $backupFilePath = Join-Path $BackupPath $backupFileName
    
    if ($Encrypt -and -not $Password) {
        if (-not $Silent) {
            $securePassword = Read-Host "Enter password for encryption" -AsSecureString
            $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            )
        }
        else {
            throw "Encryption requested but no password provided"
        }
    }
    
    $finalBackupPath = Compress-Backup `
        -SourcePath $tempBackupPath `
        -DestinationPath $backupFilePath `
        -Encrypt $Encrypt `
        -Password $Password
    
    # Calculate final size
    $backupSize = (Get-Item $finalBackupPath).Length / 1MB
    Write-Log "Backup size: $([Math]::Round($backupSize, 2)) MB"
    
    # Upload if requested
    if ($Upload -and $UploadPath) {
        Write-Log "Uploading backup"
        $uploaded = Upload-Backup -FilePath $finalBackupPath -UploadPath $UploadPath
        
        if (-not $uploaded) {
            Write-Log "Upload failed, backup kept locally" -Level WARNING
        }
    }
    
    # Schedule if requested
    if ($Schedule) {
        Write-Log "Creating scheduled backup task"
        
        $taskParams = @{
            ProjectPath = $ProjectPath
            BackupPath = $BackupPath
            Silent = $true
        }
        
        if ($IncludeLogs) { $taskParams.IncludeLogs = $true }
        if ($Upload) { 
            $taskParams.Upload = $true
            $taskParams.UploadPath = $UploadPath
        }
        
        Create-ScheduledBackup `
            -Time $ScheduleTime `
            -ScriptPath $PSCommandPath `
            -Parameters $taskParams
    }
    
    # Cleanup
    Remove-Item -Path $tempBackupPath -Recurse -Force -ErrorAction SilentlyContinue
    
    # Create backup info file
    $backupInfo = @{
        BackupFile = Split-Path $finalBackupPath -Leaf
        Created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SizeMB = [Math]::Round($backupSize, 2)
        Encrypted = $Encrypt
        Manifest = $manifest
    }
    
    $infoPath = $finalBackupPath.Replace(".zip", ".json").Replace(".7z", ".json")
    $backupInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $infoPath -Encoding UTF8
    
    # Final summary
    Write-Log "="*60
    Write-Log "Backup completed successfully!" -Level SUCCESS
    Write-Log "="*60
    Write-Log "Backup ID: $BackupId"
    Write-Log "Backup File: $finalBackupPath"
    Write-Log "Total Files: $($manifest.Statistics.TotalFiles)"
    Write-Log "Total Size: $($manifest.Statistics.TotalSizeMB) MB"
    Write-Log "Compressed Size: $([Math]::Round($backupSize, 2)) MB"
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Backup completed successfully!"
        Write-Host ""
        Write-Host "Backup saved to:"
        Write-Host $finalBackupPath
        
        if ($Encrypt) {
            Write-Warning "This backup is encrypted. Keep the password safe!"
        }
    }
    
    # Cleanup old backups (keep last 10)
    Write-Log "Cleaning up old backups"
    $allBackups = Get-ChildItem -Path $BackupPath -Filter "*.zip" | Sort-Object CreationTime -Descending
    $allBackups += Get-ChildItem -Path $BackupPath -Filter "*.7z" | Sort-Object CreationTime -Descending
    
    if ($allBackups.Count -gt 10) {
        $toDelete = $allBackups | Select-Object -Skip 10
        foreach ($oldBackup in $toDelete) {
            Remove-Item -Path $oldBackup.FullName -Force
            $infoFile = $oldBackup.FullName.Replace(".zip", ".json").Replace(".7z", ".json")
            if (Test-Path $infoFile) {
                Remove-Item -Path $infoFile -Force
            }
            Write-Log "Removed old backup: $($oldBackup.Name)"
        }
    }
    
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Backup failed: $_" -Level ERROR
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Backup failed: $_"
        Write-Host ""
        Write-Host "Check the backup log for details:"
        Write-Host $BackupLog
    }
    
    # Cleanup on failure
    if ($tempBackupPath -and (Test-Path $tempBackupPath)) {
        Remove-Item -Path $tempBackupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}