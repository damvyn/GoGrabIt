#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-NanaZip.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-NanaZip.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = '6.0.1638.0'
            assets = @(
                [pscustomobject]@{
                    name = 'NanaZip_6.0.1638.0.msixbundle'
                    browser_download_url = 'https://example.com/download/NanaZip_6.0.1638.0.msixbundle'
                },
                [pscustomobject]@{
                    name = 'NanaZipPackage_6.0.1638.0_x64.zip'
                    browser_download_url = 'https://example.com/download/NanaZipPackage_6.0.1638.0_x64.zip'
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
                Set-Content -Path $OutFile -Value 'fake msixbundle content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/M2Team/NanaZip/releases/latest'
            }
        }

        It 'Search pattern select msixbundle asset' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/NanaZip_6.0.1638.0.msixbundle'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'M2Team\NanaZip-6.0.1638.0'
            $expectedDir | Should -Exist
        }

        It 'Download msixbundle to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'M2Team\NanaZip-6.0.1638.0\NanaZip_6.0.1638.0.msixbundle'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'M2Team\NanaZip-6.0.1638.0\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'M2Team\NanaZip-6.0.1638.0\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape("`$packageFile = 'NanaZip_6.0.1638.0.msixbundle'"))
            $content | Should -Match ([regex]::Escape("`$dependencyDir = ''"))
            $content | Should -Match 'Add-AppxProvisionedPackage'
        }

        It 'Install.ps1 has product name and version' {
            $installScript = Join-Path $TestDir 'M2Team\NanaZip-6.0.1638.0\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape("`$appName = 'NanaZip'"))
            $content | Should -Match ([regex]::Escape("`$appVersion = '6.0.1638.0'"))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<FILE>|<DEPDIR>|<DEPFILTER>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake msixbundle content' -Force
            } -ParameterFilter { $OutFile }

            $expectedDir = Join-Path $ScriptDir 'M2Team\NanaZip-6.0.1638.0'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'M2Team') -Recurse -Force -ErrorAction SilentlyContinue
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

    Context 'Package was not found in the release' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                return [pscustomobject]@{ tag_name = '6.0.1638.0'; assets = @() }
            }
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
                Set-Content -Path $OutFile -Value 'fake msixbundle content' -Force
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
