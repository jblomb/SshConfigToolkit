<#
.SYNOPSIS
    Renames an SSH host block's patterns while preserving its position and options.

.DESCRIPTION
    This function changes the host patterns of an existing SSH host block without 
    changing its location in the configuration file or its options. This is useful 
    for renaming hosts (e.g., 'myserver' to 'myserver-prod') while keeping all 
    other settings intact.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to the user's SSH config.

.PARAMETER OldPatterns
    The current host patterns that identify the block to rename. Must match exactly.

.PARAMETER NewPatterns
    The new host patterns to replace the old ones.

.PARAMETER NoBackup
    Skips creating a timestamped backup before making changes.

.PARAMETER WhatIf
    Shows what changes would be made without actually modifying the file.

.PARAMETER Confirm
    Prompts for confirmation before making changes.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.0
    
    Requires: Get-SshConfigEntities, Find-SshHostBlock, ConvertFrom-SshHostBlockText,
              New-SshHostBlockText, Update-SshHostBlock, Save-SshConfig

.EXAMPLE
    Rename-SshHostBlock -OldPatterns 'myserver' -NewPatterns 'myserver-prod'
    
    Renames a single-pattern host block.

.EXAMPLE
    Rename-SshHostBlock -OldPatterns @('web01', 'webserver') -NewPatterns @('web01-prod', 'webserver-prod')
    
    Renames a multi-pattern host block.

.EXAMPLE
    Rename-SshHostBlock -OldPatterns 'test' -NewPatterns @('test', 'test.local') -WhatIf
    
    Shows what would happen when adding an additional pattern.

.EXAMPLE
    # Rename with precedence checking
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    $check = Test-SshHostPrecedence -Entities $entities -NewPatterns @('newname*')
    if ($check.Safe) {
        Rename-SshHostBlock -OldPatterns 'oldname' -NewPatterns 'newname*'
    }
    
    Manually check precedence before renaming to a glob pattern.
#>
function Rename-SshHostBlock {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$OldPatterns,

        [Parameter(Mandatory)]
        [string[]]$NewPatterns,

        [switch]$NoBackup
    )

    # Determine default SSH config path if not specified
    if (-not $Path) {
        if ($IsWindows -or $env:OS -match 'Windows') {
            $Path = Join-Path $env:USERPROFILE '.ssh\config'
        } else {
            $Path = '~/.ssh/config'
        }
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    Write-Verbose "SSH config path: $Path"
    Write-Verbose "Old patterns: $($OldPatterns -join ', ')"
    Write-Verbose "New patterns: $($NewPatterns -join ', ')"

    # Verify file exists
    if (-not (Test-Path -Path $Path)) {
        throw "SSH config file not found: $Path"
    }

    # Parse the existing configuration
    Write-Verbose "Parsing SSH configuration..."
    $entities = Get-SshConfigEntities -Path $Path

    # Convert to mutable list if needed
    if ($entities -isnot [System.Collections.Generic.List[object]]) {
        $entities = [System.Collections.Generic.List[object]]::new($entities)
    }

    # Find the host block to rename
    $existing = Find-SshHostBlock -Entities $entities -Patterns $OldPatterns

    if (-not $existing) {
        throw "Host block not found with patterns: $($OldPatterns -join ', ')"
    }

    Write-Verbose "Found host block at lines $($existing.StartLine)-$($existing.EndLine)"

    # Parse existing options
    $options = ConvertFrom-SshHostBlockText -RawText $existing.RawText

    # Generate new block text with new patterns but same options
    $newBlockText = New-SshHostBlockText -Patterns $NewPatterns -Options $options

    # Prepare message for ShouldProcess
    $renameMessage = "'$($OldPatterns -join ' ')' -> '$($NewPatterns -join ' ')'"

    if (-not $PSCmdlet.ShouldProcess($renameMessage, "Rename host block")) {
        return
    }

    # Update the host block with new patterns
    $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $newBlockText

    Write-Verbose "Host block patterns updated"

    # Save the modified configuration
    $saveParams = @{
        Entities = $entities
        Path     = $Path
    }
    if ($NoBackup) {
        $saveParams['NoBackup'] = $true
    }

    Save-SshConfig @saveParams

    # Return summary information
    Write-Verbose "Configuration saved successfully"

    return [PSCustomObject]@{
        Path        = $Path
        OldPatterns = $OldPatterns
        NewPatterns = $NewPatterns
        Action      = 'Renamed'
        LineRange   = "$($existing.StartLine)-$($existing.EndLine)"
    }
}
