<#
.SYNOPSIS
    Creates or updates an SSH host block in a configuration file (upsert operation).

.DESCRIPTION
    This high-level function provides a complete workflow for managing SSH host blocks 
    in automation scenarios. It handles reading, parsing, updating/inserting, validation, 
    and saving the SSH config file. The function automatically determines whether to 
    update an existing host block or insert a new one, and includes safety features like 
    precedence checking, backups, and atomic writes.

    For batch operations, use -Entities to pass a pre-parsed entity collection (skipping
    the file read) and -PassThru to return the modified entities instead of saving. This
    allows multiple mutations to be composed before a single Save-SshConfig call.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to "$env:USERPROFILE\.ssh\config" 
    on Windows or "~/.ssh/config" on Unix systems. Required when saving (i.e., when -PassThru
    is not specified and -Entities is provided).

.PARAMETER Patterns
    An array of host patterns for the Host directive (e.g., 'myserver', 'myserver.local').
    These are used to identify an existing host block or create a new one.

.PARAMETER Options
    A hashtable of SSH configuration options (e.g., @{HostName='10.0.1.50'; User='admin'}).
    For updates with -Merge, these options are merged with existing options.

.PARAMETER HostName
    A convenience parameter to specify the remote host's real IP address or DNS name.
    This value is added to the 'HostName' option. If the 'HostName' key already
    exists in the -Options hashtable, this parameter's value will take precedence.

.PARAMETER JumpHost
    A convenience parameter to configure a jump host for this connection. The value should be
    an existing host in the SSH config. This sets the 'ProxyCommand' option to
    'ssh <JumpHost> -W %h:%p'. If the 'ProxyCommand' key already exists in the
    -Options hashtable, this parameter's value will take precedence.

.PARAMETER Entities
    Optional. A pre-parsed collection of SSH config entities (typically from Get-SshConfigEntities).
    When provided, the function skips reading and parsing the config file from disk. The collection
    is mutated in place and either saved or returned depending on -PassThru.

.PARAMETER PassThru
    When specified, returns the modified entities collection instead of saving to disk. This
    allows multiple Set-SshHostBlock calls to be chained before a single Save-SshConfig call,
    reducing file I/O and creating only one backup for a batch of changes.

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
    Version: 1.2
    
    Version History:
    1.2 - Added -Entities and -PassThru parameters for batch operations
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
    Set-SshHostBlock -Patterns 'internal-app' -HostName '10.20.30.40' -JumpHost 'bastion' -Options @{ User = 'app_user' }
    
    Creates or updates the 'internal-app' host, setting its 'HostName' and configuring
    it to connect through the 'bastion' host.

.EXAMPLE
    Set-SshHostBlock -Path "C:\custom\ssh_config" -Patterns 'test' -Options @{
        HostName = 'test.local'
    } -WhatIf
    
    Shows what would be changed without actually modifying the file.

.EXAMPLE
    # Batch operation: add an entire environment in one save
    $path = "$env:USERPROFILE\.ssh\config"
    $entities = Get-SshConfigEntities -Path $path
    $entities = Set-SshHostBlock -Entities $entities -Patterns 'jumpex' -HostName 'jump.example.com' -IsBastion -PassThru
    $entities = Set-SshHostBlock -Entities $entities -Patterns 'exserver' -HostName '%h.example.com' -JumpHost 'jumpex' -PassThru
    $entities = Set-SshHostBlock -Entities $entities -Patterns 'exserver.example.com' -HostName '%h' -JumpHost 'jumpex' -PassThru
    Save-SshConfig -Entities $entities -Path $path
    
    Performs three mutations on the in-memory entity collection, then saves once.
