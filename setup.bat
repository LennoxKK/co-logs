@echo off
setlocal enabledelayedexpansion
REM ==== INPUTS ====
set "ScriptName=%~1"
set "AliasName=%~2"
REM ==== CHECK FOR INPUT ====
if "%ScriptName%"=="" (
    echo ERROR: Missing script name.
    echo Usage: setup_alias.bat ScriptName AliasName
    exit /b 1
)
if "%AliasName%"=="" (
    echo ERROR: Missing alias name.
    echo Usage: setup_alias.bat ScriptName AliasName
    exit /b 1
)
REM ==== ADMIN CHECK ====
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: This script must be run as Administrator.
    pause
    exit /b 1
)
REM ==== CHECK IF SCRIPT EXISTS ====
set "ScriptPath=%CD%\%ScriptName%"
if not exist "%ScriptPath%" (
    echo ERROR: Script file "%ScriptName%" not found in current directory: %CD%
    exit /b 1
)
REM ==== ADD TO SYSTEM PATH ====
set "CurrentPath="
for /f "tokens=*" %%i in ('powershell -Command "[Environment]::GetEnvironmentVariable('Path', 'Machine')"') do set "CurrentPath=%%i"
echo Current PATH: !CurrentPath! | find /i "%CD%" >nul
if !errorlevel! equ 1 (
    echo Adding "%CD%" to system PATH...
    powershell -Command "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';%CD%', 'Machine')"
    echo Done.
) else (
    echo Current directory already in system PATH.
)
REM ==== GET POWERSHELL PROFILE PATH ====
for /f "delims=" %%a in ('powershell -NoProfile -Command "if (-not (Test-Path $PROFILE)) { $ProfileDir = Split-Path $PROFILE; if (-not (Test-Path $ProfileDir)) { New-Item -Path $ProfileDir -ItemType Directory -Force | Out-Null }; }; $PROFILE"') do set "ProfilePath=%%a"
REM ==== CREATE PROFILE IF NOT EXISTS ====
if not exist "%ProfilePath%" (
    echo Creating PowerShell profile at: "%ProfilePath%"
    powershell -Command "New-Item -ItemType File -Path $PROFILE -Force" >nul
)
REM ==== ADD ALIAS TO PROFILE ====
set "AliasLine=Set-Alias -Name %AliasName% -Value '%ScriptPath%'"
REM ==== CHECK IF ALIAS ALREADY EXISTS ====
powershell -Command "if (Select-String -Path $PROFILE -Pattern 'Set-Alias -Name %AliasName%' -Quiet) { exit 0 } else { exit 1 }" >nul 2>&1
if !errorlevel! equ 1 (
    echo Adding alias to profile...
    powershell -Command "Add-Content -Path $PROFILE -Value \"`nSet-Alias -Name %AliasName% -Value '%ScriptPath%'\"" 
    echo Alias added.
) else (
    echo Alias '%AliasName%' already exists in profile.
)
REM ==== BACKUP PROFILE ====
powershell -Command "Copy-Item -Path $PROFILE -Destination \"$PROFILE.bak\" -Force"
echo Backup created: "%ProfilePath%.bak"
REM ==== APPLY CHANGES IN CURRENT SESSION ====
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { . $PROFILE } catch { Write-Output 'Could not reload profile. Changes will take effect in new PowerShell sessions.' }"
echo PowerShell profile reloaded.
REM ==== VERIFY ALIAS ====
powershell -Command "try { Get-Command %AliasName% -ErrorAction Stop | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if !errorlevel! equ 1 (
    echo WARNING: Alias might not be immediately available. Try restarting PowerShell.
) else (
    echo ✅ Alias '%AliasName%' set successfully.
)
echo.
echo Setup complete!
echo You can now run '%AliasName%' from PowerShell to launch '%ScriptName%'.
echo Location: %ScriptPath%
echo Restart PowerShell if the alias isn't working right away.
endlocal