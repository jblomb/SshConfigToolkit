<#
.SYNOPSIS
    Converts an SSH glob pattern into a compiled regular expression.

.DESCRIPTION
    This helper function translates SSH-style glob patterns (using * and ? wildcards) 
    into equivalent regular expressions for hostname matching. It escapes all regex 
    metacharacters first, then restores glob wildcard behavior by replacing escaped 
    wildcards with their regex equivalents.

.PARAMETER Pattern
    The SSH glob pattern to convert (e.g., 'server*', 'host?.example.com').
    Negation patterns starting with '!' are not supported by this function and 
    should be handled separately.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
    
    Version History:
    1.1 - Documented negation pattern limitation

.EXAMPLE
    $regex = ConvertFrom-SshGlobToRegex -Pattern 'web*.example.com'
    $regex.IsMatch('webserver.example.com')  # Returns $true
    
    Converts a glob pattern and tests it against a hostname.
#>
function ConvertFrom-SshGlobToRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    # SSH Host patterns are glob-ish; treat ? and * like glob wildcards.
    # Escape all regex metacharacters to treat pattern as literal, then restore glob wildcards
    $escaped = [regex]::Escape($Pattern)
    $regex   = '^' + ($escaped -replace '\\\*','.*' -replace '\\\?','.') + '$'
    return [regex]$regex
}

<#
.SYNOPSIS
    Tests whether a hostname matches an SSH host pattern, respecting negation patterns.

.DESCRIPTION
    This helper function tests if a hostname matches a given SSH host pattern. It 
    properly handles negation patterns (starting with '!') which exclude matching 
    hosts from a Host block.

.PARAMETER Hostname
    The hostname to test against the pattern.

.PARAMETER Pattern
    The SSH host pattern to test. Can be a glob pattern or a negation pattern 
    starting with '!'.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.0

.EXAMPLE
    Test-SshPatternMatch -Hostname 'server.acme.com' -Pattern '*.acme.com'
    # Returns: @{ Matches = $true; IsNegation = $false }

.EXAMPLE
    Test-SshPatternMatch -Hostname 'server.acme.com' -Pattern '!*.acme.com'
    # Returns: @{ Matches = $true; IsNegation = $true }
#>
function Test-SshPatternMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Hostname,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    # Check for negation pattern
    $isNegation = $Pattern.StartsWith('!')
    $actualPattern = if ($isNegation) { $Pattern.Substring(1) } else { $Pattern }

    # Convert to regex and test
    $regex = ConvertFrom-SshGlobToRegex -Pattern $actualPattern
    $matches = $regex.IsMatch($Hostname)

    return [PSCustomObject]@{
        Matches    = $matches
        IsNegation = $isNegation
    }
}

<#
.SYNOPSIS
    Tests whether new SSH host patterns would be shadowed by existing earlier patterns.

.DESCRIPTION
    This function performs precedence analysis on SSH config host patterns to detect 
    potential shadowing issues. SSH config uses first-match semantics, so earlier Host 
    blocks can shadow later ones. The function generates sample hostnames that match 
    the new patterns, then checks if any earlier host block patterns would match those 
    samples first, indicating a precedence conflict.

    This version properly handles negation patterns (!) which exclude hosts from 
    matching a Host block.

.PARAMETER Entities
    A collection of SSH config entities (typically from Get-SshConfigEntities) 
    representing the existing configuration in order.

.PARAMETER NewPatterns
    An array of new host patterns to be tested for precedence conflicts against 
    existing patterns.

.PARAMETER InsertionIndex
    Optional. The index at which the new patterns would be inserted. If provided, 
    only patterns before this index are checked for precedence conflicts.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
    
    Version History:
    1.1 - Added proper handling of negation patterns (!)
    1.0 - Initial version

.EXAMPLE
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    $result = Test-SshHostPrecedence -Entities $entities -NewPatterns @('server*')
    
    if (-not $result.Safe) {
        Write-Warning "Precedence issue: $($result.Reason)"
    }
    
    Tests if a new pattern would be shadowed by existing configuration.

.EXAMPLE
    # Test patterns that might conflict with negation patterns
    $result = Test-SshHostPrecedence -Entities $entities -NewPatterns @('*.acme.com')
    
    # If config has: Host ac* !*.acme.com
    # This checks if the negation properly excludes *.acme.com hosts
