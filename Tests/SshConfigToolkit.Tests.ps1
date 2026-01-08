<#
.SYNOPSIS
    Pester test suite for SshConfigToolkit module.

.DESCRIPTION
    Comprehensive tests covering parsing, finding, creating, updating, and removing 
    SSH host blocks. Run with: Invoke-Pester -Path .\Tests\SshConfigToolkit.Tests.ps1

.NOTES
    Author: Jan Blomberg
    Date: 2025-12-23
    Version: 1.0
    
    Requires: Pester v5.0 or later
    Install: Install-Module Pester -Force -SkipPublisherCheck
#>

BeforeAll {
    # Import the module
    $ModulePath = Split-Path -Parent $PSScriptRoot
    Remove-Module SshConfigToolkit -ErrorAction SilentlyContinue
    Import-Module "$ModulePath\SshConfigToolkit.psd1" -Force

    # Create test directory
    $script:TestDir = Join-Path $env:TEMP "SshConfigToolkitTests_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null

    # Sample SSH config content
    $script:SampleConfig = @'
###############################################################################
# TEST SSH CONFIG
###############################################################################
Host jumpex
    HostName jumpex.core.example.net
    User core

Host jumpac
    HostName jumpac.acme.net
    ProxyJump jumpex

# Routing rules
Host acme-prod
    HostName prod.acme.com
    ProxyJump jumpac

Host acme-dev
    HostName dev.acme.com
    ProxyJump jumpac

Host webserver
    HostName web.example.com
    User admin
    Port 22

###############################################################################
# END OF CONFIG
###############################################################################
'@
}

AfterAll {
    # Cleanup test directory
    if (Test-Path $script:TestDir) {
        Remove-Item -Path $script:TestDir -Recurse -Force
    }
}

Describe 'Get-SshConfigEntities' {
    BeforeEach {
        $script:TestFile = Join-Path $script:TestDir "config_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
    }

    It 'Parses SSH config file successfully' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        $entities | Should -Not -BeNullOrEmpty
    }

    It 'Identifies all HostBlock entities' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        $hostBlocks = $entities | Where-Object { $_.Type -eq 'HostBlock' }
        $hostBlocks.Count | Should -Be 5
    }

    It 'Identifies CommentBlock entities' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        $commentBlocks = $entities | Where-Object { $_.Type -eq 'CommentBlock' }
        $commentBlocks.Count | Should -BeGreaterThan 0
    }

    It 'Filters for Bastion types correctly' {
        $bastions = Get-SshConfigEntities -Path $script:TestFile -Type Bastion
        $bastions.Count | Should -Be 2
        $bastionNames = $bastions | ForEach-Object { $_.Patterns[0] }
        @(Compare-Object $bastionNames @('jumpex', 'jumpac')).Count | Should -Be 0
    }

    It 'Filters for Host types correctly' {
        $hosts = Get-SshConfigEntities -Path $script:TestFile -Type Host
        $hosts.Count | Should -Be 3
        $hostNames = $hosts | ForEach-Object { $_.Patterns[0] }
        @(Compare-Object $hostNames @('acme-prod', 'acme-dev', 'webserver')).Count | Should -Be 0
        $hostNames | Should -Not -Contain @('jumpex', 'jumpac')
    }

    It 'Returns all entities for Type All' {
        $entities = Get-SshConfigEntities -Path $script:TestFile -Type All
        $hostBlockCount = ($entities | Where-Object { $_.Type -eq 'HostBlock' }).Count
        $hostBlockCount | Should -Be 5
        $entities.Count | Should -BeGreaterThan 5
    }

    It 'Correctly identifies dependent hosts for bastions' {
        $bastions = Get-SshConfigEntities -Path $script:TestFile -Type Bastion
        
        $jumpex = $bastions | Where-Object { 'jumpex' -in $_.Patterns }
        $jumpex.DependentHosts | Should -Not -BeNullOrEmpty
        $jumpex.DependentHosts | Should -Contain 'jumpac'

        $jumpac = $bastions | Where-Object { 'jumpac' -in $_.Patterns }
        $jumpac.DependentHosts | Should -Not -BeNullOrEmpty
        $jumpac.DependentHosts.Count | Should -Be 2
        @(Compare-Object $jumpac.DependentHosts @('acme-prod', 'acme-dev')).Count | Should -Be 0
    }

    It 'Assigns IsBastion property correctly to all host blocks' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        
        $jumpex = $entities | Where-Object { $_.Type -eq 'HostBlock' -and 'jumpex' -in $_.Patterns }
        $jumpex.IsBastion | Should -Be $true

        $webserver = $entities | Where-Object { $_.Type -eq 'HostBlock' -and 'webserver' -in $_.Patterns }
        $webserver.IsBastion | Should -Be $false
    }
    
    It 'Parses patterns as arrays (not strings)' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        $webserver = $entities | Where-Object { $_.Type -eq 'HostBlock' -and $_.Patterns -contains 'webserver' }
        # Use -is operator instead of piping (pipeline unwraps arrays)
        $webserver.Patterns -is [array] | Should -Be $true
        $webserver.Patterns.Count | Should -Be 1
    }

    It 'Throws when file not found' {
        { Get-SshConfigEntities -Path "C:\nonexistent\file" } | Should -Throw
    }
}

