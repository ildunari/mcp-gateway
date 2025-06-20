# MCP Gateway Log Cleanup Script
# Manages log rotation, archival, and cleanup
# Author: MCP Gateway Team
# Version: 1.0.0

#Requires -Version 5.0

param(
    [string]$LogPath = "C:\Services\mcp-gateway\logs",
    [int]$RetentionDays = 30,
    [int]$ArchiveDays = 7,
    [int64]$MaxLogSizeMB = 1000,
    [switch]$Archive,
    [switch]$Compress,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Analyze,
    [string]$ArchivePath,
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
if (-not $Silent -and -not $Analyze) {
    Write-Info @"
==============================================================
            MCP Gateway Log Cleanup Utility v1.0              
==============================================================
"@
}

# Log file for cleanup operations
$CleanupLog = Join-Path $LogPath "cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Create log directory if it doesn't exist
    $logDir = Split-Path $CleanupLog -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $CleanupLog -Value $LogMessage -ErrorAction SilentlyContinue
    
    if (-not $Silent) {
        switch ($Level) {
            "SUCCESS" { Write-Success $Message }
            "INFO" { Write-Info $Message }
            "WARNING" { Write-Warning $Message }
            "ERROR" { Write-Error $Message }
            "DRY-RUN" { Write-Host "[DRY-RUN] $Message" -ForegroundColor Magenta }
            default { Write-Host $Message }
        }
    }
}

function Get-LogAnalysis {
    param([string]$Path)
    
    $analysis = @{
        TotalFiles = 0
        TotalSizeMB = 0
        FilesByType = @{}
        FilesByAge = @{
            Today = 0
            ThisWeek = 0
            ThisMonth = 0
            Older = 0
        }
        LargestFiles = @()
        OldestFiles = @()
        LogTypes = @{}
    }
    
    if (-not (Test-Path $Path)) {
        return $analysis
    }
    
    $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
    $analysis.TotalFiles = $files.Count
    
    $now = Get-Date
    $weekAgo = $now.AddDays(-7)
    $monthAgo = $now.AddDays(-30)
    
    foreach ($file in $files) {
        # Size analysis
        $sizeMB = $file.Length / 1MB
        $analysis.TotalSizeMB += $sizeMB
        
        # Type analysis
        $ext = $file.Extension.ToLower()
        if (-not $analysis.FilesByType.ContainsKey($ext)) {
            $analysis.FilesByType[$ext] = @{
                Count = 0
                SizeMB = 0
            }
        }
        $analysis.FilesByType[$ext].Count++
        $analysis.FilesByType[$ext].SizeMB += $sizeMB
        
        # Age analysis
        if ($file.LastWriteTime.Date -eq $now.Date) {
            $analysis.FilesByAge.Today++
        }
        elseif ($file.LastWriteTime -gt $weekAgo) {
            $analysis.FilesByAge.ThisWeek++
        }
        elseif ($file.LastWriteTime -gt $monthAgo) {
            $analysis.FilesByAge.ThisMonth++
        }
        else {
            $analysis.FilesByAge.Older++
        }
        
        # Log type analysis
        $logType = "Other"
        if ($file.Name -match "error") { $logType = "Error" }
        elseif ($file.Name -match "service") { $logType = "Service" }
        elseif ($file.Name -match "combined") { $logType = "Combined" }
        elseif ($file.Name -match "access") { $logType = "Access" }
        elseif ($file.Name -match "debug") { $logType = "Debug" }
        
        if (-not $analysis.LogTypes.ContainsKey($logType)) {
            $analysis.LogTypes[$logType] = @{
                Count = 0
                SizeMB = 0
            }
        }
        $analysis.LogTypes[$logType].Count++
        $analysis.LogTypes[$logType].SizeMB += $sizeMB
    }
    
    # Get largest and oldest files
    $analysis.LargestFiles = $files | Sort-Object Length -Descending | Select-Object -First 10 | ForEach-Object {
        @{
            Name = $_.Name
            SizeMB = [Math]::Round($_.Length / 1MB, 2)
            Path = $_.FullName
            Modified = $_.LastWriteTime
        }
    }
    
    $analysis.OldestFiles = $files | Sort-Object LastWriteTime | Select-Object -First 10 | ForEach-Object {
        @{
            Name = $_.Name
            Age = (New-TimeSpan -Start $_.LastWriteTime -End $now).Days
            SizeMB = [Math]::Round($_.Length / 1MB, 2)
            Path = $_.FullName
        }
    }
    
    return $analysis
}

