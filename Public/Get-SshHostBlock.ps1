<#
.SYNOPSIS
    Retrieves an SSH host block's configuration, either by exact pattern definition or by resolving a hostname.

.DESCRIPTION
    This function provides a simple way to read an SSH host block's configuration. It has two modes:
    1. FindByPatterns (Default): Finds a host block by matching its defined patterns exactly.
    2. ResolveByHostName: Finds the first host block that applies to a given hostname, mimicking ssh.exe's behavior.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to the user's SSH config.

.PARAMETER Patterns
    (FindByPatterns set) An array of host patterns to search for. Must match the host definition exactly.

.PARAMETER HostNameToResolve
    (ResolveByHostName set) The hostname to resolve against the configuration to find the first applicable host block.

.PARAMETER Entities
    Optional. A pre-parsed collection of config entities. If not provided, the file at -Path will be parsed.

.NOTES
    Author: Jan Blomberg
    Date: 2026-01-05
    Version: 2.0

.OUTPUTS
    PSCustomObject with the host block's configuration, or $null if not found.

.EXAMPLE
    # Mode 1: Get a host by its exact pattern definition
    Get-SshHostBlock -Patterns 'myserver'

.EXAMPLE
    # Mode 2: Get the config that applies to a hostname
    Get-SshHostBlock -HostNameToResolve 'dev.server.acme.com'
#>
function Get-SshHostBlock {
    [CmdletBinding(DefaultParameterSetName = 'FindByPatterns')]
    param(
        [Parameter(ParameterSetName = 'FindByPatterns')]
        [Parameter(ParameterSetName = 'ResolveByHostName')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'FindByPatterns')]
        [string[]]$Patterns,

        [Parameter(Mandatory, ParameterSetName = 'ResolveByHostName')]
        [string]$HostNameToResolve,

        [Parameter(ParameterSetName = 'FindByPatterns')]
        [Parameter(ParameterSetName = 'ResolveByHostName')]
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

    # Find the host block using the appropriate parameter set
    $findParams = @{ Entities = $Entities }
    if ($PSCmdlet.ParameterSetName -eq 'ResolveByHostName') {
        Write-Verbose "Resolving hostname: $HostNameToResolve"
        $findParams.HostNameToResolve = $HostNameToResolve
    } else {
        Write-Verbose "Searching for exact patterns: $($Patterns -join ', ')"
        $findParams.Patterns = $Patterns
    }
    $hostBlock = Find-SshHostBlock @findParams

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
