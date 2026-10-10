#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-ResInsight.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-ResInsight.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = 'v2025.04.1'
            assets = @(
                [pscustomobject]@{
                    name = 'ResInsight-2025.04.1_el8.zip'
                    browser_download_url = 'https://example.com/download/ResInsight-2025.04.1_el8.zip'
                },
                [pscustomobject]@{
                    name = 'ResInsight-macOS-arm64-v2025.04.1.zip'
                    browser_download_url = 'https://example.com/download/ResInsight-macOS-arm64-v2025.04.1.zip'
                },
                [pscustomobject]@{
                    name = 'ResInsight-2025.04.1_win64.zip'
                    browser_download_url = 'https://example.com/download/ResInsight-2025.04.1_win64.zip'
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
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/OPM/ResInsight/releases/latest'
            }
        }

        It 'Search pattern selects correct asset' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/ResInsight-2025.04.1_win64.zip'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'Ceetron\ResInsight-2025.04.1'
            $expectedDir | Should -Exist
        }

        It 'Download zip to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'Ceetron\ResInsight-2025.04.1\ResInsight-2025.04.1_win64.zip'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'Ceetron\ResInsight-2025.04.1\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'Ceetron\ResInsight-2025.04.1\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('ResInsight-2025.04.1_win64.zip'))
            $content | Should -Match ([regex]::Escape('Expand-Archive'))
            $content | Should -Match ([regex]::Escape('$env:ProgramFiles'))
            $content | Should -Match ([regex]::Escape('ErrorAction'))
        }

        It 'Install.ps1 has product name and version' {
            $installScript = Join-Path $TestDir 'Ceetron\ResInsight-2025.04.1\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('Install ResInsight 2025.04.1...'))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }

            $expectedDir = Join-Path $ScriptDir 'Ceetron\ResInsight-2025.04.1'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Ceetron') -Recurse -Force -ErrorAction SilentlyContinue
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

    Context 'Version cannot be detected' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { return [pscustomobject]@{ tag_name = 'latest'; name = 'latest'; assets = @() } }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Download link cannot be detected' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                $reply = $FakeReply.PSObject.Copy()
                $reply.assets = @()
                return $reply
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
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            Mock Out-File { throw 'Access to the path is denied' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Generated Install.ps1 unpacks the archive' {
        BeforeAll {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }
            & $ScriptPath -Destination $TestDir

            $script:InstallDir = Join-Path $TestDir 'Ceetron\ResInsight-2025.04.1'
            $script:ArchivePath = Join-Path $InstallDir 'ResInsight-2025.04.1_win64.zip'
            # the real script requires elevation: run a copy without '#Requires' against a fake Program Files
            $script:RunnableScript = Join-Path $InstallDir 'Install.runnable.ps1'
            Get-Content -Path (Join-Path $InstallDir 'Install.ps1') |
                Where-Object { $_ -notmatch '^#Requires' } |
                Set-Content -Path $RunnableScript
            $script:OriginalProgramFiles = $env:ProgramFiles
        }

        BeforeEach {
            $script:FakeProgramFiles = Join-Path $TestDrive "pf-$((new-guid).guid)"
            $null = New-Item -Path $FakeProgramFiles -ItemType Directory -Force
            $env:ProgramFiles = $FakeProgramFiles
        }

        AfterEach {
            $env:ProgramFiles = $OriginalProgramFiles
        }

        It 'Install.ps1 is a valid PowerShell script' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $InstallDir 'Install.ps1'), [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }

        It 'Unpack archive into Program Files and return 0' {
            $src = Join-Path $TestDrive "src-$((new-guid).guid)"
            $null = New-Item -Path (Join-Path $src 'ResInsight-2025.04.1_win64\bin') -ItemType Directory -Force
            Set-Content -Path (Join-Path $src 'ResInsight-2025.04.1_win64\bin\ResInsight.exe') -Value 'fake exe'
            Compress-Archive -Path (Join-Path $src 'ResInsight-2025.04.1_win64') -DestinationPath $ArchivePath -Force

            & $RunnableScript
            $LASTEXITCODE | Should -Be 0
            Join-Path $FakeProgramFiles 'ResInsight-2025.04.1_win64\bin\ResInsight.exe' | Should -Exist
        }

        It 'Return 1 when the archive is missing' {
            Remove-Item -Path $ArchivePath -Force -ErrorAction SilentlyContinue
            & $RunnableScript
            $LASTEXITCODE | Should -Be 1
        }

        It 'Return 1 when the archive is corrupted' {
            Set-Content -Path $ArchivePath -Value 'this is not a zip file' -Force
            & $RunnableScript
            $LASTEXITCODE | Should -Be 1
        }

        It 'Return 1 when the archive does not contain the product folder' {
            $src = Join-Path $TestDrive "src-$((new-guid).guid)"
            $null = New-Item -Path (Join-Path $src 'SomethingElse') -ItemType Directory -Force
            Set-Content -Path (Join-Path $src 'SomethingElse\file.txt') -Value 'x'
            Compress-Archive -Path (Join-Path $src 'SomethingElse') -DestinationPath $ArchivePath -Force

            & $RunnableScript
            $LASTEXITCODE | Should -Be 1
        }
    }
}
