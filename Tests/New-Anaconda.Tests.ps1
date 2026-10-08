#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-Anaconda.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-Anaconda.ps1"

        $script:FakeReply = [pscustomobject]@{
            'Anaconda3-2024.06-1-Windows-x86_64.exe' = [pscustomobject]@{ mtime = 1719000000.0 }
            'Anaconda3-2024.10-1-Windows-x86_64.exe' = [pscustomobject]@{ mtime = 1729000000.0 }
            'Anaconda3-2024.10-1-Linux-x86_64.sh'    = [pscustomobject]@{ mtime = 1729000001.0 }
            'Anaconda3-2024.10-1-MacOSX-arm64.pkg'   = [pscustomobject]@{ mtime = 1729000002.0 }
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
                $Uri -eq 'https://repo.anaconda.com/archive/.files.json'
            }
        }

        It 'Search pattern select latest Windows x86_64 installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://repo.anaconda.com/archive/Anaconda3-2024.10-1-Windows-x86_64.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'Anaconda\Anaconda3-2024.10-1'
            $expectedDir | Should -Exist
        }

        It 'Download exe to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'Anaconda\Anaconda3-2024.10-1\Anaconda3-2024.10-1-Windows-x86_64.exe'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'Anaconda\Anaconda3-2024.10-1\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'Anaconda\Anaconda3-2024.10-1\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('"$PSScriptRoot\Anaconda3-2024.10-1-Windows-x86_64.exe"'))
            $content | Should -Match '/InstallationType=AllUsers'
            $content | Should -Match '/RegisterPython=1'
            $content | Should -Match '/S'
            $content | Should -Match ([regex]::Escape('/D=C:\ProgramData\Anaconda3'))
            $content | Should -Match ([regex]::Escape('$exitCodes = 0, 3010'))
        }

        It 'Install.ps1 has product name and version' {
            $installScript = Join-Path $TestDir 'Anaconda\Anaconda3-2024.10-1\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('Install Anaconda3 2024.10-1...'))
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

            $expectedDir = Join-Path $ScriptDir 'Anaconda\Anaconda3-2024.10-1'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Anaconda') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Repository API failed' {
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

    Context 'Installer not found in reply' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    'Anaconda3-2024.10-1-Linux-x86_64.sh' = [pscustomobject]@{ mtime = 1729000001.0 }
                }
            }
            Mock Invoke-WebRequest { }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }

        It 'Do not download anything' {
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
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
