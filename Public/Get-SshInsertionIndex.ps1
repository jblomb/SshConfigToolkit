<#
.SYNOPSIS
    Determines the correct insertion point for a new SSH host block based on type.

.DESCRIPTION
    This function analyzes SSH config entities to find the appropriate line number where a new 
    host block should be inserted, respecting the standard SSH config structure: primary bastions, 
    customer bastions, then routing rules. Inserting at the correct location maintains proper 
    precedence and keeps the config file organized.

.PARAMETER Entities
    A collection of SSH config entities (typically returned from Get-SshConfigEntities).

.PARAMETER IsBastion
    Switch parameter indicating whether the new host block is a bastion/jump host. If specified, 
    the insertion point will be after existing bastions but before routing rules. If omitted, 
    the insertion point will be at the end of existing routing rules.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-22
    Version: 1.1
    
    Version History:
    1.1 - Fixed routing insertion to respect trailing comments (END OF CONFIG blocks)
    1.0 - Initial version

.EXAMPLE
    $entities = Get-SshConfigEntities -Path .\ssh_config.txt
    $index = Get-SshInsertionIndex -Entities $entities -IsBastion
    
    Returns insertion point for a new bastion host (after existing bastions).

.EXAMPLE
    $entities = Get-SshConfigEntities -Path .\ssh_config.txt
    $index = Get-SshInsertionIndex -Entities $entities
    
    Returns insertion point for a new routing rule (after existing routing rules).

.EXAMPLE
    $index = Get-SshInsertionIndex -Entities $entities -IsBastion
    Write-Host "Insert new bastion after line $($index.InsertAtLine)"
    Write-Host "Section: $($index.Section)"
    
    Displays detailed insertion information including line number and section description.
#>
function Get-SshInsertionIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Entities,

        [Parameter()]
        [switch]$IsBastion
    )

    # Filter to get only HostBlock entities in order
    $hostBlocks = @($Entities | Where-Object { $_.Type -eq 'HostBlock' })

    # Handle empty config (no host blocks)
    if ($hostBlocks.Count -eq 0) {
        # Find the last non-blank entity to insert after, or use entity 0 if all blank
        $lastNonBlank = $Entities | Where-Object { $_.Type -ne 'BlankBlock' } | Select-Object -Last 1
        
        if ($lastNonBlank) {
            return [PSCustomObject]@{
                InsertAfterEntity = $lastNonBlank
                InsertAtLine      = $lastNonBlank.EndLine + 1
                Section           = 'Beginning (no hosts exist yet)'
            }
        } else {
            # Completely empty file or only blanks
            return [PSCustomObject]@{
                InsertAfterEntity = $null
                InsertAtLine      = 1
                Section           = 'Beginning (empty file)'
            }
        }
    }

    if ($IsBastion) {
        # Insert new bastion after the last existing bastion
        $lastBastion = $hostBlocks | Where-Object { $_.IsBastion } | Select-Object -Last 1
        
        if ($lastBastion) {
            # Found existing bastions - insert after the last one
            return [PSCustomObject]@{
                InsertAfterEntity = $lastBastion
                InsertAtLine      = $lastBastion.EndLine + 1
                Section           = 'After bastions (before routing rules)'
            }
        } else {
            # No bastions exist yet - insert before first routing rule (or at beginning)
            $firstRoutingRule = $hostBlocks | Where-Object { -not $_.IsBastion } | Select-Object -First 1
            
            if ($firstRoutingRule) {
                # Find the entity immediately before the first routing rule
                $insertAfter = $Entities | Where-Object { $_.EndLine -lt $firstRoutingRule.StartLine } | Select-Object -Last 1
                
                return [PSCustomObject]@{
                    InsertAfterEntity = $insertAfter
                    InsertAtLine      = if ($insertAfter) { $insertAfter.EndLine + 1 } else { 1 }
                    Section           = 'Before routing rules (no bastions exist yet)'
                }
            } else {
                # No routing rules either - insert at end
                $lastEntity = $Entities | Select-Object -Last 1
                
                return [PSCustomObject]@{
                    InsertAfterEntity = $lastEntity
                    InsertAtLine      = $lastEntity.EndLine + 1
                    Section           = 'End of file (first bastion)'
                }
            }
        }
    } else {
        # Insert new routing rule after ALL existing routing rules
        # Strategy: Find the actual end of the routing rules section by working backwards
        # from the end of the file, skipping trailing comments/blanks
        
        $lastRoutingRule = $hostBlocks | Where-Object { -not $_.IsBastion } | Select-Object -Last 1
        
        if ($lastRoutingRule) {
            # Find where routing rules section actually ends
            # Look for any trailing comment blocks (like "# END OF...") that come after routing rules
            $trailingComments = $Entities | Where-Object {
                $_.StartLine -gt $lastRoutingRule.EndLine -and
                $_.Type -eq 'CommentBlock'
            }
            
            if ($trailingComments) {
                # There are comments after routing rules - find the last entity before these comments
                $firstTrailingComment = $trailingComments | Select-Object -First 1
                $insertAfter = $Entities | Where-Object {
                    $_.EndLine -lt $firstTrailingComment.StartLine
                } | Select-Object -Last 1
                
                if ($insertAfter -and $insertAfter.Type -eq 'HostBlock' -and -not $insertAfter.IsBastion) {
                    # Insert after the last routing rule that comes before trailing comments
                    return [PSCustomObject]@{
                        InsertAfterEntity = $insertAfter
                        InsertAtLine      = $insertAfter.EndLine + 1
                        Section           = 'End of routing rules (before trailing comments)'
                    }
                }
            }
            
            # No trailing comments, or insertAfter logic didn't work - insert right after last routing rule
            return [PSCustomObject]@{
                InsertAfterEntity = $lastRoutingRule
                InsertAtLine      = $lastRoutingRule.EndLine + 1
                Section           = 'After routing rules'
            }
        } else {
            # No routing rules exist yet - insert after last bastion
            $lastBastion = $hostBlocks | Where-Object { $_.IsBastion } | Select-Object -Last 1
            
            if ($lastBastion) {
                return [PSCustomObject]@{
                    InsertAfterEntity = $lastBastion
                    InsertAtLine      = $lastBastion.EndLine + 1
                    Section           = 'After bastions (first routing rule)'
                }
            } else {
                # No hosts at all - insert at end
                $lastEntity = $Entities | Select-Object -Last 1
                
                return [PSCustomObject]@{
                    InsertAfterEntity = $lastEntity
                    InsertAtLine      = $lastEntity.EndLine + 1
                    Section           = 'End of file (first host block)'
                }
            }
        }
    }
}