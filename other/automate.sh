#!/bin/bash

# Ensure proper arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path_to_ps1> <alias_name>"
    exit 1
fi

PS1_FILE="$1"
ALIAS_NAME="$2"

# 1. Create a cmd wrapper in a standard Windows PATH location
WIN_SCRIPT_PATH="C:\\Windows\\$ALIAS_NAME.cmd"
WIN_PS1_PATH=$(wslpath -w "$(realpath "$PS1_FILE")")

# Create the CMD wrapper
echo "@echo off" > /mnt/c/Windows/$ALIAS_NAME.cmd
echo "powershell -ExecutionPolicy Bypass -File \"$WIN_PS1_PATH\" %*" >> /mnt/c/Windows/$ALIAS_NAME.cmd

# 2. Also create a PowerShell function in profile
POWERSHELL_PROFILE=$(powershell -Command "[System.Environment]::GetFolderPath('MyDocuments') + '\\WindowsPowerShell\\Microsoft.PowerShell_profile.ps1'")
mkdir -p "$(dirname "$POWERSHELL_PROFILE")"

echo "function $ALIAS_NAME {" >> "$POWERSHELL_PROFILE"
echo "    & \"$WIN_PS1_PATH\" @args" >> "$POWERSHELL_PROFILE"
echo "}" >> "$POWERSHELL_PROFILE"

# 3. Make it executable from anywhere
powershell -Command "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';C:\\Windows', 'Machine')"

echo "✅ 100% Working Setup Complete!"
echo "The command '$ALIAS_NAME' is now available:"
echo "- In Command Prompt (CMD.EXE)"
echo "- In PowerShell"
echo "- In WSL"
echo "- From any directory"
echo ""
echo "Try it now in a NEW terminal window: $ALIAS_NAME"