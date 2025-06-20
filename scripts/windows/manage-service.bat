@echo off
setlocal enabledelayedexpansion

:: MCP Gateway Service Management Script
:: Enterprise-grade service management for Windows
:: Author: MCP Gateway Team
:: Version: 1.0.0

:: Configuration
set SERVICE_NAME=MCPGateway
set SERVICE_DISPLAY_NAME=MCP Gateway Service
set NSSM_PATH=%~dp0nssm.exe
set PROJECT_PATH=%~dp0
set NODE_PATH=C:\Program Files\nodejs\node.exe
set SCRIPT_PATH=%PROJECT_PATH%src\server.js
set LOG_DIR=%PROJECT_PATH%logs
set CONFIG_DIR=%PROJECT_PATH%config
set ENV_FILE=%PROJECT_PATH%.env
set BACKUP_DIR=%PROJECT_PATH%backups

:: Colors for output
set RED=[91m
set GREEN=[92m
set YELLOW=[93m
set BLUE=[94m
set CYAN=[96m
set RESET=[0m

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%ERROR: This script requires administrator privileges.%RESET%
    echo.
    echo Please run as Administrator by:
    echo 1. Right-click on %~nx0
    echo 2. Select "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: Main menu
:MAIN_MENU
cls
echo %CYAN%==============================================================
echo                 MCP Gateway Service Manager v1.0              
echo ==============================================================%RESET%
echo.
echo %YELLOW%Current Status:%RESET%
call :CHECK_SERVICE_STATUS
echo.
echo %BLUE%Available Operations:%RESET%
echo.
echo   [1] Install Service
echo   [2] Uninstall Service
echo   [3] Start Service
echo   [4] Stop Service
echo   [5] Restart Service
echo   [6] Service Status (Detailed)
echo   [7] View Logs
echo   [8] Configuration Management
echo   [9] Backup and Restore
echo   [A] Advanced Options
echo   [X] Exit
echo.
set /p choice="Select an option: "

if /i "%choice%"=="1" goto INSTALL_SERVICE
if /i "%choice%"=="2" goto UNINSTALL_SERVICE
if /i "%choice%"=="3" goto START_SERVICE
if /i "%choice%"=="4" goto STOP_SERVICE
if /i "%choice%"=="5" goto RESTART_SERVICE
if /i "%choice%"=="6" goto DETAILED_STATUS
if /i "%choice%"=="7" goto VIEW_LOGS
if /i "%choice%"=="8" goto CONFIG_MENU
if /i "%choice%"=="9" goto BACKUP_MENU
if /i "%choice%"=="A" goto ADVANCED_MENU
if /i "%choice%"=="X" goto EXIT
echo %RED%Invalid option. Please try again.%RESET%
pause
goto MAIN_MENU

:: Install Service
:INSTALL_SERVICE
cls
echo %CYAN%Installing MCP Gateway Service...%RESET%
echo.

:: Check if NSSM exists
if not exist "%NSSM_PATH%" (
    echo %YELLOW%NSSM not found. Downloading...%RESET%
    call :DOWNLOAD_NSSM
    if errorlevel 1 (
        echo %RED%Failed to download NSSM. Please download manually from https://nssm.cc%RESET%
        pause
        goto MAIN_MENU
    )
)

:: Check if service already exists
"%NSSM_PATH%" status %SERVICE_NAME% >nul 2>&1
if %errorlevel% equ 0 (
    echo %RED%Service already exists. Please uninstall first.%RESET%
    pause
    goto MAIN_MENU
)

:: Create logs directory
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Install the service
echo Installing service...
"%NSSM_PATH%" install %SERVICE_NAME% "%NODE_PATH%" "%SCRIPT_PATH%"

:: Set service display name and description
"%NSSM_PATH%" set %SERVICE_NAME% DisplayName "%SERVICE_DISPLAY_NAME%"
"%NSSM_PATH%" set %SERVICE_NAME% Description "MCP Gateway - Unified gateway for Model Context Protocol servers"

:: Set working directory
"%NSSM_PATH%" set %SERVICE_NAME% AppDirectory "%PROJECT_PATH%"

:: Set environment variables
"%NSSM_PATH%" set %SERVICE_NAME% AppEnvironmentExtra "NODE_ENV=production"

:: Configure logging
"%NSSM_PATH%" set %SERVICE_NAME% AppStdout "%LOG_DIR%\service.log"
"%NSSM_PATH%" set %SERVICE_NAME% AppStderr "%LOG_DIR%\service-error.log"
"%NSSM_PATH%" set %SERVICE_NAME% AppRotateFiles 1
"%NSSM_PATH%" set %SERVICE_NAME% AppRotateBytes 10485760
"%NSSM_PATH%" set %SERVICE_NAME% AppRotateOnline 1

:: Set startup type
"%NSSM_PATH%" set %SERVICE_NAME% Start SERVICE_AUTO_START

:: Configure recovery options
"%NSSM_PATH%" set %SERVICE_NAME% AppRestartDelay 5000
"%NSSM_PATH%" set %SERVICE_NAME% AppThrottle 30000

:: Set dependencies (if needed)
"%NSSM_PATH%" set %SERVICE_NAME% DependOnService ""

echo.
echo %GREEN%Service installed successfully!%RESET%
echo.
echo Would you like to start the service now? (Y/N)
set /p startchoice=""
if /i "%startchoice%"=="Y" goto START_SERVICE
pause
goto MAIN_MENU

:: Uninstall Service
:UNINSTALL_SERVICE
cls
echo %CYAN%Uninstalling MCP Gateway Service...%RESET%
echo.
echo %YELLOW%WARNING: This will remove the service completely.%RESET%
echo.
echo Are you sure? (Y/N)
set /p confirm=""
if /i not "%confirm%"=="Y" goto MAIN_MENU

:: Stop service if running
"%NSSM_PATH%" stop %SERVICE_NAME% >nul 2>&1

:: Remove the service
"%NSSM_PATH%" remove %SERVICE_NAME% confirm
if %errorlevel% equ 0 (
    echo %GREEN%Service uninstalled successfully!%RESET%
) else (
    echo %RED%Failed to uninstall service.%RESET%
)
pause
goto MAIN_MENU

:: Start Service
:START_SERVICE
cls
echo %CYAN%Starting MCP Gateway Service...%RESET%
echo.
"%NSSM_PATH%" start %SERVICE_NAME%
if %errorlevel% equ 0 (
    echo %GREEN%Service started successfully!%RESET%
    timeout /t 3 /nobreak >nul
    call :CHECK_SERVICE_HEALTH
) else (
    echo %RED%Failed to start service.%RESET%
    echo.
    echo Checking logs for errors...
    timeout /t 2 /nobreak >nul
    call :SHOW_RECENT_ERRORS
)
pause
goto MAIN_MENU

:: Stop Service
:STOP_SERVICE
cls
echo %CYAN%Stopping MCP Gateway Service...%RESET%
echo.
"%NSSM_PATH%" stop %SERVICE_NAME%
if %errorlevel% equ 0 (
    echo %GREEN%Service stopped successfully!%RESET%
) else (
    echo %RED%Failed to stop service.%RESET%
)
pause
goto MAIN_MENU

:: Restart Service
:RESTART_SERVICE
cls
echo %CYAN%Restarting MCP Gateway Service...%RESET%
echo.
"%NSSM_PATH%" restart %SERVICE_NAME%
if %errorlevel% equ 0 (
    echo %GREEN%Service restarted successfully!%RESET%
    timeout /t 3 /nobreak >nul
    call :CHECK_SERVICE_HEALTH
) else (
    echo %RED%Failed to restart service.%RESET%
)
pause
goto MAIN_MENU

:: Detailed Status
:DETAILED_STATUS
cls
echo %CYAN%MCP Gateway Service - Detailed Status%RESET%
echo %CYAN%====================================%RESET%
echo.

:: Get service status
echo %YELLOW%Service Status:%RESET%
"%NSSM_PATH%" status %SERVICE_NAME%
echo.

:: Get service configuration
echo %YELLOW%Service Configuration:%RESET%
echo Application Path:
"%NSSM_PATH%" get %SERVICE_NAME% Application
echo.
echo Working Directory:
"%NSSM_PATH%" get %SERVICE_NAME% AppDirectory
echo.
echo Environment:
"%NSSM_PATH%" get %SERVICE_NAME% AppEnvironmentExtra
echo.

:: Get process information if running
for /f "tokens=2" %%i in ('tasklist /fi "imagename eq node.exe" /fi "windowtitle eq Administrator:  %SERVICE_NAME%" /fo list 2^>nul ^| find "PID:"') do set PID=%%i
if defined PID (
    echo %YELLOW%Process Information:%RESET%
    echo PID: %PID%
    wmic process where ProcessId=%PID% get WorkingSetSize,PageFileUsage,HandleCount /format:list 2>nul
)

:: Check port availability
echo %YELLOW%Port Status:%RESET%
netstat -an | findstr :4242
echo.

:: Check gateway health
call :CHECK_SERVICE_HEALTH

pause
goto MAIN_MENU

:: View Logs Menu
:VIEW_LOGS
cls
echo %CYAN%Log Viewer%RESET%
echo %CYAN%==========%RESET%
echo.
echo [1] View Service Log (Last 50 lines)
echo [2] View Error Log (Last 50 lines)
echo [3] View Combined Log (Last 50 lines)
echo [4] Follow Service Log (Real-time)
echo [5] Follow Error Log (Real-time)
echo [6] Search Logs
echo [7] Clear Old Logs
echo [B] Back to Main Menu
echo.
set /p logchoice="Select an option: "

if "%logchoice%"=="1" goto VIEW_SERVICE_LOG
if "%logchoice%"=="2" goto VIEW_ERROR_LOG
if "%logchoice%"=="3" goto VIEW_COMBINED_LOG
if "%logchoice%"=="4" goto FOLLOW_SERVICE_LOG
if "%logchoice%"=="5" goto FOLLOW_ERROR_LOG
if "%logchoice%"=="6" goto SEARCH_LOGS
if "%logchoice%"=="7" goto CLEAR_OLD_LOGS
if /i "%logchoice%"=="B" goto MAIN_MENU
goto VIEW_LOGS

:VIEW_SERVICE_LOG
cls
echo %CYAN%Service Log (Last 50 lines):%RESET%
echo %CYAN%============================%RESET%
if exist "%LOG_DIR%\service.log" (
    powershell -command "Get-Content '%LOG_DIR%\service.log' -Tail 50"
) else (
    echo %YELLOW%No service log found.%RESET%
)
pause
goto VIEW_LOGS

:VIEW_ERROR_LOG
cls
echo %CYAN%Error Log (Last 50 lines):%RESET%
echo %CYAN%=========================%RESET%
if exist "%LOG_DIR%\service-error.log" (
    powershell -command "Get-Content '%LOG_DIR%\service-error.log' -Tail 50"
) else (
    echo %YELLOW%No error log found.%RESET%
)
pause
goto VIEW_LOGS

:VIEW_COMBINED_LOG
cls
echo %CYAN%Combined Log (Last 50 lines):%RESET%
echo %CYAN%============================%RESET%
if exist "%LOG_DIR%\combined.log" (
    powershell -command "Get-Content '%LOG_DIR%\combined.log' -Tail 50"
) else (
    echo %YELLOW%No combined log found.%RESET%
)
pause
goto VIEW_LOGS

:FOLLOW_SERVICE_LOG
cls
echo %CYAN%Following Service Log (Press Ctrl+C to stop):%RESET%
echo %CYAN%============================================%RESET%
if exist "%LOG_DIR%\service.log" (
    powershell -command "Get-Content '%LOG_DIR%\service.log' -Wait -Tail 10"
) else (
    echo %YELLOW%No service log found.%RESET%
    pause
)
goto VIEW_LOGS

:FOLLOW_ERROR_LOG
cls
echo %CYAN%Following Error Log (Press Ctrl+C to stop):%RESET%
echo %CYAN%==========================================%RESET%
if exist "%LOG_DIR%\service-error.log" (
    powershell -command "Get-Content '%LOG_DIR%\service-error.log' -Wait -Tail 10"
) else (
    echo %YELLOW%No error log found.%RESET%
    pause
)
goto VIEW_LOGS

:SEARCH_LOGS
cls
set /p searchterm="Enter search term: "
echo.
echo %CYAN%Searching for "%searchterm%" in all logs...%RESET%
echo %CYAN%=========================================%RESET%
echo.
findstr /i /c:"%searchterm%" "%LOG_DIR%\*.log" 2>nul
if %errorlevel% neq 0 (
    echo %YELLOW%No matches found.%RESET%
)
pause
goto VIEW_LOGS

:CLEAR_OLD_LOGS
cls
echo %YELLOW%WARNING: This will archive logs older than 7 days.%RESET%
echo.
set /p confirmclear="Are you sure? (Y/N): "
if /i not "%confirmclear%"=="Y" goto VIEW_LOGS

:: Create archive directory
set ARCHIVE_DIR=%LOG_DIR%\archive\%date:~-4%%date:~4,2%%date:~7,2%
if not exist "%ARCHIVE_DIR%" mkdir "%ARCHIVE_DIR%"

:: Archive old logs
forfiles /p "%LOG_DIR%" /m *.log /d -7 /c "cmd /c move @path \"%ARCHIVE_DIR%\"" 2>nul

echo %GREEN%Old logs archived to %ARCHIVE_DIR%%RESET%
pause
goto VIEW_LOGS

:: Configuration Menu
:CONFIG_MENU
cls
echo %CYAN%Configuration Management%RESET%
echo %CYAN%======================%RESET%
echo.
echo [1] View Current Configuration
echo [2] Edit Environment Variables
echo [3] Validate Configuration
echo [4] Update Service Configuration
echo [5] Test Configuration
echo [B] Back to Main Menu
echo.
set /p configchoice="Select an option: "

if "%configchoice%"=="1" goto VIEW_CONFIG
if "%configchoice%"=="2" goto EDIT_ENV
if "%configchoice%"=="3" goto VALIDATE_CONFIG
if "%configchoice%"=="4" goto UPDATE_SERVICE_CONFIG
if "%configchoice%"=="5" goto TEST_CONFIG
if /i "%configchoice%"=="B" goto MAIN_MENU
goto CONFIG_MENU

:VIEW_CONFIG
cls
echo %CYAN%Current Configuration:%RESET%
echo %CYAN%====================%RESET%
echo.
echo %YELLOW%.env file:%RESET%
if exist "%ENV_FILE%" (
    type "%ENV_FILE%" | findstr /v "TOKEN\|SECRET\|PASSWORD" || echo %YELLOW%No non-sensitive configuration found.%RESET%
) else (
    echo %RED%.env file not found!%RESET%
)
echo.
echo %YELLOW%servers.json:%RESET%
if exist "%CONFIG_DIR%\servers.json" (
    type "%CONFIG_DIR%\servers.json"
) else (
    echo %RED%servers.json not found!%RESET%
)
pause
goto CONFIG_MENU

:EDIT_ENV
cls
echo %CYAN%Edit Environment Variables%RESET%
echo %CYAN%========================%RESET%
echo.
echo Opening .env file in Notepad...
if exist "%ENV_FILE%" (
    notepad "%ENV_FILE%"
) else (
    echo %RED%.env file not found!%RESET%
    echo.
    echo Would you like to create it from .env.example? (Y/N)
    set /p createenv=""
    if /i "%createenv%"=="Y" (
        if exist "%PROJECT_PATH%.env.example" (
            copy "%PROJECT_PATH%.env.example" "%ENV_FILE%"
            notepad "%ENV_FILE%"
        ) else (
            echo %RED%.env.example not found!%RESET%
        )
    )
)
pause
goto CONFIG_MENU

:VALIDATE_CONFIG
cls
echo %CYAN%Validating Configuration...%RESET%
echo %CYAN%=========================%RESET%
echo.

set VALID=1

:: Check .env file
echo Checking .env file...
if exist "%ENV_FILE%" (
    echo %GREEN%✓ .env file exists%RESET%
    
    :: Check for required variables
    findstr /c:"PORT=" "%ENV_FILE%" >nul || (echo %RED%✗ PORT not configured%RESET% & set VALID=0)
    findstr /c:"GATEWAY_AUTH_TOKEN=" "%ENV_FILE%" >nul || (echo %RED%✗ GATEWAY_AUTH_TOKEN not configured%RESET% & set VALID=0)
    findstr /c:"NODE_ENV=" "%ENV_FILE%" >nul || (echo %YELLOW%! NODE_ENV not configured (will use default)%RESET%)
) else (
    echo %RED%✗ .env file missing%RESET%
    set VALID=0
)

echo.
echo Checking servers.json...
if exist "%CONFIG_DIR%\servers.json" (
    echo %GREEN%✓ servers.json exists%RESET%
    
    :: Validate JSON syntax
    powershell -command "try { Get-Content '%CONFIG_DIR%\servers.json' | ConvertFrom-Json | Out-Null; Write-Host '✓ Valid JSON syntax' -ForegroundColor Green } catch { Write-Host '✗ Invalid JSON syntax' -ForegroundColor Red; exit 1 }"
    if %errorlevel% neq 0 set VALID=0
) else (
    echo %RED%✗ servers.json missing%RESET%
    set VALID=0
)

echo.
echo Checking Node.js...
if exist "%NODE_PATH%" (
    echo %GREEN%✓ Node.js found%RESET%
    "%NODE_PATH%" --version
) else (
    echo %RED%✗ Node.js not found at %NODE_PATH%%RESET%
    set VALID=0
)

echo.
echo Checking main script...
if exist "%SCRIPT_PATH%" (
    echo %GREEN%✓ server.js found%RESET%
) else (
    echo %RED%✗ server.js missing%RESET%
    set VALID=0
)

echo.
if %VALID% equ 1 (
    echo %GREEN%Configuration is valid!%RESET%
) else (
    echo %RED%Configuration has errors. Please fix them before starting the service.%RESET%
)

pause
goto CONFIG_MENU

:UPDATE_SERVICE_CONFIG
cls
echo %CYAN%Update Service Configuration%RESET%
echo %CYAN%==========================%RESET%
echo.
echo This will update the service configuration with current settings.
echo.
set /p confirmupdate="Continue? (Y/N): "
if /i not "%confirmupdate%"=="Y" goto CONFIG_MENU

:: Update environment
"%NSSM_PATH%" set %SERVICE_NAME% AppEnvironmentExtra "NODE_ENV=production"

:: Update paths if needed
"%NSSM_PATH%" set %SERVICE_NAME% Application "%NODE_PATH%"
"%NSSM_PATH%" set %SERVICE_NAME% AppParameters "%SCRIPT_PATH%"
"%NSSM_PATH%" set %SERVICE_NAME% AppDirectory "%PROJECT_PATH%"

echo.
echo %GREEN%Service configuration updated!%RESET%
echo.
echo %YELLOW%Note: You may need to restart the service for changes to take effect.%RESET%
pause
goto CONFIG_MENU

:TEST_CONFIG
cls
echo %CYAN%Testing Configuration...%RESET%
echo %CYAN%======================%RESET%
echo.
echo Starting gateway in test mode...
echo.
cd /d "%PROJECT_PATH%"
"%NODE_PATH%" "%SCRIPT_PATH%"
pause
goto CONFIG_MENU

:: Backup and Restore Menu
:BACKUP_MENU
cls
echo %CYAN%Backup and Restore%RESET%
echo %CYAN%=================%RESET%
echo.
echo [1] Create Backup
echo [2] Restore from Backup
echo [3] List Backups
echo [4] Delete Old Backups
echo [5] Schedule Automatic Backups
echo [B] Back to Main Menu
echo.
set /p backupchoice="Select an option: "

if "%backupchoice%"=="1" goto CREATE_BACKUP
if "%backupchoice%"=="2" goto RESTORE_BACKUP
if "%backupchoice%"=="3" goto LIST_BACKUPS
if "%backupchoice%"=="4" goto DELETE_OLD_BACKUPS
if "%backupchoice%"=="5" goto SCHEDULE_BACKUPS
if /i "%backupchoice%"=="B" goto MAIN_MENU
goto BACKUP_MENU

:CREATE_BACKUP
cls
echo %CYAN%Creating Backup...%RESET%
echo %CYAN%================%RESET%
echo.

:: Create backup directory
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

:: Create timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set timestamp=%datetime:~0,8%_%datetime:~8,6%

:: Create backup folder
set CURRENT_BACKUP=%BACKUP_DIR%\backup_%timestamp%
mkdir "%CURRENT_BACKUP%"

:: Backup files
echo Backing up configuration files...
if exist "%ENV_FILE%" copy "%ENV_FILE%" "%CURRENT_BACKUP%\.env" >nul
if exist "%CONFIG_DIR%\servers.json" copy "%CONFIG_DIR%\servers.json" "%CURRENT_BACKUP%\servers.json" >nul

:: Backup service configuration
echo Backing up service configuration...
"%NSSM_PATH%" dump %SERVICE_NAME% > "%CURRENT_BACKUP%\service-config.txt" 2>nul

:: Create backup info
echo Backup created on %date% %time% > "%CURRENT_BACKUP%\backup-info.txt"
echo Service Status: >> "%CURRENT_BACKUP%\backup-info.txt"
"%NSSM_PATH%" status %SERVICE_NAME% >> "%CURRENT_BACKUP%\backup-info.txt" 2>nul

echo.
echo %GREEN%Backup created successfully!%RESET%
echo Location: %CURRENT_BACKUP%
pause
goto BACKUP_MENU

:RESTORE_BACKUP
cls
echo %CYAN%Available Backups:%RESET%
echo %CYAN%=================%RESET%
echo.

:: List backups
set /a count=0
for /d %%D in ("%BACKUP_DIR%\backup_*") do (
    set /a count+=1
    echo [!count!] %%~nxD
    set "backup!count!=%%D"
)

if %count% equ 0 (
    echo %YELLOW%No backups found.%RESET%
    pause
    goto BACKUP_MENU
)

echo.
set /p backupnum="Select backup to restore (1-%count%): "

:: Validate selection
if !backupnum! lss 1 goto RESTORE_BACKUP
if !backupnum! gtr %count% goto RESTORE_BACKUP

set SELECTED_BACKUP=!backup%backupnum%!

echo.
echo %YELLOW%WARNING: This will overwrite current configuration!%RESET%
echo Restoring from: %SELECTED_BACKUP%
echo.
set /p confirmrestore="Continue? (Y/N): "
if /i not "%confirmrestore%"=="Y" goto BACKUP_MENU

:: Stop service if running
echo Stopping service...
"%NSSM_PATH%" stop %SERVICE_NAME% >nul 2>&1

:: Restore files
echo Restoring configuration files...
if exist "%SELECTED_BACKUP%\.env" copy "%SELECTED_BACKUP%\.env" "%ENV_FILE%" >nul
if exist "%SELECTED_BACKUP%\servers.json" copy "%SELECTED_BACKUP%\servers.json" "%CONFIG_DIR%\servers.json" >nul

echo.
echo %GREEN%Restore completed!%RESET%
echo.
echo Would you like to start the service? (Y/N)
set /p startafterrestore=""
if /i "%startafterrestore%"=="Y" goto START_SERVICE
pause
goto BACKUP_MENU

:LIST_BACKUPS
cls
echo %CYAN%Backup List:%RESET%
echo %CYAN%===========%RESET%
echo.

if not exist "%BACKUP_DIR%" (
    echo %YELLOW%No backup directory found.%RESET%
    pause
    goto BACKUP_MENU
)

for /d %%D in ("%BACKUP_DIR%\backup_*") do (
    echo Backup: %%~nxD
    if exist "%%D\backup-info.txt" (
        type "%%D\backup-info.txt"
    )
    
    :: Calculate size
    set size=0
    for /r "%%D" %%F in (*) do set /a size+=%%~zF
    set /a size_kb=!size!/1024
    echo Size: !size_kb! KB
    echo.
)

pause
goto BACKUP_MENU

:DELETE_OLD_BACKUPS
cls
echo %CYAN%Delete Old Backups%RESET%
echo %CYAN%=================%RESET%
echo.
echo How many days of backups to keep?
set /p daystokeep="Days to keep (default 30): "
if "%daystokeep%"=="" set daystokeep=30

echo.
echo %YELLOW%This will delete backups older than %daystokeep% days.%RESET%
set /p confirmdelete="Continue? (Y/N): "
if /i not "%confirmdelete%"=="Y" goto BACKUP_MENU

:: Delete old backups
forfiles /p "%BACKUP_DIR%" /d -%daystokeep% /c "cmd /c if @isdir==TRUE rmdir /s /q @path" 2>nul

echo %GREEN%Old backups deleted.%RESET%
pause
goto BACKUP_MENU

:SCHEDULE_BACKUPS
cls
echo %CYAN%Schedule Automatic Backups%RESET%
echo %CYAN%========================%RESET%
echo.
echo Creating scheduled task for daily backups...
echo.

:: Create backup script
echo @echo off > "%PROJECT_PATH%auto-backup.bat"
echo cd /d "%PROJECT_PATH%" >> "%PROJECT_PATH%auto-backup.bat"
echo call manage-service.bat CREATE_BACKUP_SILENT >> "%PROJECT_PATH%auto-backup.bat"

:: Create scheduled task
schtasks /create /tn "MCP Gateway Backup" /tr "\"%PROJECT_PATH%auto-backup.bat\"" /sc daily /st 02:00 /f

if %errorlevel% equ 0 (
    echo %GREEN%Scheduled task created successfully!%RESET%
    echo Backups will run daily at 2:00 AM
) else (
    echo %RED%Failed to create scheduled task.%RESET%
)

pause
goto BACKUP_MENU

:: Advanced Menu
:ADVANCED_MENU
cls
echo %CYAN%Advanced Options%RESET%
echo %CYAN%===============%RESET%
echo.
echo [1] Service Recovery Settings
echo [2] Performance Tuning
echo [3] Security Settings
echo [4] Diagnostic Mode
echo [5] Export Service Configuration
echo [6] Import Service Configuration
echo [7] Check Dependencies
echo [8] Network Diagnostics
echo [B] Back to Main Menu
echo.
set /p advchoice="Select an option: "

if "%advchoice%"=="1" goto RECOVERY_SETTINGS
if "%advchoice%"=="2" goto PERFORMANCE_TUNING
if "%advchoice%"=="3" goto SECURITY_SETTINGS
if "%advchoice%"=="4" goto DIAGNOSTIC_MODE
if "%advchoice%"=="5" goto EXPORT_CONFIG
if "%advchoice%"=="6" goto IMPORT_CONFIG
if "%advchoice%"=="7" goto CHECK_DEPENDENCIES
if "%advchoice%"=="8" goto NETWORK_DIAGNOSTICS
if /i "%advchoice%"=="B" goto MAIN_MENU
goto ADVANCED_MENU

:RECOVERY_SETTINGS
cls
echo %CYAN%Service Recovery Settings%RESET%
echo %CYAN%========================%RESET%
echo.

echo Current settings:
"%NSSM_PATH%" get %SERVICE_NAME% AppRestartDelay
"%NSSM_PATH%" get %SERVICE_NAME% AppThrottle
echo.

echo Configure automatic restart on failure:
echo [1] Enable with 5 second delay
echo [2] Enable with 30 second delay
echo [3] Enable with 60 second delay
echo [4] Disable automatic restart
echo [B] Back
echo.
set /p recoverychoice="Select option: "

if "%recoverychoice%"=="1" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppRestartDelay 5000
    "%NSSM_PATH%" set %SERVICE_NAME% AppThrottle 30000
    echo %GREEN%Recovery configured: 5 second restart delay%RESET%
)
if "%recoverychoice%"=="2" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppRestartDelay 30000
    "%NSSM_PATH%" set %SERVICE_NAME% AppThrottle 60000
    echo %GREEN%Recovery configured: 30 second restart delay%RESET%
)
if "%recoverychoice%"=="3" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppRestartDelay 60000
    "%NSSM_PATH%" set %SERVICE_NAME% AppThrottle 120000
    echo %GREEN%Recovery configured: 60 second restart delay%RESET%
)
if "%recoverychoice%"=="4" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppRestartDelay 0
    echo %GREEN%Automatic restart disabled%RESET%
)

pause
goto ADVANCED_MENU

:PERFORMANCE_TUNING
cls
echo %CYAN%Performance Tuning%RESET%
echo %CYAN%=================%RESET%
echo.

echo Configure Node.js performance settings:
echo.
echo [1] Standard (Default)
echo [2] High Performance (More memory)
echo [3] Low Resource (Limited memory)
echo [4] Custom Settings
echo [B] Back
echo.
set /p perfchoice="Select option: "

if "%perfchoice%"=="1" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppParameters "%SCRIPT_PATH%"
    echo %GREEN%Standard performance settings applied%RESET%
)
if "%perfchoice%"=="2" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppParameters "--max-old-space-size=4096 %SCRIPT_PATH%"
    echo %GREEN%High performance settings applied (4GB heap)%RESET%
)
if "%perfchoice%"=="3" (
    "%NSSM_PATH%" set %SERVICE_NAME% AppParameters "--max-old-space-size=512 %SCRIPT_PATH%"
    echo %GREEN%Low resource settings applied (512MB heap)%RESET%
)
if "%perfchoice%"=="4" (
    set /p custommem="Enter max heap size in MB: "
    "%NSSM_PATH%" set %SERVICE_NAME% AppParameters "--max-old-space-size=!custommem! %SCRIPT_PATH%"
    echo %GREEN%Custom settings applied (!custommem!MB heap)%RESET%
)

