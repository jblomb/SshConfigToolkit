<#
.SYNOPSIS
    Parses an SSH config file into structured entities representing host blocks, 
    match blocks, comments, and other content.

.DESCRIPTION
    This function reads an SSH configuration file and parses it into distinct 
    entities such as HostBlock, MatchBlock, CommentBlock, BlankBlock, and OtherBlock. 
    Each entity includes metadata about its type, line range, and raw text content. 
    Host blocks are further analyzed to identify bastion/jump hosts based on naming 
    patterns and configuration options.

.PARAMETER Path
    The full path to the SSH configuration file to parse. The file must exist or 
    an error will be thrown.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.3
    
    Version History:
    1.3 - Added Match block support
    1.2 - Improved bastion detection (checks ProxyCommand/ProxyJump presence)
    1.1 - Fixed bug where single-pattern hosts were stored as strings instead of arrays

    LIMITATIONS:
    - Include directives are parsed but not followed. Each included file must be 
      managed separately.

.EXAMPLE
    Get-SshConfigEntities -Path "C:\Users\username\.ssh\config"
    
    Parses the specified SSH config file and returns a collection of entity objects.

.EXAMPLE
    $entities = Get-SshConfigEntities -Path "$env:USERPROFILE\.ssh\config"
    $bastionHosts = $entities | Where-Object { $_.Type -eq 'HostBlock' -and $_.IsBastion }
    
    Retrieves all bastion/jump host entries from the SSH config.

.EXAMPLE
    $entities = Get-SshConfigEntities -Path "~/.ssh/config"
    $matchBlocks = $entities | Where-Object { $_.Type -eq 'MatchBlock' }
    
    Retrieves all Match blocks from the SSH config.
