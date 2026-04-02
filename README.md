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
Import-Module SshConfigToolkit -Force
```

### Manual Import

```powershell
# Import directly from any location
Import-Module .\SshConfigToolkit\SshConfigToolkit.psd1 -Force
```

## Quick Start

### Finding & Reading Host Blocks

There are two ways to get a host block:

**1. Resolve by Hostname (like `ssh.exe`)**

This is the most common use case. It finds the *first* configuration block that applies to a given hostname, respecting wildcards and file order.

```powershell
# Find the configuration that will be used for 'acme-web-prod'
$config = Get-SshHostBlock -HostNameToResolve 'acme-web-prod'

if ($config) {
    Write-Host "Host 'acme-web-prod' will use ProxyJump: $($config.Options['ProxyJump'])"
}
```

**2. Find by Exact Definition**

This finds a host block by its unique, literal `Host` line definition. This is useful for managing a specific entry.

```powershell
# Get the block defined as "Host ac* !*.acme.com"
$config = Get-SshHostBlock -Patterns 'ac*', '!*.acme.com'
```

### Creating and Updating Host Blocks

`Set-SshHostBlock` provides a powerful way to create or update host entries. You can pass SSH options as a hashtable, or use dedicated parameters for common settings like `HostName` and `JumpHost`.

**Basic Example**

```powershell
# Create or update a simple host entry
Set-SshHostBlock -Patterns 'myserver' -Options @{
    HostName = '10.0.1.50'
    User     = 'admin'
}
```

**Using Convenience Parameters**

For clarity and convenience, you can use top-level parameters like `-HostName` and `-JumpHost`.

-   `-HostName`: Sets the `HostName` option.
-   `-JumpHost`: Sets the `ProxyCommand` to route traffic through the specified jump host.

These parameters can be combined with the `-Options` hashtable. If a key is present in both, the top-level parameter takes precedence.

```powershell
# Create or update an entry that uses a jump host
Set-SshHostBlock -Patterns 'internal-server' -HostName '10.10.10.5' -JumpHost 'bastion.example.com' -Options @{
    User = 'dev'
    Port = 2222
}
```

This command creates the following SSH configuration:

```ssh
Host internal-server
    HostName 10.10.10.5
    ProxyCommand ssh bastion.example.com -W %h:%p
    User dev
    Port 2222
```

### Batch Operations

When you need to create, update, or remove multiple host blocks at once, use `-Entities` and `-PassThru` to compose changes in memory before a single save. This reduces file I/O and produces only one backup for the entire batch.

```powershell
# Add an entire environment in one save
$path = "$env:USERPROFILE\.ssh\config"
$entities = Get-SshConfigEntities -Path $path

$entities = Set-SshHostBlock -Entities $entities -Patterns 'jumpex' -HostName 'jump.example.com' -IsBastion -PassThru
$entities = Set-SshHostBlock -Entities $entities -Patterns 'exserver' -HostName '%h.example.com' -JumpHost 'jumpex' -PassThru
$entities = Set-SshHostBlock -Entities $entities -Patterns 'exserver.example.com' -HostName '%h' -JumpHost 'jumpex' -PassThru

Save-SshConfig -Entities $entities -Path $path
```

Removals work the same way, and can be mixed with additions:

```powershell
# Replace an old environment with a new one
$entities = Get-SshConfigEntities -Path $path

$entities = Remove-SshHostBlock -Entities $entities -Patterns 'old-server' -RemoveBlankLines -PassThru
$entities = Remove-SshHostBlock -Entities $entities -Patterns 'old-bastion' -RemoveBlankLines -PassThru
$entities = Set-SshHostBlock -Entities $entities -Patterns 'new-bastion' -HostName '10.0.0.1' -IsBastion -PassThru
$entities = Set-SshHostBlock -Entities $entities -Patterns 'new-server' -HostName '10.0.0.50' -JumpHost 'new-bastion' -PassThru

