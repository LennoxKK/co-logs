# =====================================================================
# current_package.ps1
# =====================================================================
# <DESCRIPTION>
# Tool: Current Android Package Detector
# Version: 1.1
# Author: LKK
# Date: June 10, 2024
# Purpose: Get the package name of currently focused Android app
# Requirements: ADB (Android Debug Bridge), PowerShell 5.0+
# Usage: ./current_package.ps1
# Features: 
#   - Detects currently focused Android application
#   - Returns clean package name only
#   - Works with multiple device configurations
#   - Enhanced error handling with detailed feedback
#   - Supports both mCurrentFocus and mFocusedApp fields
#   - Handles manufacturer-specific Android variations
#   - Provides troubleshooting suggestions
# </DESCRIPTION>
# =====================================================================

# Set title and clear screen
$Host.UI.RawUI.WindowTitle = "Current Package Detector (Enhanced)"
Clear-Host
Write-Host " Android Current Package Detector " -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ""

# Function to check ADB
function Test-ADB {
    try {
        $null = adb version 2>$null
        return $true
    } catch {
        return $false
    }
}

# Function to get connected devices
function Get-ADBDevices {
    try {
        $devices = adb devices | Select-Object -Skip 1
        return $devices | Where-Object { $_ -match "device$" }
    } catch {
        return @()
    }
}

# Improved function to extract package name with multiple pattern matching attempts
function Get-CurrentPackage {
    param (
        [switch]$Debug
    )
    
    try {
        $windowInfo = adb shell dumpsys window windows 2>$null
        
        if ($Debug) {
            Write-Host " > DEBUG: Received window dump data" -ForegroundColor Gray
        }
        
        # Pattern 1: Standard mCurrentFocus format
        $focusLine = $windowInfo | Select-String "mCurrentFocus" | Select-Object -First 1
        if ($focusLine) {
            if ($Debug) {
                Write-Host " > DEBUG: Found mCurrentFocus line: $focusLine" -ForegroundColor Gray
            }
            
            if ($focusLine -match "mCurrentFocus=.*\{[^}]*\s+([^\/\s]+)/") {
                return $matches[1]
            }
        }
        
        # Pattern 2: Alternative mFocusedApp format
        $focusLine = $windowInfo | Select-String "mFocusedApp" | Select-Object -First 1
        if ($focusLine) {
            if ($Debug) {
                Write-Host " > DEBUG: Found mFocusedApp line: $focusLine" -ForegroundColor Gray
            }
            
            if ($focusLine -match "mFocusedApp=.*\{[^}]*\s+([^\/\s]+)/") {
                return $matches[1]
            }
        }
        
        # Pattern 3: ActivityRecord format
        $focusLine = $windowInfo | Select-String "ActivityRecord" | Select-Object -First 1
        if ($focusLine) {
            if ($Debug) {
                Write-Host " > DEBUG: Found ActivityRecord line: $focusLine" -ForegroundColor Gray
            }
            
            if ($focusLine -match "ActivityRecord\{[^\s]+\s[^\s]+\s([^\/\s]+)") {
                return $matches[1]
            }
        }
        
        # Alternative approach: Try focused-activity command
        if ($Debug) {
            Write-Host " > DEBUG: Trying alternative dumpsys activity focused-activity command" -ForegroundColor Gray
        }
        
        $focusActivity = adb shell dumpsys activity focused-activity 2>$null
        if ($focusActivity) {
            $activityLine = $focusActivity | Select-String "([a-zA-Z0-9\.\_]+)/[a-zA-Z0-9\.\_\$]+" | Select-Object -First 1
            if ($activityLine -match "([a-zA-Z0-9\.\_]+)/[a-zA-Z0-9\.\_\$]+") {
                return $matches[1]
            }
        }
        
        # Last resort: Try top activity
        if ($Debug) {
            Write-Host " > DEBUG: Trying top activity command" -ForegroundColor Gray
        }
        
        $topActivity = adb shell dumpsys activity recents | Select-String "Recent #0" -Context 0,3
        if ($topActivity) {
            if ($topActivity -match "([a-zA-Z0-9\.\_]+)/[a-zA-Z0-9\.\_\$]+") {
                return $matches[1]
            }
        }
        
        return $null
    } catch {
        if ($Debug) {
            Write-Host " > DEBUG: Error in Get-CurrentPackage: $_" -ForegroundColor Red
        }
        return $null
    }
}

# Main execution
Write-Host " > Checking ADB..." -ForegroundColor Yellow
if (-not (Test-ADB)) {
    Write-Host " > ERROR: ADB not found or not working!" -ForegroundColor Red
    Write-Host " > 1. Install Android SDK Platform-Tools"
    Write-Host " > 2. Add to PATH environment variable"
    Write-Host " > 3. Enable USB debugging on your device"
    Read-Host " Press Enter to exit"
    exit 1
}

Write-Host " > Checking devices..." -ForegroundColor Yellow
$devices = Get-ADBDevices
if ($devices.Count -eq 0) {
    Write-Host " > ERROR: No devices found!" -ForegroundColor Red
    Write-Host " > - Connect device with USB cable"
    Write-Host " > - Enable USB debugging"
    Write-Host " > - Confirm authorization dialog on device"
    Read-Host " Press Enter to exit"
    exit 1
}

# Add debug mode option
$debugMode = $false
Write-Host " > Do you want to run in debug mode? (y/n)" -ForegroundColor Yellow -NoNewline
$response = Read-Host " "
if ($response -eq "y") {
    $debugMode = $true
    Write-Host " > Debug mode enabled. More information will be shown." -ForegroundColor Yellow
}

Write-Host " > Detecting current package..." -ForegroundColor Yellow
$package = Get-CurrentPackage -Debug:$debugMode

if ($package) {
    Write-Host " > CURRENT PACKAGE:" -ForegroundColor Green
    Write-Host "   $package" -ForegroundColor Cyan
} else {
    Write-Host " > Could not detect package!" -ForegroundColor Red
    
    # Show raw dumpsys output for debugging
    if ($debugMode) {
        Write-Host " > DEBUG: Showing sample of raw dumpsys window windows output:" -ForegroundColor Yellow
        $windowSample = adb shell dumpsys window windows | Select-Object -First 20
        Write-Host $windowSample -ForegroundColor Gray
    }
    
    Write-Host " > Possible reasons:"
    Write-Host " > - Device screen is locked"
    Write-Host " > - No app is focused"
    Write-Host " > - Device manufacturer customizations"
    Write-Host " > - ADB permissions need to be granted for dumpsys commands"
}

Write-Host ""
Write-Host " Operation completed. " -ForegroundColor White -BackgroundColor DarkBlue
Read-Host " Press Enter to exit"