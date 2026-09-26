#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-Paint.Net.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-Paint.Net.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = 'v5.0.1'
            assets = @(
                [pscustomobject]@{
                    name = 'PaintDotNet_5.0.1_winmsi_x64.zip'
                    browser_download_url = 'https://example.com/download/PaintDotNet_5.0.1_winmsi_x64.zip'
                },
                [pscustomobject]@{
                    name = 'PaintDotNet_5.0.1_winmsi_x86.zip'
                    browser_download_url = 'https://example.com/download/PaintDotNet_5.0.1_winmsi_x86.zip'
                },
                [pscustomobject]@{
                    name = 'PaintDotNet_5.0.1_winmsi_x64.msi'
                    browser_download_url = 'https://example.com/download/PaintDotNet_5.0.1_winmsi_x64.msi'
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
                $zipPath = $OutFile
                $contentPath = Join-Path -Path $TestDir -ChildPath 'zip-content'
                $null = New-Item -Path $contentPath -ItemType Directory -Force
                $msiPath = Join-Path -Path $contentPath -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
                Compress-Archive -Path $msiPath -DestinationPath $zipPath -Force
            } -ParameterFilter { $OutFile }

            Mock Expand-Archive {
                param($Path, $DestinationPath)
                $msiPath = Join-Path -Path $DestinationPath -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
            }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/paintdotnet/release/releases/latest'
            }
        }

        It 'Search pattern *winmsi*x64.zip select correct asset' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/PaintDotNet_5.0.1_winmsi_x64.zip'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'dotPND\PaintDotNet-5.0.1'
            $expectedDir | Should -Exist
        }

        It 'Call Expand-Archive for zip package' {
            $expectedDir = Join-Path $TestDir 'dotPND\PaintDotNet-5.0.1'
            Should -Invoke Expand-Archive -Times 1 -Exactly -ParameterFilter {
                $Path -like '*PaintDotNet_5.0.1_winmsi_x64.zip' -and $DestinationPath -eq $expectedDir
            }
        }

        It 'Remove zip file after extraction' {
            $zipFile = Join-Path $TestDir 'dotPND\PaintDotNet-5.0.1\PaintDotNet_5.0.1_winmsi_x64.zip'
            $zipFile | Should -Not -Exist
        }

        It '$InstallerPath is renewed with full path to msi and file exists' {
            $expectedFile = Join-Path $TestDir 'dotPND\PaintDotNet-5.0.1\PaintDotNet_5.0.1_winmsi_x64.msi'
            $expectedFile | Should -Exist

            . $ScriptPath -Destination $TestDir

            $InstallerPath | Should -Be $expectedFile
            $InstallerPath | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'dotPND\PaintDotNet-5.0.1\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'dotPND\PaintDotNet-5.0.1\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('PaintDotNet_5.0.1_winmsi_x64.msi'))
            $content | Should -Match 'ALLUSERS=1'
            $content | Should -Match 'REBOOT=ReallySuppress'
            $content | Should -Match '/qb'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                $contentPath = Join-Path -Path $TestDir -ChildPath 'zip-content'
                $null = New-Item -Path $contentPath -ItemType Directory -Force
                $msiPath = Join-Path -Path $contentPath -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
                Compress-Archive -Path $msiPath -DestinationPath $OutFile -Force
            } -ParameterFilter { $OutFile }

            Mock Expand-Archive {
                param($Path, $DestinationPath)
                $msiPath = Join-Path -Path $DestinationPath -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
            }

            $expectedDir = Join-Path $ScriptDir 'dotPND\PaintDotNet-5.0.1'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'dotPND') -Recurse -Force -ErrorAction SilentlyContinue
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
                $msiPath = Join-Path -Path $TestDir -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
                Compress-Archive -Path $msiPath -DestinationPath $OutFile -Force
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
                $msiPath = Join-Path -Path $TestDir -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
                Compress-Archive -Path $msiPath -DestinationPath $OutFile -Force
            } -ParameterFilter { $OutFile }
            Mock Expand-Archive {
                param($Path, $DestinationPath)
                $msiPath = Join-Path -Path $DestinationPath -ChildPath 'PaintDotNet_5.0.1_winmsi_x64.msi'
                Set-Content -Path $msiPath -Value 'fake msi content' -Force
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