pause
goto ADVANCED_MENU

:SECURITY_SETTINGS
cls
echo %CYAN%Security Settings%RESET%
echo %CYAN%================%RESET%
echo.

echo [1] Check file permissions
echo [2] Verify authentication tokens
echo [3] Review allowed paths
echo [4] Generate new auth token
echo [5] Check HTTPS/TLS settings
echo [B] Back
echo.
set /p secchoice="Select option: "

if "%secchoice%"=="1" (
    echo.
    echo Checking file permissions...
    icacls "%PROJECT_PATH%" /t /q
    echo.
    echo %YELLOW%Ensure only authorized users have access to the project directory.%RESET%
    pause
)
if "%secchoice%"=="2" (
    echo.
    echo Checking authentication tokens...
    if exist "%ENV_FILE%" (
        findstr /c:"GATEWAY_AUTH_TOKEN=" "%ENV_FILE%" >nul
        if %errorlevel% equ 0 (
            echo %GREEN%✓ Gateway auth token is configured%RESET%
        ) else (
            echo %RED%✗ Gateway auth token not found%RESET%
        )
        findstr /c:"GITHUB_TOKEN=" "%ENV_FILE%" >nul
        if %errorlevel% equ 0 (
            echo %GREEN%✓ GitHub token is configured%RESET%
        ) else (
            echo %YELLOW%! GitHub token not configured%RESET%
        )
    ) else (
        echo %RED%✗ .env file not found%RESET%
    )
    pause
)
if "%secchoice%"=="3" (
    echo.
    echo Reviewing allowed paths...
    if exist "%ENV_FILE%" (
        findstr /c:"DESKTOP_ALLOWED_PATHS=" "%ENV_FILE%"
    ) else (
        echo %RED%.env file not found%RESET%
    )
    pause
)
if "%secchoice%"=="4" (
    echo.
    echo Generating new authentication token...
    powershell -command "[System.Web.Security.Membership]::GeneratePassword(32,8)"
    echo.
    echo %YELLOW%Copy this token and update GATEWAY_AUTH_TOKEN in .env%RESET%
    pause
)
if "%secchoice%"=="5" (
    echo.
    echo HTTPS/TLS Configuration:
    echo - Gateway runs behind Cloudflare tunnel (automatic HTTPS)
    echo - Local service listens on HTTP (port 4242)
    echo - All external traffic is encrypted by Cloudflare
    echo.
    echo %GREEN%✓ HTTPS is handled by Cloudflare tunnel%RESET%
    pause
)

