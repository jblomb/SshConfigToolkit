@{
    # Module identification
    RootModule        = 'SshConfigToolkit.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a3b5c7d9-e1f3-4a5b-8c7d-9e1f3a5b7c9d'
    Author            = 'Jan Blomberg'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2026 Jan Blomberg. All rights reserved.'
    Description       = 'A comprehensive PowerShell toolkit for programmatically managing SSH configuration files in automation scenarios. Supports parsing, creating, updating, and removing host blocks with safety features like backups, atomic writes, and precedence checking.'

    # Minimum PowerShell version
    PowerShellVersion = '5.1'

    # Functions to export
    FunctionsToExport = @(
        # Core parsing & analysis
        'Get-SshConfigEntities'
        'Find-SshHostBlock'
        'Get-SshHostBlock'
        'Test-SshHostPrecedence'
        
        # Generation & positioning
        'New-SshHostBlockText'
        'Get-SshInsertionIndex'
        'ConvertFrom-SshHostBlockText'
        
        # Mutation
        'Insert-SshHostBlock'
        'Update-SshHostBlock'
        
        # High-level operations
        'Set-SshHostBlock'
        'Remove-SshHostBlock'
        'Rename-SshHostBlock'
        
        # Persistence
        'Save-SshConfig'
        
        # Helpers (exported for advanced use)
        'ConvertFrom-SshGlobToRegex'
    )

    # Cmdlets, variables, aliases to export
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @('SSH', 'Config', 'Automation', 'DevOps', 'Infrastructure')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = @'
v2.0.0 (2026-01-05)
- BREAKING CHANGE: Integrated host resolution logic directly into Get-SshHostBlock and Find-SshHostBlock.
- Added -HostNameToResolve parameter to Get-SshHostBlock and Find-SshHostBlock to find the first applicable host block, mimicking ssh.exe behavior.
- The -Patterns parameter on these functions is now only for finding host blocks by their exact pattern definition.
- The standalone Resolve-SshHostConfig function is no longer exported and is considered deprecated.

v1.5.0 (2026-01-05)
- Added Resolve-SshHostConfig to find the first host block that matches a given hostname, mimicking ssh.exe behavior.

v1.4.0 (2026-01-05)
- Fixed Pester tests by using Compare-Object for robust collection comparison.
- Added -Type parameter to Get-SshConfigEntities.
- Enriched HostBlock entities with DependentHosts property.

v1.1.0 (2025-12-23)
- Added Get-SshHostBlock, ConvertFrom-SshHostBlockText, and Rename-SshHostBlock.
- Added Match block support in parser.
- Fixed negation pattern (!) handling in precedence checks.
- Improved bastion detection.
- Added comprehensive Pester test suite.
- Packaged as proper PowerShell module.

v1.0.0 (2025-12-23)
- Initial release with complete CRUD operations
'@
        }
    }
}
