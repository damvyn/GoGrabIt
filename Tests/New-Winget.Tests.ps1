#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-Winget.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-Winget.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = 'v1.11.510'
            assets = @(
                [pscustomobject]@{
                    name = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
                    browser_download_url = 'https://example.com/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
                },
                [pscustomobject]@{
                    name = 'DesktopAppInstaller_Dependencies.zip'
                    browser_download_url = 'https://example.com/download/DesktopAppInstaller_Dependencies.zip'
                },
                [pscustomobject]@{
                    name = 'winget-cli-tools.zip'
                    browser_download_url = 'https://example.com/download/winget-cli-tools.zip'
                }
            )
        }
        $script:ProductDir = 'Microsoft\Winget-1.11.510'
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }

            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake content' -Force
            } -ParameterFilter { $OutFile }

            Mock Expand-Archive {
                param($Path, $DestinationPath)
                $x64 = Join-Path $DestinationPath 'x64'
                $null = New-Item -Path $x64 -ItemType Directory -Force
                Set-Content -Path (Join-Path $x64 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.33519.0_x64__8wekyb3d8bbwe.appx') -Value 'fake appx' -Force
            }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
            }
        }

        It 'Download msixbundle and dependencies assets' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            }
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/DesktopAppInstaller_Dependencies.zip'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            Join-Path $TestDir $ProductDir | Should -Exist
        }

        It 'Download msixbundle to the Vendor\Product-Version' {
            Join-Path $TestDir "$ProductDir\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" | Should -Exist
        }

        It 'Call Expand-Archive for dependencies zip' {
            $expectedDir = Join-Path $TestDir "$ProductDir\Dependencies"
            Should -Invoke Expand-Archive -Times 1 -Exactly -ParameterFilter {
                $Path -like '*DesktopAppInstaller_Dependencies.zip' -and $DestinationPath -eq $expectedDir
            }
        }

        It 'Extract dependencies to Dependencies folder' {
            Join-Path $TestDir "$ProductDir\Dependencies\x64\Microsoft.VCLibs.140.00.UWPDesktop_14.0.33519.0_x64__8wekyb3d8bbwe.appx" | Should -Exist
        }

        It 'Remove dependencies zip after extraction' {
            Join-Path $TestDir "$ProductDir\DesktopAppInstaller_Dependencies.zip" | Should -Not -Exist
        }

        It 'Create Install.ps1 script' {
            Join-Path $TestDir "$ProductDir\Install.ps1" | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape("`$packageFile = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'"))
            $content | Should -Match ([regex]::Escape("`$dependencyDir = 'Dependencies'"))
            $content | Should -Match ([regex]::Escape("`$dependencyFilter = '*x64*'"))
        }

        It 'Install.ps1 has product name and version' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape("`$appName = 'Winget'"))
            $content | Should -Match ([regex]::Escape("`$appVersion = '1.11.510'"))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<FILE>|<DEPDIR>|<DEPFILTER>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive { }

            try {
                & $ScriptPath
                Join-Path $ScriptDir $ProductDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Microsoft') -Recurse -Force -ErrorAction SilentlyContinue
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

    Context 'Dependencies asset was not found in the release' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    tag_name = 'v1.11.510'
                    assets = @($FakeReply.assets[0])
                }
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

    Context 'Cannot extract dependencies' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive { throw 'The archive is invalid or corrupted.' }

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
                Set-Content -Path $OutFile -Value 'fake content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive { }
            Mock Out-File { throw 'Access to the path is denied' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }
}