#>
function Test-SshHostPrecedence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Entities,

        [Parameter(Mandatory)]
        [string[]]$NewPatterns,

        [Parameter()]
        [int]$InsertionIndex = -1
    )

    # Extract only HostBlock entities in their original order (order matters for precedence)
    $hostBlocks = @(foreach ($e in $Entities) {
        if ($e.Type -eq 'HostBlock') { $e }
    })

    # If insertion index specified, only check blocks before that point
    if ($InsertionIndex -ge 0) {
        $hostBlocks = @($hostBlocks | Where-Object { $_.StartLine -lt $InsertionIndex })
    }

    # Filter out negation patterns from new patterns (they don't create matches, only exclude)
    $positiveNewPatterns = @($NewPatterns | Where-Object { -not $_.StartsWith('!') })

    if ($positiveNewPatterns.Count -eq 0) {
        # All patterns are negations - no precedence issues possible
        return [PSCustomObject]@{ Safe = $true }
    }

    # Precompile info for each new positive pattern
    $newPatternInfo = foreach ($p in $positiveNewPatterns) {
        [PSCustomObject]@{
            Pattern = $p
            Regex   = ConvertFrom-SshGlobToRegex -Pattern $p
            HasGlob = ($p -match '[\*\?]')
        }
    }

    # Helper function to generate conservative sample hostnames that match a given pattern
    function New-SamplesForPattern {
        param([string]$Pattern)

        # The '*' wildcard matches everything, so provide generic samples
        if ($Pattern -eq '*') { return @('anything.example', 'host', 'a') }

        # If no glob, the literal hostname is the sample
        if ($Pattern -notmatch '[\*\?]') { return @($Pattern) }

        # Build a few plausible candidates:
        # Replace '*' with various strings, '?' with single chars
        $base = $Pattern
        $c1 = ($base -replace '\*','a'    -replace '\?','b')
        $c2 = ($base -replace '\*','host' -replace '\?','c')
        $c3 = ($base -replace '\*','x'    -replace '\?','d')

        # Extra: if pattern contains '.': try a domainish sample
        $c4 = if ($base -match '\.') {
            ($base -replace '\*','example' -replace '\?','e')
        }

        @($c1,$c2,$c3,$c4) | Where-Object { $_ } | Select-Object -Unique
    }

    # Generate sample hostnames for all new patterns to test against earlier patterns
    $newSamples = foreach ($np in $newPatternInfo) {
        foreach ($s in (New-SamplesForPattern -Pattern $np.Pattern)) {
            [PSCustomObject]@{ Pattern = $np.Pattern; Sample = $s }
        }
    }

    # Scan each earlier host block to detect if any patterns shadow the new patterns
    foreach ($hb in $hostBlocks) {
        # Collect positive and negative patterns from this host block
        $positivePatterns = @($hb.Patterns | Where-Object { -not $_.StartsWith('!') })
        $negativePatterns = @($hb.Patterns | Where-Object { $_.StartsWith('!') })

        foreach ($ns in $newSamples) {
            # Check if any positive pattern in this block matches the sample
            $matchedByPositive = $false
            $matchingPositivePattern = $null

            foreach ($pp in $positivePatterns) {
                # The wildcard '*' matches everything
                if ($pp -eq '*') {
                    $matchedByPositive = $true
                    $matchingPositivePattern = '*'
                    break
                }

                $ppRegex = ConvertFrom-SshGlobToRegex -Pattern $pp
                if ($ppRegex.IsMatch($ns.Sample)) {
                    $matchedByPositive = $true
                    $matchingPositivePattern = $pp
                    break
                }
            }

            # If matched by positive, check if excluded by negative
            if ($matchedByPositive) {
                $excludedByNegative = $false

                foreach ($np in $negativePatterns) {
                    $actualNp = $np.Substring(1)  # Remove the '!'
                    $npRegex = ConvertFrom-SshGlobToRegex -Pattern $actualNp
                    if ($npRegex.IsMatch($ns.Sample)) {
                        $excludedByNegative = $true
                        break
                    }
                }

                # If matched by positive AND not excluded by negative = shadowed
                if (-not $excludedByNegative) {
                    return [PSCustomObject]@{
                        Safe            = $false
                        Reason          = "New pattern '$($ns.Pattern)' may be shadowed by earlier pattern '$matchingPositivePattern'."
                        Offender        = $hb
                        OffenderPattern = $matchingPositivePattern
                        Example         = $ns.Sample
                    }
                }
            }
        }
    }

    # If no shadowing detected, return safe status
    [PSCustomObject]@{ Safe = $true }
}
