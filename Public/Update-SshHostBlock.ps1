<#
.SYNOPSIS
    Updates an existing SSH host block in the entities collection with new content.

.DESCRIPTION
    This function replaces an existing HostBlock entity with new content, updating all metadata
    (patterns, IsBastion flag, etc.) while preserving its position in the configuration file.
    The function modifies the entities collection in place and returns it for method chaining.

.PARAMETER Entities
    A collection of SSH config entities (typically returned from Get-SshConfigEntities).
    This collection will be modified and returned.

.PARAMETER HostBlock
    The existing HostBlock entity to update (typically found using Find-SshHostBlock).

.PARAMETER BlockText
    The new formatted SSH host block text to replace the existing content (typically generated
    by New-SshHostBlockText). Should include the Host line and all configuration options.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.0

.EXAMPLE
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    $existing = Find-SshHostBlock -Entities $entities -Patterns 'myserver'
    $newText = New-SshHostBlockText -Patterns 'myserver' -Options @{HostName='10.0.1.100'; User='admin'}
    $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $newText
    Save-SshConfig -Entities $entities -Path "~/.ssh/config"
    
    Complete workflow: find, update, and save.

.EXAMPLE
    $existing = Find-SshHostBlock -Entities $entities -Patterns @('web*', 'webserver')
    if ($existing) {
        $newOptions = @{
            HostName = 'webserver.example.com'
            User = 'deploy'
            Port = '2222'
        }
        $newText = New-SshHostBlockText -Patterns $existing.Patterns -Options $newOptions
        $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $newText
    }
    
    Updates an existing block while preserving its patterns.
#>
function Update-SshHostBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Entities,

        [Parameter(Mandatory)]
        [PSCustomObject]$HostBlock,

        [Parameter(Mandatory)]
        [string]$BlockText
    )

    Write-Verbose "Updating host block: $($HostBlock.HostLine)"
    Write-Verbose "Original lines: $($HostBlock.StartLine)-$($HostBlock.EndLine)"

    # Validate that the HostBlock is actually in the entities collection
    $found = $false
    for ($i = 0; $i -lt $Entities.Count; $i++) {
        if ($Entities[$i] -eq $HostBlock) {
            $found = $true
            $entityIndex = $i
            break
        }
    }

    if (-not $found) {
        throw "The specified HostBlock was not found in the Entities collection"
    }

    # Parse the new block text to extract metadata
    $lines = $BlockText -split "`r?`n"
    $hostLine = $lines[0]

    # Extract patterns from the Host line
    if ($hostLine -match '^\s*Host\s+(.+)$') {
        $patterns = @($Matches[1] -split '\s+' | Where-Object { $_ })
    } else {
        throw "Invalid host block text: must start with 'Host' directive"
    }

    # Detect if this is a bastion host
    $isBastion = ($patterns | Where-Object { $_ -like 'jump*' }).Count -gt 0

    # Update the entity in place
    # Note: StartLine and EndLine will be recalculated when saved
    $HostBlock.RawText   = $BlockText.TrimEnd("`r`n")
    $HostBlock.HostLine  = $hostLine.Trim()
    $HostBlock.Patterns  = $patterns
    $HostBlock.IsBastion = $isBastion
    # EndLine might change if the new block has different line count
    $HostBlock.EndLine   = $HostBlock.StartLine + $lines.Count - 1

    Write-Verbose "Updated host block to: $($HostBlock.HostLine)"
    Write-Verbose "New patterns: $($patterns -join ', ')"

    return $Entities
}