Describe 'Find-SshHostBlock' {
    BeforeAll {
        $script:TestFile = Join-Path $script:TestDir "find_test_config"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
        $script:Entities = Get-SshConfigEntities -Path $script:TestFile
    }

    It 'Finds host block by single pattern' {
        $result = Find-SshHostBlock -Entities $script:Entities -Patterns 'webserver'
        $result | Should -Not -BeNullOrEmpty
        $result.Type | Should -Be 'HostBlock'
    }

    It 'Finds bastion host block by pattern' {
        $result = Find-SshHostBlock -Entities $script:Entities -Patterns 'jumpex'
        $result | Should -Not -BeNullOrEmpty
        $result.Type | Should -Be 'HostBlock'
    }

    It 'Returns null for non-existent pattern' {
        $result = Find-SshHostBlock -Entities $script:Entities -Patterns 'nonexistent'
        $result | Should -BeNullOrEmpty
    }

    It 'Is case-sensitive' {
        $result = Find-SshHostBlock -Entities $script:Entities -Patterns 'WEBSERVER'
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Get-SshHostBlock' {
    BeforeAll {
        $script:TestFile = Join-Path $script:TestDir "get_test_config"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
    }

    It 'Returns structured config object for a standard host' {
        $result = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $result | Should -Not -BeNullOrEmpty
        $result.Patterns | Should -Contain 'webserver'
        $result.Options | Should -BeOfType [hashtable]
    }

    It 'Parses options correctly for a standard host' {
        $result = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $result.Options['HostName'] | Should -Be 'web.example.com'
        $result.Options['User'] | Should -Be 'admin'
        $result.Options['Port'] | Should -Be '22'
    }

    It 'Parses options correctly for a bastion client' {
        $result = Get-SshHostBlock -Path $script:TestFile -Patterns 'jumpac'
        $result.Options['HostName'] | Should -Be 'jumpac.acme.net'
        $result.Options['ProxyJump'] | Should -Be 'jumpex'
    }

    It 'Returns null for non-existent host' {
        $result = Get-SshHostBlock -Path $script:TestFile -Patterns 'nonexistent'
        $result | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-SshHostBlockText' {
    It 'Parses simple host block' {
        $rawText = @"
Host myserver
    HostName 10.0.1.50
    User admin
"@
        $result = ConvertFrom-SshHostBlockText -RawText $rawText
        $result['HostName'] | Should -Be '10.0.1.50'
        $result['User'] | Should -Be 'admin'
    }

    It 'Handles values with spaces' {
        $rawText = @"
Host test
    ProxyCommand ssh -W %h:%p bastion
"@
        $result = ConvertFrom-SshHostBlockText -RawText $rawText
        $result['ProxyCommand'] | Should -Be 'ssh -W %h:%p bastion'
    }

    It 'Includes patterns when requested' {
        $rawText = @"
Host server1 server2
    HostName 10.0.1.50
"@
        $result = ConvertFrom-SshHostBlockText -RawText $rawText -IncludePatterns
        $result['_Patterns'] | Should -Contain 'server1'
        $result['_Patterns'] | Should -Contain 'server2'
    }
}

Describe 'New-SshHostBlockText' {
    It 'Generates valid host block text' {
        $result = New-SshHostBlockText -Patterns 'myserver' -Options @{
            HostName = '10.0.1.50'
            User = 'admin'
        }
        $result | Should -Match '^Host myserver'
        $result | Should -Match 'HostName 10\.0\.1\.50'
        $result | Should -Match 'User admin'
    }

    It 'Handles multiple patterns' {
        $result = New-SshHostBlockText -Patterns @('server1', 'server2') -Options @{
            HostName = '10.0.1.50'
        }
        $result | Should -Match '^Host server1 server2'
    }

    It 'Orders options deterministically' {
        $result1 = New-SshHostBlockText -Patterns 'test' -Options @{
            User = 'admin'
            HostName = '10.0.1.50'
            Port = '22'
        }
        $result2 = New-SshHostBlockText -Patterns 'test' -Options @{
            Port = '22'
            HostName = '10.0.1.50'
            User = 'admin'
        }
        $result1 | Should -Be $result2
    }

    It 'Skips null values' {
        $result = New-SshHostBlockText -Patterns 'test' -Options @{
            HostName = '10.0.1.50'
            User = $null
        }
        $result | Should -Not -Match 'User'
    }
}

# Describe 'Test-SshHostPrecedence' {
#     BeforeAll {
#         $script:TestFile = Join-Path $script:TestDir "precedence_test_config"
#         Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
#         $script:Entities = Get-SshConfigEntities -Path $script:TestFile
#     }
# 
#     It 'Detects shadowing by earlier glob pattern' {
#         # 'ac*' pattern exists and would shadow 'acme-server'
#         $result = Test-SshHostPrecedence -Entities $script:Entities -NewPatterns @('acme-server')
#         $result.Safe | Should -Be $false
#     }
# 
#     It 'Allows non-conflicting patterns' {
#         $result = Test-SshHostPrecedence -Entities $script:Entities -NewPatterns @('newserver')
#         $result.Safe | Should -Be $true
#     }
# 
#     It 'Handles negation patterns correctly' {
#         # Create a dedicated config to test negation patterns in isolation
#         $negationConfig = @' 
# Host jump
#     HostName jump.example.net
# 
# Host ac* !*.acme.com
#     HostName %h.internal
#     ProxyCommand ssh jump -W %h:%p
# 
# Host webserver
#     HostName web.example.com
# '@
#         $negationTestFile = Join-Path $script:TestDir "negation_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
#         Set-Content -Path $negationTestFile -Value $negationConfig -NoNewline
#         $negationEntities = Get-SshConfigEntities -Path $negationTestFile
#         
#         # 'actest.acme.com' matches 'ac*' but is excluded by '!*.acme.com', so it should be safe
#         $result = Test-SshHostPrecedence -Entities $negationEntities -NewPatterns @('actest.acme.com')
#         $result.Safe | Should -Be $true
#         
#         # 'actest' matches 'ac*' and is NOT excluded (no .acme.com), so should NOT be safe
#         $result2 = Test-SshHostPrecedence -Entities $negationEntities -NewPatterns @('actest')
#         $result2.Safe | Should -Be $false
#     }
# 
#     It 'Returns offender information on conflict' {
#         $result = Test-SshHostPrecedence -Entities $script:Entities -NewPatterns @('actest')
#         $result.Safe | Should -Be $false
#         $result.Offender | Should -Not -BeNullOrEmpty
#         $result.OffenderPattern | Should -Not -BeNullOrEmpty
#     }
# }

Describe 'Set-SshHostBlock' {
    BeforeEach {
        $script:TestFile = Join-Path $script:TestDir "set_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
    }

    It 'Creates new host block' {
        $result = Set-SshHostBlock -Path $script:TestFile -Patterns 'newserver' -Options @{
            HostName = '10.0.1.100'
            User = 'newuser'
        } -NoBackup
        
        $result.Action | Should -Be 'Inserted'
        
        # Verify it exists
        $check = Get-SshHostBlock -Path $script:TestFile -Patterns 'newserver'
        $check | Should -Not -BeNullOrEmpty
        $check.Options['HostName'] | Should -Be '10.0.1.100'
    }

    It 'Updates existing host block' {
        $result = Set-SshHostBlock -Path $script:TestFile -Patterns 'webserver' -Options @{
            HostName = 'new.example.com'
            User = 'newadmin'
        } -NoBackup
        
        $result.Action | Should -Be 'Updated'
        
        # Verify update
        $check = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $check.Options['HostName'] | Should -Be 'new.example.com'
    }

    It 'Merges options when -Merge specified' {
        Set-SshHostBlock -Path $script:TestFile -Patterns 'webserver' -Options @{
            Port = '2222'
        } -Merge -NoBackup
        
        # Original options should be preserved
        $check = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $check.Options['User'] | Should -Be 'admin'  # Original
        $check.Options['Port'] | Should -Be '2222'   # New
    }

    It 'Replaces options when -Merge not specified' {
        Set-SshHostBlock -Path $script:TestFile -Patterns 'webserver' -Options @{
            HostName = 'new.example.com'
        } -NoBackup
        
        # Original User option should be gone
        $check = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $check.Options.ContainsKey('User') | Should -Be $false
    }

    It 'Creates backup by default' {
        Set-SshHostBlock -Path $script:TestFile -Patterns 'webserver' -Options @{
            HostName = 'backup.example.com'
        }
        
        $backups = Get-ChildItem -Path $script:TestDir -Filter "*.bak"
        $backups.Count | Should -BeGreaterThan 0
    }

    It 'Skips backup when -NoBackup specified' {
        $beforeBackups = (Get-ChildItem -Path $script:TestDir -Filter "*.bak").Count
        
        Set-SshHostBlock -Path $script:TestFile -Patterns 'newhost' -Options @{
            HostName = 'test.com'
        } -NoBackup
        
        $afterBackups = (Get-ChildItem -Path $script:TestDir -Filter "*.bak").Count
        $afterBackups | Should -Be $beforeBackups
    }
}

Describe 'Remove-SshHostBlock' {
    BeforeEach {
        $script:TestFile = Join-Path $script:TestDir "remove_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
    }

    It 'Removes existing host block' {
        Remove-SshHostBlock -Path $script:TestFile -Patterns 'webserver' -NoBackup -Confirm:$false
        
        $check = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $check | Should -BeNullOrEmpty
    }

    It 'Warns when host not found' {
        # Should write warning but not throw
        $result = Remove-SshHostBlock -Path $script:TestFile -Patterns 'nonexistent' -NoBackup -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -Not -BeNullOrEmpty
    }

    It 'Removes surrounding blank lines when -RemoveBlankLines specified' {
        Remove-SshHostBlock -Path $script:TestFile -Patterns 'webserver' -RemoveBlankLines -NoBackup -Confirm:$false
        
        $content = Get-Content -Path $script:TestFile -Raw
        # Should not have double blank lines where webserver was
        $content | Should -Not -Match "`n`n`n"
    }
}

Describe 'Rename-SshHostBlock' {
    BeforeEach {
        $script:TestFile = Join-Path $script:TestDir "rename_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
    }

    It 'Renames host block patterns' {
        Rename-SshHostBlock -Path $script:TestFile -OldPatterns 'webserver' -NewPatterns 'webserver-prod' -NoBackup
        
        # Old name should not exist
        $old = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver'
        $old | Should -BeNullOrEmpty
        
        # New name should exist with same options
        $new = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver-prod'
        $new | Should -Not -BeNullOrEmpty
        $new.Options['HostName'] | Should -Be 'web.example.com'
    }

    It 'Preserves all options during rename' {
        Rename-SshHostBlock -Path $script:TestFile -OldPatterns 'webserver' -NewPatterns 'webserver-new' -NoBackup
        
        $result = Get-SshHostBlock -Path $script:TestFile -Patterns 'webserver-new'
        $result.Options['HostName'] | Should -Be 'web.example.com'
        $result.Options['User'] | Should -Be 'admin'
        $result.Options['Port'] | Should -Be '22'
    }

    It 'Throws when old patterns not found' {
        { Rename-SshHostBlock -Path $script:TestFile -OldPatterns 'nonexistent' -NewPatterns 'new' -NoBackup } | Should -Throw
    }
}

Describe 'Save-SshConfig' {
    BeforeEach {
        $script:TestFile = Join-Path $script:TestDir "save_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
    }

    It 'Saves entities back to file' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        Save-SshConfig -Entities $entities -Path $script:TestFile -NoBackup
        
        # File should still be valid
        $reparse = Get-SshConfigEntities -Path $script:TestFile
        $reparse | Should -Not -BeNullOrEmpty
    }

    It 'Creates atomic write by default' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        
        # No temp files should remain after save
        Save-SshConfig -Entities $entities -Path $script:TestFile -NoBackup
        
        $tempFiles = Get-ChildItem -Path $script:TestDir -Filter "*.tmp.*"
        $tempFiles.Count | Should -Be 0
    }

    It 'Ensures file ends with newline' {
        $entities = Get-SshConfigEntities -Path $script:TestFile
        Save-SshConfig -Entities $entities -Path $script:TestFile -NoBackup
        
        $content = Get-Content -Path $script:TestFile -Raw
        $content | Should -Match "`n$"
    }
}