goto ADVANCED_MENU

:DIAGNOSTIC_MODE
cls
echo %CYAN%Diagnostic Mode%RESET%
echo %CYAN%==============%RESET%
echo.
echo This will start the service in diagnostic mode with verbose logging.
echo.
set /p diagconfirm="Continue? (Y/N): "
if /i not "%diagconfirm%"=="Y" goto ADVANCED_MENU

:: Stop service if running
"%NSSM_PATH%" stop %SERVICE_NAME% >nul 2>&1

:: Start in diagnostic mode
echo Starting gateway with diagnostic logging...
echo.
cd /d "%PROJECT_PATH%"
set NODE_ENV=development
set LOG_LEVEL=debug
"%NODE_PATH%" "%SCRIPT_PATH%"
pause
goto ADVANCED_MENU

:EXPORT_CONFIG
cls
echo %CYAN%Export Service Configuration%RESET%
echo %CYAN%==========================%RESET%
echo.

set EXPORT_FILE=%PROJECT_PATH%service-config-export.txt
echo Exporting configuration to %EXPORT_FILE%...
echo.

echo MCP Gateway Service Configuration Export > "%EXPORT_FILE%"
echo ======================================= >> "%EXPORT_FILE%"
echo Export Date: %date% %time% >> "%EXPORT_FILE%"
echo. >> "%EXPORT_FILE%"

