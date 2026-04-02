<#
.SYNOPSIS
    Renames an SSH host block's patterns while preserving its position and options.

.DESCRIPTION
    This function changes the host patterns of an existing SSH host block without 
    changing its location in the configuration file or its options. This is useful 
    for renaming hosts (e.g., 'myserver' to 'myserver-prod') while keeping all 
    other settings intact.

    For batch operations, use -Entities to pass a pre-parsed entity collection (skipping
    the file read) and -PassThru to return the modified entities instead of saving. This
    allows renames to be composed with other operations before a single Save-SshConfig call.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to the user's SSH config.
    Required when saving (i.e., when -PassThru is not specified and -Entities is provided).

.PARAMETER OldPatterns
    The current host patterns that identify the block to rename. Must match exactly.

.PARAMETER NewPatterns
    The new host patterns to replace the old ones.

.PARAMETER Entities
    Optional. A pre-parsed collection of SSH config entities (typically from Get-SshConfigEntities).
    When provided, the function skips reading and parsing the config file from disk. The collection
    is mutated in place and either saved or returned depending on -PassThru.

.PARAMETER PassThru
    When specified, returns the modified entities collection instead of saving to disk. This
    allows multiple operations to be chained before a single Save-SshConfig call.

.PARAMETER NoBackup
    Skips creating a timestamped backup before making changes.

.PARAMETER WhatIf
    Shows what changes would be made without actually modifying the file.

.PARAMETER Confirm
    Prompts for confirmation before making changes.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
    
    Version History:
    1.1 - Added -Entities and -PassThru parameters for batch operations
    1.0 - Initial release
    
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

.EXAMPLE
    # Batch operation: rename multiple hosts in one save
    $path = "$env:USERPROFILE\.ssh\config"
    $entities = Get-SshConfigEntities -Path $path
    $entities = Rename-SshHostBlock -Entities $entities -OldPatterns 'web01' -NewPatterns 'web01-prod' -PassThru
    $entities = Rename-SshHostBlock -Entities $entities -OldPatterns 'db01' -NewPatterns 'db01-prod' -PassThru
    Save-SshConfig -Entities $entities -Path $path
    
    Performs two renames on the in-memory entity collection, then saves once.
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

        [Parameter()]
        [System.Collections.Generic.List[object]]$Entities,

        [switch]$PassThru,

        [switch]$NoBackup
    )

    # Validate parameter combinations
    $hasEntities = $PSBoundParameters.ContainsKey('Entities')

    if (-not $hasEntities -and -not $Path) {
        # No entities and no path: resolve default path (original behavior)
        if ($IsWindows -or $env:OS -match 'Windows') {
            $Path = Join-Path $env:USERPROFILE '.ssh\config'
        } else {
            $Path = '~/.ssh/config'
        }
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    elseif ($hasEntities -and -not $PassThru -and -not $Path) {
        throw "The -Path parameter is required when using -Entities without -PassThru, because the modified entities need a destination to save to."
    }
    elseif ($Path) {
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    Write-Debug "SSH config path: $(if ($Path) { $Path } else { '(in-memory only)' })"
    Write-Debug "Old patterns: $($OldPatterns -join ', ')"
    Write-Debug "New patterns: $($NewPatterns -join ', ')"

    # When not using pre-parsed entities, read from disk
    if (-not $hasEntities) {
        if (-not (Test-Path -Path $Path)) {
            throw "SSH config file not found: $Path"
        }

        # Parse the existing configuration
        $Entities = Get-SshConfigEntities -Path $Path
    }

    # Convert to mutable list if needed
    if ($Entities -isnot [System.Collections.Generic.List[object]]) {
        $Entities = [System.Collections.Generic.List[object]]::new($Entities)
    }

    # Find the host block to rename
    $existing = Find-SshHostBlock -Entities $Entities -Patterns $OldPatterns

    if (-not $existing) {
        throw "Host block not found with patterns: $($OldPatterns -join ', ')"
    }

    Write-Debug "Found host block at lines $($existing.StartLine)-$($existing.EndLine)"

    # Parse existing options
    $options = ConvertFrom-SshHostBlockText -RawText $existing.RawText

    # Generate new block text with new patterns but same options
    $newBlockText = New-SshHostBlockText -Patterns $NewPatterns -Options $options

    # Prepare message for ShouldProcess
    $renameMessage = "'$($OldPatterns -join ' ')' -> '$($NewPatterns -join ' ')'"

    if (-not $PSCmdlet.ShouldProcess($renameMessage, "Rename host block")) {
        if ($PassThru) { return $Entities }
        return
    }

    # Update the host block with new patterns
    $Entities = Update-SshHostBlock -Entities $Entities -HostBlock $existing -BlockText $newBlockText

    # If PassThru, return entities without saving
    if ($PassThru) {
        Write-Debug "PassThru: returning modified entities without saving"
        return $Entities
    }

    # Save the modified configuration
    $saveParams = @{
        Entities = $Entities
        Path     = $Path
    }
    if ($NoBackup) {
        $saveParams['NoBackup'] = $true
    }

    Save-SshConfig @saveParams

    Write-Verbose "Renamed '$($OldPatterns -join ' ')' -> '$($NewPatterns -join ' ')'"

    return [PSCustomObject]@{
        Path        = $Path
        OldPatterns = $OldPatterns
        NewPatterns = $NewPatterns
        Action      = 'Renamed'
        LineRange   = "$($existing.StartLine)-$($existing.EndLine)"
    }
}