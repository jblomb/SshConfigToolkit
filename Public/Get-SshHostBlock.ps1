<#
.SYNOPSIS
    Retrieves an SSH host block's configuration as a structured object.

.DESCRIPTION
    This function provides a simple way to read SSH host block configurations. It 
    combines Find-SshHostBlock and ConvertFrom-SshHostBlockText to return a clean 
    object containing the host patterns, all SSH options as a hashtable, and metadata 
    about the block's location in the file.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to the user's SSH config.

.PARAMETER Patterns
    An array of host patterns to search for. Must match exactly (case-sensitive, 
    same count, same order).

.PARAMETER Entities
    Optional. Pre-parsed entities collection. If not provided, the function will 
    parse the config file specified by -Path.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.0

.OUTPUTS
    PSCustomObject with properties:
    - Patterns: Array of host patterns
    - Options: Hashtable of SSH configuration options
    - IsBastion: Boolean indicating if this is a bastion host
    - StartLine: Starting line number in the config file
    - EndLine: Ending line number in the config file
    - RawText: Original raw text of the block

    Returns $null if the host block is not found.

.EXAMPLE
    $config = Get-SshHostBlock -Patterns 'myserver'
    $config.Options['HostName']  # Returns the HostName
    $config.Options['User']      # Returns the User

    Gets configuration for a specific host.

.EXAMPLE
    $config = Get-SshHostBlock -Path "C:\custom\ssh_config" -Patterns @('jump01', 'bastion')
    if ($config) {
        Write-Host "Found bastion at lines $($config.StartLine)-$($config.EndLine)"
        Write-Host "HostName: $($config.Options['HostName'])"
    }

    Gets configuration from a custom path with multiple patterns.

.EXAMPLE
    # Check if a host exists and inspect its configuration
    if ($config = Get-SshHostBlock -Patterns 'webserver') {
        $config.Options.GetEnumerator() | ForEach-Object {
            Write-Host "$($_.Key): $($_.Value)"
        }
    } else {
        Write-Host "Host not found"
    }

    Enumerates all options for a host block.
#>
function Get-SshHostBlock {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter()]
        [System.Collections.IEnumerable]$Entities
    )

    # Determine default SSH config path if not specified
    if (-not $Path -and -not $Entities) {
        if ($IsWindows -or $env:OS -match 'Windows') {
            $Path = Join-Path $env:USERPROFILE '.ssh\config'
        } else {
            $Path = '~/.ssh/config'
        }
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    # Parse entities if not provided
    if (-not $Entities) {
        if (-not (Test-Path -Path $Path)) {
            Write-Verbose "SSH config file not found: $Path"
            return $null
        }
        
        Write-Verbose "Parsing SSH config from: $Path"
        $Entities = Get-SshConfigEntities -Path $Path
    }

    # Find the host block
    Write-Verbose "Searching for patterns: $($Patterns -join ', ')"
    $hostBlock = Find-SshHostBlock -Entities $Entities -Patterns $Patterns

    if (-not $hostBlock) {
        Write-Verbose "Host block not found"
        return $null
    }

    Write-Verbose "Found host block at lines $($hostBlock.StartLine)-$($hostBlock.EndLine)"

    # Parse options from raw text
    $options = ConvertFrom-SshHostBlockText -RawText $hostBlock.RawText

    # Return structured result
    return [PSCustomObject]@{
        Patterns  = $hostBlock.Patterns
        Options   = $options
        IsBastion = $hostBlock.IsBastion
        StartLine = $hostBlock.StartLine
        EndLine   = $hostBlock.EndLine
        RawText   = $hostBlock.RawText
    }
}