"%NSSM_PATH%" dump %SERVICE_NAME% >> "%EXPORT_FILE%" 2>nul

echo %GREEN%Configuration exported successfully!%RESET%
echo File: %EXPORT_FILE%
pause
goto ADVANCED_MENU

:IMPORT_CONFIG
cls
echo %CYAN%Import Service Configuration%RESET%
echo %CYAN%==========================%RESET%
echo.
echo %YELLOW%This feature is for advanced users only!%RESET%
echo.
echo Place your configuration file at:
echo %PROJECT_PATH%service-config-import.txt
echo.
echo Then restart this script and try again.
pause
goto ADVANCED_MENU

:CHECK_DEPENDENCIES
cls
echo %CYAN%Checking Dependencies...%RESET%
echo %CYAN%======================%RESET%
echo.

echo Node.js:
where node >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node --version') do echo %GREEN%✓ Found %%i%RESET%
) else (
    echo %RED%✗ Not found in PATH%RESET%
)

echo.
echo NPM:
where npm >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('npm --version') do echo %GREEN%✓ Found v%%i%RESET%
) else (
    echo %RED%✗ Not found in PATH%RESET%
)

echo.
echo NPX:
where npx >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('npx --version') do echo %GREEN%✓ Found v%%i%RESET%
) else (
    echo %RED%✗ Not found in PATH%RESET%
)

