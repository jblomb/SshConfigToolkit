# SSH Config Management Toolkit

A comprehensive PowerShell module for programmatically managing SSH configuration files in automation scenarios.

## Overview

This toolkit provides building blocks and high-level functions for parsing, analyzing, modifying, and saving SSH configuration files. It respects SSH's first-match-wins precedence rules, maintains proper file structure (bastions before routing rules), and includes safety features like backups, atomic writes, and precedence checking.

## Installation

### From Local Directory

```powershell
# Copy the SshConfigToolkit folder to your PowerShell modules directory
Copy-Item -Path .\SshConfigToolkit -Destination "$env:USERPROFILE\Documents\PowerShell\Modules\" -Recurse

# Or for Windows PowerShell 5.1
Copy-Item -Path .\SshConfigToolkit -Destination "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" -Recurse

# Import the module
Import-Module SshConfigToolkit
```

### Manual Import

```powershell
# Import directly from any location
Import-Module .\SshConfigToolkit\SshConfigToolkit.psd1
```

## Quick Start

### Basic Usage

```powershell
# Create or update a simple host entry
Set-SshHostBlock -Patterns 'myserver' -Options @{
    HostName = '10.0.1.50'
    User     = 'admin'
    Port     = '22'
}

# Read a host's configuration
$config = Get-SshHostBlock -Patterns 'myserver'
$config.Options['HostName']  # Returns '10.0.1.50'

# Update existing host (merge mode - preserves other options)
Set-SshHostBlock -Patterns 'myserver' -Options @{
    Port = '2222'
} -Merge

# Rename a host block
Rename-SshHostBlock -OldPatterns 'myserver' -NewPatterns 'myserver-prod'

# Remove a host block
Remove-SshHostBlock -Patterns 'oldserver' -RemoveBlankLines
```

### Bastion Host Configuration

```powershell
# Create a bastion host with precedence checking
Set-SshHostBlock -Patterns @('jump01', 'bastion') -Options @{
    HostName = '192.168.1.10'
    User     = 'jumpuser'
} -IsBastion -CheckPrecedence
```

## Components

### High-Level Operations (Primary API)

| Function | Description |
|----------|-------------|
| `Set-SshHostBlock` | Creates or updates a host block (upsert operation) |
| `Get-SshHostBlock` | Reads a host block's configuration as a structured object |
| `Remove-SshHostBlock` | Removes a host block from the configuration |
| `Rename-SshHostBlock` | Changes host patterns while preserving options |

### Core Building Blocks

| Function | Description |
|----------|-------------|
| `Get-SshConfigEntities` | Parses SSH config into structured entities |
| `Find-SshHostBlock` | Finds host blocks by exact pattern matching |
| `Test-SshHostPrecedence` | Validates precedence rules for new patterns |
| `ConvertFrom-SshHostBlockText` | Parses host block text into options hashtable |

### Generation & Positioning

| Function | Description |
|----------|-------------|
| `New-SshHostBlockText` | Generates formatted SSH host block text |
| `Get-SshInsertionIndex` | Determines correct insertion point |

### Mutation & Persistence

| Function | Description |
|----------|-------------|
| `Insert-SshHostBlock` | Inserts new host block at specified position |
| `Update-SshHostBlock` | Updates existing host block content |
| `Save-SshConfig` | Writes entities back to disk with backup support |

## Entity Types

The parser recognizes these entity types:

| Type | Description |
|------|-------------|
| `HostBlock` | SSH Host directive with its configuration |
| `MatchBlock` | SSH Match directive with conditional configuration |
| `CommentBlock` | One or more consecutive comment lines |
| `BlankBlock` | One or more consecutive blank lines |
| `OtherBlock` | Other content (Include directives, etc.) |

### Entity Structure

```powershell
[PSCustomObject]@{
    Type      = 'HostBlock'     # Entity type
    StartLine = 10              # 1-indexed line number
    EndLine   = 14              # 1-indexed line number
    RawText   = "Host myserver`n    HostName 10.0.1.50"
    # HostBlock-specific:
    HostLine  = 'Host myserver'
    Patterns  = @('myserver')
    IsBastion = $false
}
```

## Advanced Usage

### Manual Workflow with Full Control

```powershell
$entities = Get-SshConfigEntities -Path "~/.ssh/config"

# Check if host exists
$existing = Find-SshHostBlock -Entities $entities -Patterns 'myserver'

if ($existing) {
    # Parse and modify options
    $options = ConvertFrom-SshHostBlockText -RawText $existing.RawText
    $options['Port'] = '2222'
    
    # Generate new block text
    $newText = New-SshHostBlockText -Patterns $existing.Patterns -Options $options
    $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $newText
} else {
    # Insert new
    $index = Get-SshInsertionIndex -Entities $entities
    $blockText = New-SshHostBlockText -Patterns 'myserver' -Options @{
        HostName = 'new.example.com'
        User     = 'newuser'
    }
    $entities = Insert-SshHostBlock -Entities $entities -InsertionIndex $index -BlockText $blockText
}

