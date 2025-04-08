# =====================================================================
# android_screen_recorder.ps1
# =====================================================================
# <DESCRIPTION>
# Tool: Android Screen Recorder with Touch Indicators and Log Collection
# Version: 1.0
# Author: LKK
# Date: April 7, 2025
# Purpose: Record Android screen with touch indicators and collect logs
# Requirements: ADB (Android Debug Bridge), PowerShell 5.0+
# Usage: ./android_screen_recorder.ps1
# Features: 
#   - Records device screen with visible touch indicators
#   - Automatically saves recording to your computer
#   - Prompts user to start logs before recording for "dut" recordings
#   - Automatically collects available logs (debuglogger or ylog) in the background
#   - Provides clear status messages throughout the process
#   - Waits for device connection if no device is detected
#   - Opens the output folder when complete
#   - Centers ALL text and input fields on the screen
#   - Loops the process for continuous recording sessions even when recording a video not named as dut
# </DESCRIPTION>
# =====================================================================
function Prompt-ContinueRecording {
    # Display prompt with centered formatting
    Write-Host ""
    Write-CenteredText "============================================" "Cyan"
    Write-CenteredText " RECORDING COMPLETED - CONTINUE OR EXIT? " "Yellow"
    Write-CenteredText "============================================" "Cyan"
    Write-Host ""
    
    # Get user input, looping until a valid response is provided
    $continue = $null
    do {
        $continue = Read-CenteredInput "Do you want to record another video? (Y/N): " $true
        $continue = $continue.ToUpper()
    } while ($continue -ne "Y" -and $continue -ne "N")
    
    # Return boolean result based on user's choice
    if ($continue -eq "Y") {
        return $true
    } else {
        # Show exit message
        Clear-Screen
        Write-CenteredText "============================================" "Cyan"
        Write-CenteredText "  THANK YOU FOR USING ANDROID SCREEN RECORDER  " "Green"
        Write-CenteredText "============================================" "Cyan"
        Write-Host ""
        Write-CenteredText "Exiting..." "Gray"
        Start-Sleep -Seconds 2
        return $false
    }
}

function Clear-Screen {
    try {
        [System.Console]::Clear()
    }
    catch {
        Write-Host "`n" * 30
    }
}

function Test-AndroidPath {
    param([string]$path)
    $result = adb shell "if [ -d '$path' ]; then echo 'exists'; fi"
    return $result -contains "exists"
}

function Write-CenteredText {
    param(
        [string]$text,
        [string]$foregroundColor = "White"
    )
    
    # Get console width for centering
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    
    # Calculate padding for centering
    $padding = [Math]::Max(0, [Math]::Floor(($consoleWidth - $text.Length) / 2))
    $paddedText = " " * $padding + $text
    
    # Write the centered text
    Write-Host $paddedText -ForegroundColor $foregroundColor
}