echo.
echo Cloudflare Tunnel:
where cloudflared >nul 2>&1
if %errorlevel% equ 0 (
    echo %GREEN%✓ Found%RESET%
    cloudflared --version
) else (
    echo %YELLOW%! Not found in PATH (optional)%RESET%
)

echo.
echo Project Dependencies:
if exist "%PROJECT_PATH%node_modules" (
    echo %GREEN%✓ node_modules exists%RESET%
    dir /b "%PROJECT_PATH%node_modules" | find /c /v "" > temp.txt
    set /p modulecount=<temp.txt
    del temp.txt
    echo   !modulecount! packages installed
) else (
    echo %RED%✗ node_modules not found%RESET%
    echo   Run 'npm install' to install dependencies
)

pause
goto ADVANCED_MENU

:NETWORK_DIAGNOSTICS
cls
echo %CYAN%Network Diagnostics%RESET%
echo %CYAN%==================%RESET%
echo.

echo Checking port 4242...
netstat -an | findstr :4242 >nul
if %errorlevel% equ 0 (
    echo %GREEN%✓ Port 4242 is in use%RESET%
    netstat -an | findstr :4242
) else (
    echo %YELLOW%! Port 4242 is not in use%RESET%
)

echo.
echo Testing localhost connection...
powershell -command "try { Invoke-WebRequest -Uri 'http://localhost:4242/health' -Method GET -TimeoutSec 5 | Select-Object -ExpandProperty StatusCode | ForEach-Object { Write-Host \"✓ Health check returned $_\" -ForegroundColor Green } } catch { Write-Host \"✗ Cannot connect to localhost:4242\" -ForegroundColor Red }"

