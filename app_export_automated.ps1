# =====================================================================
# app_export_automated.ps1
# =====================================================================
# Script to export the current foreground app from an Android device
# Author: Claude
# Date: April 3, 2025
# =====================================================================

#region UI Functions
function Clear-Interface {
    Clear-Host
    $Host.UI.RawUI.WindowTitle = "Android App Export Tool"
}

function Write-Step {
    param (
        [string]$Message,
        [string]$Status = "PROCESSING"
    )
    
    $color = switch ($Status) {
        "PROCESSING" { "Yellow" }
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "INFO" { "White" }
        "DEBUG" { "Magenta" }
        default { "White" }
    }
    
    Write-Host " > $Message" -ForegroundColor $color
}

function Write-Section {
    param (
        [string]$Title
    )
    
    Write-Host ""
    Write-Host " $Title " -ForegroundColor Cyan -BackgroundColor DarkBlue
    Write-Host ""
}

function Write-ProgressBar {
    param (
        [int]$Current,
        [int]$Total,
        [string]$Activity
    )
    
    $percent = [math]::Min(100, [math]::Round(($Current / $Total) * 100))
    $progressBar = "[" + ("■" * [math]::Floor($percent / 5)) + (" " * [math]::Ceiling((100 - $percent) / 5)) + "]"
    
    Write-Host " $progressBar $percent% - $Activity" -ForegroundColor Cyan
}

function Get-UserConfirmation {
    param (
        [string]$Prompt,
        [switch]$DefaultYes
    )
    
    $options = if ($DefaultYes) { "(Y/n)" } else { "(y/N)" }
    $response = Read-Host " $Prompt $options"
    
    if ($DefaultYes) {
        return ($response -eq "" -or $response.Trim().ToLower() -ne "n")
    }
    else {
        return ($response -ne "" -and $response.Trim().ToLower() -eq "y")
    }
}

function Read-UserInput {
    param (
        [string]$Prompt
    )
    
    return Read-Host " $Prompt"
}
#endregion

#region Functional Logic
function Check-AdbConnection {
    $devices = adb devices
    $connectedDevices = ($devices -split "`n" | Select-Object -Skip 1 | Where-Object { $_ -match "device$" }).Count
    return $connectedDevices -gt 0
}

function Get-CurrentApp {
    try {
        # Method 1: Check mCurrentFocus
        $packageName = adb shell "dumpsys window | grep mCurrentFocus" 2>$null
        
        # Extract package name using regex
        if ($packageName -match "(\S+)/(\S+)") {
            $packageName = $matches[1].Trim()
            Write-Step "Package identified via mCurrentFocus: $packageName" "DEBUG"
            return $packageName
        }
        
        # Method 2: Check mResumedActivity
        $packageName = adb shell "dumpsys activity activities | grep mResumedActivity" 2>$null
        
        if ($packageName -match "(\S+)/(\S+)") {
            $packageName = $matches[1].Trim()
            Write-Step "Package identified via mResumedActivity: $packageName" "DEBUG"
            return $packageName
        }
        
        # Method 3: Use the most generic approach
        $packageName = adb shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'" 2>$null
        
        # Try to parse out the package name from complex output
        if ($packageName -match "([a-zA-Z0-9_.]+)/[a-zA-Z0-9_.]+") {
            $packageName = $matches[1].Trim()
            Write-Step "Package identified via general parsing: $packageName" "DEBUG"
            return $packageName
        }
        
        throw "Could not determine package name using any method"
    } 
    catch {
        Write-Step "Error in Get-CurrentApp: $_" "DEBUG"
        return $null
    }
}

