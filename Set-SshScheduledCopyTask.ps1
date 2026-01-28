#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates the backups folder and scheduled task for atomic ssh_config updates.

.DESCRIPTION
    This script performs two setup tasks:
    
    1. Creates C:\ProgramData\ssh\backups\ with permissions allowing normal users
       to write files (for staging temp configs and storing backups).
    
    2. Registers a scheduled task 'Update-SshConfig' that runs as SYSTEM and performs
       atomic replacement of ssh_config. The task can be triggered by non-admin users.
    
    The task executes Update-SshConfig.ps1 from the module's Private folder.

.PARAMETER ModulePath
    Path to the SshConfigEditor module folder. If not specified, attempts to locate
    it automatically via Get-Module or falls back to the script's parent directory.

.PARAMETER TaskName
    Name of the scheduled task to create. Defaults to 'Update-SshConfig'.

.PARAMETER SshFolder
    Path to the SSH configuration folder. Defaults to 'C:\ProgramData\ssh'.

.EXAMPLE
    .\Set-SshScheduledCopyTask.ps1
    
    Creates the backups folder and scheduled task using auto-detected module path.

.EXAMPLE
    .\Set-SshScheduledCopyTask.ps1 -ModulePath "C:\Program Files\PowerShell\Modules\SshConfigEditor"
    
    Creates the task with an explicit module path.

.NOTES
    Author: Jan Blomberg
    Date: 2025-01-28
    Version: 2.0
    
    Version History:
    2.0 - Separated Update-SshConfig.ps1 to module folder, added backups folder setup
    1.0 - Initial release with embedded script
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ModulePath,

    [Parameter()]
    [string]$TaskName = 'Update-SshConfig',

    [Parameter()]
    [string]$SshFolder = 'C:\ProgramData\ssh'
)

$ErrorActionPreference = 'Stop'

# Resolve module path if not specified
if (-not $ModulePath) {
    # Try to find the module
    $module = Get-Module -Name 'SshConfigEditor' -ListAvailable | Select-Object -First 1
    if ($module) {
        $ModulePath = $module.ModuleBase
    }
    else {
        # Fall back to script's parent directory (assumes script is in module root or Public folder)
        $ModulePath = Split-Path -Parent $PSScriptRoot
        if (-not (Test-Path (Join-Path $ModulePath 'Private'))) {
            $ModulePath = $PSScriptRoot
        }
    }
}

# Validate Update-SshConfig.ps1 exists
$UpdateScriptPath = Join-Path $ModulePath 'Private\Update-SshConfig.ps1'
if (-not (Test-Path $UpdateScriptPath)) {
    throw "Update-SshConfig.ps1 not found at: $UpdateScriptPath`nEnsure the module is properly installed."
}

Write-Host "Using module path: $ModulePath" -ForegroundColor Cyan
Write-Host "Update script: $UpdateScriptPath" -ForegroundColor Cyan

# --- Step 1: Create backups folder with proper permissions ---

$BackupsFolder = Join-Path $SshFolder 'backups'

if ($PSCmdlet.ShouldProcess($BackupsFolder, 'Create backups folder with user-write permissions')) {
    
    if (-not (Test-Path $BackupsFolder)) {
        New-Item -Path $BackupsFolder -ItemType Directory -Force | Out-Null
        Write-Host "Created folder: $BackupsFolder" -ForegroundColor Green
    }
    else {
        Write-Host "Folder already exists: $BackupsFolder" -ForegroundColor Yellow
    }

    # Set ACL: SYSTEM and Admins full control, Users can modify (create/write/delete)
    $acl = Get-Acl $BackupsFolder
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, don't copy inherited rules
    
    # Clear existing rules
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
    
    # SYSTEM: Full Control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM',
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.AddAccessRule($systemRule)
    
    # Administrators: Full Control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators',
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.AddAccessRule($adminRule)
    
    # Users: Modify (allows create, write, delete own files)
    $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Users',
        'Modify',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.AddAccessRule($usersRule)
    
    Set-Acl -Path $BackupsFolder -AclObject $acl
    Write-Host "Set permissions on: $BackupsFolder" -ForegroundColor Green
    Write-Host "  - SYSTEM: Full Control" -ForegroundColor Gray
    Write-Host "  - Administrators: Full Control" -ForegroundColor Gray
    Write-Host "  - Users: Modify" -ForegroundColor Gray
}

# --- Step 2: Create scheduled task ---

if ($PSCmdlet.ShouldProcess($TaskName, 'Register scheduled task')) {
    
    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed existing task: $TaskName" -ForegroundColor Yellow
    }

    # Create the scheduled task
    $Action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$UpdateScriptPath`""
    $Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings `
        -Description "Atomic update of ssh_config with proper permissions. Triggered by Save-SshConfig." | Out-Null

    # Grant Authenticated Users permission to start the task
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    $task = $folder.GetTask($TaskName)

    $sddl = $task.GetSecurityDescriptor(0xF)

    # Authenticated Users: Generic Read + Generic Write + Generic Execute (allows starting)
    $newAce = '(A;;GRGWGX;;;AU)'
    if ($sddl -match 'S:') {
        $newSddl = $sddl -replace 'S:', "${newAce}S:"
    }
    else {
        $newSddl = $sddl + $newAce
    }

    $task.SetSecurityDescriptor($newSddl, 0)

    Write-Host "Created scheduled task: $TaskName" -ForegroundColor Green
}

# --- Summary ---

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ' Setup Complete' -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Backups folder:' -ForegroundColor White
Write-Host "  $BackupsFolder" -ForegroundColor Gray
Write-Host ''
Write-Host 'Scheduled task:' -ForegroundColor White
Write-Host "  $TaskName" -ForegroundColor Gray
Write-Host ''
Write-Host 'Usage:' -ForegroundColor White
Write-Host '  Non-admin users can now use Save-SshConfig to update the system-wide' -ForegroundColor Gray
Write-Host '  SSH configuration. The function writes to the backups folder and' -ForegroundColor Gray
Write-Host '  triggers the scheduled task to perform the atomic replacement.' -ForegroundColor Gray
Write-Host ''