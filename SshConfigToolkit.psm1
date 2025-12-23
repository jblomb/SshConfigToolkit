<#
.SYNOPSIS
    SshConfigToolkit - PowerShell module for SSH config management.

.DESCRIPTION
    This module provides comprehensive tools for programmatically managing SSH 
    configuration files. It supports parsing, creating, updating, and removing 
    host blocks with safety features like backups, atomic writes, and precedence 
    checking.

.NOTES
    Author: Jan Blomberg
    Version: 1.1.0
    
    LIMITATIONS:
    - This toolkit operates on single SSH config files. If your config uses 
      'Include' directives (e.g., Include ~/.ssh/config.d/*), each included 
      file must be managed separately.
    - UTF-8 encoding without BOM is used for all file operations, which is 
      the correct format for SSH configs.
#>

# Get the path to the Public functions directory
$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

# Dot-source all public function files
$PublicFunctions = Get-ChildItem -Path $PublicPath -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($Function in $PublicFunctions) {
    try {
        Write-Verbose "Importing function: $($Function.BaseName)"
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import function $($Function.BaseName): $_"
    }
}

# Export all public functions (manifest handles this, but belt-and-suspenders)
Export-ModuleMember -Function $PublicFunctions.BaseName
