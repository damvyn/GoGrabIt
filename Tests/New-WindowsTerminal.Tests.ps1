#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-WindowsTerminal.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-WindowsTerminal.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = 'v1.24.10921.0'
            assets = @(
                [pscustomobject]@{
                    name = 'Microsoft.WindowsTerminal_1.24.10921.0_8wekyb3d8bbwe.msixbundle'
                    browser_download_url = 'https://example.com/download/Microsoft.WindowsTerminal_1.24.10921.0_8wekyb3d8bbwe.msixbundle'
                },
                [pscustomobject]@{
                    name = 'Microsoft.WindowsTerminal_1.24.10921.0_x64.zip'
                    browser_download_url = 'https://example.com/download/Microsoft.WindowsTerminal_1.24.10921.0_x64.zip'
                },
                [pscustomobject]@{
                    name = 'Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle_PreinstallKit.zip'
                    browser_download_url = 'https://example.com/download/Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle_PreinstallKit.zip'
                }
            )
        }
        $script:KitUrl = 'https://example.com/download/Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle_PreinstallKit.zip'
        $script:ProductDir = 'Microsoft\Windows Terminal-1.24.10921.0'
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }

            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }

            Mock Expand-Archive {
                param($Path, $DestinationPath)
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle') -Value 'fake bundle' -Force
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.33519.0_x64__8wekyb3d8bbwe.appx') -Value 'fake appx' -Force
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.UI.Xaml.2.8_8.2310.30001.0_x64__8wekyb3d8bbwe.appx') -Value 'fake appx' -Force
            }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/microsoft/terminal/releases/latest'
            }
        }

        It 'Search pattern PreinstallKit.zip select correct asset' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq $KitUrl
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            Join-Path $TestDir $ProductDir | Should -Exist
        }

        It 'Remove zip file after extraction' {
            $zipFile = Join-Path $TestDir "$ProductDir\Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle_PreinstallKit.zip"
            $zipFile | Should -Not -Exist
        }

        It 'Keep msixbundle in the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir "$ProductDir\Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle"
            $expectedFile | Should -Exist
        }

        It 'Move appx dependencies to Dependencies folder' {
            $depDir = Join-Path $TestDir "$ProductDir\Dependencies"
            Join-Path $depDir 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.33519.0_x64__8wekyb3d8bbwe.appx' | Should -Exist
            Join-Path $depDir 'Microsoft.UI.Xaml.2.8_8.2310.30001.0_x64__8wekyb3d8bbwe.appx' | Should -Exist
            Join-Path $TestDir "$ProductDir\Microsoft.VCLibs.140.00.UWPDesktop_14.0.33519.0_x64__8wekyb3d8bbwe.appx" | Should -Not -Exist
        }

        It 'Create Install.ps1 script' {
            Join-Path $TestDir "$ProductDir\Install.ps1" | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape("`$packageFile = 'Microsoft.WindowsTerminal_Win11_1.24.10921.0_8wekyb3d8bbwe.msixbundle'"))
            $content | Should -Match ([regex]::Escape("`$dependencyDir = 'Dependencies'"))
            $content | Should -Match ([regex]::Escape("`$dependencyFilter = '*x64*'"))
        }

        It 'Install.ps1 has product name and version' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape("`$appName = 'Windows Terminal'"))
            $content | Should -Match ([regex]::Escape("`$appVersion = '1.24.10921.0'"))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<FILE>|<DEPDIR>|<DEPFILTER>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive {
                param($Path, $DestinationPath)
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.WindowsTerminal.msixbundle') -Value 'fake bundle' -Force
            }

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

    Context 'Cannot extract archive' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive { throw 'The archive is invalid or corrupted.' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Archive does not contain a package' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive {
                param($Path, $DestinationPath)
                Set-Content -Path (Join-Path $DestinationPath 'readme.txt') -Value 'no package' -Force
            }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Cannot move dependencies' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive {
                param($Path, $DestinationPath)
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.WindowsTerminal.msixbundle') -Value 'fake bundle' -Force
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.VCLibs.x64.appx') -Value 'fake appx' -Force
            }
            Mock Move-Item { throw 'Access to the path is denied' }

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
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive {
                param($Path, $DestinationPath)
                Set-Content -Path (Join-Path $DestinationPath 'Microsoft.WindowsTerminal.msixbundle') -Value 'fake bundle' -Force
            }
            Mock Out-File { throw 'Access to the path is denied' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }
}