Save-SshConfig -Entities $entities -Path "~/.ssh/config"
```

### Batch Operations (Optimized)

```powershell
# FAST: Single parse/save for multiple hosts
$entities = Get-SshConfigEntities -Path $path

foreach ($server in $servers) {
    $existing = Find-SshHostBlock -Entities $entities -Patterns $server.Name
    
    if ($existing) {
        $text = New-SshHostBlockText -Patterns $server.Name -Options $server.Config
        $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $text
    } else {
        $index = Get-SshInsertionIndex -Entities $entities
        $text = New-SshHostBlockText -Patterns $server.Name -Options $server.Config
        $entities = Insert-SshHostBlock -Entities $entities -InsertionIndex $index -BlockText $text
    }
}

Save-SshConfig -Entities $entities -Path $path
```

### Precedence Checking

```powershell
$entities = Get-SshConfigEntities -Path "~/.ssh/config"

# Check if new pattern would be shadowed
$check = Test-SshHostPrecedence -Entities $entities -NewPatterns @('*.example.com')

if (-not $check.Safe) {
    Write-Warning "Pattern would be shadowed by: $($check.OffenderPattern)"
    Write-Warning "Example hostname affected: $($check.Example)"
} else {
    Set-SshHostBlock -Patterns '*.example.com' -Options @{...}
}
```

## Safety Features

### Backups

```powershell
# Default: Creates timestamped backup
Set-SshHostBlock -Patterns 'test' -Options @{...}

# Skip backup (not recommended for production)
Set-SshHostBlock -Patterns 'test' -Options @{...} -NoBackup

# Custom backup directory
Save-SshConfig -Entities $entities -Path $path -BackupDirectory "~/.ssh/backups"
```

### Atomic Writes

Files are written to a temporary location and atomically renamed to prevent corruption:

```powershell
# Default: Atomic write
Save-SshConfig -Entities $entities -Path $path

# Direct write (use only if atomic writes fail)
Save-SshConfig -Entities $entities -Path $path -NoAtomic
```

### WhatIf Support

```powershell
Set-SshHostBlock -Patterns 'test' -Options @{...} -WhatIf
Remove-SshHostBlock -Patterns 'old' -WhatIf
Rename-SshHostBlock -OldPatterns 'a' -NewPatterns 'b' -WhatIf
```

## File Structure Convention

The toolkit maintains this standard SSH config structure:

1. **Primary Bastions** - `jump*` pattern hosts
2. **Customer/Secondary Bastions** - Other bastion hosts
3. **Routing Rules** - All other host patterns
4. **Trailing Comments** - Footer comments (e.g., "# END OF CONFIG")

## Limitations

### Include Directives

This toolkit operates on **single SSH config files**. If your configuration uses `Include` directives:

```
Include ~/.ssh/config.d/*
```

Each included file must be managed separately. The toolkit parses `Include` lines as `OtherBlock` entities but does not follow them.

### Match Blocks

`Match` blocks are parsed and preserved but have limited manipulation support:

- Recognized as `MatchBlock` entity type
- Preserved during modifications
- No dedicated Set/Update/Remove functions (yet)

### Encoding

All files are written using **UTF-8 without BOM**, which is the correct format for SSH configurations. PowerShell 5.1's `Out-File -Encoding UTF8` adds a BOM that may cause issues with some SSH clients - this toolkit avoids that problem.

## Testing

Run the Pester test suite:

```powershell
# Install Pester if needed
Install-Module Pester -Force -SkipPublisherCheck

# Run tests
Invoke-Pester -Path .\Tests\SshConfigToolkit.Tests.ps1 -Output Detailed
```

## Error Handling

```powershell
try {
    Set-SshHostBlock -Patterns 'test' -Options @{
        HostName = '10.0.1.50'
    } -CheckPrecedence
} catch {
    if ($_.Exception.Message -match 'Precedence conflict') {
        Write-Warning "Pattern would be shadowed by earlier entry"
    } elseif ($_.Exception.Message -match 'not found') {
        Write-Warning "SSH config file not found"
    } else {
        throw
    }
}
```

## Requirements

- PowerShell 5.1 or later (PowerShell 7+ recommended)
- Write access to SSH config file and directory
- No external dependencies

## Version History

### v1.1.0 (2025-12-23)
- Added `Get-SshHostBlock` for reading host configurations
- Added `ConvertFrom-SshHostBlockText` for parsing options
- Added `Rename-SshHostBlock` for pattern changes
- Added `Match` block support in parser
- Fixed negation pattern (`!`) handling in precedence checks
- Improved bastion detection
- Added comprehensive Pester test suite
- Packaged as proper PowerShell module

### v1.0.0 (2025-12-23)
- Initial release with complete CRUD operations

## License

Copyright © 2025 Jan Blomberg. All rights reserved.

## Author

Jan Blomberg