echo.
echo Testing gateway URL (if configured)...
powershell -command "try { Invoke-WebRequest -Uri 'https://gateway.pluginpapi.dev/health' -Method GET -TimeoutSec 5 | Select-Object -ExpandProperty StatusCode | ForEach-Object { Write-Host \"✓ Gateway health check returned $_\" -ForegroundColor Green } } catch { Write-Host \"✗ Cannot connect to gateway.pluginpapi.dev\" -ForegroundColor Yellow; Write-Host \"  This is normal if Cloudflare tunnel is not running\" -ForegroundColor Yellow }"

echo.
echo Active network connections on port 4242:
netstat -an | findstr :4242

pause
goto ADVANCED_MENU

:: Helper Functions

:CHECK_SERVICE_STATUS
"%NSSM_PATH%" status %SERVICE_NAME% >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('"%NSSM_PATH%" status %SERVICE_NAME% 2^>nul') do set status=%%i
    if "!status!"=="SERVICE_RUNNING" (
        echo   Status: %GREEN%RUNNING%RESET%
    ) else if "!status!"=="SERVICE_STOPPED" (
        echo   Status: %YELLOW%STOPPED%RESET%
    ) else if "!status!"=="SERVICE_PAUSED" (
        echo   Status: %YELLOW%PAUSED%RESET%
    ) else (
        echo   Status: %RED%!status!%RESET%
    )
) else (
    echo   Status: %RED%NOT INSTALLED%RESET%
)
goto :eof

