<#
.SYNOPSIS
    Sets the file permissions (ACL) on an SSH configuration file.

.DESCRIPTION
    Applies a known-good SDDL security descriptor to the specified SSH configuration file.
    Defaults to the system-wide OpenSSH config at C:\ProgramData\ssh\ssh_config.

    The default SDDL grants:
    - BUILTIN\Administrators: Full Access
    - NT AUTHORITY\SYSTEM: Full Access
    - Authenticated Users: Read & Execute

    This is the standard ACL for a system-wide OpenSSH config file on Windows.
    Use the -Sddl parameter to apply a custom security descriptor instead.

.PARAMETER Path
    The full path to the SSH configuration file. Defaults to C:\ProgramData\ssh\ssh_config.

.PARAMETER Sddl
    Optional SDDL string to apply. When not specified, the standard system config SDDL is used:
    O:BAG:DUD:PAI(A;;0x1200a9;;;AU)(A;;FA;;;SY)(A;;FA;;;BA)

.NOTES
    Author: Jan Blomberg
    Date: 2026-03-18
    Version: 1.0

.EXAMPLE
    Set-SshConfigPermissions

    Applies the default system config ACL to C:\ProgramData\ssh\ssh_config.

.EXAMPLE
    Set-SshConfigPermissions -Path "D:\ssh\ssh_config"

    Applies the default ACL to a config file at a custom path.

.EXAMPLE
    Set-SshConfigPermissions -Sddl 'O:BAG:DUD:PAI(A;;FA;;;SY)(A;;FA;;;BA)'

    Applies a custom SDDL (this example removes Authenticated Users read access).
#>
function Set-SshConfigPermissions {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = 'C:\ProgramData\ssh\ssh_config',

        [string]$Sddl
    )

    # Standard system-wide OpenSSH config permissions
    $DefaultSddl = 'O:BAG:DUD:PAI(A;;0x1200a9;;;AU)(A;;FA;;;SY)(A;;FA;;;BA)'

    # Resolve the path to absolute
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $sddlToApply = if ($Sddl) { $Sddl } else { $DefaultSddl }

    if ($PSCmdlet.ShouldProcess($Path, "Set ACL from SDDL: $sddlToApply")) {
        try {
            $acl = [System.Security.AccessControl.FileSecurity]::new()
            $acl.SetSecurityDescriptorSddlForm($sddlToApply)
            Set-Acl -Path $Path -AclObject $acl
            Write-Verbose "Applied permissions to: $Path"
        }
        catch {
            throw "Failed to set permissions on '$Path': $_"
        }
    }
}