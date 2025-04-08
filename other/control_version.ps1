# Optimized PowerShell Repository Background Update Script
# This script compares the existing repo with the cloned version, 
# only updates changed files, and performs the update in the background
# while allowing continued use of the existing version
# Usage: ./OptimizedUpdateRepo.ps1

# Configuration
$repoUrl = "https://github.com/LennoxKK/co-logs.git"
$tempFolderPath = ".\temp-repo"
$mainFolderPath = ".\co-logs"
$backupFolderPath = ".\co-logs-backup"
$logFile = ".\repo-update-log.txt"
$updateStatusFile = ".\update-status.txt"

# Function to log messages
function Write-Log {
    param (
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host "$timestamp - $Message"
}

# Function to update status file
function Update-Status {
    param (
        [string]$Status,
        [int]$PercentComplete = -1
    )
    
    $statusData = @{
        "Status" = $Status
        "Timestamp" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "PercentComplete" = $PercentComplete
    }
    
    $statusData | ConvertTo-Json | Out-File -FilePath $updateStatusFile -Force
}

# Function to test PowerShell scripts
function Test-PowerShellScripts {
    param (
        [string]$RepoPath
    )
    
    Write-Log "Testing PowerShell scripts in $RepoPath..."
    $allTestsPassed = $true
    $totalFiles = 0
    $testedFiles = 0
    
    # Find all PS1 files in the repository
    $ps1Files = Get-ChildItem -Path $RepoPath -Filter "*.ps1" -Recurse
    
    if ($ps1Files.Count -eq 0) {
        Write-Log "Warning: No PowerShell scripts found in the repository"
        return $false
    }
    
    $totalFiles = $ps1Files.Count
    Write-Log "Found $totalFiles PowerShell scripts to test"
    
    foreach ($file in $ps1Files) {
        $testedFiles++
        $percentComplete = [math]::Floor(($testedFiles / $totalFiles) * 100)
        Update-Status -Status "Testing scripts: $testedFiles of $totalFiles" -PercentComplete $percentComplete
        
        Write-Log "Testing script: $($file.FullName)"
        
        # Test 1: Check PowerShell syntax
        try {
            $syntaxErrors = $null
            [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$syntaxErrors)
            
            if ($syntaxErrors.Count -gt 0) {
                Write-Log "Syntax errors found in $($file.Name):"
                foreach ($error in $syntaxErrors) {
                    Write-Log "  Line $($error.Token.StartLine): $($error.Message)"
                }
                $allTestsPassed = $false
                continue
            }
            
            # Test 2: Parse script with more advanced parser
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            
            if ($errors.Count -gt 0) {
                Write-Log "Parser errors found in $($file.Name):"
                foreach ($error in $errors) {
                    Write-Log "  Line $($error.Extent.StartLineNumber): $($error.Message)"
                }
                $allTestsPassed = $false
                continue
            }
            
            # Test 3: Try to load the script in a controlled environment
            $tempTestFile = [System.IO.Path]::GetTempFileName() + ".ps1"
            
            @"
try {
    # Load the script without executing functions (dot sourcing)
    . "$($file.FullName)" -ErrorAction Stop
    Write-Output "Script loaded successfully"
    exit 0
} catch {
    Write-Error "`$_"
    exit 1
}
"@ | Out-File -FilePath $tempTestFile
            
            $result = Start-Process powershell.exe -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$tempTestFile`"" -Wait -PassThru -RedirectStandardOutput "$tempTestFile.out" -RedirectStandardError "$tempTestFile.err"
            
            if ($result.ExitCode -ne 0) {
                $errorOutput = Get-Content "$tempTestFile.err" -Raw
                Write-Log "Script $($file.Name) failed to load: $errorOutput"
                $allTestsPassed = $false
            } else {
                Write-Log "Script $($file.Name) passed all tests"
            }
            
            # Clean up temp files
            Remove-Item -Path $tempTestFile -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempTestFile.out" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempTestFile.err" -Force -ErrorAction SilentlyContinue
            
        } catch {
            Write-Log "Error testing $($file.Name): $_"
            $allTestsPassed = $false
        }
    }
    
    if ($allTestsPassed) {
        Write-Log "All PowerShell scripts passed tests"
    } else {
        Write-Log "Some PowerShell scripts failed tests"
    }
    
    return $allTestsPassed
}

# Function to compare files and get changes
function Compare-Repositories {
    param (
        [string]$SourcePath,
        [string]$TargetPath
    )
    
    Write-Log "Comparing repositories: $SourcePath vs $TargetPath"
    
    $changes = @{
        New = @()
        Modified = @()
        Deleted = @()
    }
    
    # If target doesn't exist, everything is new
    if (-not (Test-Path $TargetPath)) {
        Write-Log "Target repository doesn't exist, all files will be added"
        $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File
        $changes.New = $sourceFiles | ForEach-Object { $_.FullName.Substring($SourcePath.Length + 1) }
        return $changes
    }
    
    # Get all files from source
    $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File
    $targetFiles = Get-ChildItem -Path $TargetPath -Recurse -File
    
    # Convert to hashtable for faster lookups
    $targetFilesHash = @{}
    foreach ($file in $targetFiles) {
        $relativePath = $file.FullName.Substring($TargetPath.Length + 1)
        $targetFilesHash[$relativePath] = $file
    }
    
    # Check for new and modified files
    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($SourcePath.Length + 1)
        
        if (-not $targetFilesHash.ContainsKey($relativePath)) {
            # New file
            $changes.New += $relativePath
        } else {
            # Compare file content to see if it's modified
            $sourceHash = Get-FileHash -Path $file.FullName -Algorithm MD5
            $targetHash = Get-FileHash -Path $targetFilesHash[$relativePath].FullName -Algorithm MD5
            
            if ($sourceHash.Hash -ne $targetHash.Hash) {
                $changes.Modified += $relativePath
            }
            
            # Remove from target hash to track deleted files
            $targetFilesHash.Remove($relativePath)
        }
    }
    
    # Remaining files in target are deleted in source
    $changes.Deleted = $targetFilesHash.Keys
    
    Write-Log "Found $($changes.New.Count) new files, $($changes.Modified.Count) modified files, and $($changes.Deleted.Count) deleted files"
    
    return $changes
}

# Background job for updating repository
$backgroundJobScript = {
    param(
        $TempFolderPath,
        $MainFolderPath,
        $BackupFolderPath,
        $LogFile,
        $UpdateStatusFile,
        $Changes
    )
    
    try {
        # Function to log messages (duplicated for job scope)
        function Write-Log {
            param (
                [string]$Message
            )
            
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
        }
        
        # Function to update status file (duplicated for job scope)
        function Update-Status {
            param (
                [string]$Status,
                [int]$PercentComplete = -1
            )
            
            $statusData = @{
                "Status" = $Status
                "Timestamp" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "PercentComplete" = $PercentComplete
            }
            
            $statusData | ConvertTo-Json | Out-File -FilePath $UpdateStatusFile -Force
        }
        
        Write-Log "Starting background update process..."
        Update-Status -Status "Starting update" -PercentComplete 0
        
        # Create backup of existing files that will be modified
        if (Test-Path $MainFolderPath) {
            Write-Log "Creating backup of files that will be changed..."
            
            # Remove old backup if it exists
            if (Test-Path $BackupFolderPath) {
                Remove-Item -Path $BackupFolderPath -Recurse -Force
            }
            
            # Create backup folder structure
            New-Item -ItemType Directory -Path $BackupFolderPath -Force | Out-Null
            
            # Copy files that will be modified
            $filesToBackup = $Changes.Modified + $Changes.Deleted
            $backupCount = 0
            $totalToBackup = $filesToBackup.Count
            
            foreach ($file in $filesToBackup) {
                $sourcePath = Join-Path -Path $MainFolderPath -ChildPath $file
                $targetPath = Join-Path -Path $BackupFolderPath -ChildPath $file
                $targetDir = Split-Path -Path $targetPath -Parent
                
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                Copy-Item -Path $sourcePath -Destination $targetPath -Force
                $backupCount++
                
                if ($totalToBackup -gt 0) {
                    $percentComplete = [math]::Floor(($backupCount / $totalToBackup) * 30) # 30% of total progress
                    Update-Status -Status "Backing up files: $backupCount of $totalToBackup" -PercentComplete $percentComplete
                }
            }
            
            Write-Log "Backup of changed files completed"
        }
        
        # Apply changes
        Write-Log "Applying changes to repository..."
        Update-Status -Status "Applying changes" -PercentComplete 30
        
        # Create any missing directories in main folder
        if (-not (Test-Path $MainFolderPath)) {
            New-Item -ItemType Directory -Path $MainFolderPath -Force | Out-Null
        }
        
        # Process new and modified files
        $updateCount = 0
        $totalToUpdate = $Changes.New.Count + $Changes.Modified.Count
        
        # First create all necessary directories
        $allFilePaths = $Changes.New + $Changes.Modified
        $directories = $allFilePaths | ForEach-Object { Split-Path -Path $_ -Parent } | Select-Object -Unique
        
        foreach ($dir in $directories) {
            if ($dir) {
                $targetDir = Join-Path -Path $MainFolderPath -ChildPath $dir
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
            }
        }
        
        # Now copy new and modified files
        foreach ($file in ($Changes.New + $Changes.Modified)) {
            $sourcePath = Join-Path -Path $TempFolderPath -ChildPath $file
            $targetPath = Join-Path -Path $MainFolderPath -ChildPath $file
            
            Copy-Item -Path $sourcePath -Destination $targetPath -Force
            $updateCount++
            
            if ($totalToUpdate -gt 0) {
                $percentComplete = 30 + [math]::Floor(($updateCount / $totalToUpdate) * 60) # 30-90% of total progress
                Update-Status -Status "Updating files: $updateCount of $totalToUpdate" -PercentComplete $percentComplete
            }
        }
        
        # Handle deleted files
        $deleteCount = 0
        $totalToDelete = $Changes.Deleted.Count
        
        foreach ($file in $Changes.Deleted) {
            $targetPath = Join-Path -Path $MainFolderPath -ChildPath $file
            
            if (Test-Path $targetPath) {
                Remove-Item -Path $targetPath -Force
            }
            
            $deleteCount++
            
            if ($totalToDelete -gt 0) {
                $percentComplete = 90 + [math]::Floor(($deleteCount / $totalToDelete) * 10) # 90-100% of total progress
                Update-Status -Status "Removing deleted files: $deleteCount of $totalToDelete" -PercentComplete $percentComplete
            }
        }
        
        # Clean up empty directories
        Get-ChildItem -Path $MainFolderPath -Directory -Recurse | 
            Where-Object { (Get-ChildItem -Path $_.FullName -Recurse -File).Count -eq 0 } |
            Sort-Object -Property FullName -Descending |
            ForEach-Object { Remove-Item -Path $_.FullName -Force }
        
        Write-Log "Repository update completed successfully"
        Update-Status -Status "Update completed" -PercentComplete 100
    }
    catch {
        Write-Log "Error in background update: $_"
        Update-Status -Status "Update failed: $_" -PercentComplete -1
        
        # Attempt to restore from backup if we have one
        if (Test-Path $BackupFolderPath) {
            Write-Log "Attempting to restore from backup..."
            
            # Restore each backed up file
            $backupFiles = Get-ChildItem -Path $BackupFolderPath -Recurse -File
            
            foreach ($file in $backupFiles) {
                $relativePath = $file.FullName.Substring($BackupFolderPath.Length + 1)
                $targetPath = Join-Path -Path $MainFolderPath -ChildPath $relativePath
                $targetDir = Split-Path -Path $targetPath -Parent
                
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                Copy-Item -Path $file.FullName -Destination $targetPath -Force
            }
            
            Write-Log "Restored from backup"
            Update-Status -Status "Update failed - restored from backup" -PercentComplete 100
        }
    }
}

# Main script execution
try {
    # Initialize log file
    if (Test-Path $logFile) {
        Clear-Content -Path $logFile
    }
    
    Write-Log "Starting optimized repository update process..."
    Update-Status -Status "Initializing" -PercentComplete 0
    
    # Remove temporary folder if it exists
    if (Test-Path $tempFolderPath) {
        Remove-Item -Path $tempFolderPath -Recurse -Force
    }
    
    # Clone the repository to a temporary folder
    Write-Log "Cloning repository from $repoUrl to $tempFolderPath..."
    Update-Status -Status "Cloning repository" -PercentComplete 5
    git clone $repoUrl $tempFolderPath
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone repository"
    }
    
    Update-Status -Status "Testing repository" -PercentComplete 10
    
    # Test the cloned repository
    $testsPassed = Test-PowerShellScripts -RepoPath $tempFolderPath
    
    if (-not $testsPassed) {
        Write-Log "Tests failed. Cancelling update."
        Update-Status -Status "Update cancelled: Tests failed" -PercentComplete 100
        
        # Remove the temporary repository
        if (Test-Path $tempFolderPath) {
            Remove-Item -Path $tempFolderPath -Recurse -Force
        }
        
        return
    }
    
    Update-Status -Status "Comparing repositories" -PercentComplete 20
    
    # Compare repositories to find changes
    $changes = Compare-Repositories -SourcePath $tempFolderPath -TargetPath $mainFolderPath
    
    # If no changes found, exit
    if ($changes.New.Count -eq 0 -and $changes.Modified.Count -eq 0 -and $changes.Deleted.Count -eq 0) {
        Write-Log "No changes detected between repositories. Update not needed."
        Update-Status -Status "No changes detected" -PercentComplete 100
        
        # Clean up
        if (Test-Path $tempFolderPath) {
            Remove-Item -Path $tempFolderPath -Recurse -Force
        }
        
        return
    }
    
    Write-Log "Starting background update process..."
    Update-Status -Status "Starting background update" -PercentComplete 25
    
    # Start the background job to apply changes
    Start-Job -ScriptBlock $backgroundJobScript -ArgumentList $tempFolderPath, $mainFolderPath, $backupFolderPath, $logFile, $updateStatusFile, $changes
    
    Write-Log "Update process started in the background"
    Write-Log "You can continue to use the existing repository while the update is in progress"
    Write-Log "Check $updateStatusFile for update status"
    
    Write-Output "Update process started in the background. The current repository is still available for use."
    Write-Output "Check $updateStatusFile for update status."
}
catch {
    Write-Log "Error: $_"
    Update-Status -Status "Error: $_" -PercentComplete -1
    
    # Clean up
    if (Test-Path $tempFolderPath) {
        Remove-Item -Path $tempFolderPath -Recurse -Force
    }
}# Optimized PowerShell Repository Background Update Script
# This script compares the existing repo with the cloned version, 
# only updates changed files, and performs the update in the background
# while allowing continued use of the existing version
# Usage: ./OptimizedUpdateRepo.ps1

# Configuration
$repoUrl = "https://github.com/LennoxKK/co-logs.git"
$tempFolderPath = ".\temp-repo"
$mainFolderPath = ".\co-logs"
$backupFolderPath = ".\co-logs-backup"
$logFile = ".\repo-update-log.txt"
$updateStatusFile = ".\update-status.txt"

# Function to log messages
function Write-Log {
    param (
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host "$timestamp - $Message"
}

# Function to update status file
function Update-Status {
    param (
        [string]$Status,
        [int]$PercentComplete = -1
    )
    
    $statusData = @{
        "Status" = $Status
        "Timestamp" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "PercentComplete" = $PercentComplete
    }
    
    $statusData | ConvertTo-Json | Out-File -FilePath $updateStatusFile -Force
}

# Function to test PowerShell scripts
function Test-PowerShellScripts {
    param (
        [string]$RepoPath
    )
    
    Write-Log "Testing PowerShell scripts in $RepoPath..."
    $allTestsPassed = $true
    $totalFiles = 0
    $testedFiles = 0
    
    # Find all PS1 files in the repository
    $ps1Files = Get-ChildItem -Path $RepoPath -Filter "*.ps1" -Recurse
    
    if ($ps1Files.Count -eq 0) {
        Write-Log "Warning: No PowerShell scripts found in the repository"
        return $false
    }
    
    $totalFiles = $ps1Files.Count
    Write-Log "Found $totalFiles PowerShell scripts to test"
    
    foreach ($file in $ps1Files) {
        $testedFiles++
        $percentComplete = [math]::Floor(($testedFiles / $totalFiles) * 100)
        Update-Status -Status "Testing scripts: $testedFiles of $totalFiles" -PercentComplete $percentComplete
        
        Write-Log "Testing script: $($file.FullName)"
        
        # Test 1: Check PowerShell syntax
        try {
            $syntaxErrors = $null
            [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$syntaxErrors)
            
            if ($syntaxErrors.Count -gt 0) {
                Write-Log "Syntax errors found in $($file.Name):"
                foreach ($error in $syntaxErrors) {
                    Write-Log "  Line $($error.Token.StartLine): $($error.Message)"
                }
                $allTestsPassed = $false
                continue
            }
            
            # Test 2: Parse script with more advanced parser
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            
            if ($errors.Count -gt 0) {
                Write-Log "Parser errors found in $($file.Name):"
                foreach ($error in $errors) {
                    Write-Log "  Line $($error.Extent.StartLineNumber): $($error.Message)"
                }
                $allTestsPassed = $false
                continue
            }
            
            # Test 3: Try to load the script in a controlled environment
            $tempTestFile = [System.IO.Path]::GetTempFileName() + ".ps1"
            
            @"
try {
    # Load the script without executing functions (dot sourcing)
    . "$($file.FullName)" -ErrorAction Stop
    Write-Output "Script loaded successfully"
    exit 0
} catch {
    Write-Error "`$_"
    exit 1
}
"@ | Out-File -FilePath $tempTestFile
            
            $result = Start-Process powershell.exe -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$tempTestFile`"" -Wait -PassThru -RedirectStandardOutput "$tempTestFile.out" -RedirectStandardError "$tempTestFile.err"
            
            if ($result.ExitCode -ne 0) {
                $errorOutput = Get-Content "$tempTestFile.err" -Raw
                Write-Log "Script $($file.Name) failed to load: $errorOutput"
                $allTestsPassed = $false
            } else {
                Write-Log "Script $($file.Name) passed all tests"
            }
            
            # Clean up temp files
            Remove-Item -Path $tempTestFile -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempTestFile.out" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempTestFile.err" -Force -ErrorAction SilentlyContinue
            
        } catch {
            Write-Log "Error testing $($file.Name): $_"
            $allTestsPassed = $false
        }
    }
    
    if ($allTestsPassed) {
        Write-Log "All PowerShell scripts passed tests"
    } else {
        Write-Log "Some PowerShell scripts failed tests"
    }
    
    return $allTestsPassed
}

# Function to compare files and get changes
function Compare-Repositories {
    param (
        [string]$SourcePath,
        [string]$TargetPath
    )
    
    Write-Log "Comparing repositories: $SourcePath vs $TargetPath"
    
    $changes = @{
        New = @()
        Modified = @()
        Deleted = @()
    }
    
    # If target doesn't exist, everything is new
    if (-not (Test-Path $TargetPath)) {
        Write-Log "Target repository doesn't exist, all files will be added"
        $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File
        $changes.New = $sourceFiles | ForEach-Object { $_.FullName.Substring($SourcePath.Length + 1) }
        return $changes
    }
    
    # Get all files from source
    $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File
    $targetFiles = Get-ChildItem -Path $TargetPath -Recurse -File
    
    # Convert to hashtable for faster lookups
    $targetFilesHash = @{}
    foreach ($file in $targetFiles) {
        $relativePath = $file.FullName.Substring($TargetPath.Length + 1)
        $targetFilesHash[$relativePath] = $file
    }
    
    # Check for new and modified files
    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($SourcePath.Length + 1)
        
        if (-not $targetFilesHash.ContainsKey($relativePath)) {
            # New file
            $changes.New += $relativePath
        } else {
            # Compare file content to see if it's modified
            $sourceHash = Get-FileHash -Path $file.FullName -Algorithm MD5
            $targetHash = Get-FileHash -Path $targetFilesHash[$relativePath].FullName -Algorithm MD5
            
            if ($sourceHash.Hash -ne $targetHash.Hash) {
                $changes.Modified += $relativePath
            }
            
            # Remove from target hash to track deleted files
            $targetFilesHash.Remove($relativePath)
        }
    }
    
    # Remaining files in target are deleted in source
    $changes.Deleted = $targetFilesHash.Keys
    
    Write-Log "Found $($changes.New.Count) new files, $($changes.Modified.Count) modified files, and $($changes.Deleted.Count) deleted files"
    
    return $changes
}

# Background job for updating repository
$backgroundJobScript = {
    param(
        $TempFolderPath,
        $MainFolderPath,
        $BackupFolderPath,
        $LogFile,
        $UpdateStatusFile,
        $Changes
    )
    
    try {
        # Function to log messages (duplicated for job scope)
        function Write-Log {
            param (
                [string]$Message
            )
            
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
        }
        
        # Function to update status file (duplicated for job scope)
        function Update-Status {
            param (
                [string]$Status,
                [int]$PercentComplete = -1
            )
            
            $statusData = @{
                "Status" = $Status
                "Timestamp" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "PercentComplete" = $PercentComplete
            }
            
            $statusData | ConvertTo-Json | Out-File -FilePath $UpdateStatusFile -Force
        }
        
        Write-Log "Starting background update process..."
        Update-Status -Status "Starting update" -PercentComplete 0
        
        # Create backup of existing files that will be modified
        if (Test-Path $MainFolderPath) {
            Write-Log "Creating backup of files that will be changed..."
            
            # Remove old backup if it exists
            if (Test-Path $BackupFolderPath) {
                Remove-Item -Path $BackupFolderPath -Recurse -Force
            }
            
            # Create backup folder structure
            New-Item -ItemType Directory -Path $BackupFolderPath -Force | Out-Null
            
            # Copy files that will be modified
            $filesToBackup = $Changes.Modified + $Changes.Deleted
            $backupCount = 0
            $totalToBackup = $filesToBackup.Count
            
            foreach ($file in $filesToBackup) {
                $sourcePath = Join-Path -Path $MainFolderPath -ChildPath $file
                $targetPath = Join-Path -Path $BackupFolderPath -ChildPath $file
                $targetDir = Split-Path -Path $targetPath -Parent
                
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                Copy-Item -Path $sourcePath -Destination $targetPath -Force
                $backupCount++
                
                if ($totalToBackup -gt 0) {
                    $percentComplete = [math]::Floor(($backupCount / $totalToBackup) * 30) # 30% of total progress
                    Update-Status -Status "Backing up files: $backupCount of $totalToBackup" -PercentComplete $percentComplete
                }
            }
            
            Write-Log "Backup of changed files completed"
        }
        
        # Apply changes
        Write-Log "Applying changes to repository..."
        Update-Status -Status "Applying changes" -PercentComplete 30
        
        # Create any missing directories in main folder
        if (-not (Test-Path $MainFolderPath)) {
            New-Item -ItemType Directory -Path $MainFolderPath -Force | Out-Null
        }
        
        # Process new and modified files
        $updateCount = 0
        $totalToUpdate = $Changes.New.Count + $Changes.Modified.Count
        
        # First create all necessary directories
        $allFilePaths = $Changes.New + $Changes.Modified
        $directories = $allFilePaths | ForEach-Object { Split-Path -Path $_ -Parent } | Select-Object -Unique
        
        foreach ($dir in $directories) {
            if ($dir) {
                $targetDir = Join-Path -Path $MainFolderPath -ChildPath $dir
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
            }
        }
        
        # Now copy new and modified files
        foreach ($file in ($Changes.New + $Changes.Modified)) {
            $sourcePath = Join-Path -Path $TempFolderPath -ChildPath $file
            $targetPath = Join-Path -Path $MainFolderPath -ChildPath $file
            
            Copy-Item -Path $sourcePath -Destination $targetPath -Force
            $updateCount++
            
            if ($totalToUpdate -gt 0) {
                $percentComplete = 30 + [math]::Floor(($updateCount / $totalToUpdate) * 60) # 30-90% of total progress
                Update-Status -Status "Updating files: $updateCount of $totalToUpdate" -PercentComplete $percentComplete
            }
        }
        
        # Handle deleted files
        $deleteCount = 0
        $totalToDelete = $Changes.Deleted.Count
        
        foreach ($file in $Changes.Deleted) {
            $targetPath = Join-Path -Path $MainFolderPath -ChildPath $file
            
            if (Test-Path $targetPath) {
                Remove-Item -Path $targetPath -Force
            }
            
            $deleteCount++
            
            if ($totalToDelete -gt 0) {
                $percentComplete = 90 + [math]::Floor(($deleteCount / $totalToDelete) * 10) # 90-100% of total progress
                Update-Status -Status "Removing deleted files: $deleteCount of $totalToDelete" -PercentComplete $percentComplete
            }
        }
        
        # Clean up empty directories
        Get-ChildItem -Path $MainFolderPath -Directory -Recurse | 
            Where-Object { (Get-ChildItem -Path $_.FullName -Recurse -File).Count -eq 0 } |
            Sort-Object -Property FullName -Descending |
            ForEach-Object { Remove-Item -Path $_.FullName -Force }
        
        Write-Log "Repository update completed successfully"
        Update-Status -Status "Update completed" -PercentComplete 100
    }
    catch {
        Write-Log "Error in background update: $_"
        Update-Status -Status "Update failed: $_" -PercentComplete -1
        
        # Attempt to restore from backup if we have one
        if (Test-Path $BackupFolderPath) {
            Write-Log "Attempting to restore from backup..."
            
            # Restore each backed up file
            $backupFiles = Get-ChildItem -Path $BackupFolderPath -Recurse -File
            
            foreach ($file in $backupFiles) {
                $relativePath = $file.FullName.Substring($BackupFolderPath.Length + 1)
                $targetPath = Join-Path -Path $MainFolderPath -ChildPath $relativePath
                $targetDir = Split-Path -Path $targetPath -Parent
                
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                Copy-Item -Path $file.FullName -Destination $targetPath -Force
            }
            
            Write-Log "Restored from backup"
            Update-Status -Status "Update failed - restored from backup" -PercentComplete 100
        }
    }
}

# Main script execution
try {
    # Initialize log file
    if (Test-Path $logFile) {
        Clear-Content -Path $logFile
    }
    
    Write-Log "Starting optimized repository update process..."
    Update-Status -Status "Initializing" -PercentComplete 0
    
    # Remove temporary folder if it exists
    if (Test-Path $tempFolderPath) {
        Remove-Item -Path $tempFolderPath -Recurse -Force
    }
    
    # Clone the repository to a temporary folder
    Write-Log "Cloning repository from $repoUrl to $tempFolderPath..."
    Update-Status -Status "Cloning repository" -PercentComplete 5
    git clone $repoUrl $tempFolderPath
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone repository"
    }
    
    Update-Status -Status "Testing repository" -PercentComplete 10
    
    # Test the cloned repository
    $testsPassed = Test-PowerShellScripts -RepoPath $tempFolderPath
    
    if (-not $testsPassed) {
        Write-Log "Tests failed. Cancelling update."
        Update-Status -Status "Update cancelled: Tests failed" -PercentComplete 100
        
        # Remove the temporary repository
        if (Test-Path $tempFolderPath) {
            Remove-Item -Path $tempFolderPath -Recurse -Force
        }
        
        return
    }
    
    Update-Status -Status "Comparing repositories" -PercentComplete 20
    
    # Compare repositories to find changes
    $changes = Compare-Repositories -SourcePath $tempFolderPath -TargetPath $mainFolderPath
    
    # If no changes found, exit
    if ($changes.New.Count -eq 0 -and $changes.Modified.Count -eq 0 -and $changes.Deleted.Count -eq 0) {
        Write-Log "No changes detected between repositories. Update not needed."
        Update-Status -Status "No changes detected" -PercentComplete 100
        
        # Clean up
        if (Test-Path $tempFolderPath) {
            Remove-Item -Path $tempFolderPath -Recurse -Force
        }
        
        return
    }
    
    Write-Log "Starting background update process..."
    Update-Status -Status "Starting background update" -PercentComplete 25
    
    # Start the background job to apply changes
    Start-Job -ScriptBlock $backgroundJobScript -ArgumentList $tempFolderPath, $mainFolderPath, $backupFolderPath, $logFile, $updateStatusFile, $changes
    
    Write-Log "Update process started in the background"
    Write-Log "You can continue to use the existing repository while the update is in progress"
    Write-Log "Check $updateStatusFile for update status"
    
    Write-Output "Update process started in the background. The current repository is still available for use."
    Write-Output "Check $updateStatusFile for update status."
}
catch {
    Write-Log "Error: $_"
    Update-Status -Status "Error: $_" -PercentComplete -1
    
    # Clean up
    if (Test-Path $tempFolderPath) {
        Remove-Item -Path $tempFolderPath -Recurse -Force
    }
}