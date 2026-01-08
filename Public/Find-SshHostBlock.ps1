<#
.SYNOPSIS
    Finds a specific SSH host block, either by exact pattern definition or by resolving a hostname.

.DESCRIPTION
    This function has two modes:
    1. Default: Locates a HostBlock entity by performing an exact, case-sensitive match on its defined patterns.
    2. Resolve: Finds the first HostBlock entity that would apply to a given hostname, mimicking the way ssh.exe resolves hosts (respecting wildcards, negation, and file order).

.PARAMETER Entities
    A collection of SSH config entities (typically returned from Get-SshConfigEntities) to search through.

.PARAMETER Patterns
    (Default Parameter Set) An array of host patterns to match exactly.

.PARAMETER HostNameToResolve
    (Resolve Parameter Set) The hostname to resolve against the configuration to find the first applicable host block.

.NOTES
    Author: Jan Blomberg
    Date: 2026-01-05
    Version: 2.0

.EXAMPLE
    # Mode 1: Find by exact definition
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    Find-SshHostBlock -Entities $entities -Patterns @('ac*', '!*.acme.com')

.EXAMPLE
    # Mode 2: Resolve a hostname to see which block applies
    Find-SshHostBlock -Entities $entities -HostNameToResolve 'acme-web-prod'
#>
function Find-SshHostBlock {
    [CmdletBinding(DefaultParameterSetName = 'FindByPatterns')]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Entities,

        [Parameter(Mandatory, ParameterSetName = 'FindByPatterns')]
        [string[]]$Patterns,

        [Parameter(Mandatory, ParameterSetName = 'ResolveByHostName')]
        [string]$HostNameToResolve
    )

    if ($PSCmdlet.ParameterSetName -eq 'ResolveByHostName') {
        # MODE 2: Resolve hostname against all host blocks
        foreach ($entity in $Entities) {
            if ($entity.Type -ne 'HostBlock') {
                continue
            }

            $positivePatterns = $entity.Patterns.Where({ $_ -notlike '!*' })
            $negativePatterns = $entity.Patterns.Where({ $_ -like '!*' })

            $isNegativeMatch = $false
            foreach ($pattern in $negativePatterns) {
                $wildcard = [System.Management.Automation.WildcardPattern]::new($pattern.Substring(1), [System.Management.Automation.WildcardOptions]::IgnoreCase)
                if ($wildcard.IsMatch($HostNameToResolve)) {
                    $isNegativeMatch = $true
                    break
                }
            }

            if ($isNegativeMatch) {
                continue # A negative pattern matched, so this block is disqualified.
            }

            $isPositiveMatch = $false
            foreach ($pattern in $positivePatterns) {
                $wildcard = [System.Management.Automation.WildcardPattern]::new($pattern, [System.Management.Automation.WildcardOptions]::IgnoreCase)
                if ($wildcard.IsMatch($HostNameToResolve)) {
                    $isPositiveMatch = $true
                    break
                }
            }

            if ($isPositiveMatch) {
                # This is the first block that matches. Return it.
                return $entity
            }
        }
        # No matching block found
        return $null

    } else {
        # MODE 1: Find by exact pattern definition (original logic)
        $wanted = @($Patterns | Sort-Object -CaseSensitive)
        $matches = New-Object System.Collections.Generic.List[object]

        foreach ($entity in $Entities) {
            if ($entity.Type -ne 'HostBlock') { continue }
            if (-not $entity.Patterns) { continue }

            $existing = @($entity.Patterns | Sort-Object -CaseSensitive)

            if ($existing.Count -ne $wanted.Count) { continue }

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

        if ($matches.Count -gt 1) {
            throw "Multiple Host blocks found with identical patterns (case-sensitive): $($Patterns -join ' ')"
        }

        return $matches | Select-Object -First 1
    }
}