function Show-Analysis {
    param($Analysis)
    
    Write-Info "Log Analysis Report"
    Write-Info "=================="
    Write-Host ""
    
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "  Total Files: $($Analysis.TotalFiles)"
    Write-Host "  Total Size: $([Math]::Round($Analysis.TotalSizeMB, 2)) MB"
    Write-Host ""
    
    Write-Host "Files by Age:" -ForegroundColor Yellow
    Write-Host "  Today: $($Analysis.FilesByAge.Today)"
    Write-Host "  This Week: $($Analysis.FilesByAge.ThisWeek)"
    Write-Host "  This Month: $($Analysis.FilesByAge.ThisMonth)"
    Write-Host "  Older: $($Analysis.FilesByAge.Older)"
    Write-Host ""
    
    Write-Host "Files by Type:" -ForegroundColor Yellow
    foreach ($type in $Analysis.FilesByType.Keys | Sort-Object) {
        $info = $Analysis.FilesByType[$type]
        Write-Host "  $type: $($info.Count) files, $([Math]::Round($info.SizeMB, 2)) MB"
    }
    Write-Host ""
    
    Write-Host "Log Types:" -ForegroundColor Yellow
    foreach ($type in $Analysis.LogTypes.Keys | Sort-Object) {
        $info = $Analysis.LogTypes[$type]
        Write-Host "  $type`: $($info.Count) files, $([Math]::Round($info.SizeMB, 2)) MB"
    }
    Write-Host ""
    
    if ($Analysis.LargestFiles.Count -gt 0) {
        Write-Host "Largest Files:" -ForegroundColor Yellow
        foreach ($file in $Analysis.LargestFiles | Select-Object -First 5) {
            Write-Host "  $($file.Name): $($file.SizeMB) MB"
        }
        Write-Host ""
    }
    
    if ($Analysis.OldestFiles.Count -gt 0) {
        Write-Host "Oldest Files:" -ForegroundColor Yellow
        foreach ($file in $Analysis.OldestFiles | Select-Object -First 5) {
            Write-Host "  $($file.Name): $($file.Age) days old"
        }
    }
}

function Compress-LogFile {
    param(
        [string]$FilePath,
        [string]$DestinationPath
    )
    
    try {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $timestamp = (Get-Item $FilePath).LastWriteTime.ToString("yyyyMMdd")
        $zipName = "$fileName-$timestamp.zip"
        $zipPath = Join-Path $DestinationPath $zipName
        
        # Create zip file
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
        
        # Create new zip or add to existing
        if (Test-Path $zipPath) {
            $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Update')
        }
        else {
            $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
        }
        
        try {
            $entryName = [System.IO.Path]::GetFileName($FilePath)
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $FilePath, $entryName, $compressionLevel)
            return $zipPath
        }
        finally {
            $zip.Dispose()
        }
    }
    catch {
        Write-Log "Failed to compress $FilePath`: $_" -Level ERROR
        return $null
    }
}

function Get-FilesToClean {
    param(
        [string]$Path,
        [int]$RetentionDays,
        [int]$ArchiveDays
    )
    
    $files = @{
        ToArchive = @()
        ToDelete = @()
        ToRotate = @()
    }
    
    if (-not (Test-Path $Path)) {
        return $files
    }
    
    $now = Get-Date
    $archiveDate = $now.AddDays(-$ArchiveDays)
    $deleteDate = $now.AddDays(-$RetentionDays)
    
    # Get all log files
    $logFiles = Get-ChildItem -Path $Path -File -Filter "*.log" -Recurse -ErrorAction SilentlyContinue
    
    foreach ($file in $logFiles) {
        # Skip the current cleanup log
        if ($file.FullName -eq $CleanupLog) {
            continue
        }
        
        # Skip already compressed files
        if ($file.Name -match "\.zip$|\.gz$|\.7z$") {
            continue
        }
        
        # Categorize by age
        if ($file.LastWriteTime -lt $deleteDate) {
            $files.ToDelete += $file
        }
        elseif ($file.LastWriteTime -lt $archiveDate) {
            $files.ToArchive += $file
        }
        
        # Check for rotation (files over 100MB)
        if ($file.Length -gt 100MB) {
            $files.ToRotate += $file
        }
    }
    
    # Also check for old archive files
    $archiveFiles = Get-ChildItem -Path $Path -File -Filter "*.zip" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $archiveFiles) {
        if ($file.LastWriteTime -lt $deleteDate) {
            $files.ToDelete += $file
        }
    }
    
    return $files
}

