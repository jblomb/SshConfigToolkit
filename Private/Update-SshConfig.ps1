<#
.SYNOPSIS
    Performs atomic replacement of ssh_config with proper ACL preservation.

.DESCRIPTION
    This script is called by the 'Update-SshConfig' scheduled task to perform
    an elevated atomic replacement of the system-wide SSH configuration file.
    
    It expects a temp file at C:\ProgramData\ssh\backups\ssh_config.temp containing
    the new configuration. The script copies the ACL from the original ssh_config,
    applies it to the temp file, then performs an atomic replace (delete + rename).
    
    This script should be placed in the module's Private folder and referenced
    by the scheduled task created by Set-SshScheduledCopyTask.ps1.

.NOTES
    Author: Jan Blomberg
    Date: 2025-01-28
    Version: 2.0
    
    This script runs as SYSTEM via scheduled task and should not be called directly.
    
    SECURITY: This script only operates on specific, hardcoded paths to prevent
    abuse of the elevated scheduled task.
#>

[CmdletBinding()]
param()

# Hardcoded paths for security - prevents task from being abused to overwrite arbitrary files
$SshConfigPath = 'C:\ProgramData\ssh\ssh_config'
$BackupsFolder = 'C:\ProgramData\ssh\backups'
$TempPath = Join-Path $BackupsFolder 'ssh_config.temp'

# Validate temp file exists
if (-not (Test-Path $TempPath)) {
    Write-Error "Temp file not found: $TempPath"
    exit 1
}

# Validate original file exists
if (-not (Test-Path $SshConfigPath)) {
    Write-Error "Original file not found: $SshConfigPath"
    exit 1
}

try {
    # Get ACL from original
    $acl = Get-Acl $SshConfigPath
    
    # Apply ACL to temp file before moving
    Set-Acl $TempPath $acl
    
    # Atomic replace: delete original, rename temp
    Remove-Item $SshConfigPath -Force
    Move-Item $TempPath $SshConfigPath -Force
    
    Write-Output "Successfully updated $SshConfigPath"
    exit 0
}
catch {
    Write-Error "Failed to update ssh_config: $_"
    
    # Attempt cleanup of temp file on failure
    if (Test-Path $TempPath) {
        Remove-Item $TempPath -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}