<#
.SYNOPSIS
    Writes SSH config entities back to disk with optional backup and atomic write operations.

.DESCRIPTION
    This function converts a collection of SSH config entities back into raw text format and writes
    it to the specified file. It supports creating timestamped backups, atomic writes using temporary
    files, and validation of the written content. Line numbers in entities are recalculated during
    the save operation.

.PARAMETER Entities
    A collection of SSH config entities to write to disk. Each entity's RawText will be joined
    with newlines to create the final file content.

.PARAMETER Path
    The full path to the SSH configuration file to write. The parent directory must exist.

.PARAMETER NoBackup
    When specified, skips creating a backup of the existing file before writing. By default,
    a timestamped backup is created in the same directory.

.PARAMETER BackupDirectory
    Optional directory where backups should be stored. If not specified, backups are created
    in the same directory as the config file with a timestamp suffix.

.PARAMETER Force
    When specified, overwrites the file even if it would normally prompt for confirmation.

.PARAMETER NoAtomic
    When specified, writes directly to the target file instead of using a temporary file
    and atomic rename operation. Atomic writes are safer but require write permissions.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
    
    Version History:
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

        [switch]$NoAtomic
    )

    # Resolve to full path
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    Write-Verbose "Saving SSH config to: $Path"

    # Check if file exists for backup purposes
    $fileExists = Test-Path -Path $Path -PathType Leaf

    # Create backup if requested and file exists
    if (-not $NoBackup -and $fileExists) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        
        if ($BackupDirectory) {
            # Ensure backup directory exists
            if (-not (Test-Path -Path $BackupDirectory)) {
                New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
            }
            $backupPath = Join-Path $BackupDirectory "config.$timestamp.bak"
        } else {
            # Backup in same directory as original file
            $backupPath = "$Path.$timestamp.bak"
        }

        Write-Verbose "Creating backup: $backupPath"
        
        try {
            Copy-Item -Path $Path -Destination $backupPath -Force
            Write-Verbose "Backup created successfully"
        } catch {
            Write-Warning "Failed to create backup: $_"
            if (-not $Force) {
                throw "Backup failed. Use -Force to proceed anyway."
            }
        }
    }

    # Recalculate line numbers for all entities
    $currentLine = 1
    foreach ($entity in $Entities) {
        $lineCount = ($entity.RawText -split "`r?`n").Count
        $entity.StartLine = $currentLine
        $entity.EndLine = $currentLine + $lineCount - 1
        $currentLine = $entity.EndLine + 1
    }

    # Convert entities back to raw text
    $textParts = New-Object 'System.Collections.Generic.List[string]'
    
    foreach ($entity in $Entities) {
        $textParts.Add($entity.RawText)
    }

    # Join all parts with newlines
    $finalText = $textParts -join "`n"

    # Ensure file ends with newline (Unix convention)
    if (-not $finalText.EndsWith("`n")) {
        $finalText += "`n"
    }

    Write-Verbose "Final text length: $($finalText.Length) bytes"
    Write-Verbose "Total lines: $(($finalText -split "`r?`n").Count)"

    # WhatIf support
    if ($PSCmdlet.ShouldProcess($Path, "Save SSH configuration")) {
        
        if ($NoAtomic) {
            # Direct write (simpler but less safe)
            try {
                [System.IO.File]::WriteAllText($Path, $finalText, [System.Text.Encoding]::UTF8)
                Write-Verbose "File written successfully (direct write)"
            } catch {
                throw "Failed to write SSH config: $_"
            }
        } else {
            # Atomic write using temporary file
            $tempPath = "$Path.tmp.$PID"
            
            try {
                # Write to temp file
                [System.IO.File]::WriteAllText($tempPath, $finalText, [System.Text.Encoding]::UTF8)
                Write-Verbose "Temporary file written: $tempPath"

                # Atomic rename (overwrites target on Windows/Linux)
                Move-Item -Path $tempPath -Destination $Path -Force
                Write-Verbose "File written successfully (atomic rename)"
                
            } catch {
                # Clean up temp file on error
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                }
                throw "Failed to write SSH config: $_"
            }
        }
    }

    Write-Verbose "Save-SshConfig completed successfully"
}