#>
function Get-SshConfigEntities {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Resolve path (handles ~ and relative paths)
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    # Validate that the SSH config file exists before attempting to parse
    if (-not (Test-Path $Path)) {
        throw "SSH config file not found: $Path"
    }

    Write-Verbose "Reading SSH config from: $Path"

    # Read entire file content and split into individual lines for parsing
    $content = Get-Content -Path $Path -Raw
    $lines   = $content -split "`r?`n"

    Write-Verbose ("Total lines read: {0}" -f $lines.Count)

    # Initialize mutable collection to store parsed entities
    # IMPORTANT: mutable collection for efficient appending
    $entities = [System.Collections.Generic.List[object]]::new()

    $currentType = $null
    $startLine   = $null
    $buffer      = @()

    # Helper function to detect if a host block is a bastion
    # Checks both naming convention AND absence of proxy settings
    function Test-IsBastion {
        param(
            [string[]]$Patterns,
            [string]$RawText
        )
        
        # Check naming convention (jump* pattern)
        $hasJumpPattern = ($Patterns | Where-Object { $_ -like 'jump*' -or $_ -like 'bastion*' }).Count -gt 0
        
        # Check if it has ProxyCommand or ProxyJump (bastions typically don't)
        $hasProxyConfig = $RawText -match '(?mi)^\s+(ProxyCommand|ProxyJump)\s+'
        
        # A bastion is identified by jump/bastion naming OR no proxy config
        # But we prioritize the naming convention as the primary indicator
        return $hasJumpPattern
    }

    # Define helper function to flush accumulated lines into a structured entity object
    function Flush-Entity {
        param (
            [string]$Type,
            [int]$Start,
            [int]$End,
            [string[]]$Lines
        )

        if (-not $Type -or -not $Lines -or $Lines.Count -eq 0) {
            return
        }

        Write-Verbose ("Flushing entity [{0}] lines {1}..{2}" -f $Type, $Start, $End)

        $rawText = ($Lines -join "`n")

        # Create base entity with type, line range, and raw text content
        $entity = [pscustomobject]@{
            Type      = $Type
            StartLine = $Start + 1
            EndLine   = $End + 1
            RawText   = $rawText
        }

        # Enrich HostBlock entities with parsed host patterns and bastion detection
        if ($Type -eq 'HostBlock') {
            $hostLine = $Lines[0]

            if ($hostLine -match '^\s*Host\s+(.+)$') {
                # Force array type even for single patterns to ensure consistent handling
                $patterns = @($Matches[1] -split '\s+' | Where-Object { $_ })
            }
            else {
                $patterns = @()
            }

            # Detect bastion using both naming and config analysis
            $isBastion = Test-IsBastion -Patterns $patterns -RawText $rawText

            $entity | Add-Member -NotePropertyName HostLine  -NotePropertyValue $hostLine.Trim()
            # Use explicit [string[]] type to prevent PowerShell from unwrapping single-element arrays
            [string[]]$patternsArray = $patterns
            $entity | Add-Member -NotePropertyName Patterns  -NotePropertyValue $patternsArray
            $entity | Add-Member -NotePropertyName IsBastion -NotePropertyValue $isBastion
        }

        # Enrich MatchBlock entities with parsed criteria
        if ($Type -eq 'MatchBlock') {
            $matchLine = $Lines[0]

            if ($matchLine -match '^\s*Match\s+(.+)$') {
                $criteria = $Matches[1].Trim()
            }
            else {
                $criteria = ''
            }

            $entity | Add-Member -NotePropertyName MatchLine -NotePropertyValue $matchLine.Trim()
            $entity | Add-Member -NotePropertyName Criteria  -NotePropertyValue $criteria
        }

        # SAFE append to mutable list
        $entities.Add($entity)
    }

    # Main parsing loop: iterate through each line and classify into entity types
    for ($i = 0; $i -lt $lines.Count; $i++) {

        $line = $lines[$i]

        $isComment = $line -match '^\s*#'
        $isBlank   = $line -match '^\s*$'
        $isHost    = $line -match '^\s*Host\s+'
        $isMatch   = $line -match '^\s*Match\s+'

        Write-Verbose ("Line {0}: [{1}]" -f $i, $line)

        # Process Host directive: flush previous entity and capture entire host block
        if ($isHost) {
            Flush-Entity $currentType $startLine ($i - 1) $buffer

            $currentType = 'HostBlock'
            $startLine   = $i
            $buffer      = @($line)

            # Capture all indented config lines belonging to this host block
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match '^\s+\S') {
                    $buffer += $lines[$j]
                    $i = $j
                }
                else { break }
            }
            continue
        }

        # Process Match directive: flush previous entity and capture entire match block
        if ($isMatch) {
            Flush-Entity $currentType $startLine ($i - 1) $buffer

            $currentType = 'MatchBlock'
            $startLine   = $i
            $buffer      = @($line)

            # Capture all indented config lines belonging to this match block
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match '^\s+\S') {
                    $buffer += $lines[$j]
                    $i = $j
                }
                else { break }
            }
            continue
        }

        # Process comment lines: group consecutive comments into a CommentBlock entity
        if ($isComment) {
            if ($currentType -ne 'CommentBlock') {
                Flush-Entity $currentType $startLine ($i - 1) $buffer
                $currentType = 'CommentBlock'
                $startLine   = $i
                $buffer      = @()
            }
            $buffer += $line
            continue
        }

        # Process blank lines: group consecutive blanks into a BlankBlock entity
        if ($isBlank) {
            if ($currentType -ne 'BlankBlock') {
                Flush-Entity $currentType $startLine ($i - 1) $buffer
                $currentType = 'BlankBlock'
                $startLine   = $i
                $buffer      = @()
            }
            $buffer += $line
            continue
        }

        # Process other content: group non-Host, non-Match, non-comment, non-blank lines
        if ($currentType -ne 'OtherBlock') {
            Flush-Entity $currentType $startLine ($i - 1) $buffer
            $currentType = 'OtherBlock'
            $startLine   = $i
            $buffer      = @()
        }

        $buffer += $line
    }

    # Flush final buffered entity after completing line iteration
    Flush-Entity $currentType $startLine ($lines.Count - 1) $buffer

    Write-Verbose ("Parsing complete. Entities created: {0}" -f $entities.Count)

    # Return the complete collection of parsed SSH config entities
    return $entities
}