function Get-AppName {
    param (
        [string]$PackageName
    )
    
    try {
        # Method 1: Use get-app-label (newer Android versions)
        $appLabel = adb shell "cmd package get-app-label $PackageName" 2>$null
        if ($appLabel -and (-not [string]::IsNullOrWhiteSpace($appLabel))) {
            Write-Step "App name via get-app-label: $appLabel" "DEBUG"
            return $appLabel.Trim()
        }
        
        # Method 2: Parse from package info
        $appInfo = adb shell "dumpsys package $PackageName | grep -E 'label=' | head -1" 2>$null
        if ($appInfo -match "label=([^\s]+)") {
            $appName = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($appName)) {
                Write-Step "App name via package info: $appName" "DEBUG"
                return $appName
            }
        }
        
        # Method 3: Get from installed packages
        $appInfo = adb shell "pm list packages -f | grep $PackageName" 2>$null
        if ($appInfo -match "=($PackageName)$") {
            $apkPath = $appInfo.Split("=")[0].Replace("package:", "")
            $appLabel = adb shell "aapt dump badging '$apkPath' | grep application-label:" 2>$null
            
            if ($appLabel -match "'([^']+)'") {
                $appName = $matches[1].Trim()
                Write-Step "App name via aapt: $appName" "DEBUG"
                return $appName
            }
        }
        
        # Fallback: Use package name's last part
        $appName = $PackageName.Split(".")[-1]
        Write-Step "Using fallback app name: $appName" "DEBUG"
        return $appName
    } 
    catch {
        Write-Step "Error in Get-AppName: $_" "DEBUG"
        return $PackageName.Split(".")[-1]
    }
}

function Get-ApkFiles {
    param (
        [string]$PackageName
    )
    
    try {
        $apkPaths = adb shell "pm path $PackageName" 2>$null
        $paths = $apkPaths -split "`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim().Replace("package:", "") }
        
        if ($paths -and $paths.Count -gt 0) {
            foreach ($path in $paths) {
                Write-Step "Found APK path: $path" "DEBUG"
            }
            return $paths
        }
        
        Write-Step "No APK paths found using standard method" "DEBUG"
        
        # Alternative method for system apps
        $apkPaths = adb shell "pm dump $PackageName | grep path:" 2>$null
        $paths = $apkPaths -split "`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object {
            if ($_ -match "path:\s+(.*)") {
                $matches[1].Trim()
            }
        }
        
        if ($paths -and $paths.Count -gt 0) {
            foreach ($path in $paths) {
                Write-Step "Found APK path via dump: $path" "DEBUG"
            }
            return $paths
        }
        
        Write-Step "No APK paths found via any method" "DEBUG"
        return $null
    }
    catch {
        Write-Step "Error in Get-ApkFiles: $_" "DEBUG"
        return $null
    }
}

function Export-Apk {
    param (
        [string]$Path,
        [string]$Destination
    )
    
    try {
        Write-Step "Pulling from $Path to $Destination" "DEBUG"
        
        # Create directory structure if it doesn't exist
        $destinationDir = Split-Path -Parent $Destination
        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            Write-Step "Created directory: $destinationDir" "DEBUG"
        }
        
        # Pull the APK file
        $pullOutput = (adb pull $Path $Destination 2>&1 | Out-String)
        Write-Step "Pull output: $pullOutput" "DEBUG"
        
        # Check if file exists and has content
        if (Test-Path $Destination) {
            $fileSize = (Get-Item $Destination).Length
            if ($fileSize -gt 0) {
                Write-Step "Successfully pulled file ($fileSize bytes)" "DEBUG"
                return $true
            }
            else {
                Write-Step "File was created but is empty" "DEBUG"
                return $false
            }
        }
        else {
            Write-Step "File was not created after pull" "DEBUG"
            return $false
        }
    }
    catch {
        Write-Step "Error in Export-Apk: $_" "DEBUG"
        return $false
    }
}
#endregion