:CHECK_SERVICE_HEALTH
echo.
echo Checking service health...
timeout /t 2 /nobreak >nul
powershell -command "try { $response = Invoke-WebRequest -Uri 'http://localhost:4242/health' -Method GET -TimeoutSec 5; $json = $response.Content | ConvertFrom-Json; Write-Host 'Health Status:' $json.status -ForegroundColor Green; Write-Host 'Environment:' $json.environment; Write-Host 'Timestamp:' $json.timestamp; Write-Host 'Servers:' ($json.servers.Count) 'configured' } catch { Write-Host 'Health check failed:' $_.Exception.Message -ForegroundColor Red }"
goto :eof

:SHOW_RECENT_ERRORS
if exist "%LOG_DIR%\service-error.log" (
    echo.
    echo Recent errors:
    echo ==============
    powershell -command "Get-Content '%LOG_DIR%\service-error.log' -Tail 10"
)
if exist "%LOG_DIR%\combined.log" (
    echo.
    echo Recent combined log entries:
    echo ===========================
    powershell -command "Get-Content '%LOG_DIR%\combined.log' -Tail 10 | Select-String -Pattern 'error|ERROR|Error' -Context 1,1"
)
goto :eof

:DOWNLOAD_NSSM
echo Downloading NSSM...
powershell -command "Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile '%TEMP%\nssm.zip'"
if not exist "%TEMP%\nssm.zip" exit /b 1

