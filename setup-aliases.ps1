# Batch PS1 Alias Setup Script for Current Directory
# This script automatically creates aliases for all PS1 files in the current directory

# Error handling function
function Handle-Error {
    param (
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [bool]$Fatal = $false
    )
    
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if ($ErrorRecord) {
        Write-Host "  Details: $($ErrorRecord.Exception.Message)" -ForegroundColor Red
        Write-Host "  Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    }
    
    if ($Fatal) {
        Write-Host "Exiting script due to fatal error." -ForegroundColor Red
        exit 1
    }
}

try {
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Handle-Error -Message "This script requires administrator privileges. Please run PowerShell as Administrator and try again." -Fatal $true
    }
    
    # Use the current directory
    $currentDir = Get-Location | Select-Object -ExpandProperty Path
    
    # Get all PS1 files in the current directory
    $ps1Files = Get-ChildItem -Path $currentDir -Filter "*.ps1"
    
    if ($ps1Files.Count -eq 0) {
        Handle-Error -Message "No PS1 files found in the current directory." -Fatal $true
    }
    
    Write-Host "Found $($ps1Files.Count) PS1 files in the current directory." -ForegroundColor Green
    
    # Add current directory to PATH
    Write-Host "Adding current directory to system PATH..."
    try {
        $systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($null -eq $systemPath) {
            Handle-Error -Message "Could not retrieve system PATH variable." -Fatal $true
        }
        
        if (-not $systemPath.Contains($currentDir)) {
            [Environment]::SetEnvironmentVariable("Path", $systemPath + ";" + $currentDir, "Machine")
            $env:Path += ";$currentDir"  # Also update current session
            Write-Host "Directory added to system PATH: $currentDir" -ForegroundColor Green
        } else {
            Write-Host "Directory already in system PATH: $currentDir" -ForegroundColor Yellow
        }
    } catch {
        Handle-Error -Message "Failed to update system PATH." -ErrorRecord $_ -Fatal $true
    }
    
    # Create/update PowerShell profile if it doesn't exist
    try {
        if (-not (Test-Path -Path $PROFILE)) {
            Write-Host "Creating PowerShell profile..."
            New-Item -ItemType File -Path $PROFILE -Force | Out-Null
            if (-not (Test-Path -Path $PROFILE)) {
                Handle-Error -Message "Failed to create PowerShell profile at $PROFILE" -Fatal $true
            }
            Write-Host "PowerShell profile created: $PROFILE"
        }
    } catch {
        Handle-Error -Message "Error accessing or creating PowerShell profile." -ErrorRecord $_ -Fatal $true
    }
    
    # Backup the profile before modifying
    try {
        Copy-Item -Path $PROFILE -Destination "$PROFILE.bak" -Force
        Write-Host "Profile backup created: $PROFILE.bak" -ForegroundColor Green
    } catch {
        Handle-Error -Message "Failed to create profile backup. Continuing anyway." -ErrorRecord $_ -Fatal $false
    }
    
    # Process each PS1 file
    $successCount = 0
    $profileContent = Get-Content $PROFILE -ErrorAction SilentlyContinue
    $profileUpdated = $false
    
    foreach ($file in $ps1Files) {
        try {
            # Skip the script itself to avoid recursion
            if ($file.Name -eq $MyInvocation.MyCommand.Name) {
                Write-Host "Skipping setup script itself: $($file.Name)" -ForegroundColor Yellow
                continue
            }
            
            # Generate alias name from filename (remove .ps1 extension)
            $aliasName = $file.BaseName
            
            # Clean alias name - only allow letters, numbers, underscore and hyphen
            $cleanAliasName = $aliasName -replace '[^a-zA-Z0-9_-]', ''
            
            if ($cleanAliasName -ne $aliasName) {
                Write-Host "Alias name cleaned: '$aliasName' → '$cleanAliasName'" -ForegroundColor Yellow
                $aliasName = $cleanAliasName
            }
            
            if ($aliasName -eq '') {
                Write-Host "Skipping file '$($file.Name)' - resulted in empty alias name after cleaning" -ForegroundColor Yellow
                continue
            }
            
            $scriptPath = $file.FullName
            
            # Add alias to PowerShell profile
            $aliasLine = "Set-Alias -Name $aliasName -Value '$scriptPath'"
            
            # Check if alias already exists but with different path
            $existingAliasLine = $profileContent | Where-Object { $_ -match "Set-Alias -Name $aliasName -Value" }
            if ($existingAliasLine -and $existingAliasLine -ne $aliasLine) {
                Write-Host "Alias '$aliasName' already exists with different path. Updating..." -ForegroundColor Yellow
                $profileContent = $profileContent -replace "Set-Alias -Name $aliasName -Value .*", $aliasLine
                $profileUpdated = $true
            } elseif (-not $existingAliasLine) {
                $profileContent += "`n$aliasLine"
                $profileUpdated = $true
            } else {
                Write-Host "Alias '$aliasName' already exists with correct path. Skipping." -ForegroundColor Yellow
            }
            
            # Create the alias in the current session
            Set-Alias -Name $aliasName -Value $scriptPath -Scope Global -Force
            
            Write-Host "Alias '$aliasName' set up for script: $($file.Name)" -ForegroundColor Green
            $successCount++
        } catch {
            Handle-Error -Message "Failed to set up alias for $($file.Name)" -ErrorRecord $_ -Fatal $false
        }
    }
    
    # Save updated profile if any changes were made
    if ($profileUpdated) {
        try {
            Set-Content -Path $PROFILE -Value $profileContent
            Write-Host "PowerShell profile updated with new aliases" -ForegroundColor Green
        } catch {
            Handle-Error -Message "Failed to update PowerShell profile." -ErrorRecord $_ -Fatal $false
            Write-Host "You may need to manually update your profile." -ForegroundColor Yellow
        }
    }
    
    # Reload the profile to apply changes to current session
    Write-Host "Reloading PowerShell profile..."
    try {
        . $PROFILE
        Write-Host "Profile reloaded successfully" -ForegroundColor Green
    } catch {
        Handle-Error -Message "Failed to reload profile." -ErrorRecord $_ -Fatal $false
        Write-Host "You may need to restart PowerShell to apply changes." -ForegroundColor Yellow
    }
    
    Write-Host "`nSetup completed successfully!" -ForegroundColor Green
    Write-Host "Created aliases for $successCount out of $($ps1Files.Count - 1) PS1 files (excluding this setup script)."
    Write-Host "Note: You may need to restart PowerShell or your system for some changes to take effect."
    
} catch {
    Handle-Error -Message "Unexpected error occurred." -ErrorRecord $_ -Fatal $true
}