#region Main Script
function Main {
    # Enable debug output (comment out this line to disable detailed debugging)
    # $VerbosePreference = 'Continue'
    
    Clear-Interface
    Write-Section "Android App Export Tool"
    
    # Step 1: Check ADB
    Write-Step "Checking for Android Debug Bridge (ADB)..." 
    try {
        $adbVersion = adb version 2>$null
        if (-not $?) {
            throw "ADB command failed"
        }
        Write-Step "ADB detected: $adbVersion" "SUCCESS"
    } 
    catch {
        Write-Step "ERROR: Android Debug Bridge (ADB) not found!" "ERROR"
        Write-Step "Please install Android SDK Platform Tools and add it to your PATH" "INFO"
        Read-UserInput "Press Enter to exit"
        return
    }
    
    # Step 2: Check device connection
    Write-Step "Checking for connected Android devices..." 
    $attemptCount = 1
    $maxAttempts = 5
    $connected = $false
    
    while (-not $connected -and $attemptCount -le $maxAttempts) {
        if (Check-AdbConnection) {
            $connected = $true
            $deviceInfo = adb devices -l | Select-Object -Skip 1 | Where-Object { $_ -match "device " }
            Write-Step "Android device connected: $deviceInfo" "SUCCESS"
        }
        else {
            if ($attemptCount -eq 1) {
                Write-Step "No Android device detected" "ERROR"
                Write-Step "Please ensure:" "INFO"
                Write-Step "• Your device is connected via USB" "INFO"
                Write-Step "• USB debugging is enabled" "INFO"
                Write-Step "• You've allowed debugging when prompted" "INFO"
            }
            
            Write-Step "Waiting for connection... (Attempt $attemptCount of $maxAttempts)" "INFO"
            $attemptCount++
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $connected) {
        Write-Step "ERROR: No device connected after $maxAttempts attempts" "ERROR"
        Read-UserInput "Press Enter to exit"
        return
    }
    
    # Step 3-6: App identification loop
    $correctApp = $false
    $packageName = $null
    $appName = $null
    
    while (-not $correctApp) {
        Clear-Interface
        Write-Section "Android App Export Tool"
        Write-Step "Device connected" "SUCCESS"
        
        # Prompt user to open the app
        Write-Step "Please open the app you want to export on your device" "INFO"
        Write-Step "Make sure the app is in the foreground and visible" "INFO"
        Read-UserInput "Press Enter when the app is open"
        
        # Identify current app
        Write-Step "Identifying current foreground app..." 
        $packageName = Get-CurrentApp
        
        if (-not $packageName) {
            Write-Step "ERROR: Could not identify the current app" "ERROR"
            Write-Step "Make sure your device is unlocked and the app is in the foreground" "INFO"
            $retry = Get-UserConfirmation "Try again?" -DefaultYes
            if (-not $retry) {
                Read-UserInput "Press Enter to exit"
                return
            }
            continue
        }
        
        # Get app name
        $appName = Get-AppName -PackageName $packageName
        
        # Confirm with user
        Write-Step "App Identified: $appName ($packageName)" "SUCCESS"
        $correctApp = Get-UserConfirmation "Is this the correct app?" -DefaultYes
        
        if (-not $correctApp) {
            Write-Step "Let's try again..." "INFO"
            Start-Sleep -Seconds 1
        }
    }
    
    # Step 7: Get APK paths
    Write-Step "Getting APK locations..." 
    $apkPaths = Get-ApkFiles -PackageName $packageName
    
    if (-not $apkPaths -or $apkPaths.Count -eq 0) {
        Write-Step "ERROR: Could not locate APK files" "ERROR"
        Write-Step "The app might be a system app or have restricted access" "INFO"
        $manualOption = Get-UserConfirmation "Would you like to try a manual extraction method?" -DefaultYes
        
        if ($manualOption) {
            Write-Step "Attempting manual extraction via package dump..." "INFO"
            
            try {
                # Try to directly locate the APK file via package dump
                $packageInfo = adb shell "pm dump $packageName" 2>$null
                $apkLine = $packageInfo -split "`n" | Where-Object { $_ -match "baseCodePath=|codePath=" } | Select-Object -First 1
                
                if ($apkLine -match "(baseCodePath|codePath)=(.*)") {
                    $potentialPath = $matches[2].Trim()
                    if ($potentialPath) {
                        $apkPaths = @($potentialPath)
                        Write-Step "Found potential APK location: $potentialPath" "SUCCESS"
                    }
                }
                
                if (-not $apkPaths -or $apkPaths.Count -eq 0) {
                    Write-Step "Could not find any APK paths" "ERROR"
                    Read-UserInput "Press Enter to exit"
                    return
                }
            }
            catch {
                Write-Step "Manual extraction failed: $_" "ERROR"
                Read-UserInput "Press Enter to exit"
                return
            }
        }
        else {
            Read-UserInput "Press Enter to exit"
            return
        }
    }
    
    $totalApks = $apkPaths.Count
    Write-Step "Found $totalApks APK file(s)" "SUCCESS"
    
    # Step 8: Create export folder
    # Create export folder using the current script directory for a reliable path
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = (Get-Location).Path
    }
    
    $folderName = Join-Path $scriptDir "$packageName-export"
    try {
        if (-not (Test-Path $folderName)) {
            New-Item -ItemType Directory -Path $folderName -Force | Out-Null
            Write-Step "Created export directory: $folderName" "DEBUG"
        }
    } 
    catch {
        Write-Step "ERROR: Could not create folder $folderName" "ERROR"
        Write-Step "Error details: $_" "DEBUG"
        Read-UserInput "Press Enter to exit"
        return
    }
    
    # Step 9: Download APKs
    Clear-Interface
    Write-Section "Exporting $appName"
    Write-Step "Downloading $totalApks APK file(s) to $folderName\"
    
    $downloadedApks = 0
    $failedApks = 0
    
    foreach ($path in $apkPaths) {
        $filename = Split-Path $path -Leaf
        # Ensure filename is valid and not empty
        if ([string]::IsNullOrWhiteSpace($filename)) {
            $filename = "app_part_$($downloadedApks + 1).apk"
        }
        elseif (-not $filename.EndsWith(".apk")) {
            $filename = "$filename.apk"
        }
        
        $destination = Join-Path $folderName $filename
        
        Write-ProgressBar -Current $downloadedApks -Total $totalApks -Activity "Downloading APK $($downloadedApks + 1) of $totalApks"
        Write-Step "Exporting $filename..." 
        
        if (Export-Apk -Path $path -Destination $destination) {
            $fileSize = (Get-Item $destination).Length
            $fileSizeMB = "{0:N2}" -f ($fileSize / 1MB)
            Write-Step "$filename ($fileSizeMB MB)" "SUCCESS"
            $downloadedApks++
        }
        else {
            Write-Step "Failed to download $filename" "ERROR"
            # Try with root if available
            $rootOption = Get-UserConfirmation "Try with root access (if available)?" -DefaultYes
            
            if ($rootOption) {
                Write-Step "Attempting root extraction..." "INFO"
                try {
                    $rootResult = adb shell "su -c 'cat $path > /sdcard/temp_apk.apk' && exit" 2>$null
                    $pullResult = adb pull "/sdcard/temp_apk.apk" $destination 2>$null
                    $cleanupResult = adb shell "rm /sdcard/temp_apk.apk" 2>$null
                    
                    if (Test-Path $destination) {
                        $fileSize = (Get-Item $destination).Length
                        if ($fileSize -gt 0) {
                            $fileSizeMB = "{0:N2}" -f ($fileSize / 1MB)
                            Write-Step "$filename ($fileSizeMB MB) - extracted with root" "SUCCESS"
                            $downloadedApks++
                            continue
                        }
                    }
                    
                    Write-Step "Root extraction failed" "ERROR"
                }
                catch {
                    Write-Step "Root extraction error: $_" "ERROR"
                }
            }
            
            $failedApks++
        }
    }
    
    # Step 10: Display results
    Clear-Interface
    Write-Section "Export Complete"
    
    if ($downloadedApks -eq $totalApks) {
        Write-Step "SUCCESS: All $totalApks APK file(s) exported" "SUCCESS"
    } 
    elseif ($downloadedApks -gt 0) {
        Write-Step "PARTIAL SUCCESS: $downloadedApks of $totalApks APK file(s) exported" "INFO"
        Write-Step "Failed: $failedApks APK file(s)" "ERROR"
    } 
    else {
        Write-Step "FAILED: Could not export any APK files" "ERROR"
        Write-Step "Possible reasons:" "INFO"
        Write-Step "• The app is protected against extraction" "INFO"
        Write-Step "• The app is a system app with restricted access" "INFO"
        Write-Step "• The device needs to be rooted for this operation" "INFO"
    }
    
    try {
        $absolutePath = Resolve-Path $folderName -ErrorAction Stop
        Write-Step "Export location: $absolutePath" "INFO"
    }
    catch {
        Write-Step "Export location: $folderName (path could not be resolved)" "INFO"
    }
    
    Read-UserInput "Press Enter to exit"
}

# Run the script
Main
#endregion