<#
.SYNOPSIS
    Writes SSH config entities back to disk with optional backup and atomic write operations.

.DESCRIPTION
    This function converts a collection of SSH config entities back into raw text format and writes
    it to the specified file. It supports creating timestamped backups, atomic writes using temporary
    files, and validation of the written content. Line numbers in entities are recalculated during
    the save operation.
    
    For system-wide config files (e.g., C:\ProgramData\ssh\ssh_config), this function can use a
    scheduled task to perform the atomic write with elevated permissions, allowing non-admin users
    to update the config without UAC prompts.
    
    When using the scheduled task method, temp files and backups are written to the backups folder
    (C:\ProgramData\ssh\backups\) which has permissions allowing normal users to write.

.PARAMETER Entities
    A collection of SSH config entities to write to disk. Each entity's RawText will be joined
    with newlines to create the final file content.

.PARAMETER Path
    The full path to the SSH configuration file to write. The parent directory must exist.

.PARAMETER NoBackup
    When specified, skips creating a backup of the existing file before writing. By default,
    a timestamped backup is created.

.PARAMETER BackupDirectory
    Optional directory where backups should be stored. If not specified, defaults to
    C:\ProgramData\ssh\backups for system configs or the same directory for user configs.

.PARAMETER Force
    When specified, continues even if backup creation fails.

.PARAMETER NoAtomic
    When specified, writes directly to the target file instead of using a temporary file
    and atomic rename operation. Atomic writes are safer but require write permissions.

.PARAMETER DontUseTask
    When specified, skips using the 'Update-SshConfig' scheduled task to perform the atomic write
    with elevated permissions. When not specified (default), this allows non-admin users to update 
    system-wide config files. The task must be installed first using Set-SshScheduledCopyTask.ps1.

.PARAMETER TaskName
    The name of the scheduled task to use for elevated writes. Defaults to 'Update-SshConfig'.

.PARAMETER TaskTimeout
    Maximum time in seconds to wait for the scheduled task to complete. Defaults to 30 seconds.

.NOTES
    Author: Jan Blomberg
    Date: 2025-01-28
    Version: 2.0
    
    Version History:
    2.0 - Uses backups folder for staging temp files and backups
    1.2 - Added UseTask parameter for elevated writes via scheduled task
    1.1 - Added UTF-8 encoding documentation
    1.0 - Initial release
    
    ENCODING NOTE:
    This function writes files using UTF-8 encoding WITHOUT a Byte Order Mark (BOM).
    This is the correct format for SSH configuration files. If you need to use 
    PowerShell's Out-File or Set-Content with UTF8 encoding in PowerShell 5.1, 
    be aware that they add a BOM which may cause issues with some SSH clients.
    This function uses [System.IO.File]::WriteAllText() to avoid this issue.

.EXAMPLE
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    # ... modify entities ...
    Save-SshConfig -Entities $entities -Path "~/.ssh/config"
    
    Saves modified entities with automatic backup.

.EXAMPLE
    Save-SshConfig -Entities $entities -Path "~/.ssh/config" -NoBackup
    
    Saves without creating a backup (not recommended for production use).

.EXAMPLE
    Save-SshConfig -Entities $entities -Path "~/.ssh/config" -BackupDirectory "~/.ssh/backups"
    
    Saves with backups stored in a specific directory.

.EXAMPLE
    Save-SshConfig -Entities $entities -Path "C:\ProgramData\ssh\ssh_config"
    
    Saves system-wide config using the scheduled task for elevated permissions (default behavior).

.EXAMPLE
    Save-SshConfig -Entities $entities -Path "C:\ProgramData\ssh\ssh_config" -DontUseTask
    
    Saves system-wide config directly (requires running as administrator).
