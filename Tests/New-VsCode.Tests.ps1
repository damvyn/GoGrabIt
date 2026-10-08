#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-VsCode.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-VsCode.ps1"

        $script:FakeReply = [pscustomobject]@{
            products = @(
                [pscustomobject]@{
                    build = 'insider'
                    platform = [pscustomobject]@{ os = 'win32-x64' }
                    productVersion = '1.96.0-insider'
                    url = 'https://example.com/download/insider/VSCodeSetup-x64-1.96.0-insider.exe'
                },
                [pscustomobject]@{
                    build = 'stable'
                    platform = [pscustomobject]@{ os = 'win32-x64-user' }
                    productVersion = '1.95.3'
                    url = 'https://example.com/download/stable/VSCodeUserSetup-x64-1.95.3.exe'
                },
                [pscustomobject]@{
                    build = 'stable'
                    platform = [pscustomobject]@{ os = 'win32-x64' }
                    productVersion = '1.95.3'
                    url = 'https://example.com/download/stable/VSCodeSetup-x64-1.95.3.exe'
                },
                [pscustomobject]@{
                    build = 'stable'
                    platform = [pscustomobject]@{ os = 'win32-arm64' }
                    productVersion = '1.95.3'
                    url = 'https://example.com/download/stable/VSCodeSetup-arm64-1.95.3.exe'
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

            & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://code.visualstudio.com/sha/'
            }
        }

        It 'Select stable win32-x64 system installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/stable/VSCodeSetup-x64-1.95.3.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'Microsoft\Visual Studio Code-1.95.3'
            $expectedDir | Should -Exist
        }

        It 'Download exe to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'Microsoft\Visual Studio Code-1.95.3\VSCodeSetup-x64-1.95.3.exe'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'Microsoft\Visual Studio Code-1.95.3\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'Microsoft\Visual Studio Code-1.95.3\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('$PSScriptRoot\VSCodeSetup-x64-1.95.3.exe'))
            $content | Should -Match '/VERYSILENT'
            $content | Should -Match '/NORESTART'
            $content | Should -Match ([regex]::Escape('/MERGETASKS=!runcode'))
            $content | Should -Match ([regex]::Escape('0, 3010'))
        }

        It 'Install.ps1 has product name and version' {
            $installScript = Join-Path $TestDir 'Microsoft\Visual Studio Code-1.95.3\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('Install Visual Studio Code 1.95.3...'))
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

            $expectedDir = Join-Path $ScriptDir 'Microsoft\Visual Studio Code-1.95.3'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Microsoft') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Vendor API failed' {
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

    Context 'Cannot detect product version' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            $badVersionReply = [pscustomobject]@{
                products = @(
                    [pscustomobject]@{
                        build = 'stable'
                        platform = [pscustomobject]@{ os = 'win32-x64' }
                        productVersion = 'latest'
                        url = 'https://example.com/download/stable/VSCodeSetup-x64.exe'
                    }
                )
            }
            Mock Invoke-RestMethod { return $badVersionReply }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Download link was not detected' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            $noUrlReply = [pscustomobject]@{
                products = @(
                    [pscustomobject]@{
                        build = 'stable'
                        platform = [pscustomobject]@{ os = 'win32-x64' }
                        productVersion = '1.95.3'
                        url = ''
                    }
                )
            }
            Mock Invoke-RestMethod { return $noUrlReply }
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
