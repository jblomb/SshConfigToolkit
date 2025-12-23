<#
.SYNOPSIS
    Searches for a specific SSH host block by matching host patterns exactly.

.DESCRIPTION
    This function locates a HostBlock entity within a collection of parsed SSH config entities by 
    performing case-sensitive, order-sensitive pattern matching. It ensures that the patterns match 
    exactly (same count, same order, same case) and throws an error if duplicate host blocks are found.

.PARAMETER Entities
    A collection of SSH config entities (typically returned from Get-SshConfigEntities) to search through.

.PARAMETER Patterns
    An array of host patterns to match. The match must be exact: same number of patterns, same order, 
    and case-sensitive comparison.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-22
    Version: 1.1
    
    Version History:
    1.1 - Fixed bug where Sort-Object could unwrap single-element arrays

.EXAMPLE
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    $hostBlock = Find-SshHostBlock -Entities $entities -Patterns @('myserver', 'myserver.local')
    
    Finds the host block that matches both patterns exactly.

.EXAMPLE
    Find-SshHostBlock -Entities $configEntities -Patterns 'jump01'
    
    Searches for a host block with a single pattern 'jump01' (case-sensitive).
#>
function Find-SshHostBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Entities,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    # Define helper function to normalize input into consistent array format
    function Normalize {
        param([object]$v)
        if ($v -is [string]) { return @($v) }
        return @($v)
    }

    # Normalize and sort the target patterns for case-sensitive comparison
    # Force array type after Sort-Object to prevent single-element unwrapping
    $wanted = @(Normalize $Patterns | Sort-Object -CaseSensitive)
    $matches = New-Object System.Collections.Generic.List[object]

    # Iterate through all entities to find HostBlock entries with matching patterns
    foreach ($entity in $Entities) {
        if ($entity.Type -ne 'HostBlock') { continue }
        if (-not $entity.Patterns) { continue }

        # Force array type after Sort-Object to prevent single-element unwrapping
        $existing = @(Normalize $entity.Patterns | Sort-Object -CaseSensitive)

        # Skip if pattern counts don't match (must be exact match)
        if ($existing.Count -ne $wanted.Count) { continue }

        # Perform case-sensitive, position-sensitive comparison of patterns
        $equal = $true
        for ($i = 0; $i -lt $existing.Count; $i++) {
            if ($existing[$i] -cne $wanted[$i]) {
                $equal = $false
                break
            }
        }

        if ($equal) {
            $matches.Add($entity)
        }
    }

    # Validate that only one host block matches (prevent ambiguous results)
    if ($matches.Count -gt 1) {
        throw "Multiple Host blocks found with identical patterns (case-sensitive): $($Patterns -join ' ')"
    }

    # Return the single matching host block, or null if no match found
    return $matches | Select-Object -First 1
}