#>
function Set-SshHostBlock {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Patterns,

        [Parameter(Mandatory=$false)]
        [hashtable]$Options = @{},

        [string]$HostName,

        [string]$JumpHost,

        [Parameter()]
        [System.Collections.Generic.List[object]]$Entities,

        [switch]$PassThru,

        [switch]$IsBastion,

        [switch]$Merge,

        [switch]$CheckPrecedence,

        [switch]$NoBackup
    )

    # Process patterns to handle space-separated values passed as a single string
    $processedPatterns = @()
    foreach ($pattern in $Patterns) {
        $processedPatterns += $pattern.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    }

    # Validate parameter combinations
    $hasEntities = $PSBoundParameters.ContainsKey('Entities')

    if (-not $hasEntities -and -not $Path) {
        # No entities and no path: resolve default path (original behavior)
        if ($IsWindows -or $env:OS -match 'Windows') {
            $Path = Join-Path $env:USERPROFILE '.ssh\config'
        } else {
            $Path = '~/.ssh/config'
        }
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    elseif ($hasEntities -and -not $PassThru -and -not $Path) {
        # Entities provided without PassThru requires a Path for saving
        throw "The -Path parameter is required when using -Entities without -PassThru, because the modified entities need a destination to save to."
    }
    elseif ($Path) {
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    Write-Debug "SSH config path: $(if ($Path) { $Path } else { '(in-memory only)' })"
    Write-Debug "Patterns: $($processedPatterns -join ', ')"
    Write-Debug "Operation: $(if ($Merge) {'Merge'} else {'Replace'})$(if ($PassThru) {' (PassThru)'} else {''})"

    if ($JumpHost) {
        Write-Debug "Jump host: $JumpHost"
        $Options['ProxyCommand'] = "ssh $JumpHost -W %h:%p"
    }
    If ($HostName) {
        Write-Debug "Host name: $HostName"
        $Options['HostName'] = $HostName
    }

    # When not using pre-parsed entities, handle file creation and parsing
    if (-not $hasEntities) {
        # Ensure the SSH directory exists
        $sshDir = Split-Path -Path $Path -Parent
        if (-not (Test-Path -Path $sshDir)) {
            Write-Debug "Creating SSH directory: $sshDir"
            New-Item -Path $sshDir -ItemType Directory -Force | Out-Null
        }

        # Create empty config file if it doesn't exist
        if (-not (Test-Path -Path $Path)) {
            Write-Debug "Creating new SSH config file: $Path"
            Set-Content -Path $Path -Value '' -NoNewline
        }

        # Parse the existing configuration
        $Entities = Get-SshConfigEntities -Path $Path
    }

    # Convert to mutable list if needed
    if ($Entities -isnot [System.Collections.Generic.List[object]]) {
        # By wrapping $Entities with @(), we ensure that if it's $null (from an
        # empty file), it becomes an empty array, preventing the constructor error.
        $Entities = [System.Collections.Generic.List[object]]::new(@($Entities))
    }

    # Check if host block already exists
    $existing = Find-SshHostBlock -Entities $Entities -Patterns $processedPatterns

    if ($existing) {
        Write-Debug "Found existing host block at lines $($existing.StartLine)-$($existing.EndLine)"
        
        if ($Merge) {
            Write-Debug "Merging options with existing configuration"
            
            # Use the helper function to parse existing options
            $existingOptions = ConvertFrom-SshHostBlockText -RawText $existing.RawText
            
            # Merge: new options override existing ones
            foreach ($key in $Options.Keys) {
                $existingOptions[$key] = $Options[$key]
            }
            
            $finalOptions = $existingOptions
        } else {
            $finalOptions = $Options
        }

        # Generate new block text
        $blockText = New-SshHostBlockText -Patterns $processedPatterns -Options $finalOptions

        # Update the host block
        if ($PSCmdlet.ShouldProcess("Host block '$($processedPatterns -join ' ')'", "Update")) {
            $Entities = Update-SshHostBlock -Entities $Entities -HostBlock $existing -BlockText $blockText
        }

    } else {
        Write-Debug "Host block does not exist, will insert new entry"

        # Check precedence if requested
        if ($CheckPrecedence) {
            Write-Debug "Checking precedence rules..."
            $precedenceCheck = Test-SshHostPrecedence -Entities $Entities -NewPatterns $processedPatterns
            
            if (-not $precedenceCheck.Safe) {
                throw "Precedence conflict: $($precedenceCheck.Reason)"
            }
            Write-Debug "Precedence check passed"
        }

        # Determine insertion point
        $insertionParams = @{
            Entities = $Entities
        }
        if ($IsBastion) {
            $insertionParams['IsBastion'] = $true
        }
        
        $insertionIndex = Get-SshInsertionIndex @insertionParams
        Write-Debug "Insertion point: Line $($insertionIndex.InsertAtLine) ($($insertionIndex.Section))"

        # Generate new block text
        $blockText = New-SshHostBlockText -Patterns $processedPatterns -Options $Options

        # Insert the host block
        if ($PSCmdlet.ShouldProcess("SSH config at line $($insertionIndex.InsertAtLine)", "Insert new host block")) {
            # WORKAROUND: Insert-SshHostBlock fails parameter binding on an empty collection.
            # If the entities list is empty (new file), manually construct and add the entities.
            if ($Entities.Count -eq 0) {
                Write-Debug "Applying workaround for empty entity list"
                
                # Manually create the entities that Insert-SshHostBlock would have.
                # This logic is partially duplicated from Insert-SshHostBlock.
                $newHostBlock = [PSCustomObject]@{
                    Type      = 'HostBlock'
                    RawText   = $blockText.TrimEnd("`r`n")
                    HostLine  = ($blockText -split "`r?`n")[0].Trim()
                    Patterns  = $processedPatterns
                    IsBastion = $IsBastion
                    # StartLine/EndLine are recalculated on save
                    StartLine = 1
                    EndLine   = ($blockText -split "`r?`n").Count
                }
                $blankAfter = [PSCustomObject]@{
                    Type      = 'BlankBlock'
                    RawText   = ''
                    StartLine = 0 # Placeholder, will be recalculated
                    EndLine   = 0 # Placeholder, will be recalculated
                }

                $Entities.Add($newHostBlock)
                $Entities.Add($blankAfter)
                Write-Debug "Manually inserted new host block and blank line"
            }
            else {
                $Entities = Insert-SshHostBlock -Entities $Entities -InsertionIndex $insertionIndex -BlockText $blockText
            }
        }
    }

    # If PassThru, return entities without saving
    if ($PassThru) {
        Write-Debug "PassThru: returning modified entities without saving"
        return $Entities
    }

    # Save the modified configuration
    $saveParams = @{
        Entities = $Entities
        Path     = $Path
    }
    if ($NoBackup) {
        $saveParams['NoBackup'] = $true
    }

    Save-SshConfig @saveParams

    # Return summary information
    if (-not $WhatIfPreference) {
        $action = if ($existing) { 'Updated' } else { 'Inserted' }
        Write-Verbose "$action host block '$($processedPatterns -join ' ')'"
        
        return [PSCustomObject]@{
            Path      = $Path
            Patterns  = $processedPatterns
            Action    = $action
            LineRange = if ($existing) { 
                "$($existing.StartLine)-$($existing.EndLine)" 
            } else { 
                "~$($insertionIndex.InsertAtLine)" 
            }
        }
    }
}