# =====================================================================
# package_launcher.ps1
# =====================================================================
# <DESCRIPTION>
# Tool: Android Package Launcher
# Version: 1.0
# Author: LKK
# Date: April 7, 2025
# Purpose: Launch Android packages via ADB using market URLs
# Requirements: ADB (Android Debug Bridge), PowerShell 5.0+
# Usage: ./package_launcher.ps1
# Features: 
#   - Launch Android packages using the Google Play Store market URL scheme
#   - Interactive prompt for multiple package launches
#   - UTF-8 output encoding support
#   - Error handling with detailed feedback
# </DESCRIPTION>
# =====================================================================

# Set output encoding to UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Function Start-PackageLaunch {
    param (
        [string]$packageName
    )
    # Check if the package name is provided
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        Write-Host "Package name cannot be empty. Please try again." -ForegroundColor Red
        return
    }
    try {
        # Run the ADB command
        Write-Host "Launching package: $packageName" -ForegroundColor Green
        Start-Process "adb" "shell am start -a android.intent.action.VIEW -d market://details?id=$packageName" -ErrorAction Stop
        Write-Host "Package launched successfully. Press any key to continue..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        # Handle any errors that occur
        Write-Host "An error occurred while trying to launch the package: $packageName" -ForegroundColor Red
        Write-Host "Error details: $_" -ForegroundColor Yellow
        Write-Host "Please check if ADB is installed and the package name is valid." -ForegroundColor Cyan
    }
}

# Main loop to request package names
do {
    Write-Host "Enter the package name (or type 'exit' to quit):" -ForegroundColor White
    $packageName = Read-Host
    if ($packageName -eq "exit") {
        Write-Host "Exiting the script. Goodbye!" -ForegroundColor Green
        break
    }
    # Call the function to launch the package
    Start-PackageLaunch -packageName $packageName
} while ($true)