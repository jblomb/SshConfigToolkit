<#
.SYNOPSIS
    Generates formatted SSH config host block text from patterns and options.

.DESCRIPTION
    This function creates a properly formatted SSH configuration host block with a specified set of 
    host patterns and configuration options. It ensures deterministic output by ordering options in 
    a preferred sequence (common options first, then alphabetical), uses proper SSH config syntax 
    (space-separated key-value pairs), and provides control over indentation and trailing newlines 
    for reliable round-trip parsing.

.PARAMETER Patterns
    An array of host patterns for the Host directive (e.g., 'myserver', 'myserver.local'). At least 
    one pattern is required.

.PARAMETER Options
    A hashtable of SSH configuration options (e.g., HostName, User, Port, ProxyJump). Keys should match 
    standard SSH config option names. Null or empty values are automatically skipped.

.PARAMETER Indent
    The number of spaces to indent option lines beneath the Host directive. Default is 4 spaces.

.PARAMETER NoTrailingNewline
    When specified, suppresses the trailing newline at the end of the generated text. Useful for 
    precise string concatenation scenarios.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-22
    Version: 1.0

.EXAMPLE
    $options = @{
        HostName = '10.0.1.50'
        User = 'admin'
        Port = '22'
    }
    New-SshHostBlockText -Patterns 'myserver' -Options $options
    
    Generates a host block with standard indentation and trailing newline.

.EXAMPLE
    $jumpOptions = @{
        HostName = '192.168.1.10'
        ProxyJump = 'bastion'
        IdentityFile = '~/.ssh/id_rsa'
    }
    New-SshHostBlockText -Patterns @('target', 'target.internal') -Options $jumpOptions -Indent 2
    
    Creates a multi-pattern host block with custom 2-space indentation.
#>
function New-SshHostBlockText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter(Mandatory)]
        [hashtable]$Options,

        # Optional: keep output style flexible without branching later
        [int]$Indent = 4,

        # Control trailing newline explicitly (important for round-trip)
        [switch]$NoTrailingNewline
    )

    # Validate that at least one host pattern is provided
    if ($Patterns.Count -eq 0) {
        throw "Host block must contain at least one pattern."
    }

    $indentStr = ' ' * $Indent
    $lines     = New-Object 'System.Collections.Generic.List[string]'

    # ── Host line ──────────────────────────────────────────────
    # Generate the Host directive line with space-separated patterns
    $lines.Add(('Host {0}' -f ($Patterns -join ' ')))

    # ── Deterministic option order ─────────────────────────────
    # Establish preferred order for common SSH options to ensure consistent output across runs
    # Known/common SSH options first, rest sorted alphabetically
    $preferredOrder = @(
        'HostName',
        'User',
        'IdentityFile',
        'IdentitiesOnly',
        'ProxyCommand',
        'ProxyJump',
        'Port',
        'ServerAliveInterval',
        'ServerAliveCountMax',
        'StrictHostKeyChecking',
        'UserKnownHostsFile'
    )

    # Build ordered key list: preferred options first, then remaining options alphabetically
    $orderedKeys = @()
    $orderedKeys += $preferredOrder | Where-Object { $Options.ContainsKey($_) }
    $orderedKeys += ($Options.Keys | Where-Object { $_ -notin $preferredOrder } | Sort-Object)

    # ── Render options ─────────────────────────────────────────
    # Generate indented option lines using SSH config syntax (Key Value, no equals sign)
    foreach ($key in $orderedKeys) {
        $value = $Options[$key]

        # Skip null or empty values to avoid generating invalid config lines
        if ($null -eq $value -or $value -eq '') {
            continue
        }

        # SSH config is "Key Value" (no '=')
        $lines.Add(('{0}{1} {2}' -f $indentStr, $key, $value))
    }

    # ── Final text ─────────────────────────────────────────────
    # Return formatted host block text with or without trailing newline based on switch
    if (-not $NoTrailingNewline) {
        return ($lines -join "`n") + "`n"
    }

    return ($lines -join "`n")
}