function Rotate-LogFile {
    param(
        [string]$FilePath
    )
    
    try {
        $file = Get-Item $FilePath
        $directory = $file.DirectoryName
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $extension = $file.Extension
        
        # Find next available rotation number
        $rotationNumber = 1
        while (Test-Path (Join-Path $directory "$baseName.$rotationNumber$extension")) {
            $rotationNumber++
        }
        
        $newName = "$baseName.$rotationNumber$extension"
        $newPath = Join-Path $directory $newName
        
        # Rename the file
        Move-Item -Path $FilePath -Destination $newPath -Force
        
        # Create new empty file
        New-Item -Path $FilePath -ItemType File -Force | Out-Null
        
        return $newPath
    }
    catch {
        Write-Log "Failed to rotate $FilePath`: $_" -Level ERROR
        return $null
    }
}

# Main cleanup process
try {
    Write-Log "Starting log cleanup process"
    Write-Log "Log Path: $LogPath"
    Write-Log "Retention Days: $RetentionDays"
    Write-Log "Archive Days: $ArchiveDays"
    Write-Log "Max Log Size: $MaxLogSizeMB MB"
    
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No files will be modified" -Level WARNING
    }
    
    # Validate log path
    if (-not (Test-Path $LogPath)) {
        throw "Log path not found: $LogPath"
    }
    
    # Perform analysis if requested
    if ($Analyze) {
        Write-Log "Performing log analysis"
        $analysis = Get-LogAnalysis -Path $LogPath
        Show-Analysis -Analysis $analysis
        
        if (-not $Force) {
            Write-Host ""
            $continue = Read-Host "Continue with cleanup? (Y/N)"
            if ($continue -ne "Y") {
                Write-Log "Cleanup cancelled by user" -Level WARNING
                exit 0
            }
        }
    }
    
    # Get files to process
    Write-Log "Scanning for files to process"
    $files = Get-FilesToClean -Path $LogPath -RetentionDays $RetentionDays -ArchiveDays $ArchiveDays
    
    Write-Log "Files to archive: $($files.ToArchive.Count)"
    Write-Log "Files to delete: $($files.ToDelete.Count)"
    Write-Log "Files to rotate: $($files.ToRotate.Count)"
    
    # Process rotations
    if ($files.ToRotate.Count -gt 0) {
        Write-Log "Processing file rotations"
        
        foreach ($file in $files.ToRotate) {
            $sizeMB = [Math]::Round($file.Length / 1MB, 2)
            Write-Log "Rotating large file: $($file.Name) ($sizeMB MB)"
            
            if (-not $DryRun) {
                $rotated = Rotate-LogFile -FilePath $file.FullName
                if ($rotated) {
                    Write-Log "Rotated to: $rotated" -Level SUCCESS
                }
            }
            else {
                Write-Log "Would rotate: $($file.Name)" -Level DRY-RUN
            }
        }
    }
    
    # Process archives
    if ($Archive -and $files.ToArchive.Count -gt 0) {
        Write-Log "Processing archives"
        
        # Determine archive path
        if (-not $ArchivePath) {
            $ArchivePath = Join-Path $LogPath "archive"
        }
        
        if (-not $DryRun -and -not (Test-Path $ArchivePath)) {
            New-Item -ItemType Directory -Path $ArchivePath -Force | Out-Null
        }
        
        $archivedCount = 0
        $archivedSizeMB = 0
        
        foreach ($file in $files.ToArchive) {
            $sizeMB = [Math]::Round($file.Length / 1MB, 2)
            
            if ($Compress) {
                Write-Log "Compressing: $($file.Name) ($sizeMB MB)"
                
                if (-not $DryRun) {
                    $zipPath = Compress-LogFile -FilePath $file.FullName -DestinationPath $ArchivePath
                    if ($zipPath) {
                        Remove-Item -Path $file.FullName -Force
                        Write-Log "Compressed to: $zipPath" -Level SUCCESS
                        $archivedCount++
                        $archivedSizeMB += $sizeMB
                    }
                }
                else {
                    Write-Log "Would compress: $($file.Name)" -Level DRY-RUN
                }
            }
            else {
                # Move to archive
                $archiveFilePath = Join-Path $ArchivePath $file.Name
                Write-Log "Archiving: $($file.Name) ($sizeMB MB)"
                
                if (-not $DryRun) {
                    Move-Item -Path $file.FullName -Destination $archiveFilePath -Force
                    Write-Log "Archived to: $archiveFilePath" -Level SUCCESS
                    $archivedCount++
                    $archivedSizeMB += $sizeMB
                }
                else {
                    Write-Log "Would archive: $($file.Name)" -Level DRY-RUN
                }
            }
        }
        
        if ($archivedCount -gt 0) {
            Write-Log "Archived $archivedCount files totaling $([Math]::Round($archivedSizeMB, 2)) MB" -Level SUCCESS
        }
    }
    
    # Process deletions
    if ($files.ToDelete.Count -gt 0) {
        Write-Log "Processing deletions"
        
        $deletedCount = 0
        $deletedSizeMB = 0
        
        foreach ($file in $files.ToDelete) {
            $sizeMB = [Math]::Round($file.Length / 1MB, 2)
            $age = (New-TimeSpan -Start $file.LastWriteTime -End (Get-Date)).Days
            
            Write-Log "Deleting: $($file.Name) ($sizeMB MB, $age days old)"
            
            if (-not $DryRun) {
                try {
                    Remove-Item -Path $file.FullName -Force
                    Write-Log "Deleted: $($file.Name)" -Level SUCCESS
                    $deletedCount++
                    $deletedSizeMB += $sizeMB
                }
                catch {
                    Write-Log "Failed to delete $($file.Name): $_" -Level ERROR
                }
            }
            else {
                Write-Log "Would delete: $($file.Name)" -Level DRY-RUN
            }
        }
        
        if ($deletedCount -gt 0) {
            Write-Log "Deleted $deletedCount files totaling $([Math]::Round($deletedSizeMB, 2)) MB" -Level SUCCESS
        }
    }
    
    # Check total log size
    $currentAnalysis = Get-LogAnalysis -Path $LogPath
    $totalSizeMB = $currentAnalysis.TotalSizeMB
    
    if ($totalSizeMB -gt $MaxLogSizeMB) {
        Write-Log "Total log size ($([Math]::Round($totalSizeMB, 2)) MB) exceeds limit ($MaxLogSizeMB MB)" -Level WARNING
        
        # Additional cleanup needed
        if (-not $DryRun -and $Force) {
            Write-Log "Performing aggressive cleanup"
            
            # Delete oldest files until under limit
            $allFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" -Recurse | 
                        Sort-Object LastWriteTime
            
            foreach ($file in $allFiles) {
                if ($totalSizeMB -le $MaxLogSizeMB) {
                    break
                }
                
                if ($file.FullName -ne $CleanupLog) {
                    $sizeMB = $file.Length / 1MB
                    Remove-Item -Path $file.FullName -Force
                    $totalSizeMB -= $sizeMB
                    Write-Log "Force deleted: $($file.Name) to meet size limit" -Level WARNING
                }
            }
        }
    }
    
    # Final summary
    Write-Log "="*60
    Write-Log "Cleanup completed successfully!" -Level SUCCESS
    Write-Log "="*60
    
    $finalAnalysis = Get-LogAnalysis -Path $LogPath
    Write-Log "Final Statistics:"
    Write-Log "  Total Files: $($finalAnalysis.TotalFiles)"
    Write-Log "  Total Size: $([Math]::Round($finalAnalysis.TotalSizeMB, 2)) MB"
    Write-Log "  Space Freed: $([Math]::Round($deletedSizeMB, 2)) MB"
    
    if (-not $Silent) {
        Write-Host ""
        Write-Success "Log cleanup completed!"
        Write-Host ""
        Write-Host "Cleanup log: $CleanupLog"
    }
    
    # Clean up old cleanup logs
    $oldCleanupLogs = Get-ChildItem -Path $LogPath -Filter "cleanup-*.log" | 
                      Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    
    foreach ($oldLog in $oldCleanupLogs) {
        Remove-Item -Path $oldLog.FullName -Force -ErrorAction SilentlyContinue
    }
    
}
catch {
    Write-Log "="*60 -Level ERROR
    Write-Log "Cleanup failed: $_" -Level ERROR
    Write-Log "="*60 -Level ERROR
    
    if (-not $Silent) {
        Write-Host ""
        Write-Error "Cleanup failed: $_"
        Write-Host ""
        Write-Host "Check the cleanup log for details:"
        Write-Host $CleanupLog
    }
    
    exit 1
}