#>
function Save-SshConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Entities,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$NoBackup,

        [string]$BackupDirectory,

        [switch]$Force,

        [switch]$NoAtomic,

        [switch]$DontUseTask,

        [string]$TaskName = 'Update-SshConfig',

        [int]$TaskTimeout = 30
    )

    # Resolve the path to absolute
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $fileExists = Test-Path -Path $Path -PathType Leaf
    $parentFolder = Split-Path -Parent $Path

    # Constants for system-wide config
    $SystemConfigPath = 'C:\ProgramData\ssh\ssh_config'
    $DefaultBackupsFolder = 'C:\ProgramData\ssh\backups'

    # Only use scheduled task for the system config path it's designed for
    $UseTask = $false
    if (-not $DontUseTask) {
        if ($Path -eq $SystemConfigPath) {
            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($task) {
                $UseTask = $true
            }
            else {
                Write-Warning "Scheduled task '$TaskName' not found. Falling back to direct write (may require elevation). Run Set-SshScheduledCopyTask.ps1 as administrator to enable non-elevated writes."
            }
        }
        else {
            Write-Verbose "Scheduled task only applies to $SystemConfigPath. Using direct write for: $Path"
        }
    }

    # UseTask implies atomic write
    if ($UseTask -and $NoAtomic) {
        Write-Warning "-NoAtomic is ignored when using the scheduled task."
    }

    # Determine the backups/staging folder
    if ($BackupDirectory) {
        $stagingFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupDirectory)
    }
    elseif ($UseTask) {
        # Task requires the backups folder for staging
        $stagingFolder = $DefaultBackupsFolder
    }
    elseif (Test-Path $DefaultBackupsFolder) {
        # Use the standard backups folder if it exists (for backups, not staging)
        $stagingFolder = $DefaultBackupsFolder
    }
    else {
        # Fall back to the parent folder of the config file
        $stagingFolder = $parentFolder
    }

    # Ensure staging folder exists
    if (-not (Test-Path $stagingFolder)) {
        try {
            New-Item -Path $stagingFolder -ItemType Directory -Force | Out-Null
        }
        catch {
            throw "Failed to create staging/backup folder: $stagingFolder - $_"
        }
    }

    # Capture original ACL to preserve permissions (only needed for non-task atomic writes)
    $originalAcl = $null
    if ($fileExists -and -not $UseTask -and -not $NoAtomic) {
        $originalAcl = Get-Acl -Path $Path
    }

    # Backup logic
    if (-not $NoBackup -and $fileExists) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $configName = Split-Path -Leaf $Path
        $backupFileName = "$configName.$timestamp.bak"
        $backupPath = Join-Path $stagingFolder $backupFileName
        
        try {
            Copy-Item -Path $Path -Destination $backupPath -Force
            Write-Verbose "Backup created: $backupPath"
        }
        catch {
            if (-not $Force) {
                throw "Backup failed: $_"
            }
            Write-Warning "Backup failed (continuing due to -Force): $_"
        }
    }

    # Recalculate line numbers and join text
    $currentLine = 1
    $textParts = [System.Collections.Generic.List[string]]::new()
    
    foreach ($entity in $Entities) {
        $lineCount = ($entity.RawText -split "`r?`n").Count
        $entity.StartLine = $currentLine
        $entity.EndLine = $currentLine + $lineCount - 1
        $currentLine = $entity.EndLine + 1
        $textParts.Add($entity.RawText)
    }
    
    $finalText = $textParts -join "`n"
    if (-not $finalText.EndsWith("`n")) {
        $finalText += "`n"
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Save SSH configuration')) {
        $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        
        if ($UseTask) {
            # Write to staging folder, then trigger scheduled task
            $tempPath = Join-Path $stagingFolder 'ssh_config.temp'
            
            try {
                [System.IO.File]::WriteAllText($tempPath, $finalText, $Utf8NoBom)
                Write-Verbose "Wrote temp file: $tempPath"
                
                # Start the task and wait for completion
                Start-ScheduledTask -TaskName $TaskName
                Write-Verbose "Started scheduled task: $TaskName"
                
                # Wait for task to complete
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                do {
                    Start-Sleep -Milliseconds 100
                    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
                    $taskState = (Get-ScheduledTask -TaskName $TaskName).State
                } while ($taskState -eq 'Running' -and $stopwatch.Elapsed.TotalSeconds -lt $TaskTimeout)
                
                $stopwatch.Stop()
                
                if ($taskState -eq 'Running') {
                    throw "Scheduled task '$TaskName' timed out after $TaskTimeout seconds."
                }
                
                # Check if temp file was processed (should be gone if successful)
                if (Test-Path $tempPath) {
                    # Read any error info before cleanup
                    $lastResult = $taskInfo.LastTaskResult
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                    throw "Scheduled task completed but temp file still exists. Exit code: $lastResult"
                }
                
                # Verify the last run result
                if ($taskInfo.LastTaskResult -ne 0) {
                    throw "Scheduled task failed with exit code: $($taskInfo.LastTaskResult)"
                }
                
                Write-Verbose "SSH config updated successfully via scheduled task."
            }
            catch {
                # Cleanup temp file on failure
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                }
                throw "Failed to write using scheduled task: $_"
            }
        }
        elseif ($NoAtomic) {
            # Direct write (less safe, but simpler)
            try {
                [System.IO.File]::WriteAllText($Path, $finalText, $Utf8NoBom)
                Write-Verbose "Wrote directly to: $Path"
            }
            catch {
                throw "Failed to write: $_"
            }
        }
        else {
            # Atomic write without scheduled task (requires write permission to target folder)
            $tempPath = Join-Path $parentFolder "ssh_config.tmp.$PID"
            
            try {
                [System.IO.File]::WriteAllText($tempPath, $finalText, $Utf8NoBom)
                
                # Apply original ACL to temp file before swapping
                if ($null -ne $originalAcl) {
                    Set-Acl -Path $tempPath -AclObject $originalAcl
                }

                Move-Item -Path $tempPath -Destination $Path -Force
                Write-Verbose "Atomic write completed: $Path"
            }
            catch {
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                }
                throw "Failed to write: $_"
            }
        }
    }
}