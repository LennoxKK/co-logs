# Flexible PS1 Alias Setup Script with Enhanced Error Handling
# Usage: .\setup.ps1 -ScriptName "record_with_touches.ps1" -AliasName "recordtouch"
param (
    [Parameter(Mandatory=$true)]
    [string]$ScriptName,
    
    [Parameter(Mandatory=$true)]
    [string]$AliasName
)

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
    # Use the current directory path
    $scriptDir = Get-Location | Select-Object -ExpandProperty Path
    $scriptPath = Join-Path -Path $scriptDir -ChildPath $ScriptName
    
    # Check if script file exists
    if (-not (Test-Path -Path $scriptPath)) {
        Handle-Error -Message "Script file '$ScriptName' not found in current directory: $scriptDir" -Fatal $true
    }
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Handle-Error -Message "This script requires administrator privileges. Please run PowerShell as Administrator and try again." -Fatal $true
    }
    
    # Validate alias name format
    if ($AliasName -match '[^a-zA-Z0-9_-]') {
        Handle-Error -Message "Alias name contains invalid characters. Use only letters, numbers, underscore, and hyphen." -Fatal $true
    }
    
    # Add to PATH
    Write-Host "Adding current directory to system PATH..."
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($null -eq $currentPath) {
            Handle-Error -Message "Could not retrieve system PATH variable." -Fatal $true
        }
        
        if (-not $currentPath.Contains($scriptDir)) {
            [Environment]::SetEnvironmentVariable("Path", $currentPath + ";" + $scriptDir, "Machine")
            $env:Path += ";$scriptDir"  # Also update current session
            Write-Host "Directory added to system PATH: $scriptDir" -ForegroundColor Green
        } else {
            Write-Host "Directory already in system PATH: $scriptDir" -ForegroundColor Yellow
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
    
    # Add alias to PowerShell profile
    Write-Host "Adding alias to PowerShell profile..."
    try {
        $aliasLine = "Set-Alias -Name $AliasName -Value '$scriptPath'"
        $profileContent = Get-Content $PROFILE -ErrorAction SilentlyContinue
        
        # Check if alias already exists but with different path
        $existingAliasLine = $profileContent | Where-Object { $_ -match "Set-Alias -Name $AliasName -Value" }
        if ($existingAliasLine -and $existingAliasLine -ne $aliasLine) {
            Write-Host "WARNING: Alias '$AliasName' already exists with different path. Updating..." -ForegroundColor Yellow
            $profileContent = $profileContent -replace "Set-Alias -Name $AliasName -Value .*", $aliasLine
            Set-Content -Path $PROFILE -Value $profileContent
            Write-Host "Alias updated in profile" -ForegroundColor Green
        } elseif (-not $existingAliasLine) {
            Add-Content $PROFILE "`n$aliasLine"
            Write-Host "Alias '$AliasName' added to profile" -ForegroundColor Green
        } else {
            Write-Host "Alias '$AliasName' already exists with correct path" -ForegroundColor Yellow
        }
    } catch {
        Handle-Error -Message "Failed to update PowerShell profile." -ErrorRecord $_ -Fatal $false
        Write-Host "You may need to manually add this line to your profile ($PROFILE):" -ForegroundColor Yellow
        Write-Host "  $aliasLine" -ForegroundColor Yellow
    }
    
    # Create the alias in the current session
    try {
        Set-Alias -Name $AliasName -Value $scriptPath -Scope Global -Force
        Write-Host "Alias '$AliasName' created in current session" -ForegroundColor Green
    } catch {
        Handle-Error -Message "Could not create alias in current session." -ErrorRecord $_ -Fatal $false
    }
    
    # Backup the profile before reloading
    try {
        Copy-Item -Path $PROFILE -Destination "$PROFILE.bak" -Force
        Write-Host "Profile backup created: $PROFILE.bak" -ForegroundColor Green
    } catch {
        Handle-Error -Message "Failed to create profile backup. Continuing anyway." -ErrorRecord $_ -Fatal $false
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
    
    # Verify alias works
    try {
        $command = Get-Command -Name $AliasName -ErrorAction Stop
        Write-Host "Verified alias '$AliasName' points to: $($command.Definition)" -ForegroundColor Green
    } catch {
        Handle-Error -Message "Alias created but not immediately accessible." -ErrorRecord $_ -Fatal $false
        Write-Host "You may need to restart PowerShell to use the alias." -ForegroundColor Yellow
    }
    
    Write-Host "`nSetup completed successfully!" -ForegroundColor Green
    Write-Host "You can now use '$AliasName' command from anywhere in PowerShell to run '$ScriptName'."
    Write-Host "The script is located at: $scriptPath"
    Write-Host "Note: You may need to restart PowerShell or your system for some changes to take effect."

} catch {
    Handle-Error -Message "Unexpected error occurred." -ErrorRecord $_ -Fatal $true
}