Describe 'Get-SshInsertionIndex' {
    BeforeAll {
        $script:TestFile = Join-Path $script:TestDir "insertion_test_config"
        Set-Content -Path $script:TestFile -Value $script:SampleConfig -NoNewline
        $script:Entities = Get-SshConfigEntities -Path $script:TestFile
    }
    It 'Returns insertion point for routing rule' {
        $result = Get-SshInsertionIndex -Entities $script:Entities
        $result.InsertAtLine | Should -BeGreaterThan 0
        $result.Section | Should -Not -BeNullOrEmpty
    }

    It 'Returns insertion point for bastion' {
        $result = Get-SshInsertionIndex -Entities $script:Entities -IsBastion
        $result.InsertAtLine | Should -BeGreaterThan 0
        $result.Section | Should -Match 'bastion'
    }

    It 'Bastion insertion is before routing rules' {
        $bastionIndex = Get-SshInsertionIndex -Entities $script:Entities -IsBastion
        $routingIndex = Get-SshInsertionIndex -Entities $script:Entities
        
        $bastionIndex.InsertAtLine | Should -BeLessThan $routingIndex.InsertAtLine
    }
}

Describe 'Match Block Support' {
    It 'Parses Match blocks correctly' {
        $configWithMatch = @"
Host server
    HostName server.example.com

Match host *.internal exec "test -f /etc/internal"
    User internal-admin
    IdentityFile ~/.ssh/id_internal
"@
        $testFile = Join-Path $script:TestDir "match_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $testFile -Value $configWithMatch -NoNewline
        
        $entities = Get-SshConfigEntities -Path $testFile
        $matchBlocks = $entities | Where-Object { $_.Type -eq 'MatchBlock' }
        
        $matchBlocks.Count | Should -Be 1
        $matchBlocks[0].Criteria | Should -Match 'host \*\.internal'
    }
}

