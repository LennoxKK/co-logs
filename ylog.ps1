# =====================================================================
# ylog_pull.ps1
# =====================================================================
# <DESCRIPTION>
# Tool: Android YLog Pull Tool
# Version: 1.0
# Author: Claude
# Date: April 7, 2025
# Purpose: Pull YLog data from Android device for analysis
# Requirements: ADB (Android Debug Bridge), PowerShell 5.0+
# Usage: ./ylog_pull.ps1 [destination_directory]
# Features: 
#   - Automated extraction of YLog debug logs
#   - Support for various Android versions
#   - Optional destination parameter
#   - Error handling with detailed feedback
# </DESCRIPTION>
# =====================================================================

param (
    [string]$DestinationDir = (Get-Location).Path
)

# Set title and clear screen
$Host.UI.RawUI.WindowTitle = "Android YLog Pull Tool"
Clear-Host
Write-Host " Android YLog Pull Tool " -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ""

# Check for ADB
Write-Host " > Checking ADB availability..." -ForegroundColor Yellow
try {
    $adbVersion = adb version 2>$null
    if (-not $?) {
        throw "ADB command failed or not found"
    }
    Write-Host " > ADB detected: $($adbVersion -split "`n" | Select-Object -First 1)" -ForegroundColor Green
}
catch {
    Write-Host " > ERROR: Android Debug Bridge (ADB) not found!" -ForegroundColor Red
    Write-Host " > Please install Android SDK Platform Tools and add it to your PATH" -ForegroundColor White
    Read-Host " Press Enter to exit"
    exit 1
}

# Check device connection
Write-Host " > Checking for connected devices..." -ForegroundColor Yellow
$devices = adb devices
$connectedDevices = ($devices -split "`n" | Select-Object -Skip 1 | Where-Object { $_ -match "device$" }).Count

if ($connectedDevices -eq 0) {
    Write-Host " > ERROR: No Android devices connected" -ForegroundColor Red
    Write-Host " > Please connect a device with USB debugging enabled" -ForegroundColor White
    Read-Host " Press Enter to exit"
    exit 1
}
else {
    Write-Host " > Found $connectedDevices device(s)" -ForegroundColor Green
}

# Create destination directory if needed
if (-not (Test-Path $DestinationDir)) {
    try {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        Write-Host " > Created output directory: $DestinationDir" -ForegroundColor Green
    }
    catch {
        Write-Host " > ERROR: Failed to create output directory" -ForegroundColor Red
        Write-Host " > Error details: $_" -ForegroundColor Gray
        Read-Host " Press Enter to exit"
        exit 1
    }
}

# Pull YLogs
Write-Host " > Pulling YLogs from device..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputPath = Join-Path $DestinationDir "ylog_$timestamp"

try {
    # First attempt regular pull
    $result = adb pull data/ylog "$outputPath" 2>&1
    
    # Check if pull was partially successful
    if ($result -match "files pulled") {
        $filesPulled = [regex]::Match($result, "(\d+) files pulled").Groups[1].Value
        $filesSkipped = [regex]::Match($result, "(\d+) files skipped").Groups[1].Value
        
        Write-Host " > Successfully pulled $filesPulled files (skipped $filesSkipped)" -ForegroundColor Green
        Write-Host " > Saved to: $outputPath" -ForegroundColor Green
        
        # Report file count and size
        $fileCount = (Get-ChildItem "$outputPath" -Recurse -File).Count
        $totalSize = (Get-ChildItem "$outputPath" -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
        Write-Host " > Retrieved $fileCount file(s), total size: $("{0:N2}" -f $totalSize) MB" -ForegroundColor Green
        
        # Check if we should attempt root for skipped files
        if ($filesSkipped -gt 0) {
            Write-Host " > Some files were skipped (possibly due to permissions)" -ForegroundColor Yellow
            Write-Host " > Attempting to pull skipped files with root access..." -ForegroundColor Yellow
            
            try {
                # Check root availability
                $rootCheck = adb shell "su -c 'echo OK'" 2>&1
                if ($rootCheck -match "OK") {
                    # Create temp directory on device
                    adb shell "su -c 'mkdir -p /sdcard/temp_ylogs && cp -r data/ylog/* /sdcard/temp_ylogs/'" 2>&1 | Out-Null
                    
                    # Pull from accessible location
                    $rootResult = adb pull /sdcard/temp_ylogs "$outputPath-root" 2>&1
                    
                    # Clean up
                    adb shell "su -c 'rm -rf /sdcard/temp_ylogs'" 2>&1 | Out-Null
                    
                    if (Test-Path "$outputPath-root") {
                        Write-Host " > Successfully extracted additional files using root access" -ForegroundColor Green
                        Write-Host " > Saved to: $outputPath-root" -ForegroundColor Green
                    }
                }
                else {
                    Write-Host " > Root access not available or denied" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host " > Root extraction attempt failed: $_" -ForegroundColor Red
            }
        }
    }
    else {
        throw "ADB pull failed: $result"
    }
}
catch {
    Write-Host " > ERROR: Failed to pull YLogs" -ForegroundColor Red
    Write-Host " > Reason: $($_.Exception.Message)" -ForegroundColor Red
    
    # Check if partial files were pulled
    if (Test-Path "$outputPath") {
        $fileCount = (Get-ChildItem "$outputPath" -Recurse -File).Count
        if ($fileCount -gt 0) {
            $totalSize = (Get-ChildItem "$outputPath" -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
            Write-Host " > Partial success: $fileCount file(s) were pulled ($("{0:N2}" -f $totalSize) MB)" -ForegroundColor Yellow
            Write-Host " > Location: $outputPath" -ForegroundColor Yellow
        }
    }
}

# Final message
Write-Host ""
Write-Host " Operation completed. " -ForegroundColor White -BackgroundColor DarkBlue
Read-Host " Press Enter to exit"