echo Extracting NSSM...
powershell -command "Expand-Archive -Path '%TEMP%\nssm.zip' -DestinationPath '%TEMP%\nssm' -Force"

:: Copy appropriate version
if exist "%TEMP%\nssm\nssm-2.24\win64\nssm.exe" (
    copy "%TEMP%\nssm\nssm-2.24\win64\nssm.exe" "%NSSM_PATH%"
) else if exist "%TEMP%\nssm\nssm-2.24\win32\nssm.exe" (
    copy "%TEMP%\nssm\nssm-2.24\win32\nssm.exe" "%NSSM_PATH%"
)

:: Cleanup
del "%TEMP%\nssm.zip"
rmdir /s /q "%TEMP%\nssm"

if exist "%NSSM_PATH%" (
    echo %GREEN%NSSM downloaded successfully!%RESET%
    exit /b 0
) else (
    exit /b 1
)

:CREATE_BACKUP_SILENT
:: Silent backup for scheduled tasks
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set timestamp=%datetime:~0,8%_%datetime:~8,6%
set CURRENT_BACKUP=%BACKUP_DIR%\backup_%timestamp%
mkdir "%CURRENT_BACKUP%"
if exist "%ENV_FILE%" copy "%ENV_FILE%" "%CURRENT_BACKUP%\.env" >nul
if exist "%CONFIG_DIR%\servers.json" copy "%CONFIG_DIR%\servers.json" "%CURRENT_BACKUP%\servers.json" >nul
"%NSSM_PATH%" dump %SERVICE_NAME% > "%CURRENT_BACKUP%\service-config.txt" 2>nul
echo Backup created on %date% %time% > "%CURRENT_BACKUP%\backup-info.txt"
goto :eof

:EXIT
cls
echo %CYAN%Thank you for using MCP Gateway Service Manager!%RESET%
echo.
timeout /t 2 /nobreak >nul
exit /b 0