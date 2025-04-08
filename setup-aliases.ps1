# PowerShell Script Alias Manager
# Creates aliases for PS1 files with customization options
# v1.1.0

#Requires -RunAsAdministrator

function Show-Header {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "          PowerShell Script Alias Manager         " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host
}

function Show-Error {
    param (
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [bool]$Fatal = $false
    )
    
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if ($ErrorRecord) {
        Write-Host "  Details: $($ErrorRecord.Exception.Message)" -ForegroundColor Red
    }
    
    if ($Fatal) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

function Initialize-Environment {
    # Check for and create PowerShell profile if needed
    if (-not (Test-Path -Path $PROFILE)) {
        Write-Host "Creating PowerShell profile..." -ForegroundColor Yellow
        try {
            New-Item -ItemType File -Path $PROFILE -Force | Out-Null
            Write-Host "[OK] PowerShell profile created at $PROFILE" -ForegroundColor Green
        }
        catch {
            Show-Error -Message "Failed to create PowerShell profile." -ErrorRecord $_ -Fatal $true
        }
    }
    
    # Backup the profile
    try {
        Copy-Item -Path $PROFILE -Destination "$PROFILE.bak" -Force
        Write-Host "[OK] Profile backup created: $PROFILE.bak" -ForegroundColor Green
    }
    catch {
        Show-Error -Message "Failed to back up profile." -ErrorRecord $_ -Fatal $false
    }
    
    # Add current directory to PATH if not already there
    $currentDir = Get-Location | Select-Object -ExpandProperty Path
    $systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    
    if (-not $systemPath.Contains($currentDir)) {
        try {
            [Environment]::SetEnvironmentVariable("Path", $systemPath + ";" + $currentDir, "Machine")
            $env:Path += ";$currentDir"  # Update current session
            Write-Host "[OK] Current directory added to system PATH" -ForegroundColor Green
        }
        catch {
            Show-Error -Message "Failed to update system PATH." -ErrorRecord $_ -Fatal $false
        }
    }
    
    return $currentDir
}

function Get-CleanAliasName {
    param (
        [string]$OriginalName,
        [string]$CustomName = ""
    )
    
    $aliasName = if ($CustomName) { $CustomName } else { $OriginalName }
    $cleanAliasName = $aliasName -replace '[^a-zA-Z0-9_-]', ''
    
    if ($cleanAliasName -eq '') {
        return $null
    }
    
    return $cleanAliasName
}

function Extract-FileDescription {
    param (
        [System.IO.FileInfo]$File
    )
    
    try {
        $content = Get-Content -Path $File.FullName -Raw -ErrorAction Stop
        $descriptionPattern = '(?s)#\s*<DESCRIPTION>(.*?)#\s*</DESCRIPTION>'
        
        if ($content -match $descriptionPattern) {
            return @{
                Success     = $true
                Description = $matches[1].Trim()
            }
        }
        else {
            return @{
                Success     = $false
                Description = "No description found in file format '<DESCRIPTION></DESCRIPTION>'."
            }
        }
    }
    catch {
        return @{
            Success     = $false
            Description = "Error reading file: $($_.Exception.Message)"
        }
    }
}

function Format-ScriptDescription {
    param (
        [string]$Description
    )
    
    # Format and highlight features in description
    $lines = $Description -split "`n"
    
    foreach ($line in $lines) {
        # Special formatting for 'Features:' section and bullet points
        if ($line -match '^#\s*Features:\s*$') {
            Write-Host "$($line.TrimStart('#').Trim())" -ForegroundColor Blue
        }
        elseif ($line -match '^\s*#\s*-\s+(.+)$') {
            # Feature bullet points - use DarkCyan for professional appearance
            $feature = $matches[1]
            Write-Host "  - $feature" -ForegroundColor DarkCyan
        }
        else {
            # Regular description lines
            Write-Host "$($line.TrimStart('#').Trim())" -ForegroundColor White
        }
    }
}

function Set-ScriptAlias {
    param (
        [System.IO.FileInfo]$File,
        [string]$CustomName = "",
        [ref]$ProfileContent
    )
    
    $aliasName = Get-CleanAliasName -OriginalName $File.BaseName -CustomName $CustomName
    
    if ($null -eq $aliasName) {
        Write-Host "[WARNING] Skipping file '$($File.Name)' - invalid alias name" -ForegroundColor Yellow
        return $false
    }
    
    $scriptPath = $File.FullName
    $aliasLine = "Set-Alias -Name $aliasName -Value '$scriptPath'"
    
    # Check if alias already exists in profile
    $existingAliasLine = $ProfileContent.Value | Where-Object { $_ -match "Set-Alias -Name $aliasName -Value" }
    
    $updated = $false
    if ($existingAliasLine -and $existingAliasLine -ne $aliasLine) {
        Write-Host "[UPDATE] Updating existing alias: '$aliasName'" -ForegroundColor Yellow
        $ProfileContent.Value = $ProfileContent.Value -replace "Set-Alias -Name $aliasName -Value .*", $aliasLine
        $updated = $true
    } 
    elseif (-not $existingAliasLine) {
        $ProfileContent.Value += "`n$aliasLine"
        $updated = $true
    } 
    else {
        Write-Host "[INFO] Alias '$aliasName' already exists (unchanged)" -ForegroundColor DarkGray
        $updated = $false
    }
    
    # Create alias in current session
    Set-Alias -Name $aliasName -Value $scriptPath -Scope Global -Force
    
    if ($CustomName) {
        Write-Host "[OK] Custom alias '$aliasName' -> $($File.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "[OK] Default alias '$aliasName' -> $($File.Name)" -ForegroundColor Green
    }
    
    return $updated
}

# Helper function to center text
filter PadCenter([int]$totalLength) {
    $padding = $totalLength - $_.Length
    if ($padding -le 0) { return $_ }
    $leftPad = [math]::Floor($padding / 2)
    $rightPad = $padding - $leftPad
    return (" " * $leftPad) + $_ + (" " * $rightPad)
}

function Display-ScriptInfo {
    param (
        [System.IO.FileInfo]$File
    )
    
    # Clear the screen for a clean look
    Clear-Host
    
    # Get console width for proper formatting
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    $halfWidth = [Math]::Floor(($consoleWidth - 3) / 2)  # -3 for separator
    
    # Show elegant header spanning the full width
    $headerText = "SCRIPT ALIAS SETUP"
    $padding = [Math]::Floor(($consoleWidth - $headerText.Length) / 2)
    $headerBar = "=" * $consoleWidth
    
    Write-Host $headerBar -ForegroundColor Cyan
    Write-Host (" " * $padding + $headerText) -ForegroundColor White
    Write-Host $headerBar -ForegroundColor Cyan
    Write-Host
    
    # Display file name in a highlighted box spanning the full width
    $fileBox = "  FILE: $($File.Name)  "
    $filePadding = [Math]::Floor(($consoleWidth - $fileBox.Length) / 2)
    Write-Host (" " * $filePadding) -NoNewline
    Write-Host $fileBox -ForegroundColor Black -BackgroundColor Cyan
    Write-Host
    
    # Extract description
    $descriptionResult = Extract-FileDescription -File $File
    
    # Split description into lines and process features separately
    $descLines = @()
    $featuresLines = @()
    
    if ($descriptionResult.Success) {
        $lines = $descriptionResult.Description -split "`n"
        $inFeatures = $false
        
        foreach ($line in $lines) {
            $trimmedLine = $line.TrimStart('#').Trim()
            
            if ($line -match '^#\s*Features:\s*$') {
                $inFeatures = $true
                $featuresLines += "Features:"
            }
            elseif ($inFeatures -and $line -match '^\s*#\s*-\s+(.+)$') {
                $feature = $matches[1]
                $featuresLines += "  * $feature"
            }
            elseif ($trimmedLine) {
                $descLines += $trimmedLine
            }
        }
    }
    else {
        $descLines += $descriptionResult.Description
    }
    
    # Display in two columns: Description on left, Features on right (using standard ASCII characters)
    Write-Host "+" + ("-" * ($halfWidth - 2)) + "+ +" + ("-" * ($halfWidth - 2)) + "+" -ForegroundColor DarkCyan
    Write-Host "|" + (" DESCRIPTION".PadRight($halfWidth - 2)) + "| |" + (" FEATURES".PadRight($halfWidth - 2)) + "|" -ForegroundColor Blue
    Write-Host "+" + ("-" * ($halfWidth - 2)) + "+ +" + ("-" * ($halfWidth - 2)) + "+" -ForegroundColor DarkCyan

    # Determine how many rows to display
    $maxRows = [Math]::Max($descLines.Count, $featuresLines.Count)
    
    for ($i = 0; $i -lt $maxRows; $i++) {
        $leftText = if ($i -lt $descLines.Count) { $descLines[$i] } else { "" }
        $rightText = if ($i -lt $featuresLines.Count) { $featuresLines[$i] } else { "" }
        
        # Ensure text doesn't exceed column width
        if ($leftText.Length -gt $halfWidth - 4) {
            $leftText = $leftText.Substring(0, $halfWidth - 7) + "..."
        }
        
        if ($rightText.Length -gt $halfWidth - 4) {
            $rightText = $rightText.Substring(0, $halfWidth - 7) + "..."
        }
        
        # Output left column
        Write-Host "|" -ForegroundColor DarkCyan -NoNewline
        Write-Host (" " + $leftText.PadRight($halfWidth - 3)) -ForegroundColor White -NoNewline
        
        # Output column separator
        Write-Host "| |" -ForegroundColor DarkCyan -NoNewline
        
        # Output right column
        $color = if ($rightText -match "^Features:") { "Blue" } elseif ($rightText -match "^  \*") { "DarkCyan" } else { "White" }
        Write-Host (" " + $rightText.PadRight($halfWidth - 3)) -ForegroundColor $color -NoNewline
        
        # Output end of line
        Write-Host "|" -ForegroundColor DarkCyan
    }
    
    # Bottom border
    Write-Host "+" + ("-" * ($halfWidth - 2)) + "+ +" + ("-" * ($halfWidth - 2)) + "+" -ForegroundColor DarkCyan
    Write-Host
    
    # Alias prompt
    Write-Host "ALIAS SETUP" -ForegroundColor Yellow
    Write-Host "Default alias: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($File.BaseName)" -ForegroundColor White
}

function Process-ScriptFiles {
    param (
        [string]$Directory
    )
    
    # Get PS1 files excluding this script itself
    $scriptName = $MyInvocation.MyCommand.Name
    try {
        $ps1Files = Get-ChildItem -Path $Directory -Filter "*.ps1" -ErrorAction Stop | 
        Where-Object { $_.Name -ne $scriptName }
    }
    catch {
        Show-Error -Message "Failed to scan directory for PS1 files." -ErrorRecord $_ -Fatal $true
    }
    
    if ($ps1Files.Count -eq 0) {
        Show-Error -Message "No PS1 files found in the current directory." -Fatal $true
    }
    
    # Get current profile content
    try {
        $profileContent = Get-Content $PROFILE -ErrorAction SilentlyContinue
        if ($null -eq $profileContent) { $profileContent = @() }
    }
    catch {
        Show-Error -Message "Failed to read PowerShell profile." -ErrorRecord $_ -Fatal $true
    }
    
    $profileUpdated = $false
    $successCount = 0
    $totalScripts = $ps1Files.Count
    
    # Process each script one at a time
    foreach ($file in $ps1Files) {
        # Show only the current file's info
        Display-ScriptInfo -File $file
        
        # Show progress indicator
        Write-Host "[$($successCount + 1)/$totalScripts]" -ForegroundColor DarkGray
        
        # Ask for custom alias name
        Write-Host "Enter custom alias name (or press Enter to use default): " -ForegroundColor Cyan -NoNewline
        $customAlias = Read-Host
        
        $result = Set-ScriptAlias -File $file -CustomName $customAlias -ProfileContent ([ref]$profileContent)
        if ($result) { $profileUpdated = $true }
        $successCount++
    }
    
    # Save profile if updated
    if ($profileUpdated) {
        try {
            Set-Content -Path $PROFILE -Value $profileContent -ErrorAction Stop
            Write-Host "`n[✓] PowerShell profile updated with aliases" -ForegroundColor Green
        }
        catch {
            Show-Error -Message "Failed to save PowerShell profile." -ErrorRecord $_ -Fatal $false
        }
    }
    
    # Reload profile
    try {
        . $PROFILE
        Write-Host "[✓] Profile reloaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to reload profile. You may need to restart PowerShell." -ForegroundColor Yellow
    }
    
    # Get console width for proper formatting
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    
    Clear-Host
    Write-Host "+" + ("=" * ($consoleWidth - 2)) + "+" -ForegroundColor Green
    Write-Host "|" + (" SETUP COMPLETED ".PadCenter($consoleWidth - 2)) + "|" -ForegroundColor Green
    Write-Host "+" + ("=" * ($consoleWidth - 2)) + "+" -ForegroundColor Green
    Write-Host "`n[✓] Created aliases for $successCount PowerShell scripts" -ForegroundColor Green
    Write-Host "[✓] Profile location: $PROFILE" -ForegroundColor Green
    Write-Host "`nPress any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    return $successCount
}
}

# Main script execution
try {
    Show-Header
    
    $currentDir = Initialize-Environment
    Write-Host "`nWorking directory: $currentDir`n" -ForegroundColor Cyan
    
    $successCount = Process-ScriptFiles -Directory $currentDir
    
    Write-Host "`n=================================================" -ForegroundColor Green
    Write-Host "                Setup Completed!                 " -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host "[OK] Created aliases for $successCount PowerShell scripts" -ForegroundColor Green
    Write-Host "[OK] Profile location: $PROFILE" -ForegroundColor Green
    Write-Host
    Write-Host "Note: Some changes may require restarting PowerShell." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
}
catch {
    Show-Error -Message "Unexpected error occurred." -ErrorRecord $_ -Fatal $true
}