Describe 'QuakeCommon' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\src\quake_common.ps1')
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("quake-tests-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        $script:origEnvPath = $env:Path
        $script:origLocalAppData = $env:LOCALAPPDATA
        $script:origProgramFiles = $env:ProgramFiles
    }

    AfterAll {
        $env:Path = $script:origEnvPath
        $env:LOCALAPPDATA = $script:origLocalAppData
        $env:ProgramFiles = $script:origProgramFiles
        if ($script:tempRoot -and (Test-Path $script:tempRoot)) {
            Remove-Item -Path $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Merge-QuakeIniContent' {
        It 'appends a missing section' {
            $template = @"
[SectionA]
KeyA = 1

[SectionB]
KeyB = 2
"@
            $dest = @"
[SectionA]
KeyA = 1
"@
            $res = Merge-QuakeIniContent -TemplateText $template -DestinationText $dest
            $res.AddedSections | Should -Contain 'SectionB'
            $res.Text | Should -Match '\[SectionB\]'
            $res.Text | Should -Match 'KeyB\s*=\s*2'
        }

        It 'appends a missing key at the end of its section' {
            $template = @"
[SectionA]
Key1 = 1
Key2 = 2
"@
            $dest = @"
[SectionA]
Key1 = 1
"@
            $res = Merge-QuakeIniContent -TemplateText $template -DestinationText $dest
            $res.AddedKeys | Should -Contain 'Key2'
            $res.Text | Should -Match 'Key1 = 1[\s\S]*Key2 = 2'
        }

        It 'never duplicates a key that already exists (case-insensitive)' {
            $template = @"
[SectionA]
key1 = 99
KEY2 = 100
"@
            $dest = @"
[SectionA]
Key1 = 1
key2 = 2
"@
            $res = Merge-QuakeIniContent -TemplateText $template -DestinationText $dest
            $res.AddedKeys.Count | Should -Be 0
            $res.Text | Should -Match 'Key1 = 1'
            $res.Text | Should -Not -Match '99'
        }

        It 'preserves existing comments and ordering' {
            $template = @"
[SectionA]
Key1 = 1
NewKey = 2
"@
            $dest = @"
# Header comment
[SectionA]
; Comment before Key1
Key1 = 1
# Trailing comment
"@
            $res = Merge-QuakeIniContent -TemplateText $template -DestinationText $dest
            $res.Text | Should -Match '# Header comment[\s\S]*; Comment before Key1[\s\S]*Key1 = 1[\s\S]*# Trailing comment[\s\S]*NewKey = 2'
        }

        It 'preserves CRLF when the destination uses CRLF' {
            $template = "[SectionA]`nKeyA = 1`n"
            $dest = "[SectionA]`r`nKeyExisting = 0`r`n"
            $res = Merge-QuakeIniContent -TemplateText $template -DestinationText $dest
            $res.Text | Should -Match "`r`n"
            ($res.Text -replace "`r`n", "") | Should -Not -Match "`n"
        }
    }

    Context 'Compare-QuakeVersion' {
        It 'returns negative when left is older than right' {
            (Compare-QuakeVersion '0.13.5' '0.14.0') | Should -BeLessThan 0
        }

        It 'returns zero when build metadata differs' {
            (Compare-QuakeVersion '0.14.0+build.7' '0.14.0') | Should -Be 0
        }

        It 'returns positive when left is newer than right and handles v prefix' {
            (Compare-QuakeVersion 'v0.14.0' '0.13.9') | Should -BeGreaterThan 0
        }
    }

    Context 'Install state operations' {
        It 'round-trips Write-QuakeInstallState and Read-QuakeInstallState in a temp dir' {
            $testDir = Join-Path $script:tempRoot 'state-roundtrip'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            Write-QuakeInstallState -TargetDir $testDir -Version '0.14.0' -ConfigSchema 2 -GitCommit 'abcdef12' -Shell 'pwsh' -Layout 'quad'
            $state = Read-QuakeInstallState -TargetDir $testDir
            $state | Should -Not -BeNullOrEmpty
            $state.version | Should -Be '0.14.0'
            $state.configSchema | Should -Be 2
            $state.gitCommit | Should -Be 'abcdef12'
            $state.shell | Should -Be 'pwsh'
            $state.layout | Should -Be 'quad'
        }

        It 'returns null for a missing install state file' {
            $missingDir = Join-Path $script:tempRoot 'missing-state'
            New-Item -ItemType Directory -Path $missingDir -Force | Out-Null
            $state = Read-QuakeInstallState -TargetDir $missingDir
            $state | Should -BeNullOrEmpty
        }
    }

    Context 'Version and schema discovery' {
        It 'reads a temp VERSION file verbatim' {
            $verDir = Join-Path $script:tempRoot 'ver-dir'
            New-Item -ItemType Directory -Path $verDir -Force | Out-Null
            Set-Content -Path (Join-Path $verDir 'VERSION') -Value '0.14.0'
            $ver = Get-QuakeVersionFromDir -Directory $verDir
            $ver | Should -Be '0.14.0'
        }

        It 'reads a temp CONFIG_SCHEMA integer' {
            $schemaDir = Join-Path $script:tempRoot 'schema-dir'
            New-Item -ItemType Directory -Path $schemaDir -Force | Out-Null
            Set-Content -Path (Join-Path $schemaDir 'CONFIG_SCHEMA') -Value '2'
            $schema = Get-QuakeConfigSchemaFromDir -Directory $schemaDir
            $schema | Should -Be 2
        }
    }

    Context 'Alacritty executable discovery' {
        It 'returns configured path when ConfiguredPath exists' {
            $fakeExe = Join-Path $script:tempRoot 'fake-alacritty.exe'
            New-Item -ItemType File -Path $fakeExe -Force | Out-Null
            $resolved = Get-QuakeAlacrittyExecutable -ConfiguredPath $fakeExe
            $resolved | Should -Be (Resolve-Path $fakeExe).Path
        }

        It 'returns null when no candidate exists' {
            $emptyTemp = Join-Path $script:tempRoot 'empty-env'
            New-Item -ItemType Directory -Path $emptyTemp -Force | Out-Null

            $savedPath = $env:Path
            $savedLocal = $env:LOCALAPPDATA
            $savedProg = $env:ProgramFiles

            try {
                $env:Path = ''
                $env:LOCALAPPDATA = $emptyTemp
                $env:ProgramFiles = $emptyTemp

                $exe = Get-QuakeAlacrittyExecutable
                $exe | Should -BeNullOrEmpty
            } finally {
                $env:Path = $savedPath
                $env:LOCALAPPDATA = $savedLocal
                $env:ProgramFiles = $savedProg
            }
        }
    }
}
