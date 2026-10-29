#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-Kudu.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-Kudu.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = 'v3.10.0'
            assets = @(
                [pscustomobject]@{
                    name = 'Kudu-Portable-3.10.0.exe'
                    browser_download_url = 'https://example.com/download/Kudu-Portable-3.10.0.exe'
                },
                [pscustomobject]@{
                    name = 'Kudu-Setup-3.10.0.exe.blockmap'
                    browser_download_url = 'https://example.com/download/Kudu-Setup-3.10.0.exe.blockmap'
                },
                [pscustomobject]@{
                    name = 'Kudu-Setup-3.10.0.exe'
                    browser_download_url = 'https://example.com/download/Kudu-Setup-3.10.0.exe'
                }
            )
        }
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }

            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/AdventDevInc/kudu/releases/latest'
            }
        }

        It 'Search pattern ^Kudu-Setup-.*.exe$ selects correct asset' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/Kudu-Setup-3.10.0.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'AdventDevInc\Kudu-3.10.0'
            $expectedDir | Should -Exist
        }

        It 'Download exe to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'AdventDevInc\Kudu-3.10.0\Kudu-Setup-3.10.0.exe'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'AdventDevInc\Kudu-3.10.0\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'AdventDevInc\Kudu-3.10.0\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('Kudu-Setup-3.10.0.exe'))
            $content | Should -Match ([regex]::Escape('$PSScriptRoot\Kudu-Setup-3.10.0.exe'))
            $content | Should -Match ([regex]::Escape('"/S"'))
            $content | Should -Match ([regex]::Escape('0, 3010'))
        }

        It 'Install.ps1 has product name and version' {
            $installScript = Join-Path $TestDir 'AdventDevInc\Kudu-3.10.0\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('Install Kudu 3.10.0...'))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            $expectedDir = Join-Path $ScriptDir 'AdventDevInc\Kudu-3.10.0'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'AdventDevInc') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'GitHub API failed' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { throw 'Unable to connect to the remote server' }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Failed to create folder' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock New-Item { throw 'Access to the path is denied' }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Cannot download a file' {
        BeforeEach {
            $TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest { throw 'The remote server returned an error: (404) Not Found.' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Cannot create install.ps1' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }
            Mock Out-File { throw 'Access to the path is denied' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }
}