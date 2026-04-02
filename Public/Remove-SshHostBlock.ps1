<#
.SYNOPSIS
    Removes an SSH host block from a configuration file.

.DESCRIPTION
    This function provides a complete workflow for removing SSH host blocks from the configuration.
    It handles reading, parsing, removing the specified block, and saving the SSH config file.
    The function includes safety features like backups, atomic writes, and WhatIf support.

    For batch operations, use -Entities to pass a pre-parsed entity collection (skipping
    the file read) and -PassThru to return the modified entities instead of saving. This
    allows multiple removals (or mixed remove/add operations) to be composed before a single
    Save-SshConfig call.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to "$env:USERPROFILE\.ssh\config" on
    Windows or "~/.ssh/config" on Unix systems. Required when saving (i.e., when -PassThru
    is not specified and -Entities is provided).

.PARAMETER Patterns
    An array of host patterns that identify the host block to remove. Must match exactly
    (case-sensitive, same count, same order) as defined in Find-SshHostBlock.

.PARAMETER Entities
    Optional. A pre-parsed collection of SSH config entities (typically from Get-SshConfigEntities).
    When provided, the function skips reading and parsing the config file from disk. The collection
    is mutated in place and either saved or returned depending on -PassThru.

.PARAMETER PassThru
    When specified, returns the modified entities collection instead of saving to disk. This
    allows multiple Remove-SshHostBlock calls (or mixed operations with Set-SshHostBlock) to
    be chained before a single Save-SshConfig call.

.PARAMETER NoBackup
    Skips creating a timestamped backup of the configuration file before making changes.

.PARAMETER RemoveBlankLines
    When specified, also removes blank lines immediately before and after the host block.

.PARAMETER WhatIf
    Shows what would be removed without actually modifying the file.

.PARAMETER Confirm
    Prompts for confirmation before removing the host block.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
    
    Version History:
    1.1 - Added -Entities and -PassThru parameters for batch operations
    1.0 - Initial release
    
    Requires: Get-SshConfigEntities, Find-SshHostBlock, Save-SshConfig

.EXAMPLE
    Remove-SshHostBlock -Patterns 'myserver'
    
    Removes the 'myserver' host block from the default SSH config file.

.EXAMPLE
    Remove-SshHostBlock -Patterns @('jump01', 'bastion') -RemoveBlankLines
    
    Removes the host block and surrounding blank lines.

.EXAMPLE
    Remove-SshHostBlock -Path "C:\custom\ssh_config" -Patterns 'test' -WhatIf
    
    Shows what would be removed without actually modifying the file.

.EXAMPLE
    Remove-SshHostBlock -Patterns 'oldserver' -Confirm:$false
    
    Removes without prompting for confirmation.

.EXAMPLE
    # Batch removal: tear down an entire environment in one save
    $path = "$env:USERPROFILE\.ssh\config"
    $entities = Get-SshConfigEntities -Path $path
    $entities = Remove-SshHostBlock -Entities $entities -Patterns 'exserver' -RemoveBlankLines -PassThru
    $entities = Remove-SshHostBlock -Entities $entities -Patterns 'exserver.example.com' -RemoveBlankLines -PassThru
    $entities = Remove-SshHostBlock -Entities $entities -Patterns 'jumpex' -RemoveBlankLines -PassThru
    Save-SshConfig -Entities $entities -Path $path
    
    Performs three removals on the in-memory entity collection, then saves once.

.EXAMPLE
    # Mixed operations: remove old hosts and add new ones before a single save
    $entities = Get-SshConfigEntities -Path $path
    $entities = Remove-SshHostBlock -Entities $entities -Patterns 'old-bastion' -RemoveBlankLines -PassThru
    $entities = Set-SshHostBlock -Entities $entities -Patterns 'new-bastion' -HostName '10.0.0.1' -IsBastion -PassThru
    Save-SshConfig -Entities $entities -Path $path
#>
function Remove-SshHostBlock {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter()]
        [System.Collections.Generic.List[object]]$Entities,

        [switch]$PassThru,

        [switch]$NoBackup,

        [switch]$RemoveBlankLines
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
    Write-Debug "Patterns to remove: $($Patterns -join ', ')"

    # When not using pre-parsed entities, read from disk
    if (-not $hasEntities) {
        if (-not (Test-Path -Path $Path)) {
            throw "SSH config file not found: $Path"
        }

        # Parse the existing configuration
        $Entities = Get-SshConfigEntities -Path $Path
    }

    # Find the host block to remove
    $toRemove = Find-SshHostBlock -Entities $Entities -Patterns $Patterns

    if (-not $toRemove) {
        Write-Warning "Host block not found with patterns: $($Patterns -join ', ')"
        if ($PassThru) { return $Entities }
        return
    }

    Write-Verbose "Removing '$($toRemove.HostLine)' (lines $($toRemove.StartLine)-$($toRemove.EndLine))"

    # Prepare removal message for ShouldProcess
    $removeMessage = "Host block '$($toRemove.HostLine)' (lines $($toRemove.StartLine)-$($toRemove.EndLine))"

    if (-not $PSCmdlet.ShouldProcess($removeMessage, "Remove")) {
        if ($PassThru) { return $Entities }
        return
    }

    # Convert to mutable list if needed
    if ($Entities -isnot [System.Collections.Generic.List[object]]) {
        $Entities = [System.Collections.Generic.List[object]]::new($Entities)
    }

    # Find the index of the entity to remove
    $removeIndex = -1
    for ($i = 0; $i -lt $Entities.Count; $i++) {
        if ($Entities[$i] -eq $toRemove) {
            $removeIndex = $i
            break
        }
    }

    if ($removeIndex -eq -1) {
        throw "Internal error: Could not locate host block in entities collection"
    }

    # Optionally remove surrounding blank lines
    $indicesToRemove = @($removeIndex)

    if ($RemoveBlankLines) {
        # Check for blank line before
        if ($removeIndex -gt 0 -and $Entities[$removeIndex - 1].Type -eq 'BlankBlock') {
            $indicesToRemove = @($removeIndex - 1) + $indicesToRemove
            Write-Debug "Will also remove blank line before (index $($removeIndex - 1))"
        }

        # Check for blank line after
        if ($removeIndex -lt ($Entities.Count - 1) -and $Entities[$removeIndex + 1].Type -eq 'BlankBlock') {
            $indicesToRemove += ($removeIndex + 1)
            Write-Debug "Will also remove blank line after (index $($removeIndex + 1))"
        }
    }

    # Remove entities in reverse order to maintain indices
    foreach ($idx in ($indicesToRemove | Sort-Object -Descending)) {
        Write-Debug "Removing entity at index $idx (Type: $($Entities[$idx].Type))"
        $Entities.RemoveAt($idx)
    }

    Write-Debug "Removed $($indicesToRemove.Count) entity/entities"

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

    Write-Verbose "Removed host block '$($Patterns -join ' ')' from $Path"
    
    return [PSCustomObject]@{
        Path         = $Path
        Patterns     = $Patterns
        Action       = 'Removed'
        LinesRemoved = $indicesToRemove.Count
    }
}