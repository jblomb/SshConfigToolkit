<#
.SYNOPSIS
    Example usage of the SSH config management toolkit for automation scenarios.

.DESCRIPTION
    This script demonstrates various real-world use cases for managing SSH configurations
    programmatically using the complete toolkit. It covers creating, reading, updating, 
    renaming, and removing host blocks in different scenarios.

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.1
#>

# ═══════════════════════════════════════════════════════════════════════════════
# Setup: Import the module
# ═══════════════════════════════════════════════════════════════════════════════

# If installed as a module:
# Import-Module SshConfigToolkit

# Or import directly:
Import-Module "$PSScriptRoot\SshConfigToolkit.psd1" -Force

# ═══════════════════════════════════════════════════════════════════════════════
# Example 1: Simple host creation
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 1: Create a simple host entry ===" -ForegroundColor Cyan

Set-SshHostBlock -Patterns 'webserver01' -Options @{
    HostName = 'web01.example.com'
    User     = 'deploy'
    Port     = '22'
} -Verbose

# ═══════════════════════════════════════════════════════════════════════════════
# Example 2: Read host configuration (NEW)
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 2: Read host configuration ===" -ForegroundColor Cyan

$config = Get-SshHostBlock -Patterns 'webserver01'

if ($config) {
    Write-Host "Found host at lines $($config.StartLine)-$($config.EndLine)" -ForegroundColor Green
    Write-Host "Options:" -ForegroundColor Green
    $config.Options.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
    }
} else {
    Write-Host "Host not found" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Example 3: Create a bastion host with precedence checking
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 3: Create bastion host ===" -ForegroundColor Cyan

Set-SshHostBlock -Patterns @('jump01', 'bastion-prod') -Options @{
    HostName              = '192.168.1.10'
    User                  = 'jumpuser'
    Port                  = '22'
    IdentityFile          = '~/.ssh/id_bastion'
    StrictHostKeyChecking = 'yes'
} -IsBastion -CheckPrecedence -Verbose

# ═══════════════════════════════════════════════════════════════════════════════
# Example 4: Update existing host (merge mode)
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 4: Update host with merge ===" -ForegroundColor Cyan

# First create a host
Set-SshHostBlock -Patterns 'dbserver' -Options @{
    HostName = 'db.internal'
    User     = 'admin'
}

# Now update it, merging in new options (preserves HostName and User)
Set-SshHostBlock -Patterns 'dbserver' -Options @{
    Port         = '3306'
    ProxyJump    = 'jump01'
    IdentityFile = '~/.ssh/id_db'
} -Merge -Verbose

# Verify the merge
$dbConfig = Get-SshHostBlock -Patterns 'dbserver'
Write-Host "After merge:" -ForegroundColor Green
$dbConfig.Options.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════════
# Example 5: Rename a host block (NEW)
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 5: Rename host block ===" -ForegroundColor Cyan

# Create a host to rename
Set-SshHostBlock -Patterns 'oldserver' -Options @{
    HostName = 'old.example.com'
    User     = 'olduser'
    Port     = '22'
}

Write-Host "Before rename:" -ForegroundColor Yellow
$before = Get-SshHostBlock -Patterns 'oldserver'
Write-Host "  Patterns: $($before.Patterns -join ', ')" -ForegroundColor Gray

# Rename it (options are preserved)
Rename-SshHostBlock -OldPatterns 'oldserver' -NewPatterns 'newserver' -Verbose

Write-Host "After rename:" -ForegroundColor Green
$after = Get-SshHostBlock -Patterns 'newserver'
Write-Host "  Patterns: $($after.Patterns -join ', ')" -ForegroundColor Gray
Write-Host "  HostName preserved: $($after.Options['HostName'])" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════════════════════════════
# Example 6: Parse options from raw text (NEW)
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 6: Parse options from raw text ===" -ForegroundColor Cyan

$rawText = @"
Host myserver server.local
    HostName 10.0.1.50
    User admin
    Port 22
    ProxyCommand ssh -W %h:%p bastion
"@

$options = ConvertFrom-SshHostBlockText -RawText $rawText -IncludePatterns

Write-Host "Parsed from raw text:" -ForegroundColor Green
Write-Host "  Patterns: $($options['_Patterns'] -join ', ')" -ForegroundColor Gray
$options.GetEnumerator() | Where-Object { $_.Key -ne '_Patterns' } | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════════
# Example 7: Low-level control - manual workflow
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 7: Manual low-level workflow ===" -ForegroundColor Cyan

# Parse the config
$entities = Get-SshConfigEntities -Path "~/.ssh/config"

# Check if a specific host exists
$existing = Find-SshHostBlock -Entities $entities -Patterns 'testserver'

if ($existing) {
    Write-Host "Found existing testserver configuration" -ForegroundColor Green
    
    # Parse existing options
    $options = ConvertFrom-SshHostBlockText -RawText $existing.RawText
    
    # Modify options
    $options['HostName'] = 'test.updated.com'
    $options['ServerAliveInterval'] = '60'
    
    # Generate new block text
    $newText = New-SshHostBlockText -Patterns 'testserver' -Options $options
    
    # Update it
    $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $newText
    
} else {
    Write-Host "testserver not found, creating new entry" -ForegroundColor Yellow
    
    # Convert to mutable list
    if ($entities -isnot [System.Collections.Generic.List[object]]) {
        $entities = [System.Collections.Generic.List[object]]::new($entities)
    }
    
    # Find insertion point
    $insertionIndex = Get-SshInsertionIndex -Entities $entities
    
    # Generate block text
    $blockText = New-SshHostBlockText -Patterns 'testserver' -Options @{
        HostName = 'test.example.com'
        User     = 'tester'
    }
    
    # Insert it
    $entities = Insert-SshHostBlock -Entities $entities -InsertionIndex $insertionIndex -BlockText $blockText
}

# Save changes
Save-SshConfig -Entities $entities -Path "~/.ssh/config" -Verbose

# ═══════════════════════════════════════════════════════════════════════════════
# Example 8: Batch operations
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 8: Batch operations ===" -ForegroundColor Cyan

# Define multiple servers to configure
$servers = @(
    @{
        Patterns = 'app01'
        Options  = @{
            HostName  = 'app01.internal'
            User      = 'appuser'
            ProxyJump = 'jump01'
        }
    }
    @{
        Patterns = 'app02'
        Options  = @{
            HostName  = 'app02.internal'
            User      = 'appuser'
            ProxyJump = 'jump01'
        }
    }
    @{
        Patterns = 'app03'
        Options  = @{
            HostName  = 'app03.internal'
            User      = 'appuser'
            ProxyJump = 'jump01'
        }
    }
)

# Configure all servers
foreach ($server in $servers) {
    Write-Host "Configuring $($server.Patterns)..." -ForegroundColor Gray
    Set-SshHostBlock @server
}

Write-Host "Batch configuration complete!" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
# Example 9: Precedence checking with negation patterns (IMPROVED)
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 9: Precedence checking ===" -ForegroundColor Cyan

# Create a config with negation patterns
Set-SshHostBlock -Patterns @('ac*', '!*.acme.com') -Options @{
    HostName     = '%h.acme.com'
    ProxyCommand = 'ssh -W %h:%p jumpac'
} -NoBackup

$entities = Get-SshConfigEntities -Path "~/.ssh/config"

# Test various patterns against precedence rules
$testPatterns = @(
    @{ Pattern = 'acserver'; Expected = 'shadowed' }
    @{ Pattern = 'test.acme.com'; Expected = 'safe (negation protects it)' }
    @{ Pattern = 'newhost'; Expected = 'safe' }
)

foreach ($test in $testPatterns) {
    $result = Test-SshHostPrecedence -Entities $entities -NewPatterns @($test.Pattern)
    $status = if ($result.Safe) { 'SAFE' } else { 'SHADOWED' }
    $color = if ($result.Safe) { 'Green' } else { 'Yellow' }
    Write-Host "  Pattern '$($test.Pattern)': $status - $($test.Expected)" -ForegroundColor $color
}

# ═══════════════════════════════════════════════════════════════════════════════
# Example 10: Remove a host block
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 10: Remove host block ===" -ForegroundColor Cyan

# Remove a specific host
Remove-SshHostBlock -Patterns 'testserver' -RemoveBlankLines -Verbose -Confirm:$false

# ═══════════════════════════════════════════════════════════════════════════════
# Example 11: WhatIf testing
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 11: WhatIf testing ===" -ForegroundColor Cyan

# Test what would happen without making changes
Write-Host "Testing Set-SshHostBlock -WhatIf:" -ForegroundColor Yellow
Set-SshHostBlock -Patterns 'whatifserver' -Options @{
    HostName = 'whatif.example.com'
    User     = 'whatifuser'
} -WhatIf

Write-Host "`nTesting Rename-SshHostBlock -WhatIf:" -ForegroundColor Yellow
Rename-SshHostBlock -OldPatterns 'newserver' -NewPatterns 'renamedserver' -WhatIf

# ═══════════════════════════════════════════════════════════════════════════════
# Example 12: Reading and analyzing configuration
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n=== Example 12: Analyze configuration ===" -ForegroundColor Cyan

# Parse and analyze the current configuration
$entities = Get-SshConfigEntities -Path "~/.ssh/config"

# Count different entity types
$summary = $entities | Group-Object -Property Type | Select-Object Name, Count

Write-Host "`nConfiguration summary:" -ForegroundColor Green
$summary | Format-Table -AutoSize

# List all bastions
$bastions = $entities | Where-Object { $_.Type -eq 'HostBlock' -and $_.IsBastion }
Write-Host "Bastion hosts found: $($bastions.Count)" -ForegroundColor Green
$bastions | ForEach-Object {
    Write-Host "  - $($_.HostLine)" -ForegroundColor Gray
}

# List all routing rules
$routingRules = $entities | Where-Object { $_.Type -eq 'HostBlock' -and -not $_.IsBastion }
Write-Host "`nRouting rules found: $($routingRules.Count)" -ForegroundColor Green
$routingRules | Select-Object -First 5 | ForEach-Object {
    Write-Host "  - $($_.HostLine)" -ForegroundColor Gray
}

# Check for Match blocks
$matchBlocks = $entities | Where-Object { $_.Type -eq 'MatchBlock' }
if ($matchBlocks) {
    Write-Host "`nMatch blocks found: $($matchBlocks.Count)" -ForegroundColor Green
    $matchBlocks | ForEach-Object {
        Write-Host "  - $($_.MatchLine)" -ForegroundColor Gray
    }
}

Write-Host "`n=== All examples completed ===" -ForegroundColor Cyan