function Show-BlinkingMessage {
    param(
        [string]$text,
        [string]$foregroundColor = "Red",
        [string]$backgroundColor = $null,
        [int]$blinkCount = 3
    )
    
    # Get console width for centering
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    
    # Calculate padding for centering
    $padding = [Math]::Max(0, [Math]::Floor(($consoleWidth - $text.Length) / 2))
    $paddedText = " " * $padding + $text
    
    for ($i = 0; $i -lt $blinkCount; $i++) {
        Write-Host "`r$paddedText" -ForegroundColor $foregroundColor -NoNewline
        Start-Sleep -Milliseconds 500
        if ($backgroundColor) {
            Write-Host "`r$paddedText" -ForegroundColor "Black" -BackgroundColor $foregroundColor -NoNewline
        }
        else {
            $blankSpace = " " * ($consoleWidth)
            Write-Host "`r$blankSpace" -NoNewline
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "`r$paddedText" -ForegroundColor $foregroundColor
    Write-Host ""
}

function Read-CenteredInput {
    param(
        [string]$prompt,
        [bool]$required = $true
    )
    
    # Get console width for centering
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    
    # Calculate padding for centering
    $padding = [Math]::Max(0, [Math]::Floor(($consoleWidth - $prompt.Length) / 2))
    $paddedPrompt = " " * $padding + $prompt
    
    do {
        Write-Host ""
        Write-Host $paddedPrompt -NoNewline
        $input = Read-Host
        if ($required -and [string]::IsNullOrWhiteSpace($input)) {
            Write-CenteredText "[WARNING] Input is required" "Yellow"
        }
    } while ($required -and [string]::IsNullOrWhiteSpace($input))
    
    return $input
}

function Wait-ForDevice {
    $deviceFound = $false
    $dotCount = 0
    
    Clear-Screen
    Write-CenteredText "============================================" "Cyan"
    Write-CenteredText " WAITING FOR ANDROID DEVICE CONNECTION " "Yellow"
    Write-CenteredText "============================================" "Cyan"
    Write-Host ""
    Write-CenteredText "Please:" "Yellow"
    Write-CenteredText "1. Connect your device via USB" "White"
    Write-CenteredText "2. Enable USB debugging" "White"
    Write-CenteredText "3. Authorize this computer when prompted" "White"
    Write-Host ""
    
    while (-not $deviceFound) {
        $devices = adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" }
        if ($devices) {
            $deviceFound = $true
            Show-BlinkingMessage "[SUCCESS] Device connected successfully!" "Green" $null 3
            Start-Sleep -Seconds 1
            break
        }
        
        $dots = "." * ($dotCount % 4 + 1)
        # Get console width for centering
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        $waitText = "Waiting for device connection$dots    "
        $padding = [Math]::Max(0, [Math]::Floor(($consoleWidth - $waitText.Length) / 2))
        $paddedText = " " * $padding + $waitText
        
        Write-Host "`r$paddedText" -NoNewline -ForegroundColor Cyan
        $dotCount++
        Start-Sleep -Seconds 1
    }
    
    return $deviceFound
}

function Show-CenteredHeader {
    param(
        [string]$title,
        [string]$subtitle,
        [string]$titleColor = "Green",
        [string]$subtitleColor = "Green"
    )
    
    Write-CenteredText $title $titleColor
    Write-CenteredText $subtitle $subtitleColor
    Write-Host ""
}

function Test-ScreenOn {
    try {
        # Capture the full output from adb command
        $powerOutput = & adb shell "dumpsys power" | Out-String
        
        # For Pixel 8 devices running newer Android versions
        if ($powerOutput -match "Display Power: state=ON" -or $powerOutput -match "mPowerState=ON" -or $powerOutput -match "mScreenState=ON") {
            return $true
        } else {
            # Alternative check for newer Android versions
            $displayOutput = & adb shell "dumpsys display" | Out-String
            if ($displayOutput -match "mScreenState=ON") {
                return $true
            }
            return $false
        }
    }
    catch {
        Write-Warning "Error checking screen state: $_"
        return $false
    }
}



function Show-ProgressAnimation {
    param(
        [string]$message,
        [string]$foregroundColor = "Cyan",
        [ScriptBlock]$scriptBlock,
        [int]$maxSeconds = 180,
        [bool]$showResults = $true
    )
    
    # Run the script block in the background
    $job = Start-Job -ScriptBlock $scriptBlock
    
    # Animation while waiting for job to complete
    $animation = @('|', '/', '-', '\')
    $i = 0
    $startTime = Get-Date
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    
    while ($job.State -eq 'Running') {
        $timeSpent = (Get-Date) - $startTime
        if ($timeSpent.TotalSeconds -gt $maxSeconds) {
            Write-CenteredText "[WARNING] Operation taking longer than expected" "Yellow"
            break
        }
        
        $currentAnim = $animation[$i % $animation.Length]
        $text = "$message $currentAnim"
        $padding = [Math]::Max(0, [Math]::Floor(($consoleWidth - $text.Length) / 2))
        $paddedText = " " * $padding + $text
        
        Write-Host "`r$paddedText" -NoNewline -ForegroundColor $foregroundColor
        Start-Sleep -Milliseconds 250
        $i++
    }
    
    # Get job result
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    
    # Clear the progress line
    $blankSpace = " " * $consoleWidth
    Write-Host "`r$blankSpace" -NoNewline
    
    if ($showResults) {
        Write-Host "`r$paddedText" -ForegroundColor $foregroundColor
    }
    
    return $result
}

function Start-RecordingProcess {
    # Initialize
    Clear-Screen
    Write-CenteredText "============================================" "Cyan"
    Write-CenteredText " ANDROID SCREEN RECORDER WITH TOUCH INDICATORS " "Cyan"
    Write-CenteredText "============================================" "Cyan"
    Write-Host ""

    # Set a success flag to be returned at the end
    $processSuccess = $false
    $fileExists = $true  # Flag to track if the recording file exists

    # Check ADB availability
    if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
        Write-CenteredText "[ERROR] ADB is not available in PATH" "Red"
        Write-CenteredText "Please install Android Platform Tools first" "Yellow"
        Write-CenteredText "Download from: https://developer.android.com/tools/releases/platform-tools" "Cyan"
        return $false
    }

    # Check device connection
    Write-CenteredText "Checking device connection..." "Gray"
    $deviceConnected = $false
    $maxRetries = 3
    $retries = 0
    
    while (-not $deviceConnected -and $retries -lt $maxRetries) {
        $devices = adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" }
        if ($devices) {
            $deviceConnected = $true
            Write-CenteredText "[SUCCESS] Device connected" "Green"
        } else {
            $retries++
            if ($retries -ge $maxRetries) {
                $connected = Wait-ForDevice
                if (-not $connected) {
                    return $false
                }
                $deviceConnected = $true
            } else {
                Write-CenteredText "[WARNING] No device detected, retrying... ($retries/$maxRetries)" "Yellow"
                Start-Sleep -Seconds 2
            }
        }
    }

    # Check if screen is on
    $screenOn = Test-ScreenOn
    if (-not $screenOn) {
        Write-CenteredText "[WARNING] Device screen appears to be off" "Yellow"
        Write-CenteredText "Please turn on your device screen to continue" "Yellow"
        
        $maxWaitTime = 30
        $waitTime = 0
        $waitInterval = 3
        
        while (-not $screenOn -and $waitTime -lt $maxWaitTime) {
            Write-CenteredText "Waiting for screen to turn on... ($waitTime/$maxWaitTime seconds)" "Cyan"
            Start-Sleep -Seconds $waitInterval
            $waitTime += $waitInterval
            $screenOn = Test-ScreenOn
        }
        
        if (-not $screenOn) {
            $proceed = Read-CenteredInput "Screen still appears to be off. Proceed anyway? (Y/N): " $true
            if ($proceed -ne 'Y' -and $proceed -ne 'y') {
                Write-CenteredText "[INFO] Recording cancelled by user" "Blue"
                return $false
            }
        } else {
            Write-CenteredText "[SUCCESS] Screen is now on" "Green"
        }
    }

    # Get filename
    Clear-Screen
    Show-CenteredHeader "STEP 1: RECORDING SETUP" "------------------------"
    $videoName = Read-CenteredInput "Enter a name for your recording (without extension): " $true
    $videoPath = "/sdcard/$videoName.mp4"
    $localPath = "$PWD\$videoName.mp4"

    # Prompt to enable logging for DUT recordings
    if ($videoName -like "dut*") {
        Clear-Screen
        Show-CenteredHeader "SPECIAL SETUP FOR DUT RECORDING" "------------------------------" "Magenta" "Magenta"
        Write-Host ""
        
        Show-BlinkingMessage "[IMPORTANT] DUT recording detected!" "Yellow" $null 3
        Write-CenteredText "Before starting the recording, please:" "White"
        Write-CenteredText "1. Start the logging process on your device now" "Cyan"
        Write-CenteredText "2. Ensure debuglogger or ylog is running" "Cyan"
        Write-CenteredText "3. The logs will be collected automatically after recording" "Cyan"
        Write-Host ""

        do {
            $confirm = Read-CenteredInput "Have you started logging on the device? (Y/N): " $true
        } while ($confirm -notmatch '^[YyNn]$')  # Ensure valid input

        if ($confirm -match '^[Nn]$') {
            Write-Host ""
            Write-CenteredText "[WARNING] You should start logging before recording" "Yellow"

            do {
                $proceed = Read-CenteredInput "Do you want to proceed anyway? (Y/N): " $true
            } while ($proceed -notmatch '^[YyNn]$')  # Ensure valid input

            if ($proceed -match '^[Nn]$') {
                Write-CenteredText "[INFO] Recording cancelled by user" "Blue"
                return $false
            }
        } else {
            Write-CenteredText "[STATUS] Logging confirmed as started" "Green"
        }
    }

    # Enable touch indicators
    Clear-Screen
    Show-CenteredHeader "STEP 2: RECORDING" "-----------------"
    
    $touchIndicatorsEnabled = $false
    $maxRetries = 3
    $retries = 0
    
    while (-not $touchIndicatorsEnabled -and $retries -lt $maxRetries) {
        try {
            adb shell settings put system show_touches 1
            $touchValue = adb shell settings get system show_touches
            if ($touchValue -eq "1") {
                $touchIndicatorsEnabled = $true
                Write-CenteredText "[STATUS] Touch indicators enabled" "Green"
            } else {
                throw "Failed to enable touch indicators"
            }
        } catch {
            $retries++
            if ($retries -ge $maxRetries) {
                Write-CenteredText "[WARNING] Could not enable touch indicators" "Yellow"
                $proceed = Read-CenteredInput "Continue anyway? (Y/N): " $true
                if ($proceed -ne 'Y' -and $proceed -ne 'y') {
                    return $false
                }
                break
            } else {
                Write-CenteredText "[WARNING] Failed to enable touch indicators, retrying... ($retries/$maxRetries)" "Yellow"
                Start-Sleep -Seconds 1
            }
        }
    }

    # Start recording - with manual stop
    Write-Host ""
    Show-BlinkingMessage "STARTING RECORDING..." "Cyan" $null 3
    Write-CenteredText "* Screen recording has started" "Green"
    Write-CenteredText "* Touch indicators are enabled" "Green"
    Write-CenteredText "* Recording will continue until you press CTRL+C" "Yellow"
    Write-Host ""

    $transferSuccess = $false
    $logPath = $null
    $logDir = $null
    $logType = $null
    $logSize = 0
    $fileSize = 0
    $recordingJob = $null
    $processSuccess = $false

    try {
        # Start recording with a reasonable time limit
        adb shell screenrecord --time-limit 180 $videoPath
        $processSuccess = $true
    }
    catch {
        Write-CenteredText "[INFO] Recording stopped by user" "Blue"
        $processSuccess = $true  # Still consider this a success as it was intentionally stopped
    }
    finally {
        # Disable touch indicators
        adb shell settings put system show_touches 0
        Write-CenteredText "[STATUS] Touch indicators disabled" "Green"

        # Finalize recording
        Write-CenteredText "[STATUS] Finalizing recording..." "Gray"
        Start-Sleep -Seconds 3

        # Pull recording
        Clear-Screen
        Show-CenteredHeader "STEP 3: SAVING RECORDING" "------------------------"
        Write-CenteredText "Transferring recording from device..." "Gray"

        $progressParams = @{
            Activity = "Transferring Video"
            Status = "Please wait..."
            PercentComplete = 0
        }
        Write-Progress @progressParams

        try {
            adb pull $videoPath $localPath | Out-Null
            Write-Progress -Activity "Transferring Video" -Completed -Status "Done"

            if (Test-Path $localPath) {
                $fileSize = (Get-Item $localPath).Length/1MB
                Write-CenteredText "[SUCCESS] Recording saved to:" "Green"
                Write-CenteredText "Location: $localPath" "Gray"
                Write-CenteredText "Size: $([math]::Round($fileSize,2)) MB" "Gray"

                # Clean up device
                adb shell rm $videoPath | Out-Null
                $processSuccess = $true
            }
            else {
                Write-CenteredText "[ERROR] Failed to save recording" "Red"
                $processSuccess = $false
            }
        }
        catch {
            Write-CenteredText "[ERROR] Failed to transfer recording: $_" "Red"
            $processSuccess = $false
        }

        # Automatic log collection for DUT recordings
        if ($videoName -like "dut*" -and (Test-Path $localPath)) {
            Clear-Screen
            Show-CenteredHeader "STEP 4: AUTOMATIC LOG COLLECTION" "-------------------------------"

            # Blinking warning message
            Show-BlinkingMessage "[IMPORTANT] Before collecting logs:" "Red" $null 3

            Write-CenteredText "1. Make sure to STOP logging on the device first" "Red"
            Write-CenteredText "2. Only collect logs if the recording was successful" "Red"
            Write-Host ""

            # Get console width for proper centering
            $consoleWidth = $Host.UI.RawUI.WindowSize.Width
            
            # Center the prompt
            $confirmPrompt = "Have you stopped logging on the device? (Y/N): "
            $padding = [Math]::Max(0, [Math]::Floor(($consoleWidth - $confirmPrompt.Length) / 2))
            $paddedConfirmPrompt = " " * $padding + $confirmPrompt

            Write-Host $paddedConfirmPrompt -NoNewline
            $confirm = Read-Host

                if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                    Write-CenteredText "[STATUS] Detecting available logs..." "Gray"

                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $logPaths = @(
                        @{Type = "debug"; Path = "/data/debuglogger"},
                        @{Type = "ylog"; Path = "/data/ylog"}
                    )
                    
                    $selectedLog = $logPaths | Where-Object { Test-AndroidPath $_.Path } | Select-Object -First 1
                    
                    if ($selectedLog) {
                        $logType = $selectedLog.Type
                        $logPath = $selectedLog.Path
                        $logDir = "${logType}_logs_$timestamp"
                        
                        New-Item -ItemType Directory -Path $logDir -Force | Out-Null

                        Write-CenteredText "[STATUS] Found $logType logs, collecting..." "Gray"

                        Write-Progress -Activity "Collecting Logs" -Status "Please wait..." -PercentComplete 0
                        $null = adb pull $logPath $logDir 2>&1
                        Write-Progress -Activity "Collecting Logs" -Completed -Status "Done"

                        $logSize = (Get-ChildItem $logDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB

                        Show-BlinkingMessage "[SUCCESS] Logs collected successfully!" "Green" $null 3
                        Write-CenteredText "Type: $logType logs" "Gray"
                        Write-CenteredText "Location: $PWD\$logDir" "Cyan"
                        Write-CenteredText "Size: $([math]::Round($logSize, 2)) MB" "Gray"
                    }
                    else {
                        Write-CenteredText "[WARNING] No debuglogger or ylog directory found" "Yellow"
                        Write-CenteredText "If you expected logs, please check device permissions" "Yellow"
                    }
                }
            else {
                Write-CenteredText "[INFO] Log collection skipped by user" "Blue"
            }
        }

        # Completion
        Clear-Screen
        Write-Host ""
        Write-CenteredText "============================================" "Cyan"
        Write-CenteredText "          PROCESS COMPLETED SUCCESSFULLY         " "Green"
        Write-CenteredText "============================================" "Cyan"
        Write-Host ""

        Write-CenteredText "RECORDING DETAILS:" "Yellow"
        Write-CenteredText "------------------" "Yellow"
        Write-CenteredText "Name: $videoName.mp4" "Gray"
        Write-CenteredText "Location: $localPath" "Gray"
        Write-CenteredText "Size: $([math]::Round($fileSize,2)) MB" "Gray"

        if ($logPath) {
            Write-Host ""
            Write-CenteredText "LOG DETAILS:" "Yellow"
            Write-CenteredText "-----------" "Yellow"
            Write-CenteredText "Type: $logType logs" "Gray"
            Write-CenteredText "Location: $PWD\$logDir" "Cyan"
            Write-Host ""
            Write-CenteredText "NOTE: Logs may contain sensitive data" "Magenta"
        }

        Write-Host ""
        Write-CenteredText "Operation completed at $(Get-Date -Format "HH:mm:ss")" "Gray"
        Write-Host ""

        # Open the output folder
        try {
            if ($logPath) {
                # If logs were collected, open the parent folder with recording selected
                Start-Process "explorer.exe" -ArgumentList "/select,`"$localPath`""
                
                do {
                    try {
                        # Start the recording process
                        $success = Start-RecordingProcess
                        
                        # Clear any residual key presses
                        while ([System.Console]::KeyAvailable) {
                            [System.Console]::ReadKey($true) | Out-Null
                        }
                        
                        # Prompt to continue
                        Write-Host ""
                        Write-CenteredText "============================================" "Cyan"
                        Write-CenteredText " RECORDING COMPLETED - CONTINUE OR EXIT? " "Yellow"
                        Write-CenteredText "============================================" "Cyan"
                        Write-Host ""
                        
                        $continue = $null
                        do {
                            $continue = Read-CenteredInput "Do you want to record another video? (Y/N): " $true
                            $continue = $continue.ToUpper()
                        } while ($continue -ne "Y" -and $continue -ne "N")
                        
                        if ($continue -eq "N") {
                            Clear-Screen
                            Write-CenteredText "============================================" "Cyan"
                            Write-CenteredText "  THANK YOU FOR USING ANDROID SCREEN RECORDER  " "Green"
                            Write-CenteredText "============================================" "Cyan"
                            Write-Host ""
                            Write-CenteredText "Exiting..." "Gray"
                            Start-Sleep -Seconds 2
                            break
                        }
                        
                        # Reset ADB connection for next recording
                        adb kill-server 2>$null
                        Start-Sleep -Seconds 1
                        adb start-server 2>$null
                        Start-Sleep -Seconds 1
                        
                        # Clear the screen for the next recording
                        Clear-Screen
                    }
                    catch {
                        Write-CenteredText "[ERROR] An unexpected error occurred: $_" "Red"
                        Write-CenteredText "The script will restart..." "Yellow"
                        Start-Sleep -Seconds 3
                        
                        # Reset ADB connection after error
                        adb kill-server 2>$null
                        Start-Sleep -Seconds 1
                        adb start-server 2>$null
                    }
                } while ($true)

            } else {
                # If no logs, just open the current directory
                Start-Process "explorer.exe" -ArgumentList "`"$PWD`""
            }
            Write-CenteredText "[STATUS] Opened output folder" "Gray"
            do {
                try {
                    # Start the recording process
                    $success = Start-RecordingProcess
                    
                    # Clear any residual key presses
                    while ([System.Console]::KeyAvailable) {
                        [System.Console]::ReadKey($true) | Out-Null
                    }
                    
                    # Prompt to continue
                    Write-Host ""
                    Write-CenteredText "============================================" "Cyan"
                    Write-CenteredText " RECORDING COMPLETED - CONTINUE OR EXIT? " "Yellow"
                    Write-CenteredText "============================================" "Cyan"
                    Write-Host ""
                    
                    $continue = $null
                    do {
                        $continue = Read-CenteredInput "Do you want to record another video? (Y/N): " $true
                        $continue = $continue.ToUpper()
                    } while ($continue -ne "Y" -and $continue -ne "N")
                    
                    if ($continue -eq "N") {
                        Clear-Screen
                        Write-CenteredText "============================================" "Cyan"
                        Write-CenteredText "  THANK YOU FOR USING ANDROID SCREEN RECORDER  " "Green"
                        Write-CenteredText "============================================" "Cyan"
                        Write-Host ""
                        Write-CenteredText "Exiting..." "Gray"
                        Start-Sleep -Seconds 2
                        break
                    }
                    
                    # Reset ADB connection for next recording
                    adb kill-server 2>$null
                    Start-Sleep -Seconds 1
                    adb start-server 2>$null
                    Start-Sleep -Seconds 1
                    
                    # Clear the screen for the next recording
                    Clear-Screen
                }
                catch {
                    Write-CenteredText "[ERROR] An unexpected error occurred: $_" "Red"
                    Write-CenteredText "The script will restart..." "Yellow"
                    Start-Sleep -Seconds 3
                    
                    # Reset ADB connection after error
                    adb kill-server 2>$null
                    Start-Sleep -Seconds 1
                    adb start-server 2>$null
                }
            } while ($true)
        } catch {
            Write-CenteredText "[NOTE] Could not open folder automatically" "Yellow"
            Write-CenteredText "You can find your files at:" "Yellow"
            Write-CenteredText "$PWD" "Cyan"
        }
       
    }
    
    return $processSuccess
}



# Main execution loop for continuous operation
do {
    try {
        # Start the recording process
        $success = Start-RecordingProcess
        
        # Clear any residual key presses
        while ([System.Console]::KeyAvailable) {
            [System.Console]::ReadKey($true) | Out-Null
        }
        
        # Prompt to continue
        Write-Host ""
        Write-CenteredText "============================================" "Cyan"
        Write-CenteredText " RECORDING COMPLETED - CONTINUE OR EXIT? " "Yellow"
        Write-CenteredText "============================================" "Cyan"
        Write-Host ""
        
        $continue = $null
        do {
            $continue = Read-CenteredInput "Do you want to record another video? (Y/N): " $true
            $continue = $continue.ToUpper()
        } while ($continue -ne "Y" -and $continue -ne "N")
        
        if ($continue -eq "N") {
            Clear-Screen
            Write-CenteredText "============================================" "Cyan"
            Write-CenteredText "  THANK YOU FOR USING ANDROID SCREEN RECORDER  " "Green"
            Write-CenteredText "============================================" "Cyan"
            Write-Host ""
            Write-CenteredText "Exiting..." "Gray"
            Start-Sleep -Seconds 2
            break
        }
        
        # Reset ADB connection for next recording
        adb kill-server 2>$null
        Start-Sleep -Seconds 1
        adb start-server 2>$null
        Start-Sleep -Seconds 1
        
        # Clear the screen for the next recording
        Clear-Screen
    }
    catch {
        Write-CenteredText "[ERROR] An unexpected error occurred: $_" "Red"
        Write-CenteredText "The script will restart..." "Yellow"
        Start-Sleep -Seconds 3
        
        # Reset ADB connection after error
        adb kill-server 2>$null
        Start-Sleep -Seconds 1
        adb start-server 2>$null
    }
} while ($true)

# Use this code create a simple function that I will call to prompt a user whether they want to continue recording or not