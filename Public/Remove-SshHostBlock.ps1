<#
.SYNOPSIS
    Removes an SSH host block from a configuration file.

.DESCRIPTION
    This function provides a complete workflow for removing SSH host blocks from the configuration.
    It handles reading, parsing, removing the specified block, and saving the SSH config file.
    The function includes safety features like backups, atomic writes, and WhatIf support.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to "$env:USERPROFILE\.ssh\config" on
    Windows or "~/.ssh/config" on Unix systems.

.PARAMETER Patterns
    An array of host patterns that identify the host block to remove. Must match exactly
    (case-sensitive, same count, same order) as defined in Find-SshHostBlock.

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
    Version: 1.0
    
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
#>
function Remove-SshHostBlock {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [switch]$NoBackup,

        [switch]$RemoveBlankLines
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
    Write-Verbose "Patterns to remove: $($Patterns -join ', ')"

    # Verify file exists
    if (-not (Test-Path -Path $Path)) {
        throw "SSH config file not found: $Path"
    }

    # Parse the existing configuration
    Write-Verbose "Parsing SSH configuration..."
    $entities = Get-SshConfigEntities -Path $Path

    # Find the host block to remove
    $toRemove = Find-SshHostBlock -Entities $entities -Patterns $Patterns

    if (-not $toRemove) {
        Write-Warning "Host block not found with patterns: $($Patterns -join ', ')"
        return
    }

    Write-Verbose "Found host block at lines $($toRemove.StartLine)-$($toRemove.EndLine)"

    # Prepare removal message for ShouldProcess
    $removeMessage = "Host block '$($toRemove.HostLine)' (lines $($toRemove.StartLine)-$($toRemove.EndLine))"

    if (-not $PSCmdlet.ShouldProcess($removeMessage, "Remove")) {
        return
    }

    # Convert to mutable list if needed
    if ($entities -isnot [System.Collections.Generic.List[object]]) {
        $entities = [System.Collections.Generic.List[object]]::new($entities)
    }

    # Find the index of the entity to remove
    $removeIndex = -1
    for ($i = 0; $i -lt $entities.Count; $i++) {
        if ($entities[$i] -eq $toRemove) {
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
        if ($removeIndex -gt 0 -and $entities[$removeIndex - 1].Type -eq 'BlankBlock') {
            $indicesToRemove = @($removeIndex - 1) + $indicesToRemove
            Write-Verbose "Will also remove blank line before (index $($removeIndex - 1))"
        }

        # Check for blank line after
        if ($removeIndex -lt ($entities.Count - 1) -and $entities[$removeIndex + 1].Type -eq 'BlankBlock') {
            $indicesToRemove += ($removeIndex + 1)
            Write-Verbose "Will also remove blank line after (index $($removeIndex + 1))"
        }
    }

    # Remove entities in reverse order to maintain indices
    foreach ($idx in ($indicesToRemove | Sort-Object -Descending)) {
        Write-Verbose "Removing entity at index $idx (Type: $($entities[$idx].Type))"
        $entities.RemoveAt($idx)
    }

    Write-Verbose "Removed $($indicesToRemove.Count) entity/entities"

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
        Path         = $Path
        Patterns     = $Patterns
        Action       = 'Removed'
        LinesRemoved = $indicesToRemove.Count
    }
}
