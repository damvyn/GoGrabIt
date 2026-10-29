#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-Nmap.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-Nmap.ps1"

        $script:FakeReply = [pscustomobject]@{ Links = @([pscustomobject]@{ href = '/dist/nmap-7.94-setup.exe' }, [pscustomobject]@{ href = '/dist/nmap-7.95-setup.exe' }, [pscustomobject]@{ href = '/dist/nmap-7.96BETA1-setup.exe' }, [pscustomobject]@{ href = '/dist/nmap-7.95.tar.bz2' }) }
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-WebRequest { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-WebRequest for correct source' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://nmap.org/dist/'
            }
        }

        It 'Download the expected installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://nmap.org/dist/nmap-7.95-setup.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'Nmap Project\Nmap-7.95'
            $expectedDir | Should -Exist
        }

        It 'Download exe to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'Nmap Project\Nmap-7.95\nmap-7.95-setup.exe'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'Nmap Project\Nmap-7.95\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'Nmap Project\Nmap-7.95\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('nmap-7.95-setup.exe'))
            $content | Should -Match ([regex]::Escape('/S'))
        }

        It 'Install.ps1 has product name and version' {
            $installScript = Join-Path $TestDir 'Nmap Project\Nmap-7.95\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('Install Nmap 7.95...'))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-WebRequest { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            $expectedDir = Join-Path $ScriptDir 'Nmap Project\Nmap-7.95'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Nmap Project') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Source request failed' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest { throw 'Unable to connect to the remote server' }
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

            Mock Invoke-WebRequest { return [pscustomobject]@{ Links = @([pscustomobject]@{ href = 'nmap-7.96BETA1-setup.exe' }) } }
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

            Mock Invoke-WebRequest { return $FakeReply }
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

            Mock Invoke-WebRequest { return $FakeReply }
            Mock Invoke-WebRequest { throw 'The remote server returned an error: (404) Not Found.' } -ParameterFilter { $OutFile }

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

            Mock Invoke-WebRequest { return $FakeReply }
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
