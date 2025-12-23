<#
.SYNOPSIS
    Creates or updates an SSH host block in a configuration file (upsert operation).

.DESCRIPTION
    This high-level function provides a complete workflow for managing SSH host blocks 
    in automation scenarios. It handles reading, parsing, updating/inserting, validation, 
    and saving the SSH config file. The function automatically determines whether to 
    update an existing host block or insert a new one, and includes safety features like 
    precedence checking, backups, and atomic writes.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to "$env:USERPROFILE\.ssh\config" 
    on Windows or "~/.ssh/config" on Unix systems.

.PARAMETER Patterns
    An array of host patterns for the Host directive (e.g., 'myserver', 'myserver.local').
    These are used to identify an existing host block or create a new one.

.PARAMETER Options
    A hashtable of SSH configuration options (e.g., @{HostName='10.0.1.50'; User='admin'}).
    For updates with -Merge, these options are merged with existing options.

.PARAMETER IsBastion
    Indicates whether this host is a bastion/jump host. This affects where the host block 
    is inserted in the configuration file (bastions are placed before routing rules).

.PARAMETER Merge
    When updating an existing host block, merge the new options with existing options 
    instead of replacing them entirely. New values override existing ones for the same keys.

.PARAMETER CheckPrecedence
    When specified, validates that the new host patterns won't be shadowed by earlier 
    patterns in the configuration. Throws an error if a precedence conflict is detected.

.PARAMETER NoBackup
    Skips creating a timestamped backup of the configuration file before making changes.

.PARAMETER WhatIf
    Shows what changes would be made without actually modifying the file.

.PARAMETER Confirm
    Prompts for confirmation before making changes.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
    
    Version History:
    1.1 - Refactored to use ConvertFrom-SshHostBlockText helper
    1.0 - Initial release
    
    Requires: Get-SshConfigEntities, Find-SshHostBlock, Get-SshInsertionIndex,
              New-SshHostBlockText, Insert-SshHostBlock, Update-SshHostBlock,
              Save-SshConfig, Test-SshHostPrecedence, ConvertFrom-SshHostBlockText

.EXAMPLE
    Set-SshHostBlock -Patterns 'myserver' -Options @{
        HostName = '10.0.1.50'
        User = 'admin'
        Port = '22'
    }
    
    Creates or updates the 'myserver' host block with the specified options.

.EXAMPLE
    Set-SshHostBlock -Patterns @('jump01', 'bastion') -Options @{
        HostName = '192.168.1.10'
        User = 'jumpuser'
    } -IsBastion -CheckPrecedence
    
    Creates or updates a bastion host with precedence validation.

.EXAMPLE
    Set-SshHostBlock -Patterns 'webserver' -Options @{Port = '2222'} -Merge
    
    Updates only the Port option, leaving other existing options unchanged.

.EXAMPLE
    Set-SshHostBlock -Path "C:\custom\ssh_config" -Patterns 'test' -Options @{
        HostName = 'test.local'
    } -WhatIf
    
    Shows what would be changed without actually modifying the file.
#>
function Set-SshHostBlock {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter(Mandatory)]
        [hashtable]$Options,

        [switch]$IsBastion,

        [switch]$Merge,

        [switch]$CheckPrecedence,

        [switch]$NoBackup
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
    Write-Verbose "Patterns: $($Patterns -join ', ')"
    Write-Verbose "Operation: $(if ($Merge) {'Merge'} else {'Replace'})"

    # Ensure the SSH directory exists
    $sshDir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $sshDir)) {
        Write-Verbose "Creating SSH directory: $sshDir"
        New-Item -Path $sshDir -ItemType Directory -Force | Out-Null
    }

    # Create empty config file if it doesn't exist
    if (-not (Test-Path -Path $Path)) {
        Write-Verbose "Creating new SSH config file: $Path"
        Set-Content -Path $Path -Value '' -NoNewline
    }

    # Parse the existing configuration
    Write-Verbose "Parsing SSH configuration..."
    $entities = Get-SshConfigEntities -Path $Path

    # Convert to mutable list if needed
    if ($entities -isnot [System.Collections.Generic.List[object]]) {
        $entities = [System.Collections.Generic.List[object]]::new($entities)
    }

    # Check if host block already exists
    $existing = Find-SshHostBlock -Entities $entities -Patterns $Patterns

    if ($existing) {
        Write-Verbose "Found existing host block at lines $($existing.StartLine)-$($existing.EndLine)"
        
        if ($Merge) {
            Write-Verbose "Merging options with existing configuration"
            
            # Use the helper function to parse existing options
            $existingOptions = ConvertFrom-SshHostBlockText -RawText $existing.RawText
            
            # Merge: new options override existing ones
            foreach ($key in $Options.Keys) {
                $existingOptions[$key] = $Options[$key]
            }
            
            $finalOptions = $existingOptions
        } else {
            Write-Verbose "Replacing existing configuration"
            $finalOptions = $Options
        }

        # Generate new block text
        $blockText = New-SshHostBlockText -Patterns $Patterns -Options $finalOptions

        # Update the host block
        if ($PSCmdlet.ShouldProcess("Host block '$($Patterns -join ' ')'", "Update")) {
            $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $blockText
            Write-Verbose "Host block updated"
        }

    } else {
        Write-Verbose "Host block does not exist, will insert new entry"

        # Check precedence if requested
        if ($CheckPrecedence) {
            Write-Verbose "Checking precedence rules..."
            $precedenceCheck = Test-SshHostPrecedence -Entities $entities -NewPatterns $Patterns
            
            if (-not $precedenceCheck.Safe) {
                throw "Precedence conflict: $($precedenceCheck.Reason)"
            }
            Write-Verbose "Precedence check passed"
        }

        # Determine insertion point
        $insertionParams = @{
            Entities = $entities
        }
        if ($IsBastion) {
            $insertionParams['IsBastion'] = $true
        }
        
        $insertionIndex = Get-SshInsertionIndex @insertionParams
        Write-Verbose "Insertion point: Line $($insertionIndex.InsertAtLine) ($($insertionIndex.Section))"

        # Generate new block text
        $blockText = New-SshHostBlockText -Patterns $Patterns -Options $Options

        # Insert the host block
        if ($PSCmdlet.ShouldProcess("SSH config at line $($insertionIndex.InsertAtLine)", "Insert new host block")) {
            $entities = Insert-SshHostBlock -Entities $entities -InsertionIndex $insertionIndex -BlockText $blockText
            Write-Verbose "Host block inserted"
        }
    }

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
    if (-not $WhatIfPreference) {
        Write-Verbose "Configuration saved successfully"
        
        return [PSCustomObject]@{
            Path      = $Path
            Patterns  = $Patterns
            Action    = if ($existing) { 'Updated' } else { 'Inserted' }
            LineRange = if ($existing) { 
                "$($existing.StartLine)-$($existing.EndLine)" 
            } else { 
                "~$($insertionIndex.InsertAtLine)" 
            }
        }
    }
}