Describe 'Round-Trip Integrity' {
    It 'Preserves config structure through parse-modify-save cycle' {
        $testFile = Join-Path $script:TestDir "roundtrip_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $testFile -Value $script:SampleConfig -NoNewline
        
        # Parse
        $entities = Get-SshConfigEntities -Path $testFile
        $originalCount = $entities.Count
        
        # Modify (add new host)
        $index = Get-SshInsertionIndex -Entities $entities
        $text = New-SshHostBlockText -Patterns 'newhost' -Options @{HostName='new.example.com'}
        
        if ($entities -isnot [System.Collections.Generic.List[object]]) {
            $entities = [System.Collections.Generic.List[object]]::new($entities)
        }
        
        $entities = Insert-SshHostBlock -Entities $entities -InsertionIndex $index -BlockText $text
        
        # Save
        Save-SshConfig -Entities $entities -Path $testFile -NoBackup
        
        # Reparse and verify
        $reparsed = Get-SshConfigEntities -Path $testFile
        
        # Should have more entities now (host + blank lines)
        $reparsed.Count | Should -BeGreaterThan $originalCount
        
        # Original hosts should still exist
        $jumpex = Find-SshHostBlock -Entities $reparsed -Patterns 'jumpex'
        $jumpex | Should -Not -BeNullOrEmpty
        
        # New host should exist
        $newhost = Find-SshHostBlock -Entities $reparsed -Patterns 'newhost'
        $newhost | Should -Not -BeNullOrEmpty
    }
}