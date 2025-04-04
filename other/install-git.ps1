# Script to download and install the latest version of Git for Windows

try {
    Write-Host "Finding latest Git for Windows version..." -ForegroundColor Cyan
    
    # Get the latest release information from GitHub API
    $releaseUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $releaseInfo = Invoke-RestMethod -Uri $releaseUrl -Headers @{
        "Accept" = "application/vnd.github.v3+json"
    }
    
    # Find the 64-bit installer asset
    $installer = $releaseInfo.assets | Where-Object { 
        $_.name -match "Git-.*-64-bit\.exe$" 
    } | Select-Object -First 1
    
    if (-not $installer) {
        throw "Could not find 64-bit Git installer in the latest release"
    }
    
    $downloadUrl = $installer.browser_download_url
    $version = $releaseInfo.tag_name
    
    Write-Host "Found latest version: $version" -ForegroundColor Green
    Write-Host "Download URL: $downloadUrl" -ForegroundColor Gray
    
    # Download Git installer
    $installPath = "$env:TEMP\git-installer.exe"
    Write-Host "Downloading Git installer to $installPath..." -ForegroundColor Cyan
    
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installPath
    
    if (-not (Test-Path $installPath)) {
        throw "Failed to download Git installer"
    }
    
    Write-Host "Download complete. Starting installation..." -ForegroundColor Green
    
    # Run the installer (silently with default options)
    Start-Process -FilePath $installPath -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL" -Wait
    
    # Clean up
    Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
    Remove-Item $installPath
    
    Write-Host "Git installation complete!" -ForegroundColor Green
    Write-Host "To verify installation, open a new terminal window and run: git --version" -ForegroundColor Yellow
} 
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Installation failed. Please try downloading Git manually from https://git-scm.com/download/win" -ForegroundColor Red
}