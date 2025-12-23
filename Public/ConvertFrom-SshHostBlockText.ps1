<#
.SYNOPSIS
    Parses SSH host block raw text into a structured hashtable of options.

.DESCRIPTION
    This function takes the raw text of an SSH host block (as stored in an entity's 
    RawText property) and parses it into a hashtable containing the host patterns 
    and all configuration options. This is useful for inspecting, modifying, or 
    merging host block configurations programmatically.

.PARAMETER RawText
    The raw text of an SSH host block, typically from an entity's RawText property.
    Should start with a 'Host' line followed by indented configuration options.

.PARAMETER IncludePatterns
    When specified, includes the parsed host patterns in the output hashtable under 
    the '_Patterns' key. By default, only SSH options are returned.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.0

.OUTPUTS
    System.Collections.Hashtable
    A hashtable containing SSH configuration options as key-value pairs.

.EXAMPLE
    $entity = Find-SshHostBlock -Entities $entities -Patterns 'myserver'
    $options = ConvertFrom-SshHostBlockText -RawText $entity.RawText
    $options['HostName']  # Returns the HostName value

    Parses an existing host block's options into a hashtable.

.EXAMPLE
    $rawText = @"
    Host myserver
        HostName 10.0.1.50
        User admin
        Port 22
    "@
    $options = ConvertFrom-SshHostBlockText -RawText $rawText -IncludePatterns
    $options['_Patterns']  # Returns @('myserver')
    $options['User']       # Returns 'admin'

    Parses raw text including the host patterns.

.EXAMPLE
    # Merge existing options with new ones
    $existing = ConvertFrom-SshHostBlockText -RawText $hostBlock.RawText
    $existing['Port'] = '2222'  # Override port
    $existing['ProxyJump'] = 'bastion'  # Add new option
    $newText = New-SshHostBlockText -Patterns $hostBlock.Patterns -Options $existing

    Demonstrates modifying parsed options and regenerating block text.
#>
function ConvertFrom-SshHostBlockText {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$RawText,

        [switch]$IncludePatterns
    )

    process {
        $options = @{}
        $patterns = @()

        # Split into lines and process
        $lines = $RawText -split "`r?`n"

        foreach ($line in $lines) {
            # Skip empty lines
            if ($line -match '^\s*$') {
                continue
            }

            # Parse Host line
            if ($line -match '^\s*Host\s+(.+)$') {
                $patterns = @($Matches[1] -split '\s+' | Where-Object { $_ })
                continue
            }

            # Parse option lines (indented Key Value pairs)
            # SSH config format: Key Value (no equals sign)
            # Value can contain spaces, so we split on first whitespace only
            if ($line -match '^\s+(\S+)\s+(.+)$') {
                $key = $Matches[1]
                $value = $Matches[2].TrimEnd()
                
                # Handle duplicate keys (some SSH options can appear multiple times)
                # For now, last value wins (consistent with Set-SshHostBlock merge behavior)
                $options[$key] = $value
            }
        }

        # Optionally include patterns in output
        if ($IncludePatterns -and $patterns.Count -gt 0) {
            $options['_Patterns'] = $patterns
        }

        return $options
    }
}