Save-SshConfig -Entities $entities -Path $path
```

## Components

### High-Level Operations (Primary API)

| Function | Description |
|----------|-------------|
| `Set-SshHostBlock` | Creates or updates a host block (upsert operation). |
| `Get-SshHostBlock` | Retrieves a host block, either by resolving a hostname or by exact pattern definition. |
| `Remove-SshHostBlock` | Removes a host block from the configuration. |
| `Rename-SshHostBlock` | Changes host patterns while preserving options. |

### Core Building Blocks

| Function | Description |
|----------|-------------|
| `Find-SshHostBlock` | Finds a host block, either by resolving a hostname or by exact pattern definition. |
| `Get-SshConfigEntities` | Parses an entire SSH config into structured entities (HostBlocks, CommentBlocks, etc.). |
| `Test-SshHostPrecedence` | Validates precedence rules for new patterns. |
| `ConvertFrom-SshHostBlockText` | Parses host block text into an options hashtable. |

### Generation & Positioning

| Function | Description |
|----------|-------------|
| `New-SshHostBlockText` | Generates formatted SSH host block text. |
| `Get-SshInsertionIndex` | Determines the correct line number to insert a new host block. |

### Mutation & Persistence

| Function | Description |
|----------|-------------|
| `Insert-SshHostBlock` | Inserts a new host block at a specified position. |
| `Update-SshHostBlock` | Updates the text of an existing host block. |
| `Save-SshConfig` | Writes entities back to disk with backup support. |
| `Set-SshConfigPermissions` | Applies a known-good SDDL security descriptor to SSH config files. |

## Entity Types

The parser recognizes these entity types:

| Type | Description |
|------|-------------|
| `HostBlock` | SSH Host directive with its configuration. |
| `MatchBlock` | SSH Match directive with conditional configuration. |
| `CommentBlock` | One or more consecutive comment lines. |
| `BlankBlock` | One or more consecutive blank lines. |
| `OtherBlock` | Other content (Include directives, etc.). |

### Entity Structure

```powershell
[PSCustomObject]@{
    Type           = 'HostBlock'     # Entity type
    StartLine      = 10              # 1-indexed line number
    EndLine        = 14              # 1-indexed line number
    RawText        = "Host myserver`n    HostName 10.0.1.50"
    # HostBlock-specific:
    HostLine       = 'Host myserver'
    Patterns       = @('myserver')
    IsBastion      = $true
    DependentHosts = @('client-host-1', 'client-host-2')
}
```

## Advanced Usage

### Manual Workflow with Full Control

```powershell
$entities = Get-SshConfigEntities -Path "~/.ssh/config"

# Find a block by its exact definition
$existing = Find-SshHostBlock -Entities $entities -Patterns 'myserver'

if ($existing) {
    # Parse and modify options
    $options = ConvertFrom-SshHostBlockText -RawText $existing.RawText
    $options['Port'] = '2222'
    
    # Generate new block text
    $newText = New-SshHostBlockText -Patterns $existing.Patterns -Options $options
    $entities = Update-SshHostBlock -Entities $entities -HostBlock $existing -BlockText $newText
}

Save-SshConfig -Entities $entities -Path "~/.ssh/config"
```

## Requirements

- PowerShell 5.1 or later (PowerShell 7+ recommended)
- Write access to SSH config file and directory
- No external dependencies

## Version History

### v2.2.0 (2026-04-01)
- Added `-Entities` and `-PassThru` parameters to `Set-SshHostBlock`, `Remove-SshHostBlock`, and `Rename-SshHostBlock` for batch operations. Multiple host blocks can now be created, updated, removed, and renamed in memory before a single `Save-SshConfig` call, reducing file I/O and producing only one backup per batch.

### v2.1.1 (2026-03-18)
- Fixed ACL preservation in `Save-SshConfig` and `Update-SshConfig`: original file permissions are now restored after the file is at its final destination, instead of being applied to the temp file before the move. This prevents permission drift caused by inconsistent `Move-Item` ACL behavior.

### v2.1.0 (2026-03-18)
- Added `Set-SshConfigPermissions` to apply known-good SDDL security descriptors to SSH config files. Defaults to the system-wide OpenSSH config path with standard Windows permissions (Administrators/SYSTEM full control, Authenticated Users read). Supports custom SDDL via parameter.

### v2.0.0 (2026-01-05)
- **BREAKING CHANGE**: Integrated host resolution logic directly into `Get-SshHostBlock` and `Find-SshHostBlock`.
- Added `-HostNameToResolve` parameter to `Get-SshHostBlock` and `Find-SshHostBlock` to find the first applicable host block, mimicking `ssh.exe` behavior.
- The `-Patterns` parameter on these functions is now only for finding host blocks by their exact pattern definition.
- The standalone `Resolve-SshHostConfig` function is no longer exported.

### v1.4.0 (2026-01-05)
- Fixed Pester tests by using `Compare-Object` for robust collection comparison.
- Added `-Type` parameter to `Get-SshConfigEntities` to filter for `Host`, `Bastion`, or `All` entities.
- Enriched `HostBlock` entities with a `DependentHosts` property.

### v1.1.0 (2025-12-23)
- Initial release of major features (`Get-SshHostBlock`, `Rename-SshHostBlock`, etc.).
- Added `Match` block support in parser.
- Packaged as proper PowerShell module.

### v1.0.0 (2025-12-23)
- Initial release with basic CRUD operations.

## License

CC0 1.0 Universal - This work is dedicated to the public domain. See https://creativecommons.org/publicdomain/zero/1.0/

## Author

